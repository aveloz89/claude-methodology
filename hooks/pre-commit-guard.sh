#!/bin/bash
# Pre-commit guard: detecta si Claude va a hacer git commit y corre los
# tests del árbol correspondiente antes de dejarlo pasar.
# Recibe JSON en stdin con tool_input del comando Bash.
#
# hooks.json registra este guard SIN "if" (decisión del usuario, ronda 1 de
# review): corre en cada Bash, también con un wrapper, un if/then o un backtick
# delante de git. La validación de abajo mira el comando completo saneado
# (spans quoted/heredoc) y anclado a posición de comando — mismo helper que
# pre-merge-check.sh (hooks/lib/guard-matching.sh); sin "git" sale 0.
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
# TEMPORAL (Lote 2 de suite-on-push): la lógica de suite vive en
# hooks/lib/suite-runner.sh (guard_suite_run); este guard solo detecta el
# commit, resuelve el árbol y la llama. El Lote 3 lo elimina.
#
# Preámbulo común (guard_init, hooks/lib/guard-matching.sh): fail-closed sin
# jq ni grep, lee INPUT/COMMAND/INPUT_CWD, bloquea ante un byte NUL y deja
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
GIT_COMMIT_RE="${GUARD_ANCHOR}${GUARD_ENV_PREFIX}git\s+${GUARD_GIT_OPTS}commit(\s|\$|[;&|)])"
if ! echo "$SANITIZED_COMMAND" | grep -qE "$GIT_COMMIT_RE"; then
  exit 0
fi

SUITE_LIB="${0%/*}/lib/suite-runner.sh"
[ -r "$SUITE_LIB" ] || { echo "BLOCKED: pre-commit-guard no operativo: falta hooks/lib/suite-runner.sh" >&2; exit 2; }
# shellcheck source=lib/suite-runner.sh
source "$SUITE_LIB"


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
if echo "$SANITIZED_COMMAND" | grep -qE "${GUARD_ANCHOR}${GUARD_ENV_PREFIX}git\s+${GUARD_GIT_OPTS}-C\s"; then
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

guard_suite_run "$SESSION_DIR" "$TARGET_DIR"
exit 0
