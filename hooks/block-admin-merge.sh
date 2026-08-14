#!/bin/bash
# Bloquea gh pr merge --admin que bypasea branch protections.
#
# Matching endurecido (#47): el match se sanea (spans quoted/heredoc) y se
# ancla a posición de comando en vez de al string completo — mismo helper
# que usa pre-merge-check.sh. Ver hooks/lib/guard-matching.sh.

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
  printf '{"decision":"block","reason":"block-admin-merge no operativo: falta hooks/lib/guard-matching.sh"}\n'
  exit 0
fi
# shellcheck source=lib/guard-matching.sh
source "$LIB"

SANITIZED_COMMAND=$(guard_sanitize "$COMMAND")

if echo "$SANITIZED_COMMAND" | grep -qE "${GUARD_ANCHOR}gh\s+pr\s+merge\b.*--admin"; then
  echo '{"decision":"block","reason":"Blocked: --admin bypasses branch protections. PRs must pass all required checks before merging."}'
  exit 0
fi

echo '{"continue":true}'
