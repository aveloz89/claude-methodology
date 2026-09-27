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
assert_not_contains "$ORCHESTRATOR_SKILL" "Flujo de trabajo: nueva feature" \
  "skill orchestrator ya no cita el header viejo 'Flujo de trabajo: nueva feature' (movido a 'Fase 2: Implementación')"

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
echo "--- Condiciones para saltar el brainstorming: una sola lista, en la skill ---"

assert_contains "$ORCHESTRATOR_SKILL" "causa raíz ya identificada" \
  "skill orchestrator §3 tiene la condición de bug fix / cambio técnico sin funcionalidad nueva"
assert_contains "$ORCHESTRATOR_SKILL" "No cambia contratos públicos" \
  "skill orchestrator §3 tiene la condición de no cambiar contratos públicos"
assert_contains "$ORCHESTRATOR_SKILL" "No agrega dependencias nuevas" \
  "skill orchestrator §3 tiene la condición de no agregar dependencias"
assert_contains "$ORCHESTRATOR_SKILL" "precisión suficiente" \
  "skill orchestrator §3 tiene la condición de descripción con precisión suficiente"
assert_not_contains "$RUNBOOK" "Bug fix con pasos de reproducción claros" \
  "runbook (Fase 0) ya no tiene su propia lista de condiciones para saltar brainstorming"

echo ""
echo "--- global/CLAUDE.md: restricciones de rol, degradación y pre-commit-guard ---"

assert_contains "$GLOBAL_CLAUDE_MD" "Bash solo para git" \
  "Rol de la sesión principal restringe Bash a git/gh/lectura de estado/orquestación"
assert_contains "$GLOBAL_CLAUDE_MD" "si te tienta escribir código" \
  "Rol de la sesión principal advierte contra escribir código \"porque es rápido\""
assert_contains "$GLOBAL_CLAUDE_MD" "auth, crypto, secrets o pagos" \
  "Workflow obligatorio #4 tiene la regla de degradación de security-reviewer"
assert_contains "$GLOBAL_CLAUDE_MD" "pre-commit-guard.sh" \
  "Verificación pre-commit menciona que el paso 1 lo refuerza pre-commit-guard.sh"

echo ""
echo "--- skills/orchestrator/SKILL.md: allowed-tools sin Bash (pre-aprueba, no restringe) y declara sus agentes ---"

ORCH_ALLOWED_TOOLS=$(grep -E "^allowed-tools:" "$ORCHESTRATOR_SKILL" | head -1)

# allowed-tools de una skill SUMA pre-aprobaciones, no restringe (verificado
# ejecutando: Bash(git *) deja correr `git -c alias.x='!cmd' x`, es decir
# cualquier comando; ver .planning/reviews/pre-pr-orchestrator-skill.md,
# Ronda 2, M2 de security-reviewer). El commit 8cc659c afirmaba que
# Bash(git *)/Bash(gh *)/Bash(jq *) "acotan" Bash: es falso, por eso este
# check ahora exige la ausencia de Bash en cualquier forma.
TOTAL=$((TOTAL + 1))
if echo "$ORCH_ALLOWED_TOOLS" | grep -qE '(^|, )Bash(\(|,|$)'; then
  echo -e "${RED}FAIL${NC}: allowed-tools todavía tiene Bash (pre-aprueba, no restringe)"
  FAIL=$((FAIL + 1))
else
  echo -e "${GREEN}PASS${NC}: allowed-tools no tiene Bash en ninguna forma"
  PASS=$((PASS + 1))
fi

for agent in architect ui-ux backend-dev frontend-dev docs security-reviewer qa-frontend qa-backend e2e-runner product-reviewer; do
  TOTAL=$((TOTAL + 1))
  if echo "$ORCH_ALLOWED_TOOLS" | grep -qF "Agent(methodology:$agent)"; then
    echo -e "${GREEN}PASS${NC}: allowed-tools declara Agent(methodology:$agent)"
    PASS=$((PASS + 1))
  else
    echo -e "${RED}FAIL${NC}: allowed-tools no declara Agent(methodology:$agent)"
    FAIL=$((FAIL + 1))
  fi
done

# build-resolver y db-specialist se fusionaron en rulebooks/build-errors.md
# y rulebooks/db-migrations.md (PR 3, lotes 5 y 6): ya no son agentes, así
# que su ausencia de allowed-tools es la condición correcta (antes de cada
# fusión este check exigía lo contrario).
for merged_agent in build-resolver db-specialist; do
  TOTAL=$((TOTAL + 1))
  if echo "$ORCH_ALLOWED_TOOLS" | grep -qF "Agent(methodology:$merged_agent)"; then
    echo -e "${RED}FAIL${NC}: allowed-tools todavía declara Agent(methodology:$merged_agent) (fusionado en rulebooks/)"
    FAIL=$((FAIL + 1))
  else
    echo -e "${GREEN}PASS${NC}: allowed-tools no declara Agent(methodology:$merged_agent)"
    PASS=$((PASS + 1))
  fi
done

echo ""
echo "--- skills/orchestrator/SKILL.md §1: puntero al núcleo, sin redefinir el rol ---"

assert_not_contains "$ORCHESTRATOR_SKILL" "Coordinas: entiendes el pedido, haces diseñar, repartes lotes" \
  "§1 ya no redefine el rol (evita divergencia con global/CLAUDE.md)"
assert_contains "$ORCHESTRATOR_SKILL" "para que no diverja" \
  "§1 apunta a global/CLAUDE.md como fuente única del rol"

echo ""
echo "--- Tuteo consistente en global/CLAUDE.md y skills/orchestrator/SKILL.md ---"

assert_no_voseo() {
  local file="$1"
  # Lista explícita de formas voseantes (recopilada del historial del repo:
  # commits c036779, 1b07627, 82f1f0c, 5caedaf), en vez de un patrón
  # genérico por sufijo/tilde. Un patrón genérico necesita una lista blanca
  # de excepciones ("está", "así", "metodología"...) que crece sin fin; uno
  # explícito no necesita ninguna.
  #
  # Delimitadores literales en vez de \b: \b depende de qué locale trata
  # los acentos como caracteres de palabra. En locale C, glibc no reconoce
  # las vocales acentuadas como "word chars" y \b marca borde en cualquier
  # lado de ellas (falso positivo dentro de "metodología"); en UTF-8 sí las
  # reconoce y \b funciona bien — pero depender de que el locale correcto
  # esté generado en la máquina que corre el test (imágenes slim no lo
  # tienen) es justamente el bug que este comentario reemplaza. Usamos en
  # cambio "no es letra ASCII, o inicio/fin de línea" como borde: eso no
  # depende de ninguna configuración de locale.
  # Un solo patrón grande con delimitadores no-zero-width (ERE no soporta
  # lookaround) consume el delimitador de cierre de un match y se lo roba
  # al siguiente: "Vos podés" no detecta "podés" porque el espacio entre
  # ambas palabras ya lo consumió el match de "Vos". Se recorre la lista
  # palabra por palabra en llamadas de grep independientes para que cada
  # búsqueda arranque limpia sobre el archivo completo.
  local voseo_forms=(
    vos sos tenés podés hacé hacés querés sabés decís usás notás cargala
    leelo retomá fijate mirá esperá decilo cortalo aplicá lanzás coordinás
    entendés escalás escalá cargá obtené arreglás preferís necesitás
    trabajás reportá
  )
  local delim='[^[:alpha:]]'
  TOTAL=$((TOTAL + 1))
  local hits=""
  local word pattern word_hits
  for word in "${voseo_forms[@]}"; do
    pattern="(^|${delim})(${word})(${delim}|\$)"
    word_hits=$(grep -noiE "$pattern" "$file" || true)
    if [ -n "$word_hits" ]; then
      hits="${hits}${word_hits}"$'\n'
    fi
  done
  if [ -z "$hits" ]; then
    echo -e "${GREEN}PASS${NC}: $file usa tuteo (sin formas voseantes)"
    PASS=$((PASS + 1))
  else
    echo -e "${RED}FAIL${NC}: $file tiene formas voseantes: $(echo "$hits" | tr '\n' ' ')"
    FAIL=$((FAIL + 1))
  fi
}

assert_no_voseo "$REPO_ROOT/global/CLAUDE.md"
assert_no_voseo "$ORCHESTRATOR_SKILL"
assert_no_voseo "$REPO_ROOT/rulebooks/build-errors.md"
assert_no_voseo "$REPO_ROOT/rulebooks/db-migrations.md"

echo ""
echo "--- agents/product-reviewer.md: existe y es read-only ---"

PRODUCT_REVIEWER="$REPO_ROOT/agents/product-reviewer.md"

# assert_agent_read_only <file>: verifica que el agente sea opus, que
# `tools:` no incluya Write/Edit/Bash y que `disallowedTools:` incluya
# Write, Edit, Bash y Agent. No usa las funciones de test-frontmatter.sh
# (script independiente); parsea el frontmatter con grep/sed inline.
assert_agent_read_only() {
  local file="$1"
  local model_line tools_line disallowed_line
  model_line=$(grep -E "^model:" "$file" | head -1 | sed -E 's/^model:[[:space:]]*//')
  tools_line=$(grep -E "^tools:" "$file" | head -1 | sed -E 's/^tools:[[:space:]]*//')
  disallowed_line=$(grep -E "^disallowedTools:" "$file" | head -1 | sed -E 's/^disallowedTools:[[:space:]]*//')

  TOTAL=$((TOTAL + 1))
  if [ "$model_line" = "opus" ]; then
    echo -e "${GREEN}PASS${NC}: $(basename "$file") model: opus"
    PASS=$((PASS + 1))
  else
    echo -e "${RED}FAIL${NC}: $(basename "$file") model=\"$model_line\" (esperado opus)"
    FAIL=$((FAIL + 1))
  fi

  local tool bad_tool=""
  for tool in Write Edit Bash; do
    if echo "$tools_line" | grep -qE "(^|, )$tool(,|\$)"; then
      bad_tool="$tool"
      break
    fi
  done
  TOTAL=$((TOTAL + 1))
  if [ -z "$bad_tool" ]; then
    echo -e "${GREEN}PASS${NC}: $(basename "$file") tools sin Write/Edit/Bash"
    PASS=$((PASS + 1))
  else
    echo -e "${RED}FAIL${NC}: $(basename "$file") tools incluye $bad_tool (debe ser read-only)"
    FAIL=$((FAIL + 1))
  fi

  local missing=""
  for tool in Write Edit Bash Agent; do
    if ! echo "$disallowed_line" | grep -qE "(^|, )$tool(,|\$)"; then
      missing="$missing $tool"
    fi
  done
  TOTAL=$((TOTAL + 1))
  if [ -z "$missing" ]; then
    echo -e "${GREEN}PASS${NC}: $(basename "$file") disallowedTools incluye Write, Edit, Bash, Agent"
    PASS=$((PASS + 1))
  else
    echo -e "${RED}FAIL${NC}: $(basename "$file") disallowedTools le faltan:$missing"
    FAIL=$((FAIL + 1))
  fi
}

TOTAL=$((TOTAL + 1))
if [ -f "$PRODUCT_REVIEWER" ]; then
  echo -e "${GREEN}PASS${NC}: agents/product-reviewer.md existe"
  PASS=$((PASS + 1))
else
  echo -e "${RED}FAIL${NC}: agents/product-reviewer.md no existe"
  FAIL=$((FAIL + 1))
fi

if [ -f "$PRODUCT_REVIEWER" ]; then
  assert_agent_read_only "$PRODUCT_REVIEWER"

  TOTAL=$((TOTAL + 1))
  PR_LINES=$(wc -l < "$PRODUCT_REVIEWER" | tr -d ' ')
  if [ "$PR_LINES" -le 150 ]; then
    echo -e "${GREEN}PASS${NC}: agents/product-reviewer.md tiene $PR_LINES líneas (<= 150)"
    PASS=$((PASS + 1))
  else
    echo -e "${RED}FAIL${NC}: agents/product-reviewer.md tiene $PR_LINES líneas (esperado <= 150)"
    FAIL=$((FAIL + 1))
  fi

  assert_contains "$PRODUCT_REVIEWER" "seguir | reducir alcance | repensar" \
    "agents/product-reviewer.md declara las tres opciones del veredicto"
  assert_contains "$PRODUCT_REVIEWER" "### Resultado esperado" \
    "agents/product-reviewer.md tiene el encabezado Resultado esperado (compartido con BRIEF.md)"
  assert_contains "$PRODUCT_REVIEWER" "### Criterios de aceptación" \
    "agents/product-reviewer.md tiene el encabezado Criterios de aceptación (compartido con BRIEF.md)"
  assert_contains "$PRODUCT_REVIEWER" "### Preguntas" \
    "agents/product-reviewer.md tiene la regla de preguntar en vez de suponer (D-05)"
  assert_not_contains "$PRODUCT_REVIEWER" "declara supuestos" \
    "agents/product-reviewer.md ya no ofrece \"declara supuestos\" como alternativa a preguntar (D-05)"
  assert_not_contains "$PRODUCT_REVIEWER" "### Supuestos" \
    "agents/product-reviewer.md ya no tiene la sección Supuestos en el formato del reporte (D-05)"

  assert_no_voseo "$PRODUCT_REVIEWER"

  # assert_no_emphasis_caps: lista explícita de mayúsculas de énfasis
  # prohibidas (mismo patrón que assert_no_voseo: lista explícita en vez de
  # heurística genérica, para no necesitar lista blanca de excepciones).
  # Case-sensitive (sin -i): "no" en minúscula es una palabra normal del
  # español; solo la forma en mayúsculas de énfasis está prohibida.
  assert_no_emphasis_caps() {
    local file="$1"
    local forms=(NUNCA SIEMPRE SOLO OBLIGATORIO NO)
    local delim='[^[:alpha:]]'
    TOTAL=$((TOTAL + 1))
    local hits="" word pattern word_hits
    for word in "${forms[@]}"; do
      pattern="(^|${delim})(${word})(${delim}|\$)"
      word_hits=$(grep -noE "$pattern" "$file" || true)
      if [ -n "$word_hits" ]; then
        hits="${hits}${word_hits}"$'\n'
      fi
    done
    if [ -z "$hits" ]; then
      echo -e "${GREEN}PASS${NC}: $file sin mayúsculas de énfasis prohibidas"
      PASS=$((PASS + 1))
    else
      echo -e "${RED}FAIL${NC}: $file tiene mayúsculas de énfasis: $(echo "$hits" | tr '\n' ' ')"
      FAIL=$((FAIL + 1))
    fi
  }
  assert_no_emphasis_caps "$PRODUCT_REVIEWER"
fi

echo ""
echo "--- Sandbox: assert_agent_read_only detecta un agente que no es read-only ---"

SANDBOX_AGENT_BAD=$(mktemp)
cat > "$SANDBOX_AGENT_BAD" <<'EOF'
---
name: sandbox-agent-bad
description: agente de prueba sin restricciones
model: opus
tools: Read, Write
---
EOF

SANDBOX_FAIL_BEFORE=$FAIL
assert_agent_read_only "$SANDBOX_AGENT_BAD" > /dev/null
TOTAL=$((TOTAL + 1))
if [ "$FAIL" -gt "$SANDBOX_FAIL_BEFORE" ]; then
  echo -e "${GREEN}PASS${NC}: assert_agent_read_only detecta el sandbox con tools:Write y sin disallowedTools"
  PASS=$((PASS + 1))
  # Los fallos del sandbox no son fallos reales del repo: se descuentan.
  FAIL=$SANDBOX_FAIL_BEFORE
else
  echo -e "${RED}FAIL${NC}: assert_agent_read_only no detectó el sandbox inseguro"
  FAIL=$((FAIL + 1))
fi
rm -f "$SANDBOX_AGENT_BAD"

SANDBOX_AGENT_GOOD=$(mktemp)
cat > "$SANDBOX_AGENT_GOOD" <<'EOF'
---
name: sandbox-agent-good
description: agente de prueba read-only
model: opus
tools: Read, Grep, Glob
disallowedTools: Write, Edit, Bash, Agent
---
EOF

SANDBOX_FAIL_BEFORE2=$FAIL
SANDBOX_PASS_BEFORE2=$PASS
assert_agent_read_only "$SANDBOX_AGENT_GOOD" > /dev/null
TOTAL=$((TOTAL + 1))
if [ "$FAIL" -eq "$SANDBOX_FAIL_BEFORE2" ] && [ "$PASS" -eq "$((SANDBOX_PASS_BEFORE2 + 3))" ]; then
  echo -e "${GREEN}PASS${NC}: assert_agent_read_only no reporta falsos positivos sobre un agente read-only correcto"
  PASS=$((PASS + 1))
else
  echo -e "${RED}FAIL${NC}: assert_agent_read_only reportó fallos sobre un agente read-only correcto"
  FAIL=$((FAIL + 1))
fi
rm -f "$SANDBOX_AGENT_GOOD"

echo ""
echo "--- Fase 2.5: saltar docs cuando el diff no toca superficie pública ---"

assert_contains "$RUNBOOK" "salta \`docs\`" \
  "runbook Fase 2.5 documenta el salto de docs cuando el diff no toca superficie pública"
assert_contains "$RUNBOOK" "lo registra en el body del PR" \
  "runbook Fase 2.5 exige registrar el salto de docs en el body del PR"
assert_contains "$ORCHESTRATOR_SKILL" "salta \`docs\`" \
  "skill orchestrator fila 2.5 documenta el salto de docs"

echo ""
echo "--- Fase 0.5: disparadores estrictos para invocar ui-ux ---"

assert_contains "$RUNBOOK" "solo si no existe \`design-system" \
  "runbook Fase 0.5 invoca ui-ux solo si no existe MASTER.md o hay página crítica/patrón nuevo"
assert_contains "$RUNBOOK" "el \`frontend-dev\` lee \`MASTER.md\` y aplica sus constraints" \
  "runbook Fase 0.5 dice que en UI chica el frontend-dev lee MASTER.md y aplica sus constraints"
assert_contains "$ORCHESTRATOR_SKILL" "solo si no existe \`MASTER.md\`" \
  "skill orchestrator fila 0.5 invoca ui-ux solo si no existe MASTER.md o hay página crítica/patrón nuevo"

echo ""
echo "--- rulebooks/db-migrations.md: normalización pragmática, desviación de índice, guardas de producción y secrets ---"

DB_MIGRATIONS="$REPO_ROOT/rulebooks/db-migrations.md"

assert_contains "$DB_MIGRATIONS" "3NF por defecto" \
  "Principios de migración incluye normalización pragmática (3NF por defecto)"
assert_contains "$DB_MIGRATIONS" "índice compuesto o parcial" \
  "Principios de migración incluye la desviación de índice compuesto o parcial documentada en ARCHITECTURE.md"
assert_contains "$DB_MIGRATIONS" "corras la migración contra producción desde el lote" \
  "Principios de migración menciona la guarda de no correr migraciones contra producción desde el lote"
assert_contains "$DB_MIGRATIONS" "secrets ni credenciales en migraciones ni seeds" \
  "Principios de migración incluye la guarda de no poner secrets ni credenciales en migraciones ni seeds"

echo ""
echo "--- rulebooks/dev-common.md: guardas de dependencias y checks visibles en todo lote ---"

DEV_COMMON="$REPO_ROOT/rulebooks/dev-common.md"

assert_contains "$DEV_COMMON" "dependencia nueva, major o downgrade" \
  "dev-common.md tiene la línea de guardas de dependencias visible en todo lote"
assert_contains "$DEV_COMMON" "no silenciar checks" \
  "dev-common.md tiene la línea de no silenciar checks (ignore/disable/strict: false)"
assert_contains "$DEV_COMMON" "rulebooks/build-errors.md" \
  "dev-common.md apunta a build-errors.md para el detalle de las guardas"

echo ""
echo "--- rulebooks/db-migrations.md: referencia circular corregida ---"

assert_not_contains "$DB_MIGRATIONS" "Migraciones de DB: simple vs complejo" \
  "db-migrations.md ya no referencia la sección renombrada de backend-dev.md (circular)"
assert_contains "$DB_MIGRATIONS" "Cuándo un lote es DB complejo" \
  "db-migrations.md apunta a la sección del runbook \"Cuándo un lote es DB complejo\""

echo ""
echo "--- Fase 2.5: hooks/permisos/auth/seguridad siempre invocan docs ---"

assert_contains "$RUNBOOK" "hooks, permisos, auth o controles de seguridad" \
  "runbook Fase 2.5 exige invocar docs siempre que el diff toque hooks/permisos/auth/seguridad"
assert_contains "$ORCHESTRATOR_SKILL" "hooks, permisos, auth o controles de seguridad" \
  "skill orchestrator fila 2.5 exige invocar docs siempre que el diff toque hooks/permisos/auth/seguridad"

echo ""
echo "--- Fase 0.5: término alineado con agents/frontend-dev.md (lee MASTER.md y aplica sus constraints) ---"

assert_contains "$RUNBOOK" "lee \`MASTER.md\` y aplica sus constraints" \
  "runbook Fase 0.5 usa el mismo término que agents/frontend-dev.md (constraints, no checklist)"
assert_not_contains "$RUNBOOK" "aplica su checklist directamente" \
  "runbook Fase 0.5 ya no usa el término checklist, ausente en agents/frontend-dev.md"

echo ""
echo "--- Fase 0.3: skills/orchestrator/SKILL.md declara la revisión de producto ---"

assert_contains "$ORCHESTRATOR_SKILL" "0.3. Revisión de producto" \
  "skill orchestrator tiene la fila 0.3 en el mapa del flujo"
assert_contains "$ORCHESTRATOR_SKILL" "Tipo: producto con usuarios" \
  "skill orchestrator documenta la condición de activación Tipo: producto con usuarios"
assert_contains "$ORCHESTRATOR_SKILL" "\`product-reviewer\` → sonnet aceptable siempre" \
  "skill orchestrator agrega la degradación de product-reviewer"
assert_contains "$ORCHESTRATOR_SKILL" "y de \`product-reviewer\` si corrió" \
  "skill orchestrator actualiza la fila de ui-ux para mencionar a product-reviewer"
assert_contains "$ORCHESTRATOR_SKILL" "Presentar el reporte de \`product-reviewer\`" \
  "skill orchestrator §9 remite al runbook para la Fase 0.3"

echo ""
echo "--- Fase 0.3: rulebooks/orchestrator-runbook.md tiene el ciclo de preguntas (D-05) ---"

assert_contains "$RUNBOOK" "### Fase 0.3: Revisión de producto" \
  "runbook tiene la sección Fase 0.3"
assert_contains "$RUNBOOK" "Tipo: producto con usuarios" \
  "runbook Fase 0.3 documenta la condición de activación"
assert_contains "$RUNBOOK" "Sin la línea" \
  "runbook Fase 0.3 documenta que sin la línea no corre y no se pregunta si agregarla"
assert_contains "$RUNBOOK" "### Preguntas\` (D-05)" \
  "runbook Fase 0.3 documenta el caso en que product-reviewer devuelve preguntas"
assert_contains "$RUNBOOK" "SendMessage" \
  "runbook Fase 0.3 reanuda al mismo agente con SendMessage en vez de reinvocar de cero"
assert_contains "$RUNBOOK" "Solo hay una ronda de preguntas" \
  "runbook Fase 0.3 documenta que solo hay una ronda de preguntas"
assert_contains "$RUNBOOK" "Incorporar todo" \
  "runbook Fase 0.3 tiene la opción Incorporar todo"
assert_contains "$RUNBOOK" "Elegir qué incorporar" \
  "runbook Fase 0.3 tiene la opción Elegir qué incorporar"
assert_contains "$RUNBOOK" "Seguir sin cambios" \
  "runbook Fase 0.3 tiene la opción Seguir sin cambios"

echo ""
echo "--- Fase 0.3: formatos de BRIEF.md, context isolation y reporte de review ---"

assert_contains "$RUNBOOK" "### Resultado esperado (si pasó por product-reviewer)" \
  "runbook formato BRIEF.md tiene la sección Resultado esperado"
assert_contains "$RUNBOOK" "### Criterios de aceptación (si pasó por product-reviewer)" \
  "runbook formato BRIEF.md tiene la sección Criterios de aceptación"
assert_contains "$RUNBOOK" "\`product-reviewer\` recibe:" \
  "runbook (Context isolation) documenta qué recibe product-reviewer"
assert_contains "$RUNBOOK" "Criterios de aceptación del brief: cubiertos" \
  "runbook (Formato de reporte de review) tiene la línea opcional de criterios de aceptación"

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
