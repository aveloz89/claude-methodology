#!/bin/bash
# Instala la metodología de Claude Code en ~/.claude/
# Uso: ./install.sh [--symlink | --copy]
#
# --symlink: Crea symlinks de los DIRECTORIOS completos (agents/, hooks/, rules/, rulebooks/, skills/).
#            Cualquier archivo que agregues al repo aparece al instante en ~/.claude/,
#            sin reinstalar.
# --copy:    Copia los archivos uno por uno (independiente del repo).
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

mkdir -p "$CLAUDE_DIR"

# Symlinkea (o copia) un directorio completo del repo a ~/.claude/.
# Si el destino existe como directorio real, lo respalda a *.bak antes.
install_dir() {
  local src="$1"
  local dest="$2"
  local label="$3"

  if [ ! -d "$src" ]; then
    echo "  SKIP: $src no existe"
    return
  fi

  if [ -L "$dest" ]; then
    rm "$dest"
  elif [ -d "$dest" ]; then
    echo "  BACKUP: $dest → ${dest}.bak"
    rm -rf "${dest}.bak"
    mv "$dest" "${dest}.bak"
  fi

  if [ "$MODE" = "--symlink" ]; then
    ln -s "$src" "$dest"
    local count
    count=$(find "$src" -maxdepth 1 -mindepth 1 | wc -l | tr -d ' ')
    echo "  LINK: $dest → $src ($count $label)"
  else
    cp -R "$src" "$dest"
    local count
    count=$(find "$dest" -maxdepth 1 -mindepth 1 | wc -l | tr -d ' ')
    echo "  COPY: $src → $dest ($count $label)"
  fi
}

# Symlinkea (o copia) un archivo individual.
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

echo ""
echo "Installing agents..."
install_dir "$SCRIPT_DIR/agents" "$CLAUDE_DIR/agents" "agents"

echo ""
echo "Installing hooks..."
install_dir "$SCRIPT_DIR/hooks" "$CLAUDE_DIR/hooks" "hooks"

echo ""
echo "Installing skills..."
install_dir "$SCRIPT_DIR/skills" "$CLAUDE_DIR/skills" "skills"

echo ""
echo "Installing rules..."
install_dir "$SCRIPT_DIR/rules" "$CLAUDE_DIR/rules" "rules"

echo ""
echo "Installing rulebooks..."
install_dir "$SCRIPT_DIR/rulebooks" "$CLAUDE_DIR/rulebooks" "rulebooks"

echo ""
echo "Installing statusline..."
install_file "$SCRIPT_DIR/statusline.sh" "$CLAUDE_DIR/statusline.sh"
chmod +x "$CLAUDE_DIR/statusline.sh" 2>/dev/null || true

echo ""
if [ -e "$CLAUDE_DIR/settings.json" ] && [ ! -L "$CLAUDE_DIR/settings.json" ]; then
  echo "WARNING: ~/.claude/settings.json already exists."
  echo "  Your current settings.json will be backed up to settings.json.bak"
  echo "  Review and merge manually if needed."
fi
install_file "$SCRIPT_DIR/settings.json" "$CLAUDE_DIR/settings.json"

echo ""
echo "=== Installation complete ==="
if [ "$MODE" = "--symlink" ]; then
  echo ""
  echo "Los directorios agents/, hooks/, skills/, rules/, rulebooks/ son symlinks al repo."
  echo "Cualquier archivo nuevo que agregues está disponible al instante,"
  echo "sin volver a correr este script."
fi
echo ""
echo "Restart Claude Code for changes to take effect."
