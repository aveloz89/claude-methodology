#!/bin/bash
# Adversarial tests for Claude Code hooks
# Verifica que los hooks bloquean los comandos peligrosos correctamente.
#
# Uso: bash tests/adversarial/test-hooks.sh
#
# Los hooks de Claude Code reciben JSON por stdin con el formato:
#   { "tool_input": { "command": "..." } }
# Y retornan exit code 2 para bloquear.

set -e

HOOKS_DIR="hooks"
PASS=0
FAIL=0
TOTAL=0

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

assert_blocked() {
  local test_name="$1"
  local hook="$2"
  local command="$3"
  TOTAL=$((TOTAL + 1))

  local json="{\"tool_input\": {\"command\": \"$command\"}}"
  local exit_code=0
  echo "$json" | bash "$HOOKS_DIR/$hook" > /dev/null 2>&1 || exit_code=$?

  if [ "$exit_code" -eq 2 ]; then
    echo -e "${GREEN}PASS${NC}: $test_name (blocked as expected)"
    PASS=$((PASS + 1))
  else
    echo -e "${RED}FAIL${NC}: $test_name (exit code: $exit_code, expected: 2)"
    FAIL=$((FAIL + 1))
  fi
}

assert_allowed() {
  local test_name="$1"
  local hook="$2"
  local command="$3"
  TOTAL=$((TOTAL + 1))

  local json="{\"tool_input\": {\"command\": \"$command\"}}"
  local exit_code=0
  echo "$json" | bash "$HOOKS_DIR/$hook" > /dev/null 2>&1 || exit_code=$?

  if [ "$exit_code" -eq 0 ]; then
    echo -e "${GREEN}PASS${NC}: $test_name (allowed as expected)"
    PASS=$((PASS + 1))
  else
    echo -e "${RED}FAIL${NC}: $test_name (exit code: $exit_code, expected: 0)"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== Adversarial Hook Tests ==="
echo ""

# --- pre-push-guard.sh ---
echo "--- pre-push-guard.sh ---"

# Para testear push a main, necesitamos estar en main temporalmente
ORIGINAL_BRANCH=$(git branch --show-current)

# Test: push desde feature branch (debe permitirse)
assert_allowed "Push from feature branch" "pre-push-guard.sh" "git push origin feature/test"

# Test: comandos no-push (debe permitirse)
assert_allowed "Non-push command passes through" "pre-push-guard.sh" "git status"

# Test: push a main desde main (debe bloquearse si no es merge commit)
# Solo correr si podemos cambiar de branch temporalmente
if git stash --include-untracked -q 2>/dev/null; then
  git checkout main -q 2>/dev/null
  LAST_MSG=$(git log -1 --pretty=%s)
  if echo "$LAST_MSG" | grep -qiE '^Merge'; then
    # El último commit en main es un merge — el hook lo permite (correcto).
    # Creamos un commit temporal non-merge para testear el bloqueo.
    git commit --allow-empty -m "test: non-merge commit" -q 2>/dev/null
    assert_blocked "Push from main (non-merge commit)" "pre-push-guard.sh" "git push origin main"
    git reset --soft HEAD~1 -q 2>/dev/null
  else
    assert_blocked "Push from main branch" "pre-push-guard.sh" "git push origin main"
  fi
  git checkout "$ORIGINAL_BRANCH" -q 2>/dev/null
  git stash pop -q 2>/dev/null || true
fi

echo ""

# --- pre-commit-guard.sh ---
echo "--- pre-commit-guard.sh ---"

# Test: non-commit command (debe permitirse)
assert_allowed "Non-commit command passes through" "pre-commit-guard.sh" "git status"
assert_allowed "Git diff passes through" "pre-commit-guard.sh" "git diff"

# Nota: el test de commit bloqueado depende de que haya un test runner configurado
# en el proyecto. En este repo (methodology) no hay package.json ni pytest,
# así que el hook permite el commit (no encuentra test runner).
assert_allowed "Commit in repo without test runner passes through" "pre-commit-guard.sh" "git commit -m 'test'"

echo ""

# --- Resumen ---
echo "=== Results ==="
echo -e "Total: $TOTAL | ${GREEN}Pass: $PASS${NC} | ${RED}Fail: $FAIL${NC}"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
