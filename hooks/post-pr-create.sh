#!/bin/bash
# Post PR create (v2): checkpoint de respaldo al detectar `gh pr create`.
# El review dual ocurre ANTES del push (Fase 2.6), así que este hook ya no
# instruye lanzarlo por default — verifica evidencia en .planning/state.json:
#   CASO A — PR del flujo, ya revisado. Tres señales obligatorias:
#     phases.review=done, branch igual al actual, y review_sha (SHA de HEAD
#     al cerrar la Fase 2.6 con veredictos limpios) ancestro de HEAD con
#     delta posterior SOLO bajo .planning/ (los commits legítimos
#     post-review son registro/reconciliación). Solo recuerda confirmar la
#     reconciliación del registro (.planning/reviews/PR-<N>.md, Fase 2.7).
#     No se relanzan reviewers.
#   CASO B — sin evidencia de review pre-push (todo lo demás, incluido un
#     review_sha ausente/inválido o que no cubre los commits actuales): PR
#     fuera del flujo — instruye lanzar el review dual (comportamiento v1
#     conservado).
# Ante cualquier ambigüedad falla hacia CASO B (el costo del falso negativo
# es un review redundante; el del falso positivo sería un PR sin review).
# Recibe JSON en stdin con tool_input y stdout del comando ejecutado.
# Siempre exit 0 (checkpoint, no guard). Sin jq en PATH: no-op limpio
# (degradación estándar de hooks de observabilidad, ARCHITECTURE 2026-08-14).
# NOTA: Este hook NO ejecuta agentes directamente — emite instrucciones en stdout
# que el agente orquestador lee y actúa en consecuencia.

command -v jq > /dev/null 2>&1 || exit 0

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
  CURRENT_BRANCH=$(git branch --show-current 2>/dev/null)
  REVIEW_PHASE=""
  STATE_BRANCH=""
  REVIEW_SHA=""
  if [ -n "$TOPLEVEL" ] && [ -f "$STATE_FILE" ]; then
    # 2>/dev/null: un state.json malformado degrada a CASO B sin filtrar
    # el error de parseo de jq al output del checkpoint.
    REVIEW_PHASE=$(jq -r '.phases.review // empty' "$STATE_FILE" 2>/dev/null)
    STATE_BRANCH=$(jq -r '.branch // empty' "$STATE_FILE" 2>/dev/null)
    REVIEW_SHA=$(jq -r '.review_sha // empty' "$STATE_FILE" 2>/dev/null)
  fi
  CASO_B_DIAG="No hay evidencia de review dual pre-push para este branch — se trata como PR fuera del flujo."
  if [ "$REVIEW_PHASE" = "done" ] && [ -n "$CURRENT_BRANCH" ] && [ "$STATE_BRANCH" = "$CURRENT_BRANCH" ]; then
    # Tercera señal (anclaje): review_sha debe ser hex plausible (state.json
    # es input no confiable — nunca se interpola sin validar), ancestro de
    # HEAD, y el delta review_sha..HEAD debe tocar SOLO paths bajo
    # .planning/ (registro/reconciliación legítimos post-review). Cualquier
    # otro delta, o el campo ausente/inválido → CASO B.
    SHA_ANCHOR_OK=false
    case "$REVIEW_SHA" in
      *[!0-9a-f]* | '') : ;;
      *)
        if git merge-base --is-ancestor "$REVIEW_SHA" HEAD 2>/dev/null; then
          # grep -cv cuenta las líneas que NO empiezan con .planning/;
          # con delta vacío o todo-.planning imprime 0 (exit 1, inocuo).
          NON_PLANNING_DELTA=$(git diff --name-only "$REVIEW_SHA"..HEAD 2>/dev/null | grep -cv '^\.planning/')
          [ "$NON_PLANNING_DELTA" = "0" ] && SHA_ANCHOR_OK=true
        fi
        ;;
    esac
    if [ "$SHA_ANCHOR_OK" = true ]; then
      # CASO A: PR del flujo, ya revisado en Fase 2.6 (exige las tres
      # señales: fase, branch Y anclaje — cualquier otra combinación cae
      # a CASO B)
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
    CASO_B_DIAG="La evidencia de review no cubre los commits actuales (review_sha ausente/inválido, no-ancestro de HEAD, o delta post-review fuera de .planning/) — se trata como PR fuera del flujo."
  fi
  # CASO B: sin evidencia de review dual pre-push — PR fuera del flujo
  echo "PR creado: $PR_URL"
  echo ""
  echo "$CASO_B_DIAG"
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
