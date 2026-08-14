#!/bin/bash
# Adversarial tests for the plugin manifests (.claude-plugin/, hooks/hooks.json).
#
# Verifica:
#   (a) paridad hooks/*.sh <-> hooks/hooks.json — cada script (excluyendo
#       hooks/lib/) debe estar registrado EXACTAMENTE una vez. Mata la clase
#       de bug C5 "hook documentado pero no instalado".
#   (b) los 3 manifests (plugin.json, marketplace.json, hooks.json) parsean
#       como JSON válido.
#   (c) si la CLI `claude` está en PATH, `claude plugin validate --strict .`
#       pasa sobre el repo completo; si no está, SKIP declarado (el test
#       crítico —la paridad— no depende de la CLI).
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
