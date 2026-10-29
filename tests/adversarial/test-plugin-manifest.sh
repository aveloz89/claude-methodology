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
# imprimiendo "0"), necesario bajo `set -e`. El segundo `sed` quita una
# comilla doble literal de cierre: desde que los commands entrecomillan
# ${CLAUDE_PLUGIN_ROOT} (`"${CLAUDE_PLUGIN_ROOT}/hooks/x.sh"`), el basename
# extraído por el primer `sed` arrastra esa comilla de cierre.
count_hook_registrations() {
  local hooks_json="$1"
  local script_name="$2"
  local n
  n=$(jq -r '.. | .command? // empty' "$hooks_json" 2>/dev/null \
    | sed 's#.*/##' \
    | sed 's/"$//' \
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
# `endswith($name) or endswith($name + "\"")`: los commands entrecomillan
# ${CLAUDE_PLUGIN_ROOT} (`"${CLAUDE_PLUGIN_ROOT}/hooks/x.sh"`), así que el
# script name puede quedar seguido de una comilla doble de cierre.
assert_hook_if() {
  local script_name="$1"
  local expected_if="$2"
  local actual
  actual=$(jq -r --arg name "$script_name" \
    '.hooks.PreToolUse[].hooks[] | select(.command | endswith($name) or endswith($name + "\"")) | .if // "MISSING"' \
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
PCG_TIMEOUT=$(jq -r '.hooks.PreToolUse[].hooks[] | select(.command | endswith("pre-commit-guard.sh") or endswith("pre-commit-guard.sh\"")) | .timeout' "$HOOKS_JSON")
if [ "$PCG_TIMEOUT" = "600" ]; then
  echo -e "${GREEN}PASS${NC}: pre-commit-guard.sh tiene timeout=600"
  PASS=$((PASS + 1))
else
  echo -e "${RED}FAIL${NC}: pre-commit-guard.sh tiene timeout=$PCG_TIMEOUT (esperado 600)"
  FAIL=$((FAIL + 1))
fi

TOTAL=$((TOTAL + 1))
if [ "$(jq '.hooks | has("SessionEnd")' "$HOOKS_JSON")" = "false" ]; then
  echo -e "${GREEN}PASS${NC}: hooks.json no tiene clave \"SessionEnd\""
  PASS=$((PASS + 1))
else
  echo -e "${RED}FAIL${NC}: hooks.json todavía tiene clave \"SessionEnd\""
  FAIL=$((FAIL + 1))
fi

echo ""
echo "--- hooks.json: CLAUDE_PLUGIN_ROOT entrecomillado en cada command ---"

# assert_plugin_root_quoted: `claude plugin validate --strict` (CLI 2.1.283)
# marca warning en cada entrada donde el placeholder ${CLAUDE_PLUGIN_ROOT} no
# va entre comillas dobles literales en el comando de shell (puede partirse
# en varias palabras si el path expandido tiene espacios). Un command
# correctamente entrecomillado empieza con el caracter `"` seguido del
# placeholder; uno sin comillas empieza directo con `${CLAUDE_PLUGIN_ROOT}`.
UNQUOTED_ROOT=$(jq -r '.. | .command? // empty' "$HOOKS_JSON" | grep -c '^\${CLAUDE_PLUGIN_ROOT}' || true)
TOTAL=$((TOTAL + 1))
if [ "$UNQUOTED_ROOT" -eq 0 ]; then
  echo -e "${GREEN}PASS${NC}: todos los commands entrecomillan \${CLAUDE_PLUGIN_ROOT}"
  PASS=$((PASS + 1))
else
  echo -e "${RED}FAIL${NC}: $UNQUOTED_ROOT commands tienen \${CLAUDE_PLUGIN_ROOT} sin comillas"
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

# grep: exit 0 = match, 1 = sin match, >=2 = error (patrón inválido, archivo
# ilegible). El error es FAIL con el mensaje de grep, nunca "sin match".
assert_contains() {
  local file="$1" pattern="$2" label="$3" err rc
  TOTAL=$((TOTAL + 1))
  err=$(grep -q -- "$pattern" "$file" 2>&1) && rc=0 || rc=$?
  if [ "$rc" -eq 0 ]; then
    echo -e "${GREEN}PASS${NC}: $label"
    PASS=$((PASS + 1))
  elif [ "$rc" -eq 1 ]; then
    echo -e "${RED}FAIL${NC}: $label (no se encontró \"$pattern\" en $file)"
    FAIL=$((FAIL + 1))
  else
    echo -e "${RED}FAIL${NC}: $label (grep falló con exit $rc para el patrón \"$pattern\": $err)"
    FAIL=$((FAIL + 1))
  fi
}

assert_not_contains() {
  local file="$1" pattern="$2" label="$3" err rc
  TOTAL=$((TOTAL + 1))
  err=$(grep -q -- "$pattern" "$file" 2>&1) && rc=0 || rc=$?
  if [ "$rc" -eq 1 ]; then
    echo -e "${GREEN}PASS${NC}: $label"
    PASS=$((PASS + 1))
  elif [ "$rc" -eq 0 ]; then
    echo -e "${RED}FAIL${NC}: $label (todavía se encontró \"$pattern\" en $file)"
    FAIL=$((FAIL + 1))
  else
    echo -e "${RED}FAIL${NC}: $label (grep falló con exit $rc para el patrón \"$pattern\": $err)"
    FAIL=$((FAIL + 1))
  fi
}

# CA-14: un patrón que rompe a grep (exit 2) debe dar FAIL, no pasar en vacío.
BAD_PATTERN_FILE=$(mktemp)
echo "texto cualquiera" > "$BAD_PATTERN_FILE"
for helper in assert_not_contains assert_contains; do
  BAD_OUT=$( ($helper "$BAD_PATTERN_FILE" '[patrón inválido' "sandbox" 2>&1) || true)
  TOTAL=$((TOTAL + 1))
  if echo "$BAD_OUT" | grep -q "FAIL"; then
    echo -e "${GREEN}PASS${NC}: $helper da FAIL ante un patrón que rompe a grep"
    PASS=$((PASS + 1))
  else
    echo -e "${RED}FAIL${NC}: $helper no falló ante un patrón que rompe a grep (salida: $BAD_OUT)"
    FAIL=$((FAIL + 1))
  fi
done
rm -f "$BAD_PATTERN_FILE"

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
assert_contains "$README" "### Skills (4)" \
  "README cuenta 4 skills"
assert_contains "$README" "orchestrator/" \
  "README (árbol) lista skills/orchestrator/"

MARKETPLACE_DESC=$(jq -r '.plugins[0].description' "$MARKETPLACE_JSON")
TOTAL=$((TOTAL + 1))
if echo "$MARKETPLACE_DESC" | grep -q "4 skills"; then
  echo -e "${GREEN}PASS${NC}: marketplace.json describe 4 skills"
  PASS=$((PASS + 1))
else
  echo -e "${RED}FAIL${NC}: marketplace.json no describe 4 skills (actual: \"$MARKETPLACE_DESC\")"
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
assert_contains "$GLOBAL_CLAUDE_MD" "señales 1, 4 u 8" \
  "Workflow #4 tiene la regla de review simple (security-reviewer si toca las señales 1, 4 u 8 del runbook)"
assert_contains "$GLOBAL_CLAUDE_MD" "pre-commit-guard.sh" \
  "Verificación pre-commit menciona que el paso 1 lo refuerza pre-commit-guard.sh"

# CA-12: tono plano. Tokens de énfasis vedados en el núcleo global, como
# palabra (borde = no letra o inicio/fin de línea, sin depender del locale).
# El léxico BLOQUEANTE/APROBADO de los reportes de reviewers no está en este archivo.
BANNED_TOKENS=(NUNCA SIEMPRE JAMÁS DEBES DEBE OBLIGATORIO OBLIGATORIA OBLIGATORIOS OBLIGATORIAS BLOQUEANTE BLOQUEANTES PROHIBIDO PROHIBIDA obligatorio obligatoria obligatorios obligatorias bloqueante bloqueantes)
TOTAL=$((TOTAL + 1))
BANNED_HITS=""
for token in "${BANNED_TOKENS[@]}"; do
  token_hits=$(grep -nE "(^|[^[:alpha:]])${token}([^[:alpha:]]|\$)" "$GLOBAL_CLAUDE_MD" || true)
  [ -n "$token_hits" ] && BANNED_HITS="${BANNED_HITS}${token}: ${token_hits}"$'\n'
done
if [ -z "$BANNED_HITS" ]; then
  echo -e "${GREEN}PASS${NC}: global/CLAUDE.md sin tokens de énfasis vedados"
  PASS=$((PASS + 1))
else
  echo -e "${RED}FAIL${NC}: global/CLAUDE.md tiene tokens vedados: $(echo "$BANNED_HITS" | tr '\n' ' ')"
  FAIL=$((FAIL + 1))
fi

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

for agent in architect ui-ux backend-dev frontend-dev docs security-reviewer qa-frontend qa-backend e2e-runner code-sweep; do
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
  # Las formas en -í de verbos -er/-ir (corregí, elegí, construí, reproducí)
  # no se listan: coinciden con el pretérito de 1ª persona singular válido en
  # cualquier dialecto ("ya corregí el archivo"), no son exclusivas de voseo,
  # y listarlas da falso positivo con prosa normal.
  local voseo_forms=(
    vos sos tenés podés hacé hacés querés sabés decís usás notás cargala
    leelo retomá fijate mirá esperá esperás decilo cortalo aplicá lanzás
    coordinás entendés escalás escalá cargá obtené arreglás preferís
    necesitás trabajás reportá evaluás invocás invocá abrí reinvocalo
    consolidás corré corrés leé asigná diagnosticá eliminá
    verificá exportá cambiás actualizá creás limpiá controlás ejecutás
    lográs revertís agregá borrá bloqueá
    validá devolvé etiquetá reconciliá enunciá remití
    listá marcalo reportalo mencionalo anotalo seguí
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

# Corre sobre todos los .md normativos del repo (agentes, rulebooks, skills,
# reglas por lenguaje y los dos CLAUDE.md), no solo sobre una muestra: un
# archivo nuevo o editado en cualquiera de estas rutas queda cubierto sin
# tocar esta lista.
NORMATIVE_MD_FILES=(
  "$REPO_ROOT"/agents/*.md
  "$REPO_ROOT"/rulebooks/*.md
  "$REPO_ROOT"/skills/*/SKILL.md
  "$REPO_ROOT"/rules/*.md
  "$REPO_ROOT/global/CLAUDE.md"
  "$REPO_ROOT/README.md"
  "$REPO_ROOT/.claude/CLAUDE.md"
)
for md_file in "${NORMATIVE_MD_FILES[@]}"; do
  [ -f "$md_file" ] || continue
  assert_no_voseo "$md_file"
done

echo ""
echo "--- agents/code-sweep.md: existe y no escribe (Write/Edit vedados) ---"

CODE_SWEEP="$REPO_ROOT/agents/code-sweep.md"

# assert_agent_read_only <file> <expected_model>: verifica que el agente
# use el modelo esperado, que `tools:` no incluya Write/Edit (algunos
# agentes de solo lectura, como code-sweep, sí necesitan Bash para
# grep/find) y que `disallowedTools:` incluya Write, Edit y Agent. No usa
# las funciones de test-frontmatter.sh (script independiente); parsea el
# frontmatter con grep/sed inline.
assert_agent_read_only() {
  local file="$1" expected_model="$2"
  local model_line tools_line disallowed_line
  model_line=$(grep -E "^model:" "$file" | head -1 | sed -E 's/^model:[[:space:]]*//')
  tools_line=$(grep -E "^tools:" "$file" | head -1 | sed -E 's/^tools:[[:space:]]*//')
  disallowed_line=$(grep -E "^disallowedTools:" "$file" | head -1 | sed -E 's/^disallowedTools:[[:space:]]*//')

  TOTAL=$((TOTAL + 1))
  if [ "$model_line" = "$expected_model" ]; then
    echo -e "${GREEN}PASS${NC}: $(basename "$file") model: $expected_model"
    PASS=$((PASS + 1))
  else
    echo -e "${RED}FAIL${NC}: $(basename "$file") model=\"$model_line\" (esperado $expected_model)"
    FAIL=$((FAIL + 1))
  fi

  local tool bad_tool=""
  for tool in Write Edit; do
    if echo "$tools_line" | grep -qE "(^|, )$tool(,|\$)"; then
      bad_tool="$tool"
      break
    fi
  done
  TOTAL=$((TOTAL + 1))
  if [ -z "$bad_tool" ]; then
    echo -e "${GREEN}PASS${NC}: $(basename "$file") tools sin Write/Edit"
    PASS=$((PASS + 1))
  else
    echo -e "${RED}FAIL${NC}: $(basename "$file") tools incluye $bad_tool (debe ser read-only)"
    FAIL=$((FAIL + 1))
  fi

  local missing=""
  for tool in Write Edit Agent; do
    if ! echo "$disallowed_line" | grep -qE "(^|, )$tool(,|\$)"; then
      missing="$missing $tool"
    fi
  done
  TOTAL=$((TOTAL + 1))
  if [ -z "$missing" ]; then
    echo -e "${GREEN}PASS${NC}: $(basename "$file") disallowedTools incluye Write, Edit, Agent"
    PASS=$((PASS + 1))
  else
    echo -e "${RED}FAIL${NC}: $(basename "$file") disallowedTools le faltan:$missing"
    FAIL=$((FAIL + 1))
  fi
}

TOTAL=$((TOTAL + 1))
if [ -f "$CODE_SWEEP" ]; then
  echo -e "${GREEN}PASS${NC}: agents/code-sweep.md existe"
  PASS=$((PASS + 1))
else
  echo -e "${RED}FAIL${NC}: agents/code-sweep.md no existe"
  FAIL=$((FAIL + 1))
fi

if [ -f "$CODE_SWEEP" ]; then
  assert_agent_read_only "$CODE_SWEEP" "sonnet"
  # [lote 12, tarea 2] respaldo por escrito del filtro del workflow (D-23).
  assert_not_contains "$CODE_SWEEP" '--search "' "agents/code-sweep.md no pasa --search entre comillas dobles"
  assert_contains "$CODE_SWEEP" 'A-Za-z0-9' "agents/code-sweep.md fija el conjunto de caracteres permitido en file y pattern"
  assert_contains "$CODE_SWEEP" 'excluido de issues' "agents/code-sweep.md manda al reporte (NO CUBIERTO) los hallazgos excluidos de issues"
  assert_contains "$CODE_SWEEP" 'depende del modelo' "agents/code-sweep.md declara que el respaldo depende del modelo (riesgo residual D-23)"
  # assert_no_voseo se corre sobre agents/*.md en el loop de más arriba.
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

SANDBOX_TOTAL_BEFORE=$TOTAL
SANDBOX_PASS_BEFORE=$PASS
SANDBOX_FAIL_BEFORE=$FAIL
assert_agent_read_only "$SANDBOX_AGENT_BAD" "opus" > /dev/null
SANDBOX_DETECTED=$FAIL
# Los sub-asserts sintéticos del sandbox (TOTAL/PASS/FAIL) no son parte de
# la suite real: se descartan por completo antes de sumar el único assert
# real de este bloque, para que Total = Pass + Fail se mantenga.
TOTAL=$SANDBOX_TOTAL_BEFORE
PASS=$SANDBOX_PASS_BEFORE
FAIL=$SANDBOX_FAIL_BEFORE
TOTAL=$((TOTAL + 1))
if [ "$SANDBOX_DETECTED" -gt "$SANDBOX_FAIL_BEFORE" ]; then
  echo -e "${GREEN}PASS${NC}: assert_agent_read_only detecta el sandbox con tools:Write y sin disallowedTools"
  PASS=$((PASS + 1))
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
disallowedTools: Write, Edit, Agent
---
EOF

SANDBOX_FAIL_BEFORE2=$FAIL
SANDBOX_PASS_BEFORE2=$PASS
assert_agent_read_only "$SANDBOX_AGENT_GOOD" "opus" > /dev/null
TOTAL=$((TOTAL + 1))
if [ "$FAIL" -eq "$SANDBOX_FAIL_BEFORE2" ] && [ "$PASS" -eq "$((SANDBOX_PASS_BEFORE2 + 3))" ]; then
  echo -e "${GREEN}PASS${NC}: assert_agent_read_only no reporta falsos positivos sobre un agente read-only correcto"
  PASS=$((PASS + 1))
else
  echo -e "${RED}FAIL${NC}: assert_agent_read_only reportó fallos sobre un agente read-only correcto"
  FAIL=$((FAIL + 1))
fi
rm -f "$SANDBOX_AGENT_GOOD"

TOTAL=$((TOTAL + 1))
if [ "$TOTAL" -eq "$((PASS + FAIL + 1))" ]; then
  echo -e "${GREEN}PASS${NC}: los sandboxes de assert_agent_read_only no dejan TOTAL desalineado de PASS+FAIL"
  PASS=$((PASS + 1))
else
  echo -e "${RED}FAIL${NC}: TOTAL ($TOTAL) != PASS ($PASS) + FAIL ($FAIL) + 1 tras los sandboxes"
  FAIL=$((FAIL + 1))
fi

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
echo "--- rulebooks/dev-common.md: recibe Handoff, Reglas heredadas, Flujo de trabajo y Desviaciones de los devs ---"

assert_contains "$DEV_COMMON" "## Handoff: qué recibes y qué entregas" \
  "dev-common.md tiene la sección Handoff común a backend-dev/frontend-dev"
assert_contains "$DEV_COMMON" "## Reglas heredadas (no reimplementar acá)" \
  "dev-common.md tiene la sección Reglas heredadas común a backend-dev/frontend-dev"
assert_contains "$DEV_COMMON" "## Flujo de trabajo" \
  "dev-common.md tiene la sección Flujo de trabajo común a backend-dev/frontend-dev"
assert_contains "$DEV_COMMON" "## Desviaciones del diseño" \
  "dev-common.md tiene la sección Desviaciones del diseño común a backend-dev/frontend-dev"

for dev in backend-dev frontend-dev; do
  assert_contains "$REPO_ROOT/agents/$dev.md" "rulebooks/dev-common.md" \
    "agents/$dev.md referencia rulebooks/dev-common.md"
done

# Sin arrays asociativos: /bin/bash 3.2 (macOS) no los soporta.
dev_line_cap() {
  case "$1" in
    backend-dev) echo 110 ;;
    frontend-dev) echo 140 ;;
  esac
}
for dev in backend-dev frontend-dev; do
  DEV_LINES=$(wc -l < "$REPO_ROOT/agents/$dev.md" | tr -d ' ')
  CAP="$(dev_line_cap "$dev")"
  TOTAL=$((TOTAL + 1))
  if [ "$DEV_LINES" -le "$CAP" ]; then
    echo -e "${GREEN}PASS${NC}: agents/$dev.md tiene $DEV_LINES líneas (≤$CAP)"
    PASS=$((PASS + 1))
  else
    echo -e "${RED}FAIL${NC}: agents/$dev.md tiene $DEV_LINES líneas (>$CAP)"
    FAIL=$((FAIL + 1))
  fi
done

echo ""
echo "--- rulebooks/agent-budget.md ≤45 líneas; governance-playbook.md #10 remite sin duplicar el fallback ---"

AGENT_BUDGET="$REPO_ROOT/rulebooks/agent-budget.md"
AGENT_BUDGET_LINES=$(wc -l < "$AGENT_BUDGET" | tr -d ' ')
TOTAL=$((TOTAL + 1))
if [ "$AGENT_BUDGET_LINES" -le 45 ]; then
  echo -e "${GREEN}PASS${NC}: rulebooks/agent-budget.md tiene $AGENT_BUDGET_LINES líneas (≤45)"
  PASS=$((PASS + 1))
else
  echo -e "${RED}FAIL${NC}: rulebooks/agent-budget.md tiene $AGENT_BUDGET_LINES líneas (>45)"
  FAIL=$((FAIL + 1))
fi
assert_not_contains "$AGENT_BUDGET" "Cómo se mide" \
  "agent-budget.md ya no tiene la sección Cómo se mide (schema JSONL, fuera de scope de prosa)"
assert_not_contains "$GOVERNANCE" "El fallback completo (leer \`HANDOFF.md\`, confirmar commits per-tarea, reinvocar con las tareas restantes bajo el cap de 5)" \
  "governance-playbook.md #10 ya no repite el detalle del fallback, solo remite a agent-budget.md"

echo ""
echo "--- qa-backend.md y qa-frontend.md: Implementation Principles remite a reviewer-common.md §8 en vez de duplicarlo ---"

assert_contains "$REPO_ROOT/agents/qa-backend.md" "rulebooks/reviewer-common.md\` §8" \
  "qa-backend.md Implementation Principles remite a reviewer-common.md §8"
assert_not_contains "$REPO_ROOT/agents/qa-backend.md" "\*\*Defensive code:\*\* validaciones para casos imposibles \*\*dentro de servicios\*\*" \
  "qa-backend.md ya no duplica la lista de Implementation Principles de reviewer-common.md §8"
assert_contains "$REPO_ROOT/agents/qa-frontend.md" "rulebooks/reviewer-common.md\` §8" \
  "qa-frontend.md Implementation Principles remite a reviewer-common.md §8"
assert_contains "$REPO_ROOT/agents/qa-frontend.md" "Frontend delgado:" \
  "qa-frontend.md conserva el delta de Frontend delgado, específico de su capa"
assert_not_contains "$REPO_ROOT/agents/qa-frontend.md" "un nuevo \`useFooHelper\`" \
  "qa-frontend.md ya no duplica la lista de Implementation Principles de reviewer-common.md §8"

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
echo "--- Formatos de BRIEF.md y reporte de review (resultado esperado y criterios) ---"

assert_contains "$RUNBOOK" "### Resultado esperado" \
  "runbook formato BRIEF.md tiene la sección Resultado esperado"
assert_contains "$RUNBOOK" "origen: brief §<sección> | nuevo" \
  "runbook BRIEF.md etiqueta el origen de un criterio nuevo sin coletilla de product-reviewer"
assert_contains "$RUNBOOK" "### Criterios de aceptación" \
  "runbook formato BRIEF.md tiene la sección Criterios de aceptación"
assert_contains "$RUNBOOK" "Criterios de aceptación del brief: cubiertos" \
  "runbook (Formato de reporte de review) tiene la línea opcional de criterios de aceptación"

echo ""
echo "--- agents/architect.md y QAs: referencian los criterios de aceptación del brief ---"

assert_contains "$REPO_ROOT/agents/architect.md" "Criterios de aceptación" \
  "agents/architect.md traza los criterios de aceptación del brief a tareas atómicas"
assert_contains "$REPO_ROOT/rulebooks/reviewer-common.md" "Criterios de aceptación del brief" \
  "rulebooks/reviewer-common.md referencia los criterios de aceptación del brief (no bloquea)"

echo ""
echo "--- agents/architect.md: catálogo de arquitecturas como tabla corta, SOLID en 5 líneas, ≤240 líneas ---"

ARCHITECT="$REPO_ROOT/agents/architect.md"

assert_contains "$ARCHITECT" "| Tipo | Cuándo | Cuándo NO |" \
  "agents/architect.md tiene la tabla corta de tipos de arquitectura"
assert_not_contains "$ARCHITECT" "\*\*Cuándo NO aplicar SOLID:\*\*" \
  "agents/architect.md ya no tiene la lista larga de cuándo no aplicar SOLID"

ARCHITECT_LINES=$(wc -l < "$ARCHITECT" | tr -d ' ')
TOTAL=$((TOTAL + 1))
if [ "$ARCHITECT_LINES" -le 240 ]; then
  echo -e "${GREEN}PASS${NC}: agents/architect.md tiene $ARCHITECT_LINES líneas (≤240)"
  PASS=$((PASS + 1))
else
  echo -e "${RED}FAIL${NC}: agents/architect.md tiene $ARCHITECT_LINES líneas (>240)"
  FAIL=$((FAIL + 1))
fi

echo ""
echo "--- Conteo de agentes coherente entre agents/, README.md y marketplace.json ---"

AGENT_COUNT=$(ls "$REPO_ROOT"/agents/*.md | wc -l | tr -d ' ')

TOTAL=$((TOTAL + 1))
if grep -q "### Agentes ($AGENT_COUNT)" "$README"; then
  echo -e "${GREEN}PASS${NC}: README.md declara ### Agentes ($AGENT_COUNT)"
  PASS=$((PASS + 1))
else
  echo -e "${RED}FAIL${NC}: README.md no declara ### Agentes ($AGENT_COUNT) (agents/*.md tiene $AGENT_COUNT archivos)"
  FAIL=$((FAIL + 1))
fi

TOTAL=$((TOTAL + 1))
if echo "$MARKETPLACE_DESC" | grep -q "$AGENT_COUNT agentes"; then
  echo -e "${GREEN}PASS${NC}: marketplace.json describe $AGENT_COUNT agentes"
  PASS=$((PASS + 1))
else
  echo -e "${RED}FAIL${NC}: marketplace.json no describe $AGENT_COUNT agentes (actual: \"$MARKETPLACE_DESC\")"
  FAIL=$((FAIL + 1))
fi

echo ""
echo "--- rulebooks/reviewer-common.md: regla de sandbox para pruebas que escriben archivos ---"

# extract_section <file> <heading>: extrae el texto desde la línea que
# empieza con "$heading" (encabezado propio, p. ej. "## 3. Pruebas que
# escriben archivos") hasta la línea anterior al siguiente "## " (o EOF).
# Usa awk en vez de sed/grep porque necesita devolver el rango completo de
# líneas, no un solo match.
extract_section() {
  local file="$1" heading="$2"
  awk -v h="$heading" '
    $0 == h { found=1; print; next }
    found && /^## / { exit }
    found { print }
  ' "$file"
}

# assert_section_contains <section> <pattern> <label>: como assert_contains
# pero sobre un string ya extraído en vez de un archivo.
assert_section_contains() {
  local section="$1" pattern="$2" label="$3"
  TOTAL=$((TOTAL + 1))
  if printf '%s' "$section" | grep -q -- "$pattern"; then
    echo -e "${GREEN}PASS${NC}: $label"
    PASS=$((PASS + 1))
  else
    echo -e "${RED}FAIL${NC}: $label (no se encontró \"$pattern\" en la sección)"
    FAIL=$((FAIL + 1))
  fi
}

QA_BACKEND="$REPO_ROOT/agents/qa-backend.md"
QA_FRONTEND="$REPO_ROOT/agents/qa-frontend.md"
SECURITY_REVIEWER="$REPO_ROOT/agents/security-reviewer.md"
REVIEWER_COMMON="$REPO_ROOT/rulebooks/reviewer-common.md"
SANDBOX_HEADING="## 3. Pruebas que escriben archivos"

SECTION_REVIEWER_COMMON=$(extract_section "$REVIEWER_COMMON" "$SANDBOX_HEADING")

TOTAL=$((TOTAL + 1))
if [ -n "$SECTION_REVIEWER_COMMON" ]; then
  echo -e "${GREEN}PASS${NC}: rulebooks/reviewer-common.md tiene la sección \"$SANDBOX_HEADING\""
  PASS=$((PASS + 1))
else
  echo -e "${RED}FAIL${NC}: rulebooks/reviewer-common.md no tiene la sección \"$SANDBOX_HEADING\""
  FAIL=$((FAIL + 1))
fi

assert_section_contains "$SECTION_REVIEWER_COMMON" "git worktree add --detach" \
  "reviewer-common.md exige worktree --detach para escrituras sobre el repo (scratchpad/mktemp -d no lo necesita)"
assert_section_contains "$SECTION_REVIEWER_COMMON" "git worktree remove" \
  "reviewer-common.md exige eliminar el worktree con git worktree remove al terminar"
assert_section_contains "$SECTION_REVIEWER_COMMON" "git stash" \
  "reviewer-common.md prohíbe git stash por ser compartido entre worktrees"
assert_section_contains "$SECTION_REVIEWER_COMMON" "corre sobre el árbol del repo" \
  "reviewer-common.md prohíbe que un comando que escriba corra sobre el árbol del repo"
assert_section_contains "$SECTION_REVIEWER_COMMON" "dangerously-skip-permissions" \
  "reviewer-common.md prohíbe --dangerously-skip-permissions"
assert_section_contains "$SECTION_REVIEWER_COMMON" "bypassPermissions" \
  "reviewer-common.md prohíbe --permission-mode bypassPermissions"
assert_section_contains "$SECTION_REVIEWER_COMMON" "acceptEdits" \
  "reviewer-common.md prohíbe --permission-mode acceptEdits"
assert_section_contains "$SECTION_REVIEWER_COMMON" "NO CUBIERTO" \
  "reviewer-common.md exige declarar en NO CUBIERTO lo que requeriría permisos saltados"

for agent in qa-backend qa-frontend security-reviewer; do
  AGENT_FILE="$REPO_ROOT/agents/$agent.md"
  assert_contains "$AGENT_FILE" "rulebooks/reviewer-common.md" \
    "agents/$agent.md referencia rulebooks/reviewer-common.md"
done

assert_contains "$SECURITY_REVIEWER" "### NO CUBIERTO" \
  "security-reviewer.md tiene la sección NO CUBIERTO en el formato de reporte (revisión inicial)"

SECURITY_REREVIEW_SECTION=$(extract_section "$SECURITY_REVIEWER" "## Security Re-Review")
assert_section_contains "$SECURITY_REREVIEW_SECTION" "### NO CUBIERTO" \
  "security-reviewer.md tiene la sección NO CUBIERTO en el formato de Security Re-Review"

echo ""
echo "--- .claude/settings.json: no duplica el registro de hooks del plugin (#78) ---"

SETTINGS_JSON="$REPO_ROOT/.claude/settings.json"

TOTAL=$((TOTAL + 1))
HAS_HOOKS=$(jq 'has("hooks")' "$SETTINGS_JSON")
if [ "$HAS_HOOKS" = "false" ]; then
  echo -e "${GREEN}PASS${NC}: .claude/settings.json no tiene clave \"hooks\""
  PASS=$((PASS + 1))
else
  echo -e "${RED}FAIL${NC}: .claude/settings.json todavía tiene clave \"hooks\" (duplica el registro de hooks/hooks.json)"
  FAIL=$((FAIL + 1))
fi

TOTAL=$((TOTAL + 1))
ACTUAL_PERMISSIONS=$(jq -c '.permissions' "$SETTINGS_JSON")
EXPECTED_PERMISSIONS='{"allow":["Bash(gh issue:*)","Bash(gh label:*)"]}'
if [ "$ACTUAL_PERMISSIONS" = "$EXPECTED_PERMISSIONS" ]; then
  echo -e "${GREEN}PASS${NC}: .claude/settings.json conserva \"permissions\" sin cambios"
  PASS=$((PASS + 1))
else
  echo -e "${RED}FAIL${NC}: .claude/settings.json cambió \"permissions\" (actual: $ACTUAL_PERMISSIONS, esperado: $EXPECTED_PERMISSIONS)"
  FAIL=$((FAIL + 1))
fi

echo ""
echo "--- Lote 5: /new-project siembra worktree.baseRef y labels completos ---"

NEW_PROJECT_SKILL="$REPO_ROOT/skills/new-project/SKILL.md"
assert_contains "$NEW_PROJECT_SKILL" "baseRef" "new-project siembra worktree.baseRef"
assert_contains "$NEW_PROJECT_SKILL" "severity:critical" "new-project crea la label severity:critical"
assert_contains "$NEW_PROJECT_SKILL" "severity:high" "new-project crea la label severity:high"
assert_contains "$NEW_PROJECT_SKILL" "e2e-failure" "new-project crea la label e2e-failure"
assert_contains "$NEW_PROJECT_SKILL" "project: agregar setup inicial" "new-project: commit inicial con formato de la metodología"
assert_not_contains "$NEW_PROJECT_SKILL" "tres de las seis" "new-project ya no cuenta la anécdota de las labels"
assert_not_contains "$NEW_PROJECT_SKILL" "--public --source" "new-project no fija la visibilidad del repo sin preguntar"
TOTAL=$((TOTAL + 1))
ACTUAL_BASEREF=$(jq -r '.worktree.baseRef' "$SETTINGS_JSON")
if [ "$ACTUAL_BASEREF" = "head" ]; then
  echo -e "${GREEN}PASS${NC}: .claude/settings.json siembra worktree.baseRef = head"
  PASS=$((PASS + 1))
else
  echo -e "${RED}FAIL${NC}: .claude/settings.json worktree.baseRef es \"$ACTUAL_BASEREF\" (esperado \"head\")"
  FAIL=$((FAIL + 1))
fi

echo ""
echo "--- registro de review: escritor único documentado (#71) ---"

RUNBOOK="$REPO_ROOT/rulebooks/orchestrator-runbook.md"

TOTAL=$((TOTAL + 1))
if grep -q "único escritor del registro" "$RUNBOOK"; then
  echo -e "${GREEN}PASS${NC}: el runbook documenta al orchestrator como único escritor del registro de review"
  PASS=$((PASS + 1))
else
  echo -e "${RED}FAIL${NC}: el runbook no documenta explícitamente al orchestrator como único escritor del registro de review"
  FAIL=$((FAIL + 1))
fi

echo ""
echo "--- reviewers: no escriben el registro de review (#71) ---"

assert_contains "$REPO_ROOT/rulebooks/reviewer-common.md" "no escrib.*registro de review" \
  "rulebooks/reviewer-common.md aclara que los reviewers no escriben el registro de review"

echo ""
echo "--- CA-4: sin referencias colgantes a piezas eliminadas de la metodología ---"

# Términos que ya no deben aparecer en ningún documento normativo ni test:
# cada uno nombra un agente, hook, skill o rulebook borrado por
# simplify-methodology. Alcance: agents/, rulebooks/, skills/, hooks/,
# README.md, global/CLAUDE.md, tests/, .claude/ — excluye .planning/ (no
# versionado) y este mismo script (los términos viven acá como patrones
# de grep, no como menciones normativas).
DANGLING_SCOPE=("$REPO_ROOT/agents" "$REPO_ROOT/rulebooks" "$REPO_ROOT/skills" "$REPO_ROOT/rules" "$HOOKS_DIR" "$REPO_ROOT/README.md" "$REPO_ROOT/global/CLAUDE.md" "$REPO_ROOT/tests" "$REPO_ROOT/.claude")
DANGLING_TERMS=("product-reviewer" "latent-bugs-sweep" "refactor-scan" "learnings/" "LEARNINGS.md" "Fase 4" "workspace-scope" "pre-release-sweep" "session-end-check" "validation-schedule" "context-monitor" "CLAUDE_CONTEXT_TOKENS" "nunca el historial completo" "no el historial completo ni tareas de otros lotes" "Degradación de modelo" "rate-limited" "aviso de contexto agotándose" "NUNCA mergees" "Dual review obligatorio" "Review dual bloqueante" "Las reglas aquí son obligatorias" "Workflow obligatorio" "invariante 3" "cuatro reglas invariantes" "catálogos" "sección Stack" "levanta servicios automáticamente" "tenía tres de las seis" "Initial project setup" "--public --source" "el CLI sí" "2× el costo" "sección crítica, no abreviar" "ya no tiene bloque" "ya no se distribuye" "ya no los registra" "--repeat-each=10" "CERO mocks" "issue de \`code-sweep\`" ".clients-page__table")

# dangling_grep <patrón>: líneas "ruta:n:texto" del patrón dentro de DANGLING_SCOPE.
dangling_grep() {
  # Solo archivos trackeados: .claude/worktrees/ (untracked) guarda copias
  # viejas del repo con los términos vedados y no es contenido normativo.
  # Salida con rutas relativas a REPO_ROOT.
  local scope_rel=()
  local p probe_err probe_rc
  # Un patrón que rompe a grep (exit 2) no puede pasar por "sin hits": se
  # prueba contra /dev/null y el error sale como salida, igual que en
  # assert_not_contains.
  probe_err=$(grep -q -- "$1" /dev/null 2>&1) && probe_rc=0 || probe_rc=$?
  if [ "$probe_rc" -gt 1 ]; then
    echo "grep falló (exit $probe_rc) para el patrón \"$1\": $probe_err"
    return 0
  fi
  for p in "${DANGLING_SCOPE[@]}"; do scope_rel+=("${p#"$REPO_ROOT"/}"); done
  (cd "$REPO_ROOT" && git ls-files -z -- "${scope_rel[@]}" \
    | xargs -0 grep -n -- "$1" /dev/null 2>/dev/null) || true
}

# CA-14: el barrido solo mira archivos trackeados por git. Un worktree huérfano
# bajo .claude/worktrees/ (untracked) con un término vedado no debe fallar el check.
ORPHAN_DIR="$REPO_ROOT/.claude/worktrees/__dangling-sandbox__"
trap 'rm -rf "$ORPHAN_DIR"' EXIT
mkdir -p "$ORPHAN_DIR"
echo "product-reviewer" > "$ORPHAN_DIR/stale.md"
ORPHAN_HITS=$(dangling_grep "product-reviewer" | (grep -- "^\.claude/worktrees/" || true))
TOTAL=$((TOTAL + 1))
if [ -z "$ORPHAN_HITS" ]; then
  echo -e "${GREEN}PASS${NC}: el barrido de términos colgantes ignora archivos no trackeados bajo .claude/worktrees/"
  PASS=$((PASS + 1))
else
  echo -e "${RED}FAIL${NC}: el barrido vio un archivo no trackeado bajo .claude/worktrees/: $ORPHAN_HITS"
  FAIL=$((FAIL + 1))
fi
rm -rf "$ORPHAN_DIR"
trap - EXIT

for term in "${DANGLING_TERMS[@]}"; do
  TOTAL=$((TOTAL + 1))
  HITS=$( (dangling_grep "$term") \
    | (grep -v -- "^tests/adversarial/test-plugin-manifest.sh:" || true) \
    | (grep -v -- "\.bak:" || true))
  # Excepción documentada: test-frontmatter.sh mantiene "product-reviewer" en
  # HISTORICAL_AGENTS a propósito, para seguir detectando menciones `<agente>`
  # colgantes si alguien lo nombra de nuevo en prosa (ver comentario ahí).
  if [ "$term" = "product-reviewer" ]; then
    HITS=$(echo "$HITS" | (grep -v -- "test-frontmatter.sh:.*HISTORICAL_AGENTS=" || true))
  fi
  HITS=$(echo "$HITS" | (grep -v '^$' || true))
  if [ -z "$HITS" ]; then
    echo -e "${GREEN}PASS${NC}: sin referencias colgantes a \"$term\""
    PASS=$((PASS + 1))
  else
    echo -e "${RED}FAIL${NC}: referencia colgante a \"$term\":"
    echo "$HITS"
    FAIL=$((FAIL + 1))
  fi
done

# El agente "refactor" (viejo) se detecta aparte para no falsear con la
# palabra genérica "refactor" (refactorizar, refactor colateral, etc.):
# solo cuenta la forma que lo nombra como agente, entre backticks.
TOTAL=$((TOTAL + 1))
REFACTOR_AGENT_HITS=$( (dangling_grep '`refactor`') \
  | (grep -v -- "^tests/adversarial/test-plugin-manifest.sh:" || true) \
  | (grep -v -- "\.bak:" || true))
if [ -z "$REFACTOR_AGENT_HITS" ]; then
  echo -e "${GREEN}PASS${NC}: sin referencias colgantes al agente \`refactor\` (viejo)"
  PASS=$((PASS + 1))
else
  echo -e "${RED}FAIL${NC}: referencia colgante al agente \`refactor\` (viejo):"
  echo "$REFACTOR_AGENT_HITS"
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

echo ""
echo "--- code-sweep: rulebook común y agente de respaldo ---"

CS_RULEBOOK="$REPO_ROOT/rulebooks/code-sweep-common.md"
CS_WORKFLOW="$REPO_ROOT/workflows/code-sweep.js"

TOTAL=$((TOTAL + 1))
if [ -f "$CS_RULEBOOK" ]; then
  echo -e "${GREEN}PASS${NC}: rulebooks/code-sweep-common.md existe"
  PASS=$((PASS + 1))
else
  echo -e "${RED}FAIL${NC}: rulebooks/code-sweep-common.md no existe"
  FAIL=$((FAIL + 1))
fi
assert_contains "$CODE_SWEEP" "code-sweep-common.md" "agente code-sweep referencia el rulebook común"
assert_contains "$CODE_SWEEP" "respaldo" "agente code-sweep se declara respaldo del workflow"
assert_not_contains "$CODE_SWEEP" "| Stack | Patrones" "agente code-sweep no duplica la tabla de patrones del rulebook"
assert_agent_read_only "$CODE_SWEEP" "sonnet"

echo ""
echo "--- workflows/code-sweep.js: meta literal, determinismo y sintaxis ---"

TOTAL=$((TOTAL + 1))
if [ -f "$CS_WORKFLOW" ]; then
  echo -e "${GREEN}PASS${NC}: workflows/code-sweep.js existe"
  PASS=$((PASS + 1))
else
  echo -e "${RED}FAIL${NC}: workflows/code-sweep.js no existe"
  FAIL=$((FAIL + 1))
fi

if [ -f "$CS_WORKFLOW" ]; then
  # Primera sentencia no comentada: ignora líneas en blanco y comentarios //.
  CS_FIRST=$(grep -vE '^[[:space:]]*(//.*)?$' "$CS_WORKFLOW" | head -1)
  TOTAL=$((TOTAL + 1))
  case "$CS_FIRST" in
    "export const meta = {"*)
      echo -e "${GREEN}PASS${NC}: la primera sentencia de code-sweep.js es export const meta = {"
      PASS=$((PASS + 1)) ;;
    *)
      echo -e "${RED}FAIL${NC}: la primera sentencia de code-sweep.js no es export const meta = { (es: \"$CS_FIRST\")"
      FAIL=$((FAIL + 1)) ;;
  esac
  assert_contains "$CS_WORKFLOW" 'name: "code-sweep"' "meta de code-sweep.js declara name: \"code-sweep\""
  assert_not_contains "$CS_WORKFLOW" 'Date\.now(' "code-sweep.js no usa Date.now() (rompe resume)"
  assert_not_contains "$CS_WORKFLOW" 'Math\.random(' "code-sweep.js no usa Math.random() (rompe resume)"

  assert_contains "$CS_WORKFLOW" 'MAX_CONCURRENT = 8' "code-sweep.js limita la concurrencia con MAX_CONCURRENT = 8"
  assert_contains "$CS_WORKFLOW" '"verdict"' "code-sweep.js define el schema de hallazgo (verdict)"
  assert_contains "$CS_WORKFLOW" '"manifestation"' "code-sweep.js define el schema de hallazgo (manifestation)"
  assert_contains "$CS_WORKFLOW" 'code-sweep-common.md' "code-sweep.js apunta los prompts al rulebook común"
  assert_contains "$CS_WORKFLOW" 'refuted' "code-sweep.js verifica con veredicto refuted"
  assert_contains "$CS_WORKFLOW" 'gh issue list --label "latent-bug"' "code-sweep.js deduplica issues con gh issue list --label \"latent-bug\""
  assert_contains "$CS_WORKFLOW" 'date -u' "code-sweep.js obtiene la fecha con date -u (no Date.now)"
  assert_contains "$CS_WORKFLOW" 'BLOQUEANTE PRE-RELEASE' "code-sweep.js marca BLOQUEANTE PRE-RELEASE"
  # [lote 10, tarea 1] Los issues no se crean con texto de hallazgos entre comillas dobles.
  assert_not_contains "$CS_WORKFLOW" '--body "' "code-sweep.js no pasa el cuerpo del issue en --body \"...\" (inyección de shell)"
  assert_not_contains "$CODE_SWEEP" '--body "' "agente code-sweep no pasa el cuerpo del issue en --body \"...\" (inyección de shell)"
  assert_contains "$CS_WORKFLOW" '--body-file -' "code-sweep.js crea issues con --body-file -"
  assert_contains "$CODE_SWEEP" '--body-file -' "agente code-sweep crea issues con --body-file -"
  assert_contains "$CS_WORKFLOW" "<<'CS_ISSUE_BODY'" "code-sweep.js usa heredoc con delimitador entre comillas simples"
  assert_contains "$CODE_SWEEP" "<<'CS_ISSUE_BODY'" "agente code-sweep usa heredoc con delimitador entre comillas simples"
  # [lote 10, tarea 2] discover/audit/verify sin Bash: la restricción es de tools, no solo de prompt.
  assert_contains "$CS_WORKFLOW" 'disallowedTools: \["Write", "Edit", "NotebookEdit", "Bash"\]' "code-sweep.js: los agentes de lectura vedan Bash en disallowedTools"
  assert_contains "$CS_WORKFLOW" 'CRÍTICOS sin verificar' "code-sweep.js lista los CRÍTICOS sin verificar de pre-release en su propia sección"
  assert_contains "$CS_WORKFLOW" 'sin evidencia' "code-sweep.js degrada a unverified un confirmed sin evidencia"
  # [lote 10, tarea 3] reporte smells: lo que el pipeline no produce no se pide.
  assert_contains "$CS_WORKFLOW" 'filesScanned' "code-sweep.js pasa filesScanned al consolidador"
  assert_contains "$CS_WORKFLOW" '"refactor"' "code-sweep.js define el campo opcional refactor del hallazgo"
  assert_not_contains "$CS_RULEBOOK" 'coverage X%' "rulebook ya no pide coverage X% por archivo en el reporte smells"
  assert_contains "$CS_RULEBOOK" 'no medido' "rulebook declara el coverage como no medido por el workflow"
  assert_contains "$CS_RULEBOOK" '"refactor"' "rulebook documenta el campo opcional refactor en el schema"
  # [lote 10, tarea 5] enrutamiento donde lo lee el orchestrator.
  assert_contains "$ORCHESTRATOR_SKILL" '/methodology:code-sweep' "skill orchestrator §4 enruta code-sweep al workflow /methodology:code-sweep"
  assert_contains "$RUNBOOK" '/methodology:code-sweep' "runbook Fase 3 enruta code-sweep al workflow /methodology:code-sweep"
  assert_contains "$RUNBOOK" 'Dynamic workflows are not enabled' "runbook documenta el mensaje de workflows no habilitados como disparador del fallback"
  assert_contains "$RUNBOOK" 'Dynamic workflows are disabled by managed settings' "runbook documenta el mensaje de workflows apagados por managed settings"
  assert_contains "$ORCHESTRATOR_SKILL" '^allowed-tools:.*Workflow' "skill orchestrator permite la tool Workflow"

  # [lote 12, tarea 1] filtro determinista de hallazgos antes de crear issues.
  assert_contains "$CS_WORKFLOW" 'SAFE_FILE_RE' "code-sweep.js declara SAFE_FILE_RE (file permitido para issues)"
  assert_contains "$CS_WORKFLOW" 'SAFE_PATTERN_RE' "code-sweep.js declara SAFE_PATTERN_RE (pattern permitido para issues)"
  assert_contains "$CS_WORKFLOW" 'seenFiles\.has' "code-sweep.js exige que el file del issue esté en seenFiles"
  assert_contains "$CS_WORKFLOW" 'excluido de issues' "code-sweep.js declara en NO CUBIERTO los hallazgos excluidos de issues"
  assert_contains "$CS_WORKFLOW" '^const toPersist = .*issueSafe(' "code-sweep.js: toPersist (lo que crea issues) se construye con issueSafe("
  assert_not_contains "$CS_WORKFLOW" '--search "' "code-sweep.js no pasa --search entre comillas dobles (inyección de shell)"
  assert_not_contains "$CS_WORKFLOW" 'CS_ISSUE_BODY_2' "code-sweep.js ya no delega al modelo cambiar el delimitador (CS_ISSUE_BODY_2)"

  if command -v node > /dev/null 2>&1; then
    # El runtime ejecuta el script como cuerpo de una función async (con
    # `return` y `await` al nivel superior), que node --check rechaza como
    # módulo. Se chequea la sintaxis envolviendo el cuerpo y quitando `export`.
    CS_WRAPDIR=$(mktemp -d)
    CS_WRAPPED="$CS_WRAPDIR/code-sweep-wrapped.js"
    { echo 'async function __workflow() {'; sed 's/^export const meta/const meta/' "$CS_WORKFLOW"; echo '}'; } > "$CS_WRAPPED"
    TOTAL=$((TOTAL + 1))
    if node --check "$CS_WRAPPED" > /dev/null 2>&1; then
      echo -e "${GREEN}PASS${NC}: node --check pasa sobre code-sweep.js (cuerpo envuelto)"
      PASS=$((PASS + 1))
    else
      echo -e "${RED}FAIL${NC}: node --check falla sobre code-sweep.js"
      FAIL=$((FAIL + 1))
    fi
    rm -rf "$CS_WRAPDIR"

    # [lote 12, tarea 1] test funcional del filtro: se extraen las constantes y
    # las funciones puras del script (sin el runtime) y se evalúan en node.
    CS_FILTER_DIR=$(mktemp -d)
    CS_FILTER_JS="$CS_FILTER_DIR/filter.js"
    {
      grep -E '^const (SAFE_FILE_RE|SAFE_PATTERN_RE|ISSUE_DELIMITER|ISSUE_TEXT_FIELDS) ' "$CS_WORKFLOW" || true
      awk '/^function issue(ExclusionReason|Safe)\(/ {f=1} f {print} f && /^}/ {f=0}' "$CS_WORKFLOW"
      cat <<'JSEOF'
const seen = new Set(["src/app.js"])
const base = { severity: "ALTO", pattern: "null deref", file: "src/app.js", line: 3, snippet: "x.y", description: "d", manifestation: "m", evidence: "e" }
const cases = [
  ["valido", base, true],
  ["file con comilla simple", { ...base, file: "src/a'b.js" }, false],
  ["file con $(", { ...base, file: "src/$(id).js" }, false],
  ["file fuera de seenFiles", { ...base, file: "src/otro.js" }, false],
  ["pattern con backtick", { ...base, pattern: "null`id`" }, false],
  ["snippet con linea delimitador", { ...base, snippet: "a\n" + ISSUE_DELIMITER + "\nb" }, false],
  ["description que contiene el delimitador", { ...base, description: "xx " + ISSUE_DELIMITER + " yy" }, false],
  ["line string", { ...base, line: "42" }, false],
  ["line no entero", { ...base, line: 4.5 }, false],
  ["pattern con comilla simple", { ...base, pattern: "null'deref" }, false],
  ["evidence con linea delimitador", { ...base, evidence: "a\n" + ISSUE_DELIMITER + "\nb" }, false],
]
let bad = 0
for (const [name, f, want] of cases) {
  const got = issueSafe(f, seen, ISSUE_DELIMITER)
  if (got !== want) { bad++; console.log("MISMATCH " + name + ": " + got) }
}
if (typeof issueExclusionReason === "function" && issueExclusionReason({ ...base, file: "src/a'b.js" }, seen, ISSUE_DELIMITER) === null) { bad++; console.log("MISMATCH reason") }
process.exit(bad === 0 ? 0 : 1)
JSEOF
    } > "$CS_FILTER_JS"
    TOTAL=$((TOTAL + 1))
    if CS_FILTER_OUT=$(node "$CS_FILTER_JS" 2>&1); then
      echo -e "${GREEN}PASS${NC}: issueSafe de code-sweep.js acepta el hallazgo válido y rechaza file/pattern/campos hostiles"
      PASS=$((PASS + 1))
    else
      echo -e "${RED}FAIL${NC}: issueSafe de code-sweep.js no se comporta como se espera: $CS_FILTER_OUT"
      FAIL=$((FAIL + 1))
    fi
    rm -rf "$CS_FILTER_DIR"
  else
    echo "SKIP: 'node' no está en PATH — se omite node --check de code-sweep.js"
  fi
fi


echo ""
echo "--- Conteo de workflows: workflows/*.js vs README vs marketplace ---"

CS_WF_COUNT=$(ls "$REPO_ROOT"/workflows/*.js 2> /dev/null | wc -l | tr -d ' ')
assert_contains "$REPO_ROOT/README.md" "^### Workflows ($CS_WF_COUNT)" "README declara ### Workflows ($CS_WF_COUNT) igual a ls workflows/*.js"
assert_contains "$REPO_ROOT/.claude-plugin/marketplace.json" "$CS_WF_COUNT workflow" "marketplace.json declara $CS_WF_COUNT workflow igual a ls workflows/*.js"
assert_contains "$REPO_ROOT/README.md" '/methodology:code-sweep \[bugs.*smells\] \[pre-release\] \[paths\]' "README documenta la invocación de /methodology:code-sweep"
assert_contains "$REPO_ROOT/README.md" 'Dynamic workflows are disabled by managed settings' "README documenta el mensaje del harness con workflows apagados"

echo ""
echo "--- Conteo de hooks: hooks/*.sh vs README vs marketplace ---"

HOOK_COUNT=$(ls "$HOOKS_DIR"/*.sh | wc -l | tr -d ' ')
assert_contains "$REPO_ROOT/README.md" "^### Hooks ($HOOK_COUNT)" "README declara ### Hooks ($HOOK_COUNT) igual a ls hooks/*.sh"
assert_contains "$MARKETPLACE_JSON" "$HOOK_COUNT hooks" "marketplace.json declara $HOOK_COUNT hooks igual a ls hooks/*.sh"
assert_contains "$REPO_ROOT/README.md" 'permissionDecision: "ask"' "README documenta que pre-merge-check devuelve ask con las verificaciones en verde"

echo ""
echo "--- governance-playbook #9: sin context-monitor, con pre-compact-snapshot ---"

assert_not_contains "$GOVERNANCE" "context-monitor" "governance-playbook ya no menciona context-monitor"
assert_contains "$GOVERNANCE" "pre-compact-snapshot" "governance-playbook #9 apunta a pre-compact-snapshot"

echo ""
echo "--- Lote 4: tier del flujo en el runbook ---"

# El bloque JSON del schema de state.json (primer ```json tras "Schema de `state.json`") declara "tier".
RUNBOOK_STATE_JSON_BLOCK=$(awk '/^\*\*Schema de `state.json`/ {f=1} f && /^```json/ {b=1; next} b && /^```/ {exit} b {print}' "$RUNBOOK")
assert_section_contains "$RUNBOOK_STATE_JSON_BLOCK" '"tier"' "runbook: el bloque JSON del schema de state.json contiene \"tier\""
assert_contains "$RUNBOOK" "Tier del flujo" "runbook tiene la sección Tier del flujo"
assert_contains "$RUNBOOK" "liviano" "runbook describe el tier liviano"
assert_contains "$RUNBOOK" "escalada" "runbook describe la escalada a completo"
assert_contains "$RUNBOOK" "sexto archivo" "runbook fija el límite de edición directa (sexto archivo)"

echo ""
echo "--- Lote 4: skill orchestrator con tier liviano ---"

for term in liviano completo AskUserQuestion "sexto archivo"; do
  assert_contains "$ORCHESTRATOR_SKILL" "$term" "skill orchestrator menciona \"$term\""
done
assert_not_contains "$ORCHESTRATOR_SKILL" "el CLI sí" "skill orchestrator ya no afirma que el CLI sí expone TaskCreate"

echo ""
echo "--- Lote 4: review simple con code-review y fallback a qa-* ---"

TOTAL=$((TOTAL + 1))
if echo "$ORCH_ALLOWED_TOOLS" | grep -qF "Skill(code-review)"; then
  echo -e "${GREEN}PASS${NC}: allowed-tools declara Skill(code-review)"
  PASS=$((PASS + 1))
else
  echo -e "${RED}FAIL${NC}: allowed-tools no declara Skill(code-review)"
  FAIL=$((FAIL + 1))
fi
assert_contains "$REPO_ROOT/skills/pr-workflow/SKILL.md" "code-review" "pr-workflow describe la invocación de code-review"
assert_contains "$RUNBOOK" "code-review" "runbook (Fase 2.6) describe code-review en tier liviano"
assert_contains "$ORCHESTRATOR_SKILL" "code-review" "skill orchestrator (fila 2.6) menciona code-review"
# Párrafo "En tier liviano" del runbook: desde su inicio hasta la primera línea en blanco.
RUNBOOK_LIVIANO_PARA=$(awk '/^\*\*En tier liviano\*\*/ {f=1} f && /^$/ {exit} f {print}' "$RUNBOOK")
assert_section_contains "$RUNBOOK_LIVIANO_PARA" "qa-" "runbook: el párrafo de tier liviano describe el fallback a qa-*"
assert_section_contains "$RUNBOOK_LIVIANO_PARA" "review_sha" "runbook: el párrafo de tier liviano cierra con review_sha como 2.6"

echo ""
echo "--- Lote 4: handoff en dos modos (paquete mínimo o fork) ---"

assert_contains "$ORCHESTRATOR_SKILL" "fork" "skill orchestrator §5 describe el modo fork"
assert_contains "$RUNBOOK" "fork" "runbook (template de handoff) describe cuándo usar fork"
assert_not_contains "$ORCHESTRATOR_SKILL" "nunca el historial completo" "skill orchestrator ya no prohíbe el historial completo"
assert_not_contains "$RUNBOOK" "no el historial completo ni tareas de otros lotes" "runbook ya no prohíbe el historial completo"

echo ""
echo "--- Lote 5: fallbackModel en lugar de degradación manual ---"

assert_not_contains "$ORCHESTRATOR_SKILL" "Degradación de modelo" "skill orchestrator ya no describe degradación manual de modelo"
assert_not_contains "$ORCHESTRATOR_SKILL" "rate-limited" "skill orchestrator ya no menciona rate-limited"
assert_not_contains "$ORCHESTRATOR_SKILL" "fallback: opus" "skill orchestrator: la fila del architect no declara fallback: opus"
assert_contains "$ORCHESTRATOR_SKILL" "fallbackModel" "skill orchestrator remite a fallbackModel del harness"

echo ""
echo "--- Lote 5: lotes paralelos (worktree por llamada o mismo checkout) ---"

assert_contains "$RUNBOOK" 'isolation: "worktree"' "runbook describe isolation: \"worktree\" por llamada"
assert_contains "$RUNBOOK" "baseRef" "runbook exige worktree.baseRef"
assert_contains "$RUNBOOK" "git worktree remove" "runbook describe la limpieza del worktree"
assert_contains "$RUNBOOK" "git branch -d" "runbook describe borrar la rama worktree-*"
assert_contains "$RUNBOOK" "pathspec" "runbook describe commits con pathspec en mismo checkout"
assert_contains "$ORCHESTRATOR_SKILL" "baseRef" "skill orchestrator (reglas clave) menciona baseRef"
assert_contains "$ORCHESTRATOR_SKILL" "pathspec" "skill orchestrator (reglas clave) menciona pathspec"

echo ""
echo "--- Lote 5: governance #11 worktree huérfano ---"

assert_contains "$GOVERNANCE" "worktree-" "governance-playbook #11 cubre ramas worktree-*"
assert_contains "$GOVERNANCE" "## 11." "governance-playbook tiene el caso #11"

echo ""
echo "--- Lote 7: reconciliación de invariantes por nombre ---"

PR_WORKFLOW_SKILL="$REPO_ROOT/skills/pr-workflow/SKILL.md"
assert_not_contains "$PR_WORKFLOW_SKILL" "invariante 3" "pr-workflow ya no cita la invariante por número"
assert_contains "$RUNBOOK" "prompt de permiso" "runbook Fase 5: el hook pide la confirmación en el prompt de permiso"
assert_not_contains "$ORCHESTRATOR_SKILL" "Workflow obligatorio" "skill orchestrator cita la sección Workflow por su nombre nuevo"
assert_not_contains "$PR_WORKFLOW_SKILL" "catálogos" "pr-workflow ya no cuenta la anécdota de catálogos"
assert_contains "$README" "liviano" "README describe el tier liviano"

# D-14: lo distribuido por el plugin cita el archivo instalado (~/.claude/CLAUDE.md),
# no la ruta global/CLAUDE.md de este repo. README, .claude/CLAUDE.md e install.sh quedan fuera.
GLOBAL_PATH_HITS=$( (cd "$REPO_ROOT" && git ls-files -z -- agents skills rules rulebooks | xargs -0 grep -n -- "global/CLAUDE.md" /dev/null 2>/dev/null) || true)
TOTAL=$((TOTAL + 1))
if [ -z "$GLOBAL_PATH_HITS" ]; then
  echo -e "${GREEN}PASS${NC}: agents/, skills/, rules/ y rulebooks/ no citan global/CLAUDE.md"
  PASS=$((PASS + 1))
else
  echo -e "${RED}FAIL${NC}: citan global/CLAUDE.md en vez de ~/.claude/CLAUDE.md: $GLOBAL_PATH_HITS"
  FAIL=$((FAIL + 1))
fi

echo ""
echo "--- Lote 8: residual del prompt-audit ---"

E2E_RUNNER="$REPO_ROOT/agents/e2e-runner.md"
assert_not_contains "$E2E_RUNNER" "--repeat-each=10" "e2e-runner usa un solo umbral de estabilidad"
assert_contains "$E2E_RUNNER" "--repeat-each=5" "e2e-runner fija --repeat-each=5"
assert_not_contains "$E2E_RUNNER" "## Debugging sistemático cuando un test es flaky" "e2e-runner funde el debugging de flaky en Tests flaky"
assert_not_contains "$E2E_RUNNER" "levanta servicios automáticamente" "e2e-runner: docker-refresh solo sugiere, no levanta"
WAIT_MENTIONS=$(grep -c 'NUNCA `waitForTimeout' "$E2E_RUNNER" || true)
TOTAL=$((TOTAL + 1))
if [ "$WAIT_MENTIONS" -eq 0 ]; then
  echo -e "${GREEN}PASS${NC}: e2e-runner no repite NUNCA waitForTimeout"
  PASS=$((PASS + 1))
else
  echo -e "${RED}FAIL${NC}: e2e-runner repite NUNCA waitForTimeout ($WAIT_MENTIONS veces)"
  FAIL=$((FAIL + 1))
fi

SELF_REFLECTION="$REPO_ROOT/rules/self-reflection.md"
IMPL_PRINCIPLES="$REPO_ROOT/rules/implementation-principles.md"
assert_not_contains "$SELF_REFLECTION" "sección Stack" "self-reflection remite a la sección Reglas por lenguaje, no a Stack"
assert_contains "$SELF_REFLECTION" "candidato para el reporte de" "self-reflection: el barrido va al reporte de code-sweep"
assert_contains "$IMPL_PRINCIPLES" "candidato para el reporte de" "implementation-principles: el barrido va al reporte de code-sweep"
assert_not_contains "$IMPL_PRINCIPLES" "\.clients-page__table" "implementation-principles: ejemplo de CSS sin selector de proyecto"
assert_not_contains "$IMPL_PRINCIPLES" "post-pr-create.sh" "implementation-principles: ejemplo de hook sin nombre de proyecto"
assert_not_contains "$IMPL_PRINCIPLES" "etimes" "implementation-principles: ejemplo de plataforma sin flag concreto"

assert_not_contains "$REPO_ROOT/agents/backend-dev.md" "sección crítica, no abreviar" "backend-dev: Testing sin énfasis"
assert_not_contains "$REPO_ROOT/agents/ui-ux.md" "2× el costo" "ui-ux: sin multiplicador de costo"
assert_not_contains "$REPO_ROOT/rulebooks/dev-common.md" "formato definido en CLAUDE.md raíz" "dev-common cita ~/.claude/CLAUDE.md para el formato de commits"
assert_not_contains "$RUNBOOK" "las invariantes viven en \`CLAUDE.md\` raíz" "runbook cita ~/.claude/CLAUDE.md para las invariantes"

REPO_CLAUDE_MD="$REPO_ROOT/.claude/CLAUDE.md"
assert_not_contains "$REPO_CLAUDE_MD" "## \`rules/\` vs \`rulebooks/\`" ".claude/CLAUDE.md reduce la sección a rules/"
assert_not_contains "$REPO_CLAUDE_MD" "ya no tiene bloque" ".claude/CLAUDE.md describe el estado actual del registro de hooks"
assert_not_contains "$REPO_CLAUDE_MD" "ya no los registra" ".claude/CLAUDE.md describe el estado actual de settings.json"
assert_contains "$REPO_CLAUDE_MD" "Declara siempre" ".claude/CLAUDE.md pide declarar paths: en rules/"

# --- Configuración recomendada del harness (README e install.sh) ---
README_MD="$REPO_ROOT/README.md"
for term in "Configuración recomendada del harness" fallbackModel baseRef agent-memory security-guidance; do
  assert_contains "$README_MD" "$term" "README.md documenta $term"
done

INSTALL_SH="$REPO_ROOT/install.sh"
for term in "Recomendaciones" security-guidance fallbackModel baseRef agent-memory; do
  assert_contains "$INSTALL_SH" "$term" "install.sh recomienda $term"
done
TOTAL=$((TOTAL + 1))
if bash -n "$INSTALL_SH" 2>/dev/null; then
  echo -e "${GREEN}PASS${NC}: install.sh pasa bash -n"
  PASS=$((PASS + 1))
else
  echo -e "${RED}FAIL${NC}: install.sh no pasa bash -n"
  FAIL=$((FAIL + 1))
fi

# --- Compatibilidad con bash 3.2 (D-19) ---
# Patrón armado por partes para que este mismo check no se detecte a sí mismo.
BASH4_PATTERN="declare -""A|map""file|read""array|\\$\\{[A-Za-z_]+(,,|\\^\\^)"
for suite in test-hooks.sh test-plugin-manifest.sh test-frontmatter.sh; do
  BASH4_RC=0
  BASH4_HITS=$(grep -nE -- "$BASH4_PATTERN" "$REPO_ROOT/tests/adversarial/$suite" 2>&1) || BASH4_RC=$?
  TOTAL=$((TOTAL + 1))
  if [ "$BASH4_RC" -eq 1 ]; then
    echo -e "${GREEN}PASS${NC}: $suite sin construcciones de bash 4"
    PASS=$((PASS + 1))
  else
    echo -e "${RED}FAIL${NC}: $suite usa construcciones de bash 4 o grep falló (rc=$BASH4_RC): $BASH4_HITS"
    FAIL=$((FAIL + 1))
  fi
done

# --- Lote 11 / tarea 1: ruta real de la memoria (D-21) ---
for f in rulebooks/reviewer-common.md agents/qa-backend.md agents/qa-frontend.md agents/security-reviewer.md; do
  assert_contains "$REPO_ROOT/$f" "agent-memory/methodology-" "$f cita la ruta real agent-memory/methodology-<agente>"
done
assert_not_contains "$README_MD" "agent-memory/<agente>" "README.md no usa la ruta vieja agent-memory/<agente>"
assert_not_contains "$INSTALL_SH" "agent-memory/<agente>" "install.sh no usa la ruta vieja agent-memory/<agente>"
assert_contains "$REPO_ROOT/rulebooks/reviewer-common.md" "ni por Bash" "reviewer-common §9: el reviewer no escribe la memoria ni por Bash"

# --- Lote 11 / tarea 2: orchestrator único escritor de la memoria y anti-envenenamiento ---
assert_contains "$RUNBOOK" "memory: actualizar memoria de" "runbook Fase 2.6: el orchestrator commitea la memoria con memory:"
assert_contains "$RUNBOOK" "### Memoria" "runbook: el formato de reporte trae la sección ### Memoria"
assert_contains "$RUNBOOK" "25 KB" "runbook Fase 2.6: tope de 25 KB de MEMORY.md"
assert_contains "$REPO_ROOT/rulebooks/reviewer-common.md" "no se consideran" "reviewer-common §9: las entradas de un diff que toca la memoria no se consideran"
assert_contains "$ORCHESTRATOR_SKILL" "agent-memory" "skill orchestrator remite al volcado de memoria"
assert_contains "$REPO_ROOT/skills/pr-workflow/SKILL.md" "agent-memory" "skill pr-workflow §2 remite al volcado de memoria"

# --- Lote 11 / tarea 3: señales de riesgo del tier ---
assert_contains "$RUNBOOK" "^1\. Toca auth.*pagos, PII, CORS" "runbook: la señal 1 (línea numerada) incluye PII"
assert_contains "$RUNBOOK" "deserializa" "runbook: señal 8 de input externo que se deserializa"
assert_contains "$RUNBOOK" "settings del harness o \`.claude/agent-memory/\`" "runbook: señal 4 incluye .claude/agent-memory/"
assert_contains "$RUNBOOK" "phases.design = \"pending\"\` y \`phases.docs = \"pending\"" "runbook: la escalada vuelve phases.design y phases.docs a pending"
assert_contains "$RUNBOOK" "8 señales" "runbook cuenta 8 señales"
assert_not_contains "$RUNBOOK" "7 señales" "runbook ya no cuenta 7 señales"
assert_contains "$ORCHESTRATOR_SKILL" "phases.design = \"pending\"\` y \`phases.docs = \"pending\"" "skill orchestrator: la escalada vuelve phases.design y phases.docs a pending"
assert_contains "$GLOBAL_CLAUDE_MD" "seis pasos" "global: la edición directa aplica los seis pasos pre-commit"
assert_contains "$ORCHESTRATOR_SKILL" "seis pasos" "skill orchestrator: la edición directa aplica los seis pasos pre-commit"
assert_contains "$README_MD" "señales 1, 4 u 8" "README: condición del security-reviewer en liviano (señales 1, 4 u 8)"

# --- Lote 12 / tarea 3: condición del security-reviewer en liviano = señales 1, 4 u 8 ---
for f in global/CLAUDE.md skills/orchestrator/SKILL.md skills/pr-workflow/SKILL.md rulebooks/orchestrator-runbook.md README.md; do
  assert_contains "$REPO_ROOT/$f" "señales 1, 4 u 8" "$f: security-reviewer en liviano si el diff toca las señales 1, 4 u 8"
done
for f in global/CLAUDE.md skills/orchestrator/SKILL.md skills/pr-workflow/SKILL.md rulebooks/orchestrator-runbook.md README.md; do
  assert_not_contains "$REPO_ROOT/$f" "pagos o PII" "$f ya no usa la condición vieja (auth, crypto, secrets, pagos o PII)"
done
assert_contains "$RUNBOOK" "no cuentan para" "runbook: los archivos del commit memory: no cuentan para el tamaño ni disparan la señal 4"
assert_contains "$RUNBOOK" "viaja en el push consolidado" "runbook Fase 2.6 paso 6: con el PR abierto el commit memory: viaja en el push consolidado de la ronda"

# --- Lote 12 / tarea 4: volcado de memoria con criterio ---
RUNBOOK_MEM_STEP=$(grep -E '^6\. \*\*Memoria de los reviewers\*\*' "$RUNBOOK" || true)
assert_section_contains "$RUNBOOK_MEM_STEP" "formato exacto" "runbook paso 6: persiste solo líneas con el formato exacto de §9"
assert_section_contains "$RUNBOOK_MEM_STEP" "falso-positivo" "runbook paso 6: el falso-positivo se persiste solo si fue confirmado en la sesión"
assert_section_contains "$RUNBOOK_MEM_STEP" "ghp_" "runbook paso 6: descarta las líneas que matchean patrones de secrets (ghp_, sk-, AKIA)"
assert_section_contains "$RUNBOOK_MEM_STEP" "cite código del diff" "runbook paso 6: descarta las entradas que citan código del diff"
assert_section_contains "$RUNBOOK_MEM_STEP" "agent-memory/\*\*" "runbook paso 6: no persiste nada de un review cuyo diff tocó agent-memory/**"
assert_contains "$ORCHESTRATOR_SKILL" "formato exacto" "skill orchestrator: el volcado de memoria filtra por formato exacto"
assert_contains "$REPO_ROOT/rulebooks/reviewer-common.md" "posterior al review" "reviewer-common §9: un commit memory: del orchestrator posterior al review no se reporta como hallazgo"

# --- Lote 11 / tarea 4: ask en modos no interactivos, liviano, runbook, e2e-runner, Workflow ---
OLD_UNVERIFIED="sin verificar end-to-end en esta versión"
VERIFIED_MARK="verificado el 2026-10-28"
PENDING_MARK='sin verificar: `-p`'
for f in README.md rulebooks/orchestrator-runbook.md skills/pr-workflow/SKILL.md global/CLAUDE.md hooks/pre-merge-check.sh; do
  assert_contains "$REPO_ROOT/$f" "$VERIFIED_MARK" "$f: declara lo verificado del ask (2026-10-28)"
  assert_contains "$REPO_ROOT/$f" "$PENDING_MARK" "$f: sigue declarando sin verificar -p/dontAsk/bypassPermissions"
  assert_not_contains "$REPO_ROOT/$f" "$OLD_UNVERIFIED" "$f: sin la frase vieja de no verificado end-to-end"
  assert_not_contains "$REPO_ROOT/$f" "también en auto mode" "$f no afirma que el ask funcione también en auto mode"
done
assert_not_contains "$README_MD" "se resuelve como denegación;" "README: el ask no afirma denegación en -p/dontAsk"
assert_not_contains "$README_MD" "en modos no interactivos se deniega\." "README (flujo): el ask no afirma denegación sin verificar"
assert_contains "$GLOBAL_CLAUDE_MD" "en cualquier modo" "global PR y merge #3: la aprobación en la conversación rige en cualquier modo"
assert_contains "$GLOBAL_CLAUDE_MD" "agente \`docs\`" "global: el liviano salta el agente docs"
assert_contains "$README_MD" "agente \`docs\`" "README: el liviano salta el agente docs"
assert_contains "$README_MD" "sexto archivo" "README: el liviano delega un único lote al sexto archivo"
assert_contains "$README_MD" "checks en verde" "README pre-merge-check: motivo del ask con checks en verde"
assert_contains "$README_MD" "sin checks configurados" "README pre-merge-check: motivo del ask sin checks configurados"
assert_contains "$RUNBOOK" "instalado como" "runbook cita el núcleo global como instalado como ~/.claude/CLAUDE.md"
assert_not_contains "$RUNBOOK" "el núcleo global del repo" "runbook sin la perífrasis del núcleo global del repo"
assert_contains "$ORCHESTRATOR_SKILL" "Workflow(methodology:code-sweep)" "skill orchestrator: allowed-tools acota el Workflow a code-sweep"
assert_not_contains "$ORCHESTRATOR_SKILL" ", Workflow$" "skill orchestrator: sin Workflow a secas en allowed-tools"
assert_not_contains "$ORCHESTRATOR_SKILL" ", Workflow," "skill orchestrator: sin Workflow a secas intercalado en allowed-tools"
assert_contains "$E2E_RUNNER" "4. \*\*Fix\*\* — agrega waits" "e2e-runner: Verifica y Fix son pasos distintos"

# --- Lote 11 / tarea 5: asserts faltantes (hunk 10, umbrales del tier, memoria) ---
for dev in frontend-dev architect backend-dev; do
  assert_contains "$REPO_ROOT/agents/$dev.md" '~/.claude/CLAUDE.md' "$dev cita ~/.claude/CLAUDE.md (hunk 10)"
done
assert_not_contains "$REPO_ROOT/agents/frontend-dev.md" 'Ver "Frontend delgado" en CLAUDE.md raíz' "frontend-dev (~25) remite Frontend delgado a ~/.claude/CLAUDE.md"
assert_not_contains "$REPO_ROOT/agents/frontend-dev.md" 'Ver CLAUDE.md raíz para exclusiones' "frontend-dev (~53) remite las exclusiones a ~/.claude/CLAUDE.md"
assert_not_contains "$REPO_ROOT/agents/architect.md" 'definido en CLAUDE.md raíz' "architect (~92) remite Frontend delgado a ~/.claude/CLAUDE.md"
assert_not_contains "$REPO_ROOT/agents/backend-dev.md" '(ver CLAUDE.md raíz)' "backend-dev (~20) remite el escape hatch de TDD a ~/.claude/CLAUDE.md"
assert_not_contains "$REPO_ROOT/agents/backend-dev.md" 'ver CLAUDE.md raíz para exclusiones' "backend-dev (~41) remite las exclusiones a ~/.claude/CLAUDE.md"
assert_contains "$REPO_ROOT/agents/architect.md" 'Leer `CLAUDE.md` raíz' "architect (~35) sigue leyendo el CLAUDE.md del proyecto"
assert_contains "$RUNBOOK" '≤10 archivos' "runbook: umbral de ≤10 archivos del tier liviano"
assert_contains "$RUNBOOK" '300 líneas' "runbook: umbral de 300 líneas del tier liviano"
assert_contains "$RUNBOOK" 'sexto archivo' "runbook: umbral del sexto archivo en edición directa"
assert_contains "$GLOBAL_CLAUDE_MD" 'Piden confirmación' "global: lista lo que pide confirmación"
assert_contains "$RUNBOOK" 'toque exclusivamente' "runbook señal 4: la excepción memory: vale solo si el commit toca exclusivamente agent-memory"
assert_contains "$REPO_ROOT/rulebooks/reviewer-common.md" 'git show --name-only' "reviewer-common §9: el reviewer comprueba el commit memory: con git show --name-only"
assert_contains "$RUNBOOK" 'Muestra al usuario, en el reporte de fase' "runbook Fase 2.6 paso 6: el orchestrator muestra al usuario las líneas de memoria que persiste"
assert_contains "$REPO_ROOT/skills/orchestrator/SKILL.md" 'Muestras al usuario, en el reporte de fase' "SKILL orchestrator: muestra al usuario las líneas de memoria que persiste"
assert_contains "$REPO_ROOT/rulebooks/reviewer-common.md" '200 líneas' "reviewer-common §9: tope de 200 líneas de MEMORY.md"
assert_contains "$REPO_ROOT/rulebooks/reviewer-common.md" '25 KB' "reviewer-common §9: tope de 25 KB de MEMORY.md"
for rv in security-reviewer qa-backend qa-frontend; do
  assert_contains "$REPO_ROOT/agents/$rv.md" '### Memoria' "$rv: el formato de reporte trae ### Memoria"
done

# dangling_grep: un error de grep (exit 2) no se confunde con "sin hits".
INVALID_HITS=$(dangling_grep '[')
TOTAL=$((TOTAL + 1))
if echo "$INVALID_HITS" | grep -q "grep falló"; then
  echo -e "${GREEN}PASS${NC}: dangling_grep reporta el error de grep ante un patrón inválido"
  PASS=$((PASS + 1))
else
  echo -e "${RED}FAIL${NC}: dangling_grep devolvió \"$INVALID_HITS\" ante un patrón inválido (esperado: mensaje \"grep falló\")"
  FAIL=$((FAIL + 1))
fi

# --- /code-sweep tests ---

# --- Resumen ---
echo "=== Results ==="
echo -e "Total: $TOTAL | ${GREEN}Pass: $PASS${NC} | ${RED}Fail: $FAIL${NC}"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
