#!/bin/bash
# Pre-push guard: Previene push directo a main.
# Debe hacerse por PR.

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Solo interceptar git push
if ! echo "$COMMAND" | grep -qE '^\s*git\s+push'; then
  exit 0
fi

# Verificar si se está pusheando a main directamente (no como parte de un PR merge)
CURRENT_BRANCH=$(git branch --show-current 2>/dev/null)

if [ "$CURRENT_BRANCH" = "main" ] || [ "$CURRENT_BRANCH" = "master" ]; then
  # Permitir si es un merge desde dev (el último commit es un merge commit)
  if git log -1 --pretty=%s | grep -qiE '^Merge'; then
    exit 0
  fi
  echo "BLOCKED: No push directo a main. Usa un PR desde dev o feature branch." >&2
  exit 2
fi

exit 0
