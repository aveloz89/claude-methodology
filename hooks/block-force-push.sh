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

# NUL en el comando (#77 §3): ver guard_command_has_nul en guard-matching.sh
# para por qué se detecta sobre $INPUT y no sobre $COMMAND.
if guard_command_has_nul "$INPUT"; then
  echo "BLOCKED: block-force-push: el comando trae un byte NUL" >&2
  exit 2
fi

SANITIZED_COMMAND=$(guard_sanitize "$COMMAND")

# #77 comentario 2: un refspec forzado (+<ref>, ej. "git push origin
# +main") es equivalente a --force y antes pasaba sin bloquear.
FORCE_PATTERN="${GUARD_ANCHOR}git\s+push\s+.*((-f|--force)\b|\s\+[^\s:]+)"

if echo "$SANITIZED_COMMAND" | grep -qE "$FORCE_PATTERN"; then
  echo "BLOCKED: --force push can overwrite remote history and bypass branch protections. Use normal push." >&2
  exit 2
fi

# Regresión (auditoría best-practices): guard_sanitize() borra el contenido
# de CUALQUIER span quoted por diseño (#47) — pero un flag real que el
# shell recibe igual con o sin comillas (ej. `git push origin "--force"`)
# es una invocación real, no texto literal, y el saneo lo deja
# indistinguible de una mención dentro de un mensaje de commit.
#
# Ronda 2 (revisión pre-push, security LOW): la versión anterior compensaba
# grepeando el patrón COMPLETO (git push + flag SIN comillas) sobre el
# comando sin sanear, con el mismo GUARD_ANCHOR de siempre — pero
# GUARD_ANCHOR no sabe de comillas, así que cualquier separador real (";",
# salto de línea) que aparezca DENTRO de un span quoted/heredoc lo ancla
# igual. Reproducido en vivo: un heredoc que solo mencionaba "git push
# --force" en su cuerpo (para escribir este mismo registro) quedaba
# bloqueado, igual que un mensaje de commit con ";" antes de la mención o
# un `gh pr create --body "..."` citándola.
#
# Fix: separar "hay una invocación real de git push" (ya resuelto arriba,
# sobre el comando SANEADO — guard_sanitize() borra spans quoted y cuerpos
# de heredoc enteros, así que una mención ahí dentro desaparece del texto
# saneado por completo, sin dejar ningún "git push" para anclar) de "esa
# invocación trae la flag entre comillas" (que solo puede verse en el
# comando SIN sanear, porque el saneo es justo lo que la borra). Bloquear
# solo si AMBAS condiciones se cumplen: el comando saneado tiene un "git
# push" anclado en posición de comando (invocación real, no texto dentro de
# un span borrado), y el comando sin sanear contiene la flag envuelta en
# comillas en algún punto. Limitación aceptada, igual que el resto de
# guard_sanitize(): heurística de texto, no un parser de shell real — una
# coincidencia de `"--force"` citada tal cual dentro de un mensaje, junto a
# un push real sin force en el mismo comando compuesto, bloquearía por esta
# vía.
PUSH_ANCHORED_PATTERN="${GUARD_ANCHOR}git\s+push\b"
QUOTED_FORCE_PATTERN="[\"'](-f|--force(-with-lease(=[^\"']*)?)?)[\"']"

if echo "$SANITIZED_COMMAND" | grep -qE "$PUSH_ANCHORED_PATTERN" \
  && echo "$COMMAND" | grep -qE "$QUOTED_FORCE_PATTERN"; then
  echo "BLOCKED: --force push can overwrite remote history and bypass branch protections. Use normal push." >&2
  exit 2
fi

exit 0
