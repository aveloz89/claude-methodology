#!/bin/bash
# Bloquea gh pr merge --admin que bypasea branch protections.
#
# Matching endurecido (#47): el match se sanea (spans quoted/heredoc) y se
# ancla a posición de comando en vez de al string completo — mismo helper
# que usa pre-merge-check.sh. Ver hooks/lib/guard-matching.sh.

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# shellcheck source=lib/guard-matching.sh
source "$(dirname "$0")/lib/guard-matching.sh"

SANITIZED_COMMAND=$(guard_sanitize "$COMMAND")

if echo "$SANITIZED_COMMAND" | grep -qE "${GUARD_ANCHOR}gh\s+pr\s+merge\b.*--admin"; then
  echo '{"decision":"block","reason":"Blocked: --admin bypasses branch protections. PRs must pass all required checks before merging."}'
  exit 0
fi

echo '{"continue":true}'
