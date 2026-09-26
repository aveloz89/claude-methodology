#!/bin/bash
# Bloquea git push --force / -f que puede sobrescribir historia remota.
#
# Contrato PreToolUse (auditoría best-practices): bloquear = stderr + exit 2,
# permitir = exit 0 sin stdout — la doc prescribe exit 2 para hooks de
# policy, y ya es el mecanismo de pre-push-guard.sh/pre-commit-guard.sh.
#
# Ancla el match a posición de comando (mismo helper que pre-merge-check.sh,
# block-admin-merge.sh y pre-commit-guard.sh) para detectar el push real
# dentro de un comando compuesto, ej. "cd repo && git push --force" — antes
# el match exigía "git" al INICIO del string y ese caso pasaba sin bloquear.
# Ver hooks/lib/guard-matching.sh. Fail-closed si el lib no existe o no es
# legible: un `source` fallido dejaría guard_sanitize()/GUARD_ANCHOR
# indefinidos y el grep de abajo nunca matchearía — fail-open silencioso.
LIB="${0%/*}/lib/guard-matching.sh"
if [ ! -r "$LIB" ]; then
  echo "BLOCKED: block-force-push no operativo: falta hooks/lib/guard-matching.sh" >&2
  exit 2
fi
# shellcheck source=lib/guard-matching.sh
source "$LIB"

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

SANITIZED_COMMAND=$(guard_sanitize "$COMMAND")

if echo "$SANITIZED_COMMAND" | grep -qE "${GUARD_ANCHOR}git\s+push\s+.*(-f|--force)\b"; then
  echo "BLOCKED: --force push can overwrite remote history and bypass branch protections. Use normal push." >&2
  exit 2
fi

exit 0
