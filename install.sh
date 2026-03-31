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

# Instalar agentes (dinámico — todos los .md en agents/)
echo ""
echo "Installing agents..."
mkdir -p "$CLAUDE_DIR/agents"
AGENT_COUNT=0
for f in "$SCRIPT_DIR"/agents/*.md; do
  install_file "$f" "$CLAUDE_DIR/agents/$(basename "$f")"
  AGENT_COUNT=$((AGENT_COUNT + 1))
done

# Instalar hooks
echo ""
echo "Installing hooks..."
mkdir -p "$CLAUDE_DIR/hooks"
HOOK_COUNT=0
for f in "$SCRIPT_DIR"/hooks/*.sh; do
  install_file "$f" "$CLAUDE_DIR/hooks/$(basename "$f")"
  chmod +x "$CLAUDE_DIR/hooks/$(basename "$f")"
  HOOK_COUNT=$((HOOK_COUNT + 1))
done

# Instalar skills (dinámico — todos los subdirectorios en skills/)
echo ""
echo "Installing skills..."
SKILL_COUNT=0
for skill_dir in "$SCRIPT_DIR"/skills/*/; do
  skill_name="$(basename "$skill_dir")"
  mkdir -p "$CLAUDE_DIR/skills/$skill_name"
  for f in "$skill_dir"*; do
    [ -f "$f" ] && install_file "$f" "$CLAUDE_DIR/skills/$skill_name/$(basename "$f")"
  done
  SKILL_COUNT=$((SKILL_COUNT + 1))
done

# Instalar rules (dinámico — todos los .md en rules/)
echo ""
echo "Installing rules..."
RULE_COUNT=0
if [ -d "$SCRIPT_DIR/rules" ]; then
  mkdir -p "$CLAUDE_DIR/rules"
  for f in "$SCRIPT_DIR"/rules/*.md; do
    [ -f "$f" ] && install_file "$f" "$CLAUDE_DIR/rules/$(basename "$f")"
    RULE_COUNT=$((RULE_COUNT + 1))
  done
fi

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
echo "  - $AGENT_COUNT agents"
echo "  - $HOOK_COUNT hooks"
echo "  - $SKILL_COUNT skills"
echo "  - $RULE_COUNT rules"
echo "  - statusline"
echo "  - settings.json"
echo ""
echo "Restart Claude Code for changes to take effect."
