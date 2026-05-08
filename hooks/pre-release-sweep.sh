#!/bin/bash
# Bloquea PR a main si hay issues abiertos con label `latent-bug` y severidad
# CRÍTICO/CRITICAL que afecten archivos del diff. El agente latent-bugs-sweep
# crea esos issues; este hook verifica que no se mergeen archivos con bugs
# críticos pendientes.

# Fail-open si faltan dependencias: el hook no debe bloquear comandos cuando
# no puede ejecutarse correctamente.
if ! command -v jq >/dev/null 2>&1 || ! command -v gh >/dev/null 2>&1; then
  echo '{"continue":true}'
  exit 0
fi

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Solo interceptar `gh pr create --base main` (acepta `--base main` y `--base=main`)
if ! echo "$COMMAND" | grep -qE '^\s*gh\s+pr\s+create\b.*--base[ =]main\b'; then
  echo '{"continue":true}'
  exit 0
fi

# Detectar archivos cambiados vs main
CHANGED_FILES=$(git diff --name-only origin/main...HEAD 2>/dev/null)
if [ -z "$CHANGED_FILES" ]; then
  echo '{"continue":true}'
  exit 0
fi

# Listar issues abiertos con label latent-bug
ISSUES_JSON=$(gh issue list --label latent-bug --state open --json number,title,body --limit 100 2>/dev/null)
if [ -z "$ISSUES_JSON" ] || [ "$ISSUES_JSON" = "[]" ]; then
  echo '{"continue":true}'
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
  echo "{\"decision\":\"block\",\"reason\":$(echo "$REASON" | jq -Rs .)}"
  exit 0
fi

echo '{"continue":true}'
