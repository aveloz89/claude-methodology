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
