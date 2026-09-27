#!/bin/bash
# Adversarial tests for agent/skill frontmatter (agents/*.md, skills/*/SKILL.md).
#
# Verifica (contrato en .planning/DESIGN.md, sección "Contratos"):
#   (a) claves de agentes: solo las permitidas; las ignoradas por el plugin
#       (permissionMode, hooks, mcpServers, initialPrompt) no aparecen.
#   (b) valores de memory/effort/model dentro de su enum.
#   (c) name == nombre del archivo (sin .md).
#   (d) allowed-tools de skills: toda entrada Agent(x) tiene forma
#       Agent(methodology:<agente>) con <agente> existente en agents/.
#   (e) disable-model-invocation: true obligatorio en new-project y
#       refactor-scan, ausente en pr-workflow y review-pr.
#   (f) toda referencia methodology:<x> en agents/ rulebooks/ skills/
#       README.md .claude/CLAUDE.md apunta a un agente que existe.
#   (g) toda mención `<agente>` (sin prefijo methodology:) de la lista
#       histórica de nombres de agentes, en los mismos directorios, apunta
#       a un archivo agents/<agente>.md existente. La lista es fija (no se
#       deriva de agents/) para que borrar un agente sin limpiar sus
#       menciones en prosa haga fallar este check (RED del PR 3, ver
#       .planning/DESIGN.md, sección "Contratos").
#   (h) una skill invocable por el modelo (sin disable-model-invocation:
#       true) no tiene Bash en ninguna forma (Bash, Bash(...)) en
#       allowed-tools: allowed-tools SUMA pre-aprobaciones, no restringe
#       (verificado ejecutando, ver .planning/reviews/pre-pr-orchestrator-skill.md,
#       Ronda 2, M2). Las skills solo invocables por el usuario quedan
#       exentas: su invocación ya es una decisión explícita del usuario.
#
# Uso: bash tests/adversarial/test-frontmatter.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
AGENTS_DIR="$REPO_ROOT/agents"
SKILLS_DIR="$REPO_ROOT/skills"

PASS=0
FAIL=0
TOTAL=0

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

ALLOWED_KEYS="name description model tools disallowedTools maxTurns skills memory background omitClaudeMd effort isolation"
FORBIDDEN_KEYS="permissionMode hooks mcpServers initialPrompt"
ALLOWED_MEMORY="user project local"
ALLOWED_EFFORT="low medium high xhigh max"
ALLOWED_MODEL="sonnet opus haiku fable inherit"

# Lista histórica de nombres de agentes (deliberadamente hardcodeada, NO
# derivada de "$AGENTS_DIR"/*.md): si un agente se borra de agents/ pero
# queda mencionado en prosa como `<agente>` en otro directorio del
# contrato, esta lista sigue conociendo el nombre y el check (g) más abajo
# lo reporta como mención colgante en vez de dejar de verificarlo.
HISTORICAL_AGENTS="architect backend-dev build-resolver db-specialist docs e2e-runner frontend-dev latent-bugs-sweep qa-backend qa-frontend refactor security-reviewer ui-ux"

pass() { echo -e "${GREEN}PASS${NC}: $1"; PASS=$((PASS + 1)); }
fail() { echo -e "${RED}FAIL${NC}: $1"; FAIL=$((FAIL + 1)); }
check() { TOTAL=$((TOTAL + 1)); if [ "$1" = "0" ]; then pass "$2"; else fail "$2"; fi; }

# frontmatter_block <file>: imprime las líneas entre el primer y el segundo "---".
frontmatter_block() {
  awk '/^---$/{c++; next} c==1{print} c==2{exit}' "$1"
}

# frontmatter_keys <file>: una clave por línea (lo que precede a ":" al inicio de línea).
frontmatter_keys() {
  frontmatter_block "$1" | grep -oE '^[A-Za-z_-]+:' | sed 's/:$//'
}

# frontmatter_value <file> <key>: valor crudo de una clave de línea única, sin comillas.
frontmatter_value() {
  frontmatter_block "$1" | grep -E "^$2:" | head -1 | sed -E "s/^$2:[[:space:]]*//; s/^\"(.*)\"\$/\1/"
}

word_in_list() {
  local word="$1" list="$2"
  for w in $list; do [ "$w" = "$word" ] && return 0; done
  return 1
}

# check_agent_backtick_mentions <agents_dir> <target...>: imprime por
# stdout, uno por línea, los nombres de HISTORICAL_AGENTS mencionados como
# `<agente>` en alguno de los targets que NO tienen "<agents_dir>/<agente>.md".
# Vacío si todas las menciones encontradas resuelven a un archivo.
check_agent_backtick_mentions() {
  local agents_dir="$1"
  shift
  local name
  for name in $HISTORICAL_AGENTS; do
    if grep -rlq -- "\`$name\`" "$@" 2>/dev/null; then
      [ -f "$agents_dir/$name.md" ] || echo "$name"
    fi
  done
}

echo "--- Sandbox: el lint detecta clave prohibida y valor fuera de enum ---"

SANDBOX_AGENT=$(mktemp)
cat > "$SANDBOX_AGENT" <<'EOF'
---
name: sandbox-agent
description: agente de prueba
model: gpt5
memory: true
permissionMode: plan
---
EOF

sandbox_keys=$(frontmatter_keys "$SANDBOX_AGENT")
TOTAL=$((TOTAL + 1))
if echo "$sandbox_keys" | grep -qx "permissionMode"; then
  pass "el lint detecta la clave prohibida permissionMode en el sandbox"
else
  fail "el lint no detectó permissionMode en el sandbox"
fi

TOTAL=$((TOTAL + 1))
sandbox_memory=$(frontmatter_value "$SANDBOX_AGENT" "memory")
if ! word_in_list "$sandbox_memory" "$ALLOWED_MEMORY"; then
  pass "el lint detecta memory=$sandbox_memory fuera del enum en el sandbox"
else
  fail "el lint no detectó memory=$sandbox_memory como inválido en el sandbox"
fi
rm -f "$SANDBOX_AGENT"

echo ""
echo "--- Sandbox: el lint detecta mención \`<agente>\` colgante (agente borrado) ---"

SANDBOX_HIST_DIR=$(mktemp -d)
mkdir -p "$SANDBOX_HIST_DIR/agents" "$SANDBOX_HIST_DIR/docs"
# Simula que build-resolver fue borrado de agents/ pero una mención en
# prosa (sin prefijo methodology:) sigue viva en otro directorio. No toca
# los agentes reales del repo.
cat > "$SANDBOX_HIST_DIR/agents/backend-dev.md" <<'EOF'
placeholder
EOF
cat > "$SANDBOX_HIST_DIR/docs/mention.md" <<'EOF'
Cuando el build falla, se invoca a `build-resolver` para diagnosticar.
EOF

TOTAL=$((TOTAL + 1))
SANDBOX_HIST_RESULT=$(check_agent_backtick_mentions "$SANDBOX_HIST_DIR/agents" "$SANDBOX_HIST_DIR/docs")
if [ "$SANDBOX_HIST_RESULT" = "build-resolver" ]; then
  pass "el lint detecta la mención colgante \`build-resolver\` cuando el agente fue borrado"
else
  fail "el lint no detectó la mención colgante \`build-resolver\` (resultado: \"$SANDBOX_HIST_RESULT\")"
fi

# Control positivo: si el archivo existe, la misma mención no es colgante.
cat > "$SANDBOX_HIST_DIR/agents/build-resolver.md" <<'EOF'
placeholder
EOF
TOTAL=$((TOTAL + 1))
SANDBOX_HIST_RESULT_OK=$(check_agent_backtick_mentions "$SANDBOX_HIST_DIR/agents" "$SANDBOX_HIST_DIR/docs")
if [ -z "$SANDBOX_HIST_RESULT_OK" ]; then
  pass "el lint no reporta \`build-resolver\` como colgante cuando agents/build-resolver.md existe"
else
  fail "el lint reportó \`build-resolver\` como colgante aunque el archivo existe (resultado: \"$SANDBOX_HIST_RESULT_OK\")"
fi

rm -rf "$SANDBOX_HIST_DIR"

echo ""
echo "--- agents/*.md: claves permitidas, sin claves ignoradas por el plugin ---"

for agent_file in "$AGENTS_DIR"/*.md; do
  agent_name="$(basename "$agent_file" .md)"

  keys=$(frontmatter_keys "$agent_file")

  bad_key=""
  for key in $keys; do
    if ! word_in_list "$key" "$ALLOWED_KEYS"; then
      bad_key="$key"
      break
    fi
  done
  check "$([ -z "$bad_key" ] && echo 0 || echo 1)" \
    "$agent_name: sin claves fuera del set permitido${bad_key:+ (encontrada: $bad_key)}"

  forbidden_found=""
  for key in $FORBIDDEN_KEYS; do
    if echo "$keys" | grep -qx "$key"; then
      forbidden_found="$key"
      break
    fi
  done
  check "$([ -z "$forbidden_found" ] && echo 0 || echo 1)" \
    "$agent_name: sin claves ignoradas por el plugin${forbidden_found:+ (encontrada: $forbidden_found)}"

  name_value=$(frontmatter_value "$agent_file" "name")
  check "$([ "$name_value" = "$agent_name" ] && echo 0 || echo 1)" \
    "$agent_name: name=\"$name_value\" coincide con el nombre del archivo"

  model_value=$(frontmatter_value "$agent_file" "model")
  if [ -n "$model_value" ]; then
    check "$(word_in_list "$model_value" "$ALLOWED_MODEL" && echo 0 || echo 1)" \
      "$agent_name: model=\"$model_value\" dentro del enum"
  fi

  memory_value=$(frontmatter_value "$agent_file" "memory")
  if [ -n "$memory_value" ]; then
    check "$(word_in_list "$memory_value" "$ALLOWED_MEMORY" && echo 0 || echo 1)" \
      "$agent_name: memory=\"$memory_value\" dentro del enum"
  fi

  effort_value=$(frontmatter_value "$agent_file" "effort")
  if [ -n "$effort_value" ]; then
    check "$(word_in_list "$effort_value" "$ALLOWED_EFFORT" && echo 0 || echo 1)" \
      "$agent_name: effort=\"$effort_value\" dentro del enum"
  fi
done

echo ""
echo "--- effort: high solo en qa-frontend y qa-backend (decisión D-05) ---"

for agent_file in "$AGENTS_DIR"/*.md; do
  agent_name="$(basename "$agent_file" .md)"
  effort_value=$(frontmatter_value "$agent_file" "effort")
  case "$agent_name" in
    qa-frontend|qa-backend)
      check "$([ "$effort_value" = "high" ] && echo 0 || echo 1)" \
        "$agent_name: effort=high"
      ;;
    *)
      check "$([ -z "$effort_value" ] && echo 0 || echo 1)" \
        "$agent_name: sin effort (default)${effort_value:+ (encontrado: $effort_value)}"
      ;;
  esac
done

echo ""
echo "--- skills/*/SKILL.md: Agent(...) namespaced y existente, disable-model-invocation ---"

for skill_file in "$SKILLS_DIR"/*/SKILL.md; do
  skill_name="$(basename "$(dirname "$skill_file")")"
  allowed_tools_line=$(frontmatter_block "$skill_file" | grep -E "^allowed-tools:" | head -1)

  agent_refs=$(echo "$allowed_tools_line" | grep -oE 'Agent\([^)]*\)' || true)
  if [ -n "$agent_refs" ]; then
    while IFS= read -r ref; do
      [ -z "$ref" ] && continue
      inner="${ref#Agent(}"
      inner="${inner%)}"
      TOTAL=$((TOTAL + 1))
      case "$inner" in
        methodology:*)
          agent_name="${inner#methodology:}"
          if [ -f "$AGENTS_DIR/$agent_name.md" ]; then
            pass "$skill_name: $ref referencia un agente existente"
          else
            fail "$skill_name: $ref referencia \"$agent_name\", que no existe en agents/"
          fi
          ;;
        *)
          fail "$skill_name: $ref no tiene la forma Agent(methodology:<agente>)"
          ;;
      esac
    done <<< "$agent_refs"
  fi

  disable_value=$(frontmatter_value "$skill_file" "disable-model-invocation")
  case "$skill_name" in
    new-project|refactor-scan)
      check "$([ "$disable_value" = "true" ] && echo 0 || echo 1)" \
        "$skill_name: disable-model-invocation=true"
      ;;
    pr-workflow|review-pr|orchestrator)
      check "$([ -z "$disable_value" ] && echo 0 || echo 1)" \
        "$skill_name: sin disable-model-invocation"
      ;;
  esac

  # allowed-tools de una skill SUMA pre-aprobaciones, no restringe (verificado
  # ejecutando: `Bash(git *)` deja correr `git -c alias.x='!cmd' x`, es decir
  # cualquier comando, ver .planning/reviews/pre-pr-orchestrator-skill.md,
  # Ronda 2, hallazgo M2 de security-reviewer). Una skill invocable por el
  # modelo (sin disable-model-invocation: true) no controla cuándo se carga,
  # así que no puede llevar Bash en ninguna forma. Las user-invocable-only
  # quedan exentas porque su carga ya es una decisión explícita del usuario.
  if [ "$disable_value" != "true" ]; then
    TOTAL=$((TOTAL + 1))
    if echo "$allowed_tools_line" | grep -qE '(^|, )Bash(\(|,|$)'; then
      fail "$skill_name: invocable por el modelo con Bash en allowed-tools (pre-aprueba, no restringe)"
    else
      pass "$skill_name: invocable por el modelo sin Bash en allowed-tools"
    fi
  fi
done

echo ""
echo "--- Referencias methodology:<agente> apuntan a un agente existente ---"

REF_TARGETS=("$AGENTS_DIR" "$REPO_ROOT/rulebooks" "$SKILLS_DIR" "$REPO_ROOT/README.md" "$REPO_ROOT/.claude/CLAUDE.md")
refs=$(grep -rhoE 'methodology:[A-Za-z0-9_-]+' "${REF_TARGETS[@]}" 2>/dev/null | sed 's/^methodology://' | sort -u)

if [ -z "$refs" ]; then
  echo "(sin referencias methodology:<agente> en el repo)"
else
  while IFS= read -r ref; do
    [ -z "$ref" ] && continue
    TOTAL=$((TOTAL + 1))
    if [ -f "$AGENTS_DIR/$ref.md" ] || [ -d "$SKILLS_DIR/$ref" ]; then
      pass "methodology:$ref apunta a un agente o skill existente"
    else
      fail "methodology:$ref no corresponde a ningún agente ni skill en el repo"
    fi
  done <<< "$refs"
fi

echo ""
echo "--- Menciones \`<agente>\` de la lista histórica apuntan a un agente existente ---"

DANGLING_MENTIONS=$(check_agent_backtick_mentions "$AGENTS_DIR" "${REF_TARGETS[@]}")
if [ -z "$DANGLING_MENTIONS" ]; then
  TOTAL=$((TOTAL + 1))
  pass "todas las menciones \`<agente>\` de la lista histórica resuelven a agents/"
else
  while IFS= read -r name; do
    [ -z "$name" ] && continue
    TOTAL=$((TOTAL + 1))
    fail "mención \`$name\` (lista histórica) no corresponde a ningún archivo en agents/"
  done <<< "$DANGLING_MENTIONS"
fi

echo ""

# --- Resumen ---
echo "=== Results ==="
echo -e "Total: $TOTAL | ${GREEN}Pass: $PASS${NC} | ${RED}Fail: $FAIL${NC}"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
