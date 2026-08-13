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

# Ruta absoluta a hooks/, calculada desde la ubicación del script: los tests
# de sandbox hacen `cd` a repos git temporales, así que una ruta relativa
# como "hooks" dejaría de resolver en cuanto cambia el cwd.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HOOKS_DIR="$REPO_ROOT/hooks"
PASS=0
FAIL=0
TOTAL=0

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

# --- Infraestructura de sandbox para hooks no-bloqueantes ---
# (PreCompact, SubagentStop, SessionEnd: no interceptan comandos, reaccionan
# a eventos del ciclo de vida y escriben artefactos bajo $HOME/.claude/.)
#
# sandbox_create: crea un repo git temporal con .planning/ poblado
# (SANDBOX_REPO) y un HOME aislado (SANDBOX_HOME) para que los hooks nunca
# toquen ~/.claude/methodology/ real durante los tests. Variables globales
# (no locales) para que assert_exit0 y los checks de cada test las lean.
sandbox_create() {
  # pwd -P resuelve symlinks (en macOS mktemp -d devuelve /var/folders/...
  # pero /var es symlink a /private/var; git rev-parse --show-toplevel
  # normaliza al path real). Sin esto, comparar SANDBOX_REPO contra lo que
  # el hook resuelve internamente falla por un prefijo distinto.
  SANDBOX_REPO=$(mktemp -d)
  SANDBOX_REPO=$(cd "$SANDBOX_REPO" && pwd -P)
  SANDBOX_HOME=$(mktemp -d)
  SANDBOX_HOME=$(cd "$SANDBOX_HOME" && pwd -P)
  (
    cd "$SANDBOX_REPO" || exit 1
    git init -q
    git config user.email "sandbox@example.com"
    git config user.name "Sandbox"
    mkdir -p .planning/reviews
    echo "# STATE" > .planning/STATE.md
    echo "# DESIGN" > .planning/DESIGN.md
    echo "# Review" > .planning/reviews/PR-1.md
    git add -A
    git commit -q -m "initial commit"
  ) > /dev/null 2>&1
}

sandbox_cleanup() {
  rm -rf "$SANDBOX_REPO" "$SANDBOX_HOME"
}

# assert_exit0: corre un hook no-bloqueante dentro del sandbox (cwd=run_cwd,
# HOME=run_home) con el stdin dado, y verifica exit 0 + un efecto esperado
# (o su ausencia) en filesystem. check_cmd es una expresión shell que se
# evalúa con `eval`; debe referenciar variables globales (no locales de otra
# función) para que siga resuelta en el momento del eval.
assert_exit0() {
  local test_name="$1"
  local hook_path="$2"
  local stdin_json="$3"
  local run_cwd="$4"
  local run_home="$5"
  local check_cmd="$6"
  TOTAL=$((TOTAL + 1))

  local exit_code=0
  (cd "$run_cwd" 2>/dev/null && printf '%s' "$stdin_json" | HOME="$run_home" bash "$hook_path" > /dev/null 2>&1) || exit_code=$?

  if [ "$exit_code" -ne 0 ]; then
    echo -e "${RED}FAIL${NC}: $test_name (exit code: $exit_code, expected: 0)"
    FAIL=$((FAIL + 1))
    return
  fi

  if eval "$check_cmd"; then
    echo -e "${GREEN}PASS${NC}: $test_name"
    PASS=$((PASS + 1))
  else
    echo -e "${RED}FAIL${NC}: $test_name (exit 0 pero el efecto esperado en filesystem no se cumple)"
    FAIL=$((FAIL + 1))
  fi
}

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

# --- pre-merge-check.sh ---
echo "--- pre-merge-check.sh ---"

# pre-merge-check.sh responde con {"decision":"block",...} o {"continue":true}
# en el JSON de stdout (siempre exit 0) — no usa exit code 2 como los demás
# hooks, por eso usa helpers propios en vez de assert_blocked/assert_allowed.
# Además llama a gh internamente, así que estos tests reemplazan gh en el
# PATH por un fake determinístico (sin red) que responde según $FAKE_GH_MODE.

FAKE_GH_DIR=$(mktemp -d)
cat > "$FAKE_GH_DIR/gh" <<'FAKE_GH_EOF'
#!/bin/bash
# Fake gh para tests de pre-merge-check.sh: nunca toca la red.
case "$1 $2" in
  "repo view")
    [ "$FAKE_GH_MODE" = "offline" ] && exit 1
    echo "owner/repo"
    ;;
  "pr view")
    echo '{"reviewDecision":null}'
    ;;
  "api graphql")
    echo '{"data":{"repository":{"pullRequest":{"reviewThreads":{"nodes":[]}}}}}'
    ;;
  "pr checks")
    case "$FAKE_GH_MODE" in
      checks_none)
        echo "no checks reported on the 'feature/x' branch" >&2
        exit 1
        ;;
      checks_fail)
        echo "gh: unexpected error connecting to api.github.com" >&2
        exit 1
        ;;
      *)
        printf 'some-check\tpass\t1s\n'
        ;;
    esac
    ;;
  *)
    exit 1
    ;;
esac
FAKE_GH_EOF
chmod +x "$FAKE_GH_DIR/gh"

assert_pre_merge_continue() {
  local test_name="$1" cmd="$2" fake_gh_mode="${3:-}"
  TOTAL=$((TOTAL + 1))
  local json output
  json=$(jq -n --arg cmd "$cmd" '{tool_input: {command: $cmd}}')
  output=$(echo "$json" | PATH="$FAKE_GH_DIR:$PATH" FAKE_GH_MODE="$fake_gh_mode" bash "$HOOKS_DIR/pre-merge-check.sh" 2>/dev/null)

  if echo "$output" | grep -q '"continue":true'; then
    echo -e "${GREEN}PASS${NC}: $test_name (continue as expected)"
    PASS=$((PASS + 1))
  else
    echo -e "${RED}FAIL${NC}: $test_name (output: $output)"
    FAIL=$((FAIL + 1))
  fi
}

assert_pre_merge_blocked() {
  local test_name="$1" cmd="$2" expected_substring="$3" fake_gh_mode="${4:-}"
  TOTAL=$((TOTAL + 1))
  local json output
  json=$(jq -n --arg cmd "$cmd" '{tool_input: {command: $cmd}}')
  output=$(echo "$json" | PATH="$FAKE_GH_DIR:$PATH" FAKE_GH_MODE="$fake_gh_mode" bash "$HOOKS_DIR/pre-merge-check.sh" 2>/dev/null)

  if echo "$output" | grep -q '"decision":"block"' && echo "$output" | grep -qF "$expected_substring"; then
    echo -e "${GREEN}PASS${NC}: $test_name (blocked with expected reason)"
    PASS=$((PASS + 1))
  else
    echo -e "${RED}FAIL${NC}: $test_name (output: $output)"
    FAIL=$((FAIL + 1))
  fi
}

# Caso 1: mención de la frase de merge dentro de un heredoc (mensaje de
# commit), sin dígitos — debe continuar (no es una invocación real).
HEREDOC_MENTION_COMMAND=$(cat <<'CMD_EOF'
git commit -m "$(cat <<'EOF'
hooks: aclarar mensaje de bloqueo por PR sin numero

Antes el guard bloqueaba cualquier comando cuyo texto mencionara la frase
gh pr merge sin numero explicito, incluso dentro de un heredoc como este.
EOF
)"
CMD_EOF
)
assert_pre_merge_continue "Commit heredoc mentioning merge phrase (no digits)" "$HEREDOC_MENTION_COMMAND" "offline"

# Caso 1b: la misma mención, pero con un número dentro del heredoc — antes
# el guard terminaba validando un PR sin relación con el comando real.
HEREDOC_MENTION_WITH_NUMBER_COMMAND=$(cat <<'CMD_EOF'
git commit -m "$(cat <<'EOF'
hooks: agregar ejemplo de uso al mensaje

Ejemplo de invocacion real (no ejecutada, solo referencia en el mensaje):
gh pr merge 12
EOF
)"
CMD_EOF
)
assert_pre_merge_continue "Commit heredoc mentioning merge phrase (with digits)" "$HEREDOC_MENTION_WITH_NUMBER_COMMAND" "offline"

# Caso 2: invocación real con número — debe entrar a validación (llega a
# intentar detectar el repo vía gh, prueba de que el número se extrajo bien).
assert_pre_merge_blocked "Real merge invocation with number enters validation" "gh pr merge 45" "PR #45" "offline"

# Caso 3: invocación real sin número — debe bloquear por número faltante,
# sin llegar siquiera a llamar a gh.
assert_pre_merge_blocked "Real merge invocation without number blocks" "gh pr merge --squash" "sin número de PR explícito" "offline"

# Caso 4: comando compuesto con el merge real después de && — debe entrar a
# validación igual que el caso 2 (antes, el gate solo miraba el inicio del
# string completo y esto pasaba sin validar: falso negativo).
assert_pre_merge_blocked "Compound command with merge after && enters validation" "git fetch && gh pr merge 12" "PR #12" "offline"

# Caso 5a: PR sin checks configurados (repo sin CI) — es un pass legítimo,
# no debe bloquear.
assert_pre_merge_continue "No CI checks configured does not block" "gh pr merge 45" "checks_none"

# Caso 5b: la consulta de checks falla de verdad (no es el caso "sin
# checks") — sigue bloqueando fail-closed.
assert_pre_merge_blocked "Genuine CI checks query failure still blocks" "gh pr merge 45" "no pude consultar los CI checks" "checks_fail"

rm -rf "$FAKE_GH_DIR"

echo ""

# --- Sandbox infra para hooks no-bloqueantes (PreCompact, SubagentStop, SessionEnd) ---
echo "--- sandbox infra ---"

# Caso trivial: usa sandbox_create/sandbox_cleanup + assert_exit0 con un hook
# ya existente (context-monitor.sh, siempre exit 0 y sin efectos en
# filesystem) para probar la infraestructura de sandbox en sí misma, sin
# depender de un hook todavía no implementado.
sandbox_create
assert_exit0 "Sandbox trivial: context-monitor.sh no crea nada en el sandbox" \
  "$HOOKS_DIR/context-monitor.sh" \
  '{}' \
  "$SANDBOX_REPO" \
  "$SANDBOX_HOME" \
  '[ ! -e "$SANDBOX_HOME/.claude" ]'
sandbox_cleanup

echo ""

# --- Resumen ---
echo "=== Results ==="
echo -e "Total: $TOTAL | ${GREEN}Pass: $PASS${NC} | ${RED}Fail: $FAIL${NC}"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
