#!/bin/bash
# Instala la metodología de Claude Code en ~/.claude/
# Uso: ./install.sh [--symlink | --copy]
#
# --symlink: Crea symlinks (cambios en el repo se reflejan automáticamente)
# --copy:    Copia los archivos (independiente del repo)
# Default:   --symlink

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
MODE="${1:---symlink}"

echo "=== Claude Methodology Installer ==="
echo "Source: $SCRIPT_DIR"
echo "Target: $CLAUDE_DIR"
echo "Mode: $MODE"
echo ""

# Crear directorios si no existen
mkdir -p "$CLAUDE_DIR/agents"
mkdir -p "$CLAUDE_DIR/hooks"
mkdir -p "$CLAUDE_DIR/skills/new-project"

install_file() {
  local src="$1"
  local dest="$2"

  if [ -e "$dest" ] && [ ! -L "$dest" ]; then
    echo "  BACKUP: $dest → ${dest}.bak"
    mv "$dest" "${dest}.bak"
  fi

  if [ "$MODE" = "--symlink" ]; then
    ln -sf "$src" "$dest"
    echo "  LINK: $dest → $src"
  else
    cp "$src" "$dest"
    echo "  COPY: $src → $dest"
  fi
}

# Instalar agentes
echo ""
echo "Installing agents..."
for f in "$SCRIPT_DIR"/agents/*.md; do
  install_file "$f" "$CLAUDE_DIR/agents/$(basename "$f")"
done

# Instalar hooks
echo ""
echo "Installing hooks..."
for f in "$SCRIPT_DIR"/hooks/*.sh; do
  install_file "$f" "$CLAUDE_DIR/hooks/$(basename "$f")"
  chmod +x "$CLAUDE_DIR/hooks/$(basename "$f")"
done

# Instalar skills
echo ""
echo "Installing skills..."
install_file "$SCRIPT_DIR/skills/new-project/SKILL.md" "$CLAUDE_DIR/skills/new-project/SKILL.md"

# Instalar statusline
echo ""
echo "Installing statusline..."
install_file "$SCRIPT_DIR/statusline.sh" "$CLAUDE_DIR/statusline.sh"
chmod +x "$CLAUDE_DIR/statusline.sh"

# Instalar settings.json (con cuidado — puede tener config del usuario)
echo ""
if [ -e "$CLAUDE_DIR/settings.json" ] && [ ! -L "$CLAUDE_DIR/settings.json" ]; then
  echo "WARNING: ~/.claude/settings.json already exists."
  echo "  Your current settings.json has been backed up to settings.json.bak"
  echo "  Review and merge manually if needed."
fi
install_file "$SCRIPT_DIR/settings.json" "$CLAUDE_DIR/settings.json"

echo ""
echo "=== Installation complete ==="
echo ""
echo "Installed:"
echo "  - 7 agents (orchestrator, architect, backend-dev, frontend-dev, db-specialist, qa, security-reviewer)"
echo "  - 5 hooks (pre-commit-guard, pre-push-guard, post-pr-create, session-start-context, context-monitor)"
echo "  - 1 skill (new-project)"
echo "  - statusline (model, branch, tokens, rate limits)"
echo "  - settings.json"
echo ""
echo "Restart Claude Code for the statusline to take effect."
