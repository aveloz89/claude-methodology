#!/bin/bash
# Bloquea git reset --hard que descarta cambios irreversiblemente.
#
# hooks.json filtra la invocación con "if": "Bash(git *)" — optimización de
# latencia, no reemplaza la validación de abajo, que sigue mirando el
# comando completo.
LIB="${0%/*}/lib/guard-matching.sh"
[ -r "$LIB" ] || { echo "BLOCKED: block-hard-reset no operativo: falta hooks/lib/guard-matching.sh" >&2; exit 2; }
# shellcheck source=lib/guard-matching.sh
source "$LIB"
guard_init "block-hard-reset"

# GUARD_GIT_OPTS (lib) tolera, en cualquier orden, "-C <ruta>",
# "-c <k=v>"/"--no-pager"/"-P" antes de "reset" — así "git -c
# user.name=x reset --hard" y "git -C /x -c a=b reset --hard" matchean
# como el mismo reset real.
if echo "$SANITIZED_COMMAND" | grep -qE "${GUARD_ANCHOR}git\s+${GUARD_GIT_OPTS}reset\s+--hard"; then
  echo "BLOCKED: git reset --hard descarta cambios irreversiblemente. Usa git stash o git reset --soft." >&2
  exit 2
fi

exit 0
