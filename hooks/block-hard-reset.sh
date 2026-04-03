#!/bin/bash
# Bloquea git reset --hard que descarta cambios irreversiblemente.

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

if echo "$COMMAND" | grep -qE '^\s*git\s+reset\s+--hard'; then
  echo '{"decision":"block","reason":"Blocked: git reset --hard descarta cambios irreversiblemente. Usa git stash o git reset --soft."}'
  exit 0
fi

echo '{"continue":true}'
