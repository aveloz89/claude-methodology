#!/bin/bash
# Bloquea gh pr merge --admin que bypasea branch protections.

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

if echo "$COMMAND" | grep -qE 'gh\s+pr\s+merge\b.*--admin'; then
  echo '{"decision":"block","reason":"Blocked: --admin bypasses branch protections. PRs must pass all required checks before merging."}'
  exit 0
fi

echo '{"continue":true}'
