#!/bin/bash
# Bloquea git push --force / -f que puede sobrescribir historia remota.
#
# hooks.json filtra la invocación con "if": "Bash(git *)" — optimización de
# latencia, no reemplaza la validación de abajo, que sigue mirando el
# comando completo.
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
#
# Fail-closed sin jq (mismo cierre que #50 en block-admin-merge.sh y
# pre-commit-guard.sh): sin jq, el parseo de COMMAND más abajo devuelve
# vacío, el grep nunca matchea, y un "git push --force" real pasaba en
# silencio. CAMBIA el contrato de este hook: antes, sin jq, pasaba.
if ! command -v jq > /dev/null 2>&1; then
  echo "BLOCKED: block-force-push no operativo: falta jq" >&2
  exit 2
fi

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

FORCE_PATTERN="${GUARD_ANCHOR}git\s+push\s+.*(-f|--force)\b"

if echo "$SANITIZED_COMMAND" | grep -qE "$FORCE_PATTERN"; then
  echo "BLOCKED: --force push can overwrite remote history and bypass branch protections. Use normal push." >&2
  exit 2
fi

# Regresión (auditoría best-practices): guard_sanitize() borra el contenido
# de CUALQUIER span quoted por diseño (#47) — pero un flag real que el
# shell recibe igual con o sin comillas (ej. `git push origin "--force"`)
# es una invocación real, no texto literal, y el saneo lo deja
# indistinguible de una mención dentro de un mensaje de commit. Se
# compensa grepeando también el comando SIN sanear, con el mismo anclaje a
# posición de comando: una mención dentro de `-m "..."` no queda precedida
# por uno de los separadores de GUARD_ANCHOR (lo que la precede es la
# comilla de apertura o texto del propio mensaje), así que el caso de #47
# ("git commit -m \"... git push --force ...\"") sigue sin bloquear.
# Limitación aceptada, igual que el resto de guard_sanitize(): heurística
# de texto, no un parser de shell real — un mensaje que a propósito incluya
# un separador real (ej. "; git push --force") antes de la mención
# bloquearía por esta vía.
if echo "$COMMAND" | grep -qE "$FORCE_PATTERN"; then
  echo "BLOCKED: --force push can overwrite remote history and bypass branch protections. Use normal push." >&2
  exit 2
fi

exit 0
