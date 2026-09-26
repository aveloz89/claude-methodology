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

# --- Resumen ---
echo "=== Results ==="
echo -e "Total: $TOTAL | ${GREEN}Pass: $PASS${NC} | ${RED}Fail: $FAIL${NC}"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
