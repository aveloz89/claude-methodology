#!/bin/bash
# Context monitor: Avisa cuando el contexto se está agotando.
# Se ejecuta en PostToolUse. Lee la variable de entorno CLAUDE_CONTEXT_TOKENS_USED
# y CLAUDE_CONTEXT_TOKENS_MAX si están disponibles.
# Si no, usa heurística basada en el número de tool calls.

INPUT=$(cat)

# Intentar leer métricas de contexto del entorno
TOKENS_USED="${CLAUDE_CONTEXT_TOKENS_USED:-0}"
TOKENS_MAX="${CLAUDE_CONTEXT_TOKENS_MAX:-200000}"

if [ "$TOKENS_USED" -gt 0 ] 2>/dev/null; then
  REMAINING_PCT=$(( (TOKENS_MAX - TOKENS_USED) * 100 / TOKENS_MAX ))

  if [ "$REMAINING_PCT" -le 25 ]; then
    cat <<'EOF'
⚠️ CONTEXT CRÍTICO (≤25% restante). DEBES:
1. Completar la tarea actual de forma mínima
2. Hacer commit/push de lo que tengas
3. Guardar estado en .planning/STATE.md si hay trabajo pendiente
4. NO iniciar tareas nuevas
EOF
    exit 0
  elif [ "$REMAINING_PCT" -le 35 ]; then
    cat <<'EOF'
⚠️ CONTEXT WARNING (≤35% restante). Recomendaciones:
- Termina la tarea actual, no empieces nuevas
- Si hay mucho trabajo pendiente, haz commit parcial y documenta en .planning/STATE.md
EOF
    exit 0
  fi
fi

exit 0
