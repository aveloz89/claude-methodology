#!/bin/bash
# Post PR create: Detecta cuando se crea un PR e instruye al orquestador
# para que dispare review automático con security-reviewer y los QAs aplicables
# (qa-frontend y/o qa-backend según las capas tocadas por el diff).
# Recibe JSON en stdin con tool_input y stdout del comando ejecutado.
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
  echo "PR creado: $PR_URL"
  echo ""
  echo "ACCIÓN REQUERIDA: Revisa este PR: $PR_URL"
  echo "1. Obtén el contexto con 'gh pr diff' y 'gh pr view'."
  echo "2. Clasifica los archivos del diff por capa (frontend / backend)."
  echo "3. Lanza en paralelo los reviewers aplicables:"
  echo "   - security-reviewer (subagent_type=security-reviewer) — siempre"
  echo "   - qa-frontend (subagent_type=qa-frontend) — si el diff tiene archivos de UI"
  echo "   - qa-backend  (subagent_type=qa-backend)  — si el diff tiene archivos de servidor"
  echo "Consulta agents/orchestrator.md (Fase 3) para la heurística de clasificación por extensión y ruta."
else
  echo "WARNING: Se detectó 'gh pr create' pero no se pudo extraer la URL del PR del output."
  echo "Verifica manualmente si el PR fue creado y ejecuta el review (security-reviewer + qa-frontend/qa-backend según aplique)."
fi

exit 0
