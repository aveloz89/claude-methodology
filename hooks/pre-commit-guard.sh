#!/bin/bash
# Pre-commit guard: Detecta si Claude va a hacer git commit
# y verifica que los tests pasen primero.
# Recibe JSON en stdin con tool_input del comando Bash.

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Solo interceptar comandos git commit
if ! echo "$COMMAND" | grep -qE '^\s*git\s+commit'; then
  exit 0
fi

# Detectar el test runner del proyecto
if [ -f "package.json" ]; then
  # Node.js project — detectar package manager
  if [ -f "pnpm-lock.yaml" ]; then
    PKG_MGR="pnpm"
  elif [ -f "yarn.lock" ]; then
    PKG_MGR="yarn"
  else
    PKG_MGR="npm"
  fi

  if jq -e '.scripts.test' package.json > /dev/null 2>&1; then
    TEST_CMD=$(jq -r '.scripts.test' package.json)
    if [ "$TEST_CMD" != "null" ] && [ "$TEST_CMD" != "" ] && [ "$TEST_CMD" != "echo \"Error: no test specified\" && exit 1" ]; then
      echo "Running tests before commit ($PKG_MGR)..." >&2
      $PKG_MGR test 2>&1
      if [ $? -ne 0 ]; then
        echo "BLOCKED: Tests failed. Fix tests before committing." >&2
        exit 2
      fi
      echo "Tests passed." >&2
    fi
  fi
elif [ -f "pytest.ini" ] || [ -f "pyproject.toml" ] || [ -f "setup.py" ]; then
  # Python project
  if command -v pytest > /dev/null 2>&1; then
    echo "Running pytest before commit..." >&2
    pytest 2>&1
    if [ $? -ne 0 ]; then
      echo "BLOCKED: Tests failed. Fix tests before committing." >&2
      exit 2
    fi
    echo "Tests passed." >&2
  fi
fi

exit 0
