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

SANITIZED_COMMAND=$(guard_sanitize "$COMMAND")

# Solo interceptar git push (una mención quoted no cuenta, E2).
PUSH_RE="${GUARD_ANCHOR}git\s+push\b"
if ! echo "$SANITIZED_COMMAND" | grep -qE "$PUSH_RE"; then
  exit 0
fi

# Verificar si se está pusheando a main directamente (no como parte de un PR merge)
CURRENT_BRANCH=$(git branch --show-current 2>/dev/null)

if [ "$CURRENT_BRANCH" = "main" ] || [ "$CURRENT_BRANCH" = "master" ]; then
  # Permitir si es un merge desde dev (el último commit es un merge commit)
  if git log -1 --pretty=%s | grep -qiE '^Merge'; then
    exit 0
  fi
  echo "BLOCKED: No push directo a main. Usa un PR desde dev o feature branch." >&2
  exit 2
fi

exit 0
