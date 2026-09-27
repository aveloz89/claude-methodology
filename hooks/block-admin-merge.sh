#!/bin/bash
# Bloquea gh pr merge --admin que bypasea branch protections.
#
# hooks.json filtra la invocación con "if": "Bash(gh *)" — optimización de
# latencia, no reemplaza la validación de abajo, que sigue mirando el
# comando completo.
LIB="${0%/*}/lib/guard-matching.sh"
[ -r "$LIB" ] || { echo "BLOCKED: block-admin-merge no operativo: falta hooks/lib/guard-matching.sh" >&2; exit 2; }
# shellcheck source=lib/guard-matching.sh
source "$LIB"
guard_init "block-admin-merge"

# GUARD_GH_PR_MERGE_RE (lib) tolera hasta 2 tokens entre "gh"/"pr" y entre
# "pr"/"merge" — detecta "gh -R o/r pr merge --admin" y "gh pr -R o/r merge
# --admin" como la misma invocación real (#77 comentario 2, D3).
if echo "$SANITIZED_COMMAND" | grep -qE "${GUARD_ANCHOR}${GUARD_GH_PR_MERGE_RE}\b.*--admin"; then
  echo "BLOCKED: --admin bypasses branch protections. PRs must pass all required checks before merging." >&2
  exit 2
fi

exit 0
