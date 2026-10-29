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
# como el mismo reset real. GUARD_ENV_PREFIX tolera "VAR=valor git reset
# --hard" (#121); con el valor entre comillas el saneo deja el placeholder Q.
# "--hard" no tiene que ir pegado a "reset": git acepta otras opciones antes
# ("reset -q --hard"), el commit antes ("reset HEAD~1 --hard") y cualquier
# prefijo único de la opción larga (--h, --ha, --har; medido con git 2.54: los
# tres resetean igual que --hard). Se busca en el segmento hasta el primer &, ;
# o | (GUARD_SEGMENT_END: el & de una redirección 2>&1, >&2 o &>log no corta,
# #118) y como token completo ("--hard=x" lo rechaza git, "--hard-notes.md" es
# una ruta); el token cierra también en ; & | (git reset --hard;).
if echo "$SANITIZED_COMMAND" | grep -qE "${GUARD_ANCHOR}${GUARD_ENV_PREFIX}git\s+${GUARD_GIT_OPTS}reset\s+(${GUARD_SEGMENT_END}[[:space:]])?--h(a(rd?)?)?(${GUARD_TOKEN_END}|[;&|])"; then
  echo "BLOCKED: git reset --hard descarta cambios irreversiblemente. Usa git stash o git reset --soft." >&2
  exit 2
fi

exit 0
