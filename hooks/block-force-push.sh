#!/bin/bash
# Bloquea git push --force / -f que puede sobrescribir historia remota.

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

if echo "$COMMAND" | grep -qE '^\s*git\s+push\s+.*(-f|--force)\b'; then
  echo '{"decision":"block","reason":"Blocked: --force push can overwrite remote history and bypass branch protections. Use normal push."}'
  exit 0
fi

echo '{"continue":true}'
