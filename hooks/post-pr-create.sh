#!/bin/bash
# Post PR create: Detecta cuando se crea un PR y dispara review automático.
# Recibe JSON en stdin con tool_input y stdout del comando ejecutado.
# Ejecuta automáticamente los agentes QA y security-reviewer sobre el PR.

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
  echo "ACCIÓN REQUERIDA: Ejecuta en paralelo los agentes QA (subagent_type=qa) y security-reviewer (subagent_type=security-reviewer) para revisar este PR: $PR_URL"
  echo "Usa 'gh pr diff' y 'gh pr view' para obtener el contexto del PR y pásalo a ambos agentes."
fi

exit 0
