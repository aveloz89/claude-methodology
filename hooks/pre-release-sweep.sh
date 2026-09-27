#!/bin/bash
# Bloquea PR a main si hay issues abiertos con label `latent-bug` y severidad
# CRÍTICO/CRITICAL que afecten archivos del diff. El agente latent-bugs-sweep
# crea esos issues; este hook verifica que no se mergeen archivos con bugs
# críticos pendientes.
#
# hooks.json filtra la invocación con "if": "Bash(gh *)" — optimización de
# latencia, no reemplaza la validación de abajo, que sigue mirando el
# comando completo.
#
# Contrato PreToolUse (auditoría best-practices): bloquear = stderr + exit
# 2, permitir = exit 0 sin stdout — igual que pre-push-guard.sh y pre-
# commit-guard.sh. Reemplaza el JSON {"decision":"block"}/{"continue":true}
# que este hook usaba antes.

# Fail-open si faltan dependencias: el hook no debe bloquear comandos cuando
# no puede ejecutarse correctamente.
if ! command -v jq >/dev/null 2>&1 || ! command -v gh >/dev/null 2>&1; then
  exit 0
fi

LIB="${0%/*}/lib/guard-matching.sh"
if [ ! -r "$LIB" ]; then
  echo "BLOCKED: pre-release-sweep no operativo: falta hooks/lib/guard-matching.sh" >&2
  exit 2
fi
# shellcheck source=lib/guard-matching.sh
source "$LIB"

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

SANITIZED_COMMAND=$(guard_sanitize "$COMMAND")

# Matching endurecido (D-07, #77, F): el match se sanea (spans quoted/
# heredoc) y se ancla a posición de comando en vez de exigir "gh pr create"
# al INICIO del string crudo — "cd . && gh pr create --base main" pasaba
# sin bloquear (F1). Acepta "--base main", "--base=main" y "-B main" (F2);
# el sufijo exige espacio/fin de string/separador de comando después de
# "main" para que "--base main-2" no matchee por un "\b" que solo mira el
# carácter siguiente (F3).
BASE_MAIN_RE="${GUARD_ANCHOR}gh\s+pr\s+create\b.*(--base[ =]main|-B\s+main)(\s|\$|[;&|])"
if ! echo "$SANITIZED_COMMAND" | grep -qE "$BASE_MAIN_RE"; then
  exit 0
fi

# Detectar archivos cambiados vs main
CHANGED_FILES=$(git diff --name-only origin/main...HEAD 2>/dev/null)
if [ -z "$CHANGED_FILES" ]; then
  exit 0
fi

# Listar issues abiertos con label latent-bug
ISSUES_JSON=$(gh issue list --label latent-bug --state open --json number,title,body --limit 100 2>/dev/null)
if [ -z "$ISSUES_JSON" ] || [ "$ISSUES_JSON" = "[]" ]; then
  exit 0
fi

# Buscar issues que mencionen archivos del diff con severidad CRÍTICO/CRITICAL
BLOCKING=""
while IFS= read -r file; do
  [ -z "$file" ] && continue
  MATCH=$(echo "$ISSUES_JSON" | jq -r --arg f "$file" '
    .[]
    | select((.body | contains($f)) and (.body | test("CRÍTICO|CRITICAL"; "i")))
    | "  - #\(.number): \(.title)"
  ' 2>/dev/null)
  if [ -n "$MATCH" ]; then
    BLOCKING="${BLOCKING}\n${file}:\n${MATCH}\n"
  fi
done <<< "$CHANGED_FILES"

if [ -n "$BLOCKING" ]; then
  REASON=$(printf "Blocked: PR a main bloqueado por bugs latentes CRÍTICOS abiertos en archivos del diff:%b\nResuelve los issues (fix + cerrar) o re-ejecuta latent-bugs-sweep para confirmar el estado actual antes de mergear a main." "$BLOCKING")
  echo "$REASON" >&2
  exit 2
fi

exit 0
