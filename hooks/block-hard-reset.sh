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
#
# Fail-closed sin jq (mismo cierre que #50 en block-admin-merge.sh y
# pre-commit-guard.sh): sin jq, el parseo de COMMAND más abajo devuelve
# vacío, el grep nunca matchea, y un "git reset --hard" real pasaba en
# silencio. CAMBIA el contrato de este hook: antes, sin jq, pasaba.
if ! command -v jq > /dev/null 2>&1; then
  echo "BLOCKED: block-hard-reset no operativo: falta jq" >&2
  exit 2
fi

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
