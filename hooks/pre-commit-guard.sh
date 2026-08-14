#!/bin/bash
# Pre-commit guard: Detecta si Claude va a hacer git commit
# y verifica que los tests pasen primero.
# Recibe JSON en stdin con tool_input del comando Bash.
#
# Matching endurecido (#47): el match se sanea (spans quoted/heredoc) y se
# ancla a posición de comando en vez de al string completo — mismo helper
# que usa pre-merge-check.sh. Ver hooks/lib/guard-matching.sh.
#
# Fail-closed sin jq (cierra #50 para este guard): sin jq, el parseo de
# COMMAND más abajo devuelve vacío, el grep nunca matchea, y el guard
# pasaba en silencio — un commit pasaba sin correr tests. CAMBIA el
# contrato de este hook: antes, sin jq, pasaba.
if ! command -v jq > /dev/null 2>&1; then
  echo "BLOCKED: pre-commit-guard no operativo: falta jq" >&2
  exit 2
fi

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Resolución del path del lib sin depender de un binario externo (dirname):
# "${0%/*}" es el idioma de shell para dirname cuando $0 trae al menos un
# "/" — siempre el caso dado cómo el harness invoca los hooks. Fail-closed si
# el lib no existe o no es legible: un `source` fallido dejaría el resto
# del script corriendo con guard_sanitize()/GUARD_ANCHOR indefinidos, y el
# guard pasaría en silencio (mismo fail-open que #50). Mismo mecanismo de
# bloqueo que usa este hook para tests fallando: stderr + exit 2.
LIB="${0%/*}/lib/guard-matching.sh"
if [ ! -r "$LIB" ]; then
  echo "BLOCKED: pre-commit-guard no operativo: falta hooks/lib/guard-matching.sh" >&2
  exit 2
fi
# shellcheck source=lib/guard-matching.sh
source "$LIB"

SANITIZED_COMMAND=$(guard_sanitize "$COMMAND")

# Solo interceptar comandos git commit
if ! echo "$SANITIZED_COMMAND" | grep -qE "${GUARD_ANCHOR}git\s+commit"; then
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
