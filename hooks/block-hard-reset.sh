#!/bin/bash
# Bloquea git reset --hard que descarta cambios irreversiblemente.
#
# hooks.json filtra la invocación con "if": "Bash(git *)" — optimización de
# latencia, no reemplaza la validación de abajo, que sigue mirando el
# comando completo.
#
# Contrato PreToolUse (auditoría best-practices): bloquear = stderr + exit 2,
# permitir = exit 0 sin stdout. Ver hooks/block-force-push.sh para el mismo
# cambio y el porqué de anclar con hooks/lib/guard-matching.sh (detecta el
# reset real dentro de un comando compuesto, ej. "cd repo && git reset
# --hard", que antes pasaba sin bloquear).
LIB="${0%/*}/lib/guard-matching.sh"
if [ ! -r "$LIB" ]; then
  echo "BLOCKED: block-hard-reset no operativo: falta hooks/lib/guard-matching.sh" >&2
  exit 2
fi
# shellcheck source=lib/guard-matching.sh
source "$LIB"

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

SANITIZED_COMMAND=$(guard_sanitize "$COMMAND")

if echo "$SANITIZED_COMMAND" | grep -qE "${GUARD_ANCHOR}git\s+reset\s+--hard"; then
  echo "BLOCKED: git reset --hard descarta cambios irreversiblemente. Usa git stash o git reset --soft." >&2
  exit 2
fi

exit 0
