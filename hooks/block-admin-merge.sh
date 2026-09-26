#!/bin/bash
# Bloquea gh pr merge --admin que bypasea branch protections.
#
# hooks.json filtra la invocación con "if": "Bash(gh *)" — optimización de
# latencia, no reemplaza la validación de abajo, que sigue mirando el
# comando completo.
#
# Matching endurecido (#47): el match se sanea (spans quoted/heredoc) y se
# ancla a posición de comando en vez de al string completo — mismo helper
# que usa pre-merge-check.sh. Ver hooks/lib/guard-matching.sh.
#
# Contrato PreToolUse (auditoría best-practices): bloquear = stderr + exit
# 2, permitir = exit 0 sin stdout — igual que pre-push-guard.sh y pre-
# commit-guard.sh. Reemplaza el JSON {"decision":"block"}/{"continue":true}
# que este hook usaba antes.
#
# Fail-closed sin jq (cierra #50 para este guard): sin jq, el parseo de
# COMMAND más abajo devuelve vacío, el grep nunca matchea, y el guard
# pasaba en silencio — cualquier --admin pasaba sin bloquear. CAMBIA el
# contrato de este hook: antes, sin jq, pasaba.
if ! command -v jq > /dev/null 2>&1; then
  echo "BLOCKED: block-admin-merge no operativo: falta jq" >&2
  exit 2
fi

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Resolución del path del lib sin depender de un binario externo (dirname):
# "${0%/*}" es el idioma de shell para dirname cuando $0 trae al menos un
# "/" — siempre el caso dado cómo el harness invoca los hooks. Fail-closed si
# el lib no existe o no es legible: un `source` fallido dejaría el resto
# del script corriendo con guard_sanitize()/GUARD_ANCHOR indefinidos, y el
# guard pasaría en silencio (mismo fail-open que #50).
LIB="${0%/*}/lib/guard-matching.sh"
if [ ! -r "$LIB" ]; then
  echo "BLOCKED: block-admin-merge no operativo: falta hooks/lib/guard-matching.sh" >&2
  exit 2
fi
# shellcheck source=lib/guard-matching.sh
source "$LIB"

SANITIZED_COMMAND=$(guard_sanitize "$COMMAND")

if echo "$SANITIZED_COMMAND" | grep -qE "${GUARD_ANCHOR}gh\s+pr\s+merge\b.*--admin"; then
  echo "BLOCKED: --admin bypasses branch protections. PRs must pass all required checks before merging." >&2
  exit 2
fi

exit 0
