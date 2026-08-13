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
# función) para que siga resuelta en el momento del eval. run_path (opcional)
# override de PATH — usado para simular ausencia de un binario (p. ej. jq);
# si no se pasa, usa el PATH actual (sin cambio de comportamiento).
assert_exit0() {
  local test_name="$1"
  local hook_path="$2"
  local stdin_json="$3"
  local run_cwd="$4"
  local run_home="$5"
  local check_cmd="$6"
  local run_path="${7:-$PATH}"
  TOTAL=$((TOTAL + 1))

  local exit_code=0
  (cd "$run_cwd" 2>/dev/null && printf '%s' "$stdin_json" | HOME="$run_home" PATH="$run_path" bash "$hook_path" > /dev/null 2>&1) || exit_code=$?

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

# --- pre-compact-snapshot.sh ---
echo "--- pre-compact-snapshot.sh ---"

# snapshot_dir_for: encuentra el (único) directorio de snapshot que matchea
# un sufijo de trigger dado, bajo el slug del sandbox. Usado dentro de los
# check_cmd de assert_exit0 (eval'd, por eso vive como función global).
snapshot_dir_for() {
  find "$1/.claude/methodology/snapshots/$2" -maxdepth 1 -type d -name "$3" 2>/dev/null | head -1
}

# Caso: happy path — snapshot completo de .planning/ con meta.json correcto.
sandbox_create
SLUG=$(echo "$SANDBOX_REPO" | tr '/' '-')
assert_exit0 "PreCompact crea snapshot de .planning/ con meta.json" \
  "$HOOKS_DIR/pre-compact-snapshot.sh" \
  '{"trigger":"auto"}' \
  "$SANDBOX_REPO" \
  "$SANDBOX_HOME" \
  'DIR=$(snapshot_dir_for "$SANDBOX_HOME" "$SLUG" "*-auto") && [ -n "$DIR" ] && [ -f "$DIR/STATE.md" ] && [ -f "$DIR/DESIGN.md" ] && [ -f "$DIR/reviews/PR-1.md" ] && [ -f "$DIR/meta.json" ] && [ "$(jq -r .trigger "$DIR/meta.json")" = "auto" ] && [ "$(jq -r .repo "$DIR/meta.json")" = "$SANDBOX_REPO" ] && [ "$(jq -r .branch "$DIR/meta.json")" != "null" ] && [ "$(jq -r .head "$DIR/meta.json")" != "null" ]'
sandbox_cleanup

# Caso: JSON válido sin campo trigger — cae al fallback "unknown" (D4).
sandbox_create
SLUG=$(echo "$SANDBOX_REPO" | tr '/' '-')
assert_exit0 "PreCompact usa trigger=unknown si el campo no viene en el stdin" \
  "$HOOKS_DIR/pre-compact-snapshot.sh" \
  '{}' \
  "$SANDBOX_REPO" \
  "$SANDBOX_HOME" \
  'DIR=$(snapshot_dir_for "$SANDBOX_HOME" "$SLUG" "*-unknown") && [ -n "$DIR" ] && [ "$(jq -r .trigger "$DIR/meta.json")" = "unknown" ]'
sandbox_cleanup

# Caso: no-op limpio — sin .planning/ en un repo git válido. No debe crear
# ningún artefacto bajo ~/.claude/methodology/.
sandbox_create
rm -rf "$SANDBOX_REPO/.planning"
assert_exit0 "PreCompact no-op sin .planning/" \
  "$HOOKS_DIR/pre-compact-snapshot.sh" \
  '{"trigger":"auto"}' \
  "$SANDBOX_REPO" \
  "$SANDBOX_HOME" \
  '[ ! -e "$SANDBOX_HOME/.claude" ]'
sandbox_cleanup

# Caso: no-op limpio — fuera de cualquier repo git.
NO_GIT_DIR=$(mktemp -d)
NO_GIT_DIR=$(cd "$NO_GIT_DIR" && pwd -P)
NO_GIT_HOME=$(mktemp -d)
NO_GIT_HOME=$(cd "$NO_GIT_HOME" && pwd -P)
mkdir -p "$NO_GIT_DIR/.planning"
echo "# STATE" > "$NO_GIT_DIR/.planning/STATE.md"
assert_exit0 "PreCompact no-op fuera de repo git" \
  "$HOOKS_DIR/pre-compact-snapshot.sh" \
  '{"trigger":"auto"}' \
  "$NO_GIT_DIR" \
  "$NO_GIT_HOME" \
  '[ ! -e "$NO_GIT_HOME/.claude" ]'
rm -rf "$NO_GIT_DIR" "$NO_GIT_HOME"

# Caso: no-op limpio — stdin vacío.
sandbox_create
assert_exit0 "PreCompact no-op con stdin vacío" \
  "$HOOKS_DIR/pre-compact-snapshot.sh" \
  '' \
  "$SANDBOX_REPO" \
  "$SANDBOX_HOME" \
  '[ ! -e "$SANDBOX_HOME/.claude" ]'
sandbox_cleanup

# Caso: no-op limpio — stdin con JSON malformado.
sandbox_create
assert_exit0 "PreCompact no-op con stdin malformado" \
  "$HOOKS_DIR/pre-compact-snapshot.sh" \
  '{not valid json' \
  "$SANDBOX_REPO" \
  "$SANDBOX_HOME" \
  '[ ! -e "$SANDBOX_HOME/.claude" ]'
sandbox_cleanup

# Caso: retención — con 6 snapshots preexistentes para el slug, tras invocar
# (que crea uno nuevo, el 7mo) quedan exactamente los 5 más recientes:
# el nuevo + los 4 más recientes de los 6 preexistentes.
sandbox_create
SLUG=$(echo "$SANDBOX_REPO" | tr '/' '-')
RETENTION_ROOT="$SANDBOX_HOME/.claude/methodology/snapshots/$SLUG"
mkdir -p "$RETENTION_ROOT"
for n in 1 2 3 4 5 6; do
  mkdir -p "$RETENTION_ROOT/2026010${n}-000000-manual"
  echo '{}' > "$RETENTION_ROOT/2026010${n}-000000-manual/meta.json"
done
assert_exit0 "PreCompact retención conserva solo los 5 snapshots más recientes" \
  "$HOOKS_DIR/pre-compact-snapshot.sh" \
  '{"trigger":"auto"}' \
  "$SANDBOX_REPO" \
  "$SANDBOX_HOME" \
  '[ "$(ls -1 "$RETENTION_ROOT" | wc -l | tr -d " ")" = "5" ] && [ ! -d "$RETENTION_ROOT/20260101-000000-manual" ] && [ ! -d "$RETENTION_ROOT/20260102-000000-manual" ] && [ -d "$RETENTION_ROOT/20260103-000000-manual" ] && [ -d "$RETENTION_ROOT/20260106-000000-manual" ] && [ -n "$(snapshot_dir_for "$SANDBOX_HOME" "$SLUG" "*-auto")" ]'
sandbox_cleanup

echo ""

# --- subagent-stop-log.sh ---
echo "--- subagent-stop-log.sh ---"

# Caso: happy path — línea JSONL válida con los 6 campos del contrato D2.
sandbox_create
assert_exit0 "SubagentStop appendea línea JSONL con los campos del contrato" \
  "$HOOKS_DIR/subagent-stop-log.sh" \
  '{"agent_type":"backend-dev","session_id":"sess-1","agent_transcript_path":"/tmp/transcript.jsonl"}' \
  "$SANDBOX_REPO" \
  "$SANDBOX_HOME" \
  'LOG="$SANDBOX_HOME/.claude/methodology/logs/subagent-invocations.jsonl"; [ -f "$LOG" ] && [ "$(jq -r .agent "$LOG")" = "backend-dev" ] && [ "$(jq -r .session "$LOG")" = "sess-1" ] && [ "$(jq -r .repo "$LOG")" = "$SANDBOX_REPO" ] && [ "$(jq -r .branch "$LOG")" != "null" ] && [ "$(jq -r .transcript "$LOG")" = "/tmp/transcript.jsonl" ] && [ "$(jq -r .ts "$LOG")" != "null" ]'
sandbox_cleanup

# Caso: agent_type ausente — cae al fallback .subagent_type.
sandbox_create
assert_exit0 "SubagentStop usa subagent_type si agent_type no viene" \
  "$HOOKS_DIR/subagent-stop-log.sh" \
  '{"subagent_type":"qa-backend"}' \
  "$SANDBOX_REPO" \
  "$SANDBOX_HOME" \
  '[ "$(jq -r .agent "$SANDBOX_HOME/.claude/methodology/logs/subagent-invocations.jsonl")" = "qa-backend" ]'
sandbox_cleanup

# Caso: ni agent_type ni subagent_type — cae a "unknown".
sandbox_create
assert_exit0 "SubagentStop usa agent=unknown si no viene ningún campo" \
  "$HOOKS_DIR/subagent-stop-log.sh" \
  '{"session_id":"sess-2"}' \
  "$SANDBOX_REPO" \
  "$SANDBOX_HOME" \
  '[ "$(jq -r .agent "$SANDBOX_HOME/.claude/methodology/logs/subagent-invocations.jsonl")" = "unknown" ]'
sandbox_cleanup

# Caso: stdin malformado — exit 0 y NUNCA appendea una línea corrupta.
sandbox_create
assert_exit0 "SubagentStop no-op con stdin malformado (sin appendear nada)" \
  "$HOOKS_DIR/subagent-stop-log.sh" \
  '{not valid json' \
  "$SANDBOX_REPO" \
  "$SANDBOX_HOME" \
  '[ ! -e "$SANDBOX_HOME/.claude/methodology/logs/subagent-invocations.jsonl" ]'
sandbox_cleanup

# Caso: stdin vacío — mismo no-op limpio.
sandbox_create
assert_exit0 "SubagentStop no-op con stdin vacío" \
  "$HOOKS_DIR/subagent-stop-log.sh" \
  '' \
  "$SANDBOX_REPO" \
  "$SANDBOX_HOME" \
  '[ ! -e "$SANDBOX_HOME/.claude/methodology/logs/subagent-invocations.jsonl" ]'
sandbox_cleanup

# Caso: jq ausente en PATH — exit 0, sin appendear nada. PATH restringido a
# un directorio con symlinks solo a los binarios que el hook necesita además
# de jq (git, date, mkdir, stat, mv, cat), para que la ausencia sea real y no
# un efecto colateral de romper otra dependencia.
sandbox_create
NO_JQ_BIN=$(mktemp -d)
for cmd in bash git date mkdir stat mv cat; do
  CMD_PATH=$(command -v "$cmd" 2>/dev/null)
  [ -n "$CMD_PATH" ] && ln -s "$CMD_PATH" "$NO_JQ_BIN/$cmd"
done
assert_exit0 "SubagentStop exit 0 sin jq en PATH (sin appendear nada)" \
  "$HOOKS_DIR/subagent-stop-log.sh" \
  '{"agent_type":"backend-dev"}' \
  "$SANDBOX_REPO" \
  "$SANDBOX_HOME" \
  '[ ! -e "$SANDBOX_HOME/.claude/methodology/logs/subagent-invocations.jsonl" ]' \
  "$NO_JQ_BIN"
rm -rf "$NO_JQ_BIN"
sandbox_cleanup

# Caso: rotación — un log preexistente >1MB se archiva a .old (pisando el
# .old anterior) y la línea nueva queda en un archivo fresco.
sandbox_create
ROTATION_LOG_DIR="$SANDBOX_HOME/.claude/methodology/logs"
mkdir -p "$ROTATION_LOG_DIR"
head -c 1100000 /dev/zero | tr '\0' 'x' > "$ROTATION_LOG_DIR/subagent-invocations.jsonl"
echo "MARKER_FOR_OLD" >> "$ROTATION_LOG_DIR/subagent-invocations.jsonl"
echo "PREVIOUS_OLD_MARKER" > "$ROTATION_LOG_DIR/subagent-invocations.jsonl.old"
assert_exit0 "SubagentStop rota el log a .old al superar 1MB" \
  "$HOOKS_DIR/subagent-stop-log.sh" \
  '{"agent_type":"backend-dev"}' \
  "$SANDBOX_REPO" \
  "$SANDBOX_HOME" \
  'LOG="$ROTATION_LOG_DIR/subagent-invocations.jsonl"; OLD="$LOG.old"; [ -f "$OLD" ] && grep -q "MARKER_FOR_OLD" "$OLD" && ! grep -q "PREVIOUS_OLD_MARKER" "$OLD" && [ "$(wc -l < "$LOG" | tr -d " ")" = "1" ] && [ "$(jq -r .agent "$LOG")" = "backend-dev" ]'
sandbox_cleanup

echo ""

# --- Resumen ---
echo "=== Results ==="
echo -e "Total: $TOTAL | ${GREEN}Pass: $PASS${NC} | ${RED}Fail: $FAIL${NC}"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
