#!/bin/bash
# Adversarial tests for the plugin manifests (.claude-plugin/, hooks/hooks.json).
#
# Verifica:
#   (a) paridad hooks/*.sh <-> hooks/hooks.json — cada script (excluyendo
#       hooks/lib/) debe estar registrado EXACTAMENTE una vez. Mata la clase
#       de bug C5 "hook documentado pero no instalado".
#   (b) los 3 manifests (plugin.json, marketplace.json, hooks.json) parsean
#       como JSON válido.
#   (c) si la CLI `claude` está en PATH: `claude plugin validate --strict .`
#       pasa (con marketplace.json presente valida solo el marketplace) y
#       `claude plugin validate --strict .claude-plugin/plugin.json` pasa
#       (valida el plugin en sí, incluido el CLAUDE.md del repo); si la CLI
#       no está, SKIP declarado (el test crítico —la paridad— no depende
#       de la CLI).
#
# Uso: bash tests/adversarial/test-plugin-manifest.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HOOKS_DIR="$REPO_ROOT/hooks"
PLUGIN_JSON="$REPO_ROOT/.claude-plugin/plugin.json"
MARKETPLACE_JSON="$REPO_ROOT/.claude-plugin/marketplace.json"
HOOKS_JSON="$REPO_ROOT/hooks/hooks.json"

PASS=0
FAIL=0
TOTAL=0

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

# count_hook_registrations: cuenta cuántas veces aparece <script_name> como
# basename de un "command" dentro de <hooks_json>. `.. | .command? // empty`
# recorre el árbol completo sin asumir la forma exacta de cada evento, así
# que sigue funcionando aunque un evento tenga varios matchers. `|| true`
# neutraliza el exit code no-cero que `grep -c` da con 0 matches (grep sigue
# imprimiendo "0"), necesario bajo `set -e`.
count_hook_registrations() {
  local hooks_json="$1"
  local script_name="$2"
  local n
  n=$(jq -r '.. | .command? // empty' "$hooks_json" 2>/dev/null \
    | sed 's#.*/##' \
    | grep -c -x -- "$script_name" || true)
  echo "$n"
}

echo "--- Paridad hooks/*.sh <-> hooks/hooks.json ---"

for script_path in "$HOOKS_DIR"/*.sh; do
  script_name="$(basename "$script_path")"
  count=$(count_hook_registrations "$HOOKS_JSON" "$script_name")
  TOTAL=$((TOTAL + 1))
  if [ "$count" -eq 1 ]; then
    echo -e "${GREEN}PASS${NC}: $script_name registrado exactamente 1 vez en hooks.json"
    PASS=$((PASS + 1))
  else
    echo -e "${RED}FAIL${NC}: $script_name registrado $count veces en hooks.json (esperado 1)"
    FAIL=$((FAIL + 1))
  fi
done

echo ""
echo "--- Sandbox: el check de paridad detecta un hook ausente ---"

# Demuestra que el check no es tautológico: sobre una copia corrupta de
# hooks.json (sin tocar el archivo real), borrar una entrada debe bajar su
# conteo a 0. Esta es la demostración de RED que pide el diseño — el RED se
# ejecuta contra un sandbox, nunca contra hooks/hooks.json real.
SANDBOX_HOOKS_JSON=$(mktemp)
jq 'del(.hooks.PreToolUse[0].hooks[0])' "$HOOKS_JSON" > "$SANDBOX_HOOKS_JSON"
missing_count=$(count_hook_registrations "$SANDBOX_HOOKS_JSON" "block-admin-merge.sh")
TOTAL=$((TOTAL + 1))
if [ "$missing_count" -eq 0 ]; then
  echo -e "${GREEN}PASS${NC}: el check detecta block-admin-merge.sh ausente en un hooks.json corrupto (sandbox)"
  PASS=$((PASS + 1))
else
  echo -e "${RED}FAIL${NC}: el check no detectó la ausencia de block-admin-merge.sh en el sandbox corrupto (conteo: $missing_count)"
  FAIL=$((FAIL + 1))
fi
rm -f "$SANDBOX_HOOKS_JSON"

echo ""
echo "--- Los 3 manifests parsean como JSON válido ---"

for f in "$PLUGIN_JSON" "$MARKETPLACE_JSON" "$HOOKS_JSON"; do
  label="$(basename "$(dirname "$f")")/$(basename "$f")"
  TOTAL=$((TOTAL + 1))
  if jq empty "$f" > /dev/null 2>&1; then
    echo -e "${GREEN}PASS${NC}: $label parsea como JSON válido"
    PASS=$((PASS + 1))
  else
    echo -e "${RED}FAIL${NC}: $label NO parsea como JSON válido"
    FAIL=$((FAIL + 1))
  fi
done

echo ""
echo "--- hooks.json: if por handler, matcher de SessionStart, timeout de pre-commit-guard ---"

# assert_hook_if: verifica el campo "if" de la entrada de hooks.json cuyo
# "command" termina en <script_name> — optimización de latencia (verificación
# e del diseño): cada script sigue validando el comando completo, "if" solo
# evita invocar el hook cuando ni siquiera aparece el token de comando.
assert_hook_if() {
  local script_name="$1"
  local expected_if="$2"
  local actual
  actual=$(jq -r --arg name "$script_name" \
    '.hooks.PreToolUse[].hooks[] | select(.command | endswith($name)) | .if // "MISSING"' \
    "$HOOKS_JSON")
  TOTAL=$((TOTAL + 1))
  if [ "$actual" = "$expected_if" ]; then
    echo -e "${GREEN}PASS${NC}: $script_name tiene if=\"$expected_if\""
    PASS=$((PASS + 1))
  else
    echo -e "${RED}FAIL${NC}: $script_name tiene if=\"$actual\" (esperado \"$expected_if\")"
    FAIL=$((FAIL + 1))
  fi
}

assert_hook_if "block-force-push.sh" "Bash(git *)"
assert_hook_if "block-hard-reset.sh" "Bash(git *)"
assert_hook_if "pre-push-guard.sh" "Bash(git *)"
assert_hook_if "pre-commit-guard.sh" "Bash(git *)"
assert_hook_if "block-admin-merge.sh" "Bash(gh *)"
assert_hook_if "pre-merge-check.sh" "Bash(gh *)"
assert_hook_if "pre-release-sweep.sh" "Bash(gh *)"

TOTAL=$((TOTAL + 1))
SESSION_START_MATCHER=$(jq -r '.hooks.SessionStart[0].matcher' "$HOOKS_JSON")
if [ "$SESSION_START_MATCHER" = "startup|resume|clear|compact" ]; then
  echo -e "${GREEN}PASS${NC}: SessionStart.matcher es \"startup|resume|clear|compact\""
  PASS=$((PASS + 1))
else
  echo -e "${RED}FAIL${NC}: SessionStart.matcher es \"$SESSION_START_MATCHER\" (esperado \"startup|resume|clear|compact\")"
  FAIL=$((FAIL + 1))
fi

TOTAL=$((TOTAL + 1))
PCG_TIMEOUT=$(jq -r '.hooks.PreToolUse[].hooks[] | select(.command | endswith("pre-commit-guard.sh")) | .timeout' "$HOOKS_JSON")
if [ "$PCG_TIMEOUT" = "600" ]; then
  echo -e "${GREEN}PASS${NC}: pre-commit-guard.sh tiene timeout=600"
  PASS=$((PASS + 1))
else
  echo -e "${RED}FAIL${NC}: pre-commit-guard.sh tiene timeout=$PCG_TIMEOUT (esperado 600)"
  FAIL=$((FAIL + 1))
fi

echo ""
echo "--- global/CLAUDE.md: la suite de tests bloquea el commit, no corre en background ---"

GLOBAL_CLAUDE_MD="$REPO_ROOT/global/CLAUDE.md"

TOTAL=$((TOTAL + 1))
if grep -q "^\*\*Bloquean el comando:\*\*.*commit sin" "$GLOBAL_CLAUDE_MD"; then
  echo -e "${GREEN}PASS${NC}: \"Bloquean el comando\" incluye el commit sin suite verde"
  PASS=$((PASS + 1))
else
  echo -e "${RED}FAIL${NC}: \"Bloquean el comando\" no menciona el commit sin suite verde"
  FAIL=$((FAIL + 1))
fi

TOTAL=$((TOTAL + 1))
if grep -q "^\*\*Corren en background:\*\*.*tests antes de cada commit" "$GLOBAL_CLAUDE_MD"; then
  echo -e "${RED}FAIL${NC}: \"Corren en background\" todavía menciona los tests antes de cada commit (deberían bloquear, no correr en background)"
  FAIL=$((FAIL + 1))
else
  echo -e "${GREEN}PASS${NC}: \"Corren en background\" ya no menciona los tests antes de cada commit"
  PASS=$((PASS + 1))
fi

echo ""
echo "--- skills/orchestrator/SKILL.md: existe, tamaño y frontmatter ---"

ORCHESTRATOR_SKILL="$REPO_ROOT/skills/orchestrator/SKILL.md"

TOTAL=$((TOTAL + 1))
if [ -f "$ORCHESTRATOR_SKILL" ]; then
  echo -e "${GREEN}PASS${NC}: skills/orchestrator/SKILL.md existe"
  PASS=$((PASS + 1))
else
  echo -e "${RED}FAIL${NC}: skills/orchestrator/SKILL.md no existe"
  FAIL=$((FAIL + 1))
fi

if [ -f "$ORCHESTRATOR_SKILL" ]; then
  TOTAL=$((TOTAL + 1))
  SKILL_LINES=$(wc -l < "$ORCHESTRATOR_SKILL" | tr -d ' ')
  if [ "$SKILL_LINES" -lt 500 ]; then
    echo -e "${GREEN}PASS${NC}: skills/orchestrator/SKILL.md tiene $SKILL_LINES líneas (< 500)"
    PASS=$((PASS + 1))
  else
    echo -e "${RED}FAIL${NC}: skills/orchestrator/SKILL.md tiene $SKILL_LINES líneas (esperado < 500)"
    FAIL=$((FAIL + 1))
  fi

  TOTAL=$((TOTAL + 1))
  if grep -q "^name: orchestrator$" "$ORCHESTRATOR_SKILL"; then
    echo -e "${GREEN}PASS${NC}: frontmatter tiene name: orchestrator"
    PASS=$((PASS + 1))
  else
    echo -e "${RED}FAIL${NC}: frontmatter no tiene name: orchestrator"
    FAIL=$((FAIL + 1))
  fi

  TOTAL=$((TOTAL + 1))
  if grep -q "^disable-model-invocation:" "$ORCHESTRATOR_SKILL"; then
    echo -e "${RED}FAIL${NC}: skills/orchestrator/SKILL.md tiene disable-model-invocation (debe poder cargarse sola)"
    FAIL=$((FAIL + 1))
  else
    echo -e "${GREEN}PASS${NC}: skills/orchestrator/SKILL.md no tiene disable-model-invocation"
    PASS=$((PASS + 1))
  fi

  TOTAL=$((TOTAL + 1))
  if grep -q "^user-invocable: true$" "$ORCHESTRATOR_SKILL"; then
    echo -e "${GREEN}PASS${NC}: frontmatter tiene user-invocable: true"
    PASS=$((PASS + 1))
  else
    echo -e "${RED}FAIL${NC}: frontmatter no tiene user-invocable: true"
    FAIL=$((FAIL + 1))
  fi
fi

echo ""
echo "--- global/CLAUDE.md: tamaño del núcleo tras la división ---"

TOTAL=$((TOTAL + 1))
GLOBAL_BYTES=$(wc -c < "$GLOBAL_CLAUDE_MD" | tr -d ' ')
if [ "$GLOBAL_BYTES" -le 10240 ]; then
  echo -e "${GREEN}PASS${NC}: global/CLAUDE.md pesa $GLOBAL_BYTES bytes (<= 10240)"
  PASS=$((PASS + 1))
else
  echo -e "${RED}FAIL${NC}: global/CLAUDE.md pesa $GLOBAL_BYTES bytes (esperado <= 10240)"
  FAIL=$((FAIL + 1))
fi

TOTAL=$((TOTAL + 1))
GLOBAL_LINES=$(wc -l < "$GLOBAL_CLAUDE_MD" | tr -d ' ')
if [ "$GLOBAL_LINES" -le 130 ]; then
  echo -e "${GREEN}PASS${NC}: global/CLAUDE.md tiene $GLOBAL_LINES líneas (<= 130)"
  PASS=$((PASS + 1))
else
  echo -e "${RED}FAIL${NC}: global/CLAUDE.md tiene $GLOBAL_LINES líneas (esperado <= 130)"
  FAIL=$((FAIL + 1))
fi

echo ""
echo "--- Referencias cruzadas al detalle movido a la skill orchestrator ---"

RUNBOOK="$REPO_ROOT/rulebooks/orchestrator-runbook.md"
GOVERNANCE="$REPO_ROOT/rulebooks/governance-playbook.md"

assert_contains() {
  local file="$1" pattern="$2" label="$3"
  TOTAL=$((TOTAL + 1))
  if grep -q -- "$pattern" "$file"; then
    echo -e "${GREEN}PASS${NC}: $label"
    PASS=$((PASS + 1))
  else
    echo -e "${RED}FAIL${NC}: $label (no se encontró \"$pattern\" en $file)"
    FAIL=$((FAIL + 1))
  fi
}

assert_not_contains() {
  local file="$1" pattern="$2" label="$3"
  TOTAL=$((TOTAL + 1))
  if grep -q -- "$pattern" "$file"; then
    echo -e "${RED}FAIL${NC}: $label (todavía se encontró \"$pattern\" en $file)"
    FAIL=$((FAIL + 1))
  else
    echo -e "${GREEN}PASS${NC}: $label"
    PASS=$((PASS + 1))
  fi
}

assert_not_contains "$RUNBOOK" "el comportamiento esencial vive en \`CLAUDE.md\` raíz" \
  "runbook línea 3 ya no apunta el detalle esencial a CLAUDE.md raíz"
assert_contains "$RUNBOOK" "skill \`orchestrator\`" \
  "runbook línea 3 apunta el manual de la sesión principal a la skill orchestrator"
assert_not_contains "$RUNBOOK" "regla operativa de \`CLAUDE.md\`" \
  "runbook línea 42 (AskUserQuestion) ya no cita CLAUDE.md como fuente"
assert_not_contains "$RUNBOOK" "\"Pause / Resume\" en \`CLAUDE.md\` raíz" \
  "runbook (Retomar) ya no remite Pause/Resume a CLAUDE.md raíz"
assert_not_contains "$GOVERNANCE" "Pause / Resume de CLAUDE.md" \
  "governance-playbook (#9) ya no remite Pause/Resume a CLAUDE.md"

assert_contains "$REPO_ROOT/agents/security-reviewer.md" "skills/orchestrator/SKILL.md" \
  "security-reviewer nombra skills/orchestrator/SKILL.md en la lista de documentos normativos"
assert_contains "$REPO_ROOT/agents/qa-backend.md" "skills/orchestrator/SKILL.md" \
  "qa-backend nombra skills/orchestrator/SKILL.md en la lista de documentos normativos"
assert_contains "$RUNBOOK" "skills/orchestrator/SKILL.md" \
  "runbook (Documentos normativos) nombra skills/orchestrator/SKILL.md"

README="$REPO_ROOT/README.md"
assert_contains "$README" "skill \`orchestrator\`" \
  "README menciona la skill orchestrator como definición del rol"
assert_contains "$README" "### Skills (5)" \
  "README cuenta 5 skills"
assert_contains "$README" "orchestrator/" \
  "README (árbol) lista skills/orchestrator/"

MARKETPLACE_DESC=$(jq -r '.plugins[0].description' "$MARKETPLACE_JSON")
TOTAL=$((TOTAL + 1))
if echo "$MARKETPLACE_DESC" | grep -q "5 skills"; then
  echo -e "${GREEN}PASS${NC}: marketplace.json describe 5 skills"
  PASS=$((PASS + 1))
else
  echo -e "${RED}FAIL${NC}: marketplace.json no describe 5 skills (actual: \"$MARKETPLACE_DESC\")"
  FAIL=$((FAIL + 1))
fi

AGENT_VALIDATION="$REPO_ROOT/tests/validation/agent-validation.md"
TOTAL=$((TOTAL + 1))
if grep -qi "carga la skill" "$AGENT_VALIDATION"; then
  echo -e "${GREEN}PASS${NC}: agent-validation.md (Orchestrator) espera que cargue la skill antes de delegar"
  PASS=$((PASS + 1))
else
  echo -e "${RED}FAIL${NC}: agent-validation.md (Orchestrator) no espera que cargue la skill antes de delegar"
  FAIL=$((FAIL + 1))
fi

echo ""
echo "--- claude plugin validate --strict (si la CLI está disponible) ---"

if command -v claude > /dev/null 2>&1; then
  TOTAL=$((TOTAL + 1))
  if (cd "$REPO_ROOT" && claude plugin validate --strict . < /dev/null > /dev/null 2>&1); then
    echo -e "${GREEN}PASS${NC}: claude plugin validate --strict . pasa"
    PASS=$((PASS + 1))
  else
    echo -e "${RED}FAIL${NC}: claude plugin validate --strict . no pasa"
    FAIL=$((FAIL + 1))
  fi

  TOTAL=$((TOTAL + 1))
  if (cd "$REPO_ROOT" && claude plugin validate --strict .claude-plugin/plugin.json < /dev/null > /dev/null 2>&1); then
    echo -e "${GREEN}PASS${NC}: claude plugin validate --strict .claude-plugin/plugin.json pasa"
    PASS=$((PASS + 1))
  else
    echo -e "${RED}FAIL${NC}: claude plugin validate --strict .claude-plugin/plugin.json no pasa"
    FAIL=$((FAIL + 1))
  fi
else
  echo "SKIP: CLI 'claude' no está en PATH — se omite claude plugin validate --strict (el test crítico de paridad no depende de la CLI)"
fi

echo ""

# --- Resumen ---
echo "=== Results ==="
echo -e "Total: $TOTAL | ${GREEN}Pass: $PASS${NC} | ${RED}Fail: $FAIL${NC}"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
