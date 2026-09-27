#!/bin/bash
# Pre-commit guard: detecta si Claude va a hacer git commit y corre los
# tests del árbol correspondiente antes de dejarlo pasar.
# Recibe JSON en stdin con tool_input del comando Bash.
#
# hooks.json filtra la invocación con "if": "Bash(git *)" — optimización de
# latencia, no reemplaza la validación de abajo, que mira el comando
# completo saneado (spans quoted/heredoc) y anclado a posición de comando —
# mismo helper que pre-merge-check.sh (hooks/lib/guard-matching.sh).
#
# Formas aceptadas para resolver el ÁRBOL OBJETIVO del commit — lo que no
# calza bloquea con el mensaje de "Formas aceptadas" (TREE_FORM_HELP más
# abajo), nunca se adivina ni se corre "por si acaso":
#   1. Sin redirección: el cwd de la sesión (guard_session_dir — ".cwd" del
#      input, o el cwd del proceso si el harness no lo manda).
#   2. "cd /ruta/absoluta && git commit …": "cd" al INICIO del comando, una
#      sola vez, ruta absoluta literal (sin comillas/variables/espacios/
#      "~/"), seguida directo de "&&".
#
# Sin marcador de runner (package.json/pyproject.toml/setup.py/pytest.ini)
# entre SESSION_DIR y TARGET_DIR: se deriva un candidato por el PRIMER
# SEGMENTO de cada path con cambios locales que sí tenga marcador (nunca se
# adivina "todo el repo"); corren TODOS antes de decidir y cualquier fallo
# bloquea nombrándolos; sin candidatos, pasa sin correr nada.
#
# Fuera de alcance (documentado, no parcheado — no confundir con un hueco
# no advertido):
#   - Evasión deliberada (wrappers "bash -c", funciones "git()", "\g\it"):
#     mismo modelo de amenaza que hooks/lib/guard-matching.sh. Estos guards
#     protegen errores honestos del flujo del orchestrator/dev, no un
#     adversario con control del comando.
#   - Huecos del saneo COMPARTIDO (comillas desbalanceadas, heredoc con
#     delimitador a medias) que borran el comando real antes de que este
#     hook lo vea.
#
# Limitaciones aceptadas de la derivación por primer segmento:
#   1. Un runner a 2+ niveles sin marcador arriba (ej.
#      "packages/a/package.json", sin marcador en "packages/") no corre.
#   2. Un repo git anidado de primer nivel con su propio marcador corre su
#      propio runner (no se distingue de un directorio legítimo del repo).
#   3. Un path con caracteres especiales llega C-quoteado en `git status
#      --porcelain` y no matchea ningún segmento real — esa suite en
#      particular no corre, nunca bloquea por eso.
#
# Preámbulo común (guard_init, hooks/lib/guard-matching.sh): fail-closed sin
# jq, lee INPUT/COMMAND/INPUT_CWD, bloquea ante un byte NUL y deja
# SANITIZED_COMMAND saneado — mismo contrato que el resto de los guards.
LIB="${0%/*}/lib/guard-matching.sh"
[ -r "$LIB" ] || { echo "BLOCKED: pre-commit-guard no operativo: falta hooks/lib/guard-matching.sh" >&2; exit 2; }
# shellcheck source=lib/guard-matching.sh
source "$LIB"
guard_init "pre-commit-guard"

# GIT_COMMIT_RE detecta la forma pelada ("git\s+commit") y las opciones de
# árbol entre "git" y "commit" ("git -C <ruta> commit", "GIT_DIR=... git
# commit"), para que el resolver de abajo las bloquee en vez de dejarlas
# pasar sin evaluar ("git log | grep commit" sigue sin matchear). El "\S*"
# tras cada opción es deliberado: una ruta entre comillas la colapsa
# guard_sanitize, y el detector igual tiene que disparar. "commit" puede
# venir pegado a ";"/"&"/"|"/")" sin espacio — el charset no agrega "-" ni
# letras, así que "commit-tree"/"commit-graph" no matchean.
GIT_COMMIT_RE="${GUARD_ANCHOR}((GIT_DIR|GIT_WORK_TREE)=\S*\s+)*git\s+${GUARD_GIT_OPTS}commit(\s|\$|[;&|)])"
if ! echo "$SANITIZED_COMMAND" | grep -qE "$GIT_COMMIT_RE"; then
  exit 0
fi

# Resolución del árbol objetivo: sin esto, el hook evaluaría siempre el cwd
# del PROCESO, sin importar a qué árbol redirige el comando interceptado.
TREE_FORM_HELP="Formas aceptadas: 'git commit …' en el cwd de la sesión, o 'cd /ruta/absoluta && git commit …' (cd al inicio, una sola vez, ruta absoluta literal). Alternativa: haz el cd en una llamada Bash previa."

_guard_block_tree() {
  echo "BLOCKED: pre-commit-guard no puede resolver en qué árbol va el commit: $1. ${TREE_FORM_HELP}" >&2
  exit 2
}

# _guard_toplevel_or_base: toplevel real de $1 si cae dentro de un repo git;
# si no, $1 tal cual — nunca falla abierto ni bloquea por esto.
_guard_toplevel_or_base() {
  local toplevel
  if toplevel=$(git -C "$1" rev-parse --show-toplevel 2>/dev/null); then
    printf '%s' "$toplevel"
    return 0
  fi
  printf '%s' "$1"
}

# "-C"/"--git-dir"/"--work-tree"/"GIT_DIR="/"GIT_WORK_TREE=" nunca se
# resuelven: a diferencia de "cd", no hay forma de saber si valen para TODO
# el comando sin parsear de verdad el shell — así que siempre bloquean.
# Mismo criterio para el entorno DEL PROCESO del hook.
if [ -n "${GIT_DIR:-}" ] || [ -n "${GIT_WORK_TREE:-}" ]; then
  _guard_block_tree "GIT_DIR/GIT_WORK_TREE en el entorno del hook"
fi
if echo "$SANITIZED_COMMAND" | grep -qE -- "--git-dir|--work-tree"; then
  _guard_block_tree "--git-dir/--work-tree no se resuelven"
fi
if echo "$SANITIZED_COMMAND" | grep -qE "(^|\s|;|&&|\|)(GIT_DIR|GIT_WORK_TREE)="; then
  _guard_block_tree "GIT_DIR/GIT_WORK_TREE como prefijo de entorno en el comando no se resuelven"
fi
if echo "$SANITIZED_COMMAND" | grep -qE "${GUARD_ANCHOR}git\s+-C\s"; then
  _guard_block_tree "'git -C' no se resuelve"
fi

CD_PUSHD_RE="${GUARD_ANCHOR}(cd|pushd)(\s|;|&&|\$)"

if echo "$SANITIZED_COMMAND" | grep -qE "$CD_PUSHD_RE"; then
  # Se valida sobre el comando CRUDO ($COMMAND, no el saneado, que colapsa
  # comillas): exactamente UNA ocurrencia de "cd"/"pushd" y "cd" al INICIO
  # con una ruta absoluta literal seguida directo de "&&".
  CD_OCCURRENCES=$(echo "$SANITIZED_COMMAND" | grep -oE "$CD_PUSHD_RE")
  CD_COUNT=$(printf '%s\n' "$CD_OCCURRENCES" | grep -c .)
  [ "$CD_COUNT" -eq 1 ] || _guard_block_tree "más de una mención de 'cd'/'pushd', o 'pushd' en vez de 'cd'"

  [[ "$COMMAND" =~ ^cd[[:blank:]]+(/[A-Za-z0-9_./-]*)[[:blank:]]*\&\& ]] || _guard_block_tree "'cd' no está al inicio del comando, o la ruta no es absoluta y literal seguida de '&&'"
  CD_PATH="${BASH_REMATCH[1]}"

  BASE_DIR=$(cd "$CD_PATH" 2>/dev/null && pwd -P) || _guard_block_tree "la ruta '$CD_PATH' no existe"
  TARGET_DIR=$(git -C "$BASE_DIR" rev-parse --show-toplevel 2>/dev/null) || _guard_block_tree "'$CD_PATH' no es un repo git"
  SESSION_DIR="$BASE_DIR"
else
  # Sin redirección en el texto: el árbol es el de la sesión (".cwd" del
  # input vía guard_session_dir, o el cwd del proceso si el harness no lo
  # manda).
  BASE_DIR=$(guard_session_dir) || _guard_block_tree "el cwd del input no es un directorio ($INPUT_CWD)"
  TARGET_DIR=$(_guard_toplevel_or_base "$BASE_DIR")
  SESSION_DIR="$BASE_DIR"
fi

cd "$TARGET_DIR" || _guard_block_tree "no se pudo entrar al árbol resuelto ($TARGET_DIR)"

# _guard_find_runner_dir: busca el test runner subiendo desde SESSION_DIR
# hasta TARGET_DIR (toplevel) inclusive, con la PRIMERA coincidencia. El
# "case" es una red de seguridad ante un "dir" que dejara de ser
# descendiente de "top": corta y devuelve "top" en vez de subir sin límite.
_guard_find_runner_dir() {
  local dir="$1" top="$2"
  while :; do
    if [ -f "$dir/package.json" ] || [ -f "$dir/pyproject.toml" ] || [ -f "$dir/setup.py" ] || [ -f "$dir/pytest.ini" ]; then
      printf '%s' "$dir"
      return 0
    fi
    [ "$dir" = "$top" ] && { printf '%s' "$top"; return 0; }
    case "$dir" in
      "$top"/*) : ;;
      *) printf '%s' "$top"; return 0 ;;
    esac
    dir="${dir%/*}"
    [ -z "$dir" ] && dir="/"
  done
}

# _guard_has_marker: mismo charset que _guard_find_runner_dir, que devuelve
# el MISMO valor (top) si encontró marcador ahí o si no encontró ninguno.
_guard_has_marker() {
  local dir="$1"
  [ -f "$dir/package.json" ] || [ -f "$dir/pyproject.toml" ] || [ -f "$dir/setup.py" ] || [ -f "$dir/pytest.ini" ]
}

# _guard_derive_runner_dirs: cuando NINGÚN directorio entre SESSION_DIR y
# TARGET_DIR tiene marcador, correr por el PRIMER SEGMENTO de cada path con
# cambios locales en vez de no correr nada. Un archivo en la raíz (sin "/"),
# un segmento sin marcador, o un runner a 2+ niveles se descartan sin
# bloquear — "no correr nada" sigue siendo la decisión aceptada.
_guard_derive_runner_dirs() {
  local top="$1"
  local segments
  segments=$(git status --porcelain --no-renames --untracked-files=all 2>/dev/null | cut -c4- | grep / | cut -d/ -f1 | sort -u) || return 0
  [ -z "$segments" ] && return 0

  local segment candidates=()
  while IFS= read -r segment; do
    [ -z "$segment" ] && continue
    _guard_has_marker "$top/$segment" && candidates+=("$top/$segment")
  done <<< "$segments"

  [ "${#candidates[@]}" -eq 0 ] && return 0
  printf '%s\n' "${candidates[@]}"
}

RUNNER_DIR=$(_guard_find_runner_dir "$SESSION_DIR" "$TARGET_DIR")

GUARD_RUN_DIRS=()
if _guard_has_marker "$RUNNER_DIR"; then
  GUARD_RUN_DIRS=("$RUNNER_DIR")
else
  while IFS= read -r _guard_dir; do
    [ -z "$_guard_dir" ] && continue
    GUARD_RUN_DIRS+=("$_guard_dir")
  done < <(_guard_derive_runner_dirs "$TARGET_DIR")
fi

if [ "${#GUARD_RUN_DIRS[@]}" -eq 0 ]; then
  exit 0
fi

# Watchdog fail-closed por tiempo: una suite colgada supera el timeout del
# harness (hooks.json), que DESCARTA la salida del hook y deja pasar el
# commit sin tests — el hook nunca falla abierto por diseño. Por eso
# PRECOMMIT_TEST_BUDGET (default 540, tope 570) es menor que el timeout de
# hooks.json (600), con margen para el overhead de corte. Se valida antes de
# usarlo como cap: un valor no numérico rompe la comparación de más abajo
# ("integer expression expected", que en un "if" cuenta como falso).
_guard_resolve_test_budget() {
  local raw="${PRECOMMIT_TEST_BUDGET:-}"
  if [ -z "$raw" ]; then
    echo 540
    return 0
  fi
  if [[ "$raw" =~ ^[0-9]+$ ]] && [ "$raw" -le 570 ]; then
    echo "$raw"
    return 0
  fi
  echo "PRECOMMIT_TEST_BUDGET=\"$raw\" inválido (debe ser un entero <= 570); usando el default 540." >&2
  echo 540
  return 0
}

# _guard_run_with_budget <budget> <cmd...>: mata un PROCESO EXTERNO
# (pytest/npm y sus hijos), con un job de bash en su propio grupo de
# procesos (`set -m`) + kill del grupo completo — matar solo el pid de
# arriba deja huérfanos a los hijos del test runner. $SECONDS mide el reloj
# de pared real, no vueltas de loop (con overhead variable el corte real
# llegaría después de "budget" segundos).
_guard_run_with_budget() {
  local budget="$1"
  shift
  local outfile pgid_file
  outfile=$(mktemp)
  pgid_file=$(mktemp)

  (
    set -m
    "$@" > "$outfile" 2>&1 &
    job_pid=$!
    echo "$job_pid" > "$pgid_file"
    wait "$job_pid"
  ) &
  local runner_pid=$!

  SECONDS=0
  while kill -0 "$runner_pid" 2>/dev/null; do
    if [ "$SECONDS" -ge "$budget" ]; then
      local job_pgid
      job_pgid=$(cat "$pgid_file" 2>/dev/null)
      if [ -n "$job_pgid" ]; then
        kill -TERM -- "-$job_pgid" 2>/dev/null
        sleep 1
        kill -KILL -- "-$job_pgid" 2>/dev/null
      fi
      kill -KILL "$runner_pid" 2>/dev/null
      cat "$outfile"
      echo "BLOCKED: la suite superó ${budget}s; el hook no falla abierto. Acota la suite o sube PRECOMMIT_TEST_BUDGET." >&2
      rm -f "$outfile" "$pgid_file"
      exit 2
    fi
    sleep 1
  done

  wait "$runner_pid" 2>/dev/null
  local rc=$?
  cat "$outfile"
  rm -f "$outfile" "$pgid_file"
  return "$rc"
}

# _guard_run_suite_in <dir> <budget>: detecta y corre el runner de UN
# directorio con el budget que le tocó. Devuelve 0/1 (nada que correr o
# corrió y pasó / corrió y falló) — nunca hace "exit" salvo el watchdog de
# _guard_run_with_budget: con más de un directorio el resto corre igual
# antes de decidir.
_guard_run_suite_in() {
  local dir="$1" budget="$2"
  local prev_pwd
  prev_pwd=$(pwd)
  cd "$dir" || return 1

  local rc=0
  if [ -f "package.json" ]; then
    local pkg_mgr
    if [ -f "pnpm-lock.yaml" ]; then
      pkg_mgr="pnpm"
    elif [ -f "yarn.lock" ]; then
      pkg_mgr="yarn"
    else
      pkg_mgr="npm"
    fi

    if jq -e '.scripts.test' package.json > /dev/null 2>&1; then
      local test_cmd
      test_cmd=$(jq -r '.scripts.test' package.json)
      if [ "$test_cmd" != "null" ] && [ "$test_cmd" != "" ] && [ "$test_cmd" != "echo \"Error: no test specified\" && exit 1" ]; then
        echo "Running tests before commit ($pkg_mgr) [$dir]..." >&2
        _guard_run_with_budget "$budget" "$pkg_mgr" test
        rc=$?
        [ "$rc" -eq 0 ] && echo "Tests passed [$dir]." >&2
      fi
    fi
  elif [ -f "pytest.ini" ] || [ -f "pyproject.toml" ] || [ -f "setup.py" ]; then
    if command -v pytest > /dev/null 2>&1; then
      echo "Running pytest before commit [$dir]..." >&2
      _guard_run_with_budget "$budget" pytest
      rc=$?
      [ "$rc" -eq 0 ] && echo "Tests passed [$dir]." >&2
    fi
  fi

  cd "$prev_pwd" || true
  return "$rc"
}

# Presupuesto por directorio: se divide en partes iguales entre los
# directorios a correr (división entera, mínimo 1) para que la SUMA de las
# corridas nunca supere PRECOMMIT_TEST_BUDGET sin estado compartido.
PRECOMMIT_DIR_BUDGET=$(( $(_guard_resolve_test_budget) / ${#GUARD_RUN_DIRS[@]} ))
[ "$PRECOMMIT_DIR_BUDGET" -lt 1 ] && PRECOMMIT_DIR_BUDGET=1

# Corre cada directorio resuelto arriba (uno solo, o varios derivados por
# segmento sin marcador arriba). Cualquier fallo bloquea nombrando el/los
# directorio(s) — se corren TODOS antes de decidir.
GUARD_FAILED_DIRS=()
for _guard_dir in "${GUARD_RUN_DIRS[@]}"; do
  _guard_run_suite_in "$_guard_dir" "$PRECOMMIT_DIR_BUDGET" || GUARD_FAILED_DIRS+=("$_guard_dir")
done

if [ "${#GUARD_FAILED_DIRS[@]}" -gt 0 ]; then
  echo "BLOCKED: Tests failed in: ${GUARD_FAILED_DIRS[*]}. Fix tests before committing." >&2
  exit 2
fi

exit 0
