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
# (suite roja, o marcador Python sin runner) bloquea nombrando los
# directorios; sin candidatos —ningún marcador— pasa sin correr nada.
#
# Runner Python (rama pytest.ini/pyproject.toml/setup.py): orden cerrado, el
# primero que aplica corre con cwd = directorio del marcador y bajo el mismo
# watchdog/budget que el runner Node:
#   1. uv   — uv.lock o una tabla [tool.uv…] en pyproject.toml, Y "uv" en el
#             PATH del hook → "uv run --frozen pytest" (D-02: --frozen nunca
#             reescribe uv.lock durante el commit).
#   2. venv — .venv/bin/pytest o .venv/Scripts/pytest.exe (Windows /
#             git-bash). Gana al "pytest" del PATH: un pytest global en un
#             proyecto con venv corre con el intérprete equivocado.
#   3. PATH — "pytest" del PATH.
# Ninguno aplica → exit 2 nombrando el directorio y las tres vías (D-01:
# fail-closed, el hook no pasa en silencio por no encontrar runner). Sin
# NINGÚN marcador sigue pasando: "sin marcador" no es "marcador sin runner".
# uv declarado pero "uv" fuera del PATH del hook no bloquea por sí solo: cae
# a los pasos 2 y 3.
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
# Limitaciones aceptadas del runner Python:
#   1. Workspace uv: uv.lock, [tool.uv…] y .venv se buscan SOLO en el
#      directorio del marcador, no suben hasta el toplevel (un directorio =
#      un proyecto = un runner, como el lockfile junto al package.json en
#      Node). Un miembro de workspace sin [tool.uv…] propio ni .venv local
#      bloquea con el mensaje de las tres vías; sin tocar el hook se
#      resuelve declarando [tool.uv] en su pyproject.toml, activando el venv
#      del workspace (así "pytest" queda en el PATH) o con un .venv local.
#   2. "[ tool.uv ]" con espacios dentro de los corchetes y claves entre
#      comillas no se detectan como uv.
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
#
# El prefijo de asignación es CUALQUIER "NOMBRE=valor" (identificador de
# entorno válido), no solo GIT_DIR/GIT_WORK_TREE (ronda 1 review, security
# MEDIUM): "HUSKY=0 git commit -m x" o "GIT_AUTHOR_NAME=bot git commit -m
# x" antes solo se toleraban con esos dos nombres exactos, así que
# cualquier OTRA asignación de entorno al frente del comando no matcheaba
# GIT_COMMIT_RE y el commit real pasaba de largo en la línea 65 (exit 0)
# sin correr tests. GIT_DIR/GIT_WORK_TREE como prefijo siguen bloqueando
# igual que hoy: los detecta, más abajo, el check dedicado de las líneas
# 97-99, que corre sobre el mismo SANITIZED_COMMAND una vez que este regex
# ya interceptó el comando.
# "env" opcional antepuesto a las asignaciones (ronda 2 review, security
# LOW): "env HUSKY=0 git commit" o "env -i HUSKY=0 git commit" no
# matcheaban porque el regex solo toleraba "NOMBRE=valor" pegado
# directamente a "git" — el binario "env" (con o sin flags cortas, ej.
# "-i") de por medio dejaba pasar el commit real sin correr tests.
GIT_COMMIT_RE="${GUARD_ANCHOR}(env(\s+-\S+)*\s+)?([A-Za-z_][A-Za-z0-9_]*=\S*\s+)*git\s+${GUARD_GIT_OPTS}commit(\s|\$|[;&|)])"
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

# _guard_pyproject_declares_uv <dir>: true si <dir>/pyproject.toml tiene una
# tabla [tool.uv] o [tool.uv.<sub>] al inicio de línea. "(\]|\.)" evita que
# [tool.uvicorn] cuente como uv. Fuera de alcance (documentado): "[ tool.uv ]"
# con espacios dentro de los corchetes y claves entre comillas.
_guard_pyproject_declares_uv() {
  [ -f "$1/pyproject.toml" ] && grep -qE '^[[:space:]]*\[tool\.uv(\]|\.)' "$1/pyproject.toml"
}

# _guard_resolve_python_runner <dir>: deja en GUARD_PY_RUNNER (array, nunca
# string — rules/bash.md) el comando a ejecutar con cwd=<dir>. Si devuelve 1
# deja en GUARD_PY_RUNNER_REASON (una oración sin punto final) por qué no hay
# runner; el loop final la anota junto al directorio. Orden cerrado:
#   1. uv   — uv.lock presente Y "uv" en el PATH del hook → "uv run --frozen
#             pytest" (D-02: --frozen nunca reescribe uv.lock durante el
#             commit). [tool.uv…] sin uv.lock NO es trigger: "--frozen" sin lock
#             falla siempre (rc 1, "Unable to find lockfile") y además crea
#             .venv/ (D-05).
#   2. venv — <dir>/.venv/bin/pytest o <dir>/.venv/Scripts/pytest.exe
#             (Windows / git-bash), archivo regular Y ejecutable ([ -f ] &&
#             [ -x ]: un directorio con ese nombre pasa -x; verificado). Gana
#             al pytest del PATH: un pytest global en un proyecto con venv
#             corre con el intérprete equivocado.
#   3. entorno propio declarado sin runner → bloquea con razón específica;
#             NUNCA cae al pytest del PATH (D-04): un proyecto que declara su
#             entorno no se verifica con el intérprete global. Precedencia de
#             la razón: a. uv.lock presente (uv fuera del PATH, venv sin
#             pytest); b. [tool.uv…] sin uv.lock (pide "uv sync", D-05);
#             c. .venv/ existe sin pytest ejecutable.
#   4. PATH — "pytest" del PATH, solo para proyectos sin entorno declarado.
#   5. nada → razón genérica con las tres vías (D-01).
_guard_resolve_python_runner() {
  local dir="$1" venv_pytest
  GUARD_PY_RUNNER=()
  GUARD_PY_RUNNER_REASON=""
  if [ -f "$dir/uv.lock" ] && command -v uv > /dev/null 2>&1; then
    GUARD_PY_RUNNER=(uv run --frozen pytest)
    return 0
  fi
  for venv_pytest in "$dir/.venv/bin/pytest" "$dir/.venv/Scripts/pytest.exe"; do
    if [ -f "$venv_pytest" ] && [ -x "$venv_pytest" ]; then
      GUARD_PY_RUNNER=("$venv_pytest")
      return 0
    fi
  done
  if [ -f "$dir/uv.lock" ]; then
    GUARD_PY_RUNNER_REASON="uv.lock presente pero 'uv' no está en el PATH del hook y .venv/ no tiene pytest: exporta uv al PATH (p. ej. ~/.local/bin o /opt/homebrew/bin) o crea el venv con 'uv sync'"
    return 1
  fi
  if _guard_pyproject_declares_uv "$dir"; then
    GUARD_PY_RUNNER_REASON="uv declarado sin uv.lock: corre 'uv sync' para crear uv.lock y .venv/ (el hook no invoca uv sin lock; en un workspace, activa el venv de la raíz o crea un .venv local)"
    return 1
  fi
  if [ -d "$dir/.venv" ]; then
    GUARD_PY_RUNNER_REASON=".venv/ existe sin pytest ejecutable (.venv/bin/pytest o .venv/Scripts/pytest.exe): instala pytest en ese venv ('uv sync' o '.venv/bin/pip install pytest')"
    return 1
  fi
  if command -v pytest > /dev/null 2>&1; then
    GUARD_PY_RUNNER=(pytest)
    return 0
  fi
  GUARD_PY_RUNNER_REASON="Resuélvelo con una de: (1) uv — uv.lock ('uv sync') y 'uv' en el PATH del hook; (2) venv local — .venv/bin/pytest o .venv/Scripts/pytest.exe; (3) 'pytest' en el PATH"
  return 1
}

# _guard_node_has_test_script: el package.json del cwd declara un script
# "test" usable — ni ausente/null, ni vacío, ni el placeholder de "npm init".
# Sin script usable, el package.json no "tapa" un marcador Python del mismo
# directorio (D-06: package.json de tooling + pyproject.toml, legacy).
_guard_node_has_test_script() {
  local test_cmd
  test_cmd=$(jq -r '.scripts.test // empty' package.json 2>/dev/null)
  [ -n "$test_cmd" ] && [ "$test_cmd" != "echo \"Error: no test specified\" && exit 1" ]
}

# Centinela de "marcador Python sin runner". 127 = convención "command not
# found"; NUNCA viene del runner: el rc de la suite se colapsa a 0/1 en
# _guard_run_suite_in. Verificado en macOS (bash 3.2): un script con
# "#!/usr/bin/env python" sin python en el PATH sale con 127 y, sin la
# normalización, se reportaría como "sin runner" en vez de "suite roja".
GUARD_RC_NO_RUNNER=127

# _guard_run_suite_in <dir> <budget>: detecta y corre el runner de UN
# directorio con el budget que le tocó. Devuelve 0 (nada que correr, o corrió
# y pasó), 1 (la suite falló: cualquier rc != 0 del runner) o
# GUARD_RC_NO_RUNNER (marcador Python sin runner). Nunca hace "exit" salvo el
# watchdog de _guard_run_with_budget: con más de un directorio el resto corre
# igual antes de decidir.
_guard_run_suite_in() {
  local dir="$1" budget="$2"
  local prev_pwd no_runner=0
  prev_pwd=$(pwd)
  cd "$dir" || return 1

  local rc=0
  if [ -f "package.json" ] && _guard_node_has_test_script; then
    local pkg_mgr
    if [ -f "pnpm-lock.yaml" ]; then
      pkg_mgr="pnpm"
    elif [ -f "yarn.lock" ]; then
      pkg_mgr="yarn"
    else
      pkg_mgr="npm"
    fi

    echo "Running tests before commit ($pkg_mgr) [$dir]..." >&2
    _guard_run_with_budget "$budget" "$pkg_mgr" test
    rc=$?
    [ "$rc" -eq 0 ] && echo "Tests passed [$dir]." >&2
  elif [ -f "pytest.ini" ] || [ -f "pyproject.toml" ] || [ -f "setup.py" ]; then
    if _guard_resolve_python_runner "$dir"; then
      echo "Running ${GUARD_PY_RUNNER[*]} before commit [$dir]..." >&2
      _guard_run_with_budget "$budget" "${GUARD_PY_RUNNER[@]}"
      rc=$?
      [ "$rc" -eq 0 ] && echo "Tests passed [$dir]." >&2
    else
      echo "No Python test runner [$dir]." >&2
      no_runner=1
    fi
  fi

  cd "$prev_pwd" || true
  [ "$no_runner" -eq 1 ] && return "$GUARD_RC_NO_RUNNER"
  [ "$rc" -ne 0 ] && return 1
  return 0
}

# Presupuesto por directorio: se divide en partes iguales entre los
# directorios a correr (división entera, mínimo 1) para que la SUMA de las
# corridas nunca supere PRECOMMIT_TEST_BUDGET sin estado compartido.
PRECOMMIT_DIR_BUDGET=$(( $(_guard_resolve_test_budget) / ${#GUARD_RUN_DIRS[@]} ))
[ "$PRECOMMIT_DIR_BUDGET" -lt 1 ] && PRECOMMIT_DIR_BUDGET=1

# Corre cada directorio resuelto arriba (uno solo, o varios derivados por
# segmento sin marcador arriba). Cualquier fallo —suite roja o marcador
# Python sin runner— bloquea nombrando el/los directorio(s); se corren TODOS
# antes de decidir.
GUARD_FAILED_DIRS=()
GUARD_NO_RUNNER_DIRS=()
GUARD_NO_RUNNER_REASONS=() # mismo índice que GUARD_NO_RUNNER_DIRS (bash 3.2: sin arrays asociativos)
for _guard_dir in "${GUARD_RUN_DIRS[@]}"; do
  _guard_run_suite_in "$_guard_dir" "$PRECOMMIT_DIR_BUDGET"
  _guard_rc=$?
  case "$_guard_rc" in
    0) ;;
    "$GUARD_RC_NO_RUNNER")
      GUARD_NO_RUNNER_DIRS+=("$_guard_dir")
      GUARD_NO_RUNNER_REASONS+=("$GUARD_PY_RUNNER_REASON") ;;
    *) GUARD_FAILED_DIRS+=("$_guard_dir") ;;
  esac
done

if [ "${#GUARD_FAILED_DIRS[@]}" -gt 0 ]; then
  echo "BLOCKED: Tests failed in: ${GUARD_FAILED_DIRS[*]}. Fix tests before committing." >&2
fi
_guard_i=0
while [ "$_guard_i" -lt "${#GUARD_NO_RUNNER_DIRS[@]}" ]; do
  echo "BLOCKED: pre-commit-guard no encontró un runner de pytest en: ${GUARD_NO_RUNNER_DIRS[$_guard_i]}. ${GUARD_NO_RUNNER_REASONS[$_guard_i]}. El hook no falla abierto." >&2
  _guard_i=$((_guard_i + 1))
done
if [ "${#GUARD_FAILED_DIRS[@]}" -gt 0 ] || [ "${#GUARD_NO_RUNNER_DIRS[@]}" -gt 0 ]; then
  exit 2
fi

exit 0
