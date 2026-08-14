#!/bin/bash
# Post PR create (v2): checkpoint de respaldo al detectar `gh pr create`.
# El review dual ocurre ANTES del push (Fase 2.6), así que este hook ya no
# instruye lanzarlo por default — verifica evidencia en .planning/state.json:
#   CASO A — PR del flujo, ya revisado (phases.review=done y branch igual al
#     actual): solo recuerda confirmar la reconciliación del registro
#     (.planning/reviews/PR-<N>.md, Fase 2.7). No se relanzan reviewers.
#   CASO B — sin evidencia de review pre-push (todo lo demás): PR fuera del
#     flujo — instruye lanzar el review dual (comportamiento v1 conservado).
# Ante cualquier ambigüedad falla hacia CASO B (el costo del falso negativo
# es un review redundante; el del falso positivo sería un PR sin review).
# Recibe JSON en stdin con tool_input y stdout del comando ejecutado.
# Siempre exit 0 (checkpoint, no guard).
# NOTA: Este hook NO ejecuta agentes directamente — emite instrucciones en stdout
# que el agente orquestador lee y actúa en consecuencia.

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Solo interceptar gh pr create
if ! echo "$COMMAND" | grep -qE 'gh\s+pr\s+create'; then
  exit 0
fi

# Extraer la URL del PR del stdout del comando
PR_URL=$(echo "$INPUT" | jq -r '.stdout // empty' | grep -oE 'https://github.com/[^ ]+/pull/[0-9]+')

if [ -n "$PR_URL" ]; then
  TOPLEVEL=$(git rev-parse --show-toplevel 2>/dev/null)
  STATE_FILE="$TOPLEVEL/.planning/state.json"
  if [ -n "$TOPLEVEL" ] && [ -f "$STATE_FILE" ]; then
    # CASO A: PR del flujo, ya revisado en Fase 2.6
    CURRENT_BRANCH=$(git branch --show-current 2>/dev/null)
    PR_NUMBER=${PR_URL##*/}
    FEATURE_SLUG=$(jq -r '.feature // empty' "$STATE_FILE")
    echo "PR creado: $PR_URL"
    echo ""
    echo "Review dual pre-push verificado (state.json: phases.review=done, branch $CURRENT_BRANCH)."
    echo "CHECKPOINT: confirma la reconciliación — .planning/reviews/PR-$PR_NUMBER.md debe existir"
    echo "(renombrado desde pre-pr-$FEATURE_SLUG.md). Si falta, ejecútala ahora (Fase 2.7)."
    echo "No relances reviewers: el PR nació revisado. Re-review solo si CI obliga fixes"
    echo "sobre código ya revisado (Fase 3)."
    exit 0
  fi
  # CASO B: sin evidencia de review dual pre-push — PR fuera del flujo
  echo "PR creado: $PR_URL"
  echo ""
  echo "No hay evidencia de review dual pre-push para este branch — se trata como PR fuera del flujo."
  echo "ACCIÓN REQUERIDA: Revisa este PR: $PR_URL"
  echo "1. Obtén el contexto con 'gh pr diff' y 'gh pr view'."
  echo "2. Clasifica los archivos del diff por capa (frontend / backend)."
  echo "3. Lanza en paralelo los reviewers aplicables:"
  echo "   - security-reviewer (subagent_type=security-reviewer) — siempre"
  echo "   - qa-frontend (subagent_type=qa-frontend) — si el diff tiene archivos de UI"
  echo "   - qa-backend  (subagent_type=qa-backend)  — si el diff tiene archivos de servidor"
  echo "Consulta rulebooks/orchestrator-runbook.md (sección 'Clasificación del diff por capa') para la heurística por extensión y ruta."
else
  echo "WARNING: Se detectó 'gh pr create' pero no se pudo extraer la URL del PR del output."
  echo "Verifica manualmente si el PR fue creado y ejecuta el review (security-reviewer + qa-frontend/qa-backend según aplique)."
fi

exit 0
