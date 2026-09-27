#!/bin/bash
# Pre-push guard: Previene push directo a main.
# Debe hacerse por PR.
#
# hooks.json filtra la invocación con "if": "Bash(git *)" — optimización de
# latencia, no reemplaza la validación de abajo, que sigue mirando el
# comando completo.
#
# Matching endurecido (D-07, #77): el match se sanea (spans quoted/heredoc)
# y se ancla a posición de comando en vez de "^\s*git\s+push" sobre el
# comando crudo — mismo helper que los demás guards de git. Ver
# hooks/lib/guard-matching.sh. Antes, "git commit -m x && git push origin
# main" o "npm test && git push" pasaban sin bloquear porque el match
# exigía "git push" al INICIO del string.
#
# Fail-closed sin jq y sin lib (mismo cierre que #50 en los otros guards de
# git): sin jq, COMMAND queda vacío y un push real a main pasaba en
# silencio.
if ! command -v jq > /dev/null 2>&1; then
  echo "BLOCKED: pre-push-guard no operativo: falta jq" >&2
  exit 2
fi

LIB="${0%/*}/lib/guard-matching.sh"
if [ ! -r "$LIB" ]; then
  echo "BLOCKED: pre-push-guard no operativo: falta hooks/lib/guard-matching.sh" >&2
  exit 2
fi
# shellcheck source=lib/guard-matching.sh
source "$LIB"

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
INPUT_CWD=$(echo "$INPUT" | jq -r '.cwd // empty')

# NUL en el comando (#77 §3): ver guard_command_has_nul en guard-matching.sh
# para por qué se detecta sobre $INPUT y no sobre $COMMAND.
if guard_command_has_nul "$INPUT"; then
  echo "BLOCKED: pre-push-guard: el comando trae un byte NUL" >&2
  exit 2
fi

SANITIZED_COMMAND=$(guard_sanitize "$COMMAND")

# Solo interceptar git push (una mención quoted no cuenta, E2). Tolera
# opciones de árbol ("git -C <ruta> push") y prefijo de entorno
# ("GIT_DIR=... git push") entre el ancla y "push": esas formas SÍ son un
# push real y tienen que llegar al chequeo de redirección de abajo, no
# salir en 0 sin evaluarlas.
# GUARD_GIT_GLOBAL_OPTS (D-07, review dual ronda 1) tolera "-c <k=v>"/
# "--no-pager" antes de "push" — sin esto, "git -c user.name=x push origin
# main" no matcheaba y un push real a main pasaba SIN EVALUAR (exit 0) en
# vez de bloquear por ser push directo a main. Ver hooks/lib/guard-matching.sh.
PUSH_RE="${GUARD_ANCHOR}((GIT_DIR|GIT_WORK_TREE)=\S*\s+)*git\s+${GUARD_GIT_GLOBAL_OPTS}${GUARD_GIT_TREE_OPTS}push\b"
if ! echo "$SANITIZED_COMMAND" | grep -qE "$PUSH_RE"; then
  exit 0
fi

# pre-push-guard no resuelve a qué árbol redirige el comando (D-07, punto
# 4): a diferencia de pre-commit-guard, este hook no tiene una allowlist de
# formas ("cd <ruta> && …" / "git -C <ruta> …") — el push lo hace el
# orchestrator desde el cwd de la sesión, no hay forma honesta que necesite
# pushear a OTRO árbol del que ya está trabajando. Cualquier redirección
# bloquea con este mensaje en vez de adivinar a qué árbol apunta.
REDIRECT_HELP="pre-push-guard no resuelve redirecciones; hacé el cd en una llamada previa (el hook sigue el cwd de la sesión)."
CD_PUSHD_RE="${GUARD_ANCHOR}(cd|pushd)(\s|;|&&|\$)"
if echo "$SANITIZED_COMMAND" | grep -qE "$CD_PUSHD_RE" \
  || echo "$SANITIZED_COMMAND" | grep -qE '(^|[[:space:]])-C([[:space:]=]|$)' \
  || echo "$SANITIZED_COMMAND" | grep -qE -- '--git-dir|--work-tree' \
  || echo "$SANITIZED_COMMAND" | grep -qE '(^|[[:space:]]|;|&&|\|)(GIT_DIR|GIT_WORK_TREE)=' \
  || [ -n "${GIT_DIR:-}" ] || [ -n "${GIT_WORK_TREE:-}" ]; then
  echo "BLOCKED: $REDIRECT_HELP" >&2
  exit 2
fi

# Branch desde ".cwd" del input (mismo criterio que pre-commit-guard, #73):
# BASE_DIR es el árbol de la SESIÓN, no el cwd del proceso del hook —
# ambos coinciden salvo que ".cwd" venga de una llamada Bash previa distinta
# del cwd real del proceso.
if [ -n "$INPUT_CWD" ] && [ -d "$INPUT_CWD" ]; then
  BASE_DIR=$(cd "$INPUT_CWD" && pwd -P)
else
  BASE_DIR=$(pwd -P)
fi

# Verificar si se está pusheando a main directamente (no como parte de un PR merge)
CURRENT_BRANCH=$(git -C "$BASE_DIR" branch --show-current 2>/dev/null)

if [ "$CURRENT_BRANCH" = "main" ] || [ "$CURRENT_BRANCH" = "master" ]; then
  # Permitir si es un merge desde dev (el último commit es un merge commit)
  if git -C "$BASE_DIR" log -1 --pretty=%s | grep -qiE '^Merge'; then
    exit 0
  fi
  echo "BLOCKED: No push directo a main. Usa un PR desde dev o feature branch." >&2
  exit 2
fi

exit 0
