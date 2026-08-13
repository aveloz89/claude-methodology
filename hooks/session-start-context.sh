#!/bin/bash
# Session start: Muestra contexto del proyecto al iniciar sesión.
# Incluye git status, último commit, y estado de .planning/ si existe.

# Verificar si estamos en un repo git
if ! git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
  exit 0
fi

echo "=== Session Context ==="

# Branch actual
echo "Branch: $(git branch --show-current)"

# Último commit
echo "Último commit: $(git log -1 --oneline 2>/dev/null)"

# Status resumido
CHANGES=$(git status --short 2>/dev/null | wc -l | tr -d ' ')
echo "Archivos modificados: $CHANGES"

# Issues abiertos (si gh está disponible)
if command -v gh > /dev/null 2>&1; then
  ISSUES=$(gh issue list --limit 5 --state open 2>/dev/null)
  if [ -n "$ISSUES" ]; then
    echo ""
    echo "Issues abiertos:"
    echo "$ISSUES"
  fi
fi

# Marker de SessionEnd: aviso consume-once de STATE posiblemente
# desactualizado, dejado por la sesión anterior (session-end-check.sh).
if command -v jq > /dev/null 2>&1; then
  TOPLEVEL=$(git rev-parse --show-toplevel 2>/dev/null)
  if [ -n "$TOPLEVEL" ]; then
    SLUG=$(echo "$TOPLEVEL" | tr '/' '-')
    MARKER_FILE="$HOME/.claude/methodology/session-end/$SLUG.json"
    if [ -f "$MARKER_FILE" ]; then
      SIGNALS=$(jq -r '.signals // [] | join(", ")' "$MARKER_FILE" 2>/dev/null)
      echo ""
      echo "⚠️ La sesión anterior cerró con STATE posiblemente desactualizado (señales: $SIGNALS). Verifica .planning/STATE.md y state.json antes de continuar."
      rm -f "$MARKER_FILE" 2>/dev/null
    fi
  fi
fi

# Planning state
if [ -d ".planning" ]; then
  echo ""
  echo "=== Planning State ==="

  if [ -f ".planning/STATE.md" ]; then
    echo "Active planning found."
    echo "---"
    head -30 .planning/STATE.md
    echo "---"
  fi

  if [ -f ".planning/HANDOFF.md" ]; then
    echo ""
    echo "⚠️ HANDOFF encontrado — hay trabajo pausado. Lee .planning/HANDOFF.md para retomar."
  fi
fi

echo "==========================="

exit 0
