#!/bin/bash
# Post PR create: Detecta cuando se crea un PR y notifica para review.
# Recibe JSON en stdin con tool_input y stdout del comando ejecutado.
# NOTA: Este hook es informativo — muestra la URL del PR creado.
# El orchestrator debe ser invocado manualmente por el usuario para el review.

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
  echo "Para review, invoca al @orchestrator con esta URL."
fi

exit 0
