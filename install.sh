#!/bin/bash
# Instala el residual de la metodología en ~/.claude/ (lo que el plugin de Claude Code
# no distribuye: global/CLAUDE.md, rules/, rulebooks/, statusline.sh) y migra instalaciones
# legacy por symlink de agents/hooks/skills (ahora los provee el plugin).
#
# Uso: ./install.sh
#
# Idempotente: correrlo N veces deja el mismo estado.
# Nunca borra nada que no sea un symlink cuyo target resuelve dentro de este repo —
# directorios o archivos reales del usuario se avisan y se dejan intactos.

set -e

# pwd -P: REPO_ROOT canónico (sin symlinks), para que el prefix-match de
# is_symlink_into_repo compare canónico contra canónico.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
CLAUDE_DIR="$HOME/.claude"
REPO_ROOT="$SCRIPT_DIR"

echo "=== Claude Methodology Installer (residual + migración) ==="
echo "Repo: $REPO_ROOT"
echo "Target: $CLAUDE_DIR"
echo ""

mkdir -p "$CLAUDE_DIR"

# Resuelve el target de un symlink a ruta absoluta CANÓNICA (cd -P / pwd -P).
# Sin canonicalizar, un target como "$REPO_ROOT/../otro" pasaría el
# prefix-match de is_symlink_into_repo por empezar con "$REPO_ROOT/" aunque
# resuelve FUERA del repo. Return 1 si no se puede canonicalizar (el caller
# lo trata como "no es del repo" → no se toca).
resolve_symlink_target() {
  local link="$1"
  local target dir base
  target="$(readlink "$link")"
  case "$target" in
    /*) ;;
    *) target="$(dirname "$link")/$target" ;;
  esac
  if [ -d "$target" ]; then
    (cd -P "$target" 2>/dev/null && pwd -P)
  else
    base="$(basename "$target")"
    case "$base" in
      . | ..) return 1 ;;
    esac
    dir="$(cd -P "$(dirname "$target")" 2>/dev/null && pwd -P)" || return 1
    printf '%s/%s\n' "$dir" "$base"
  fi
}

# True si $1 es un symlink cuyo target resuelve dentro de $REPO_ROOT.
is_symlink_into_repo() {
  local path="$1"
  [ -L "$path" ] || return 1
  local target
  target="$(resolve_symlink_target "$path")" || return 1
  [ -n "$target" ] || return 1
  case "$target" in
    "$REPO_ROOT"|"$REPO_ROOT"/*) return 0 ;;
    *) return 1 ;;
  esac
}

# Symlinkea src -> dest. Nunca toca dest si ya existe como algo que no sea
# un symlink hacia este repo (regla dura: no se borra nada del usuario).
link_into_home() {
  local src="$1" dest="$2" label="$3"

  if [ -L "$dest" ]; then
    if is_symlink_into_repo "$dest"; then
      echo "  OK: $dest ya symlinkeado a este repo"
    else
      echo "  SKIP: $dest es symlink a otra ubicación, no se toca ($label)"
    fi
    return
  fi

  if [ -e "$dest" ]; then
    echo "  SKIP: $dest ya existe (archivo/directorio real del usuario), no se toca ($label)"
    return
  fi

  ln -s "$src" "$dest"
  echo "  LINK: $dest -> $src"
}

# Elimina un symlink legacy (agents/, hooks/) SOLO si apunta dentro de este repo.
# Directorios reales o symlinks a otro lado se avisan y se respetan.
cleanup_legacy_dir() {
  local dest="$1" label="$2"

  if [ -L "$dest" ]; then
    if is_symlink_into_repo "$dest"; then
      rm "$dest"
      echo "  CLEANUP: $dest (symlink legacy a este repo) eliminado — ahora lo provee el plugin"
    else
      echo "  SKIP: $dest es symlink a otra ubicación, no se toca ($label)"
    fi
  elif [ -d "$dest" ]; then
    echo "  SKIP: $dest es un directorio real, no se toca — revisar manualmente si es legacy ($label)"
  else
    echo "  SKIP: $dest no existe ($label)"
  fi
}

echo "Limpiando instalación legacy de agents/ y hooks/ (ahora los provee el plugin)..."
cleanup_legacy_dir "$CLAUDE_DIR/agents" "agents"
cleanup_legacy_dir "$CLAUDE_DIR/hooks" "hooks"

echo ""
echo "Migrando skills/ (de symlink al repo completo, a directorio real + dev-loop)..."
SKILLS_DIR="$CLAUDE_DIR/skills"
if [ -L "$SKILLS_DIR" ]; then
  if is_symlink_into_repo "$SKILLS_DIR"; then
    rm "$SKILLS_DIR"
    mkdir -p "$SKILLS_DIR"
    echo "  CLEANUP: $SKILLS_DIR (symlink legacy al repo completo) reemplazado por directorio real"
  else
    echo "  SKIP: $SKILLS_DIR es symlink a otra ubicación, no se toca"
  fi
elif [ ! -d "$SKILLS_DIR" ]; then
  mkdir -p "$SKILLS_DIR"
fi

echo ""
echo "Dev-loop: symlink de skills/methodology -> raíz del repo (carga en vivo como methodology@skills-dir)..."
link_into_home "$REPO_ROOT" "$SKILLS_DIR/methodology" "dev-loop skill"

echo ""
echo "Instalando global/CLAUDE.md -> ~/.claude/CLAUDE.md..."
# Si ya existe como archivo real del usuario, link_into_home lo va a saltar
# (regla dura: no se borra nada del usuario) — se registra acá para sugerir
# la integración manual en el mensaje final.
CLAUDE_MD_REAL_SKIPPED=false
if [ -e "$CLAUDE_DIR/CLAUDE.md" ] && [ ! -L "$CLAUDE_DIR/CLAUDE.md" ]; then
  CLAUDE_MD_REAL_SKIPPED=true
fi
link_into_home "$REPO_ROOT/global/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md" "CLAUDE.md global"

echo ""
echo "Instalando rules/ y rulebooks/..."
link_into_home "$REPO_ROOT/rules" "$CLAUDE_DIR/rules" "rules"
link_into_home "$REPO_ROOT/rulebooks" "$CLAUDE_DIR/rulebooks" "rulebooks"

echo ""
echo "Instalando statusline.sh..."
link_into_home "$REPO_ROOT/statusline.sh" "$CLAUDE_DIR/statusline.sh" "statusline"
# chmod SOLO si el path es nuestro (symlink al repo, o archivo recién
# instalado — que hoy siempre es symlink al repo): chmod sigue symlinks, y a
# través de uno ajeno mutaría el modo de un archivo que no es nuestro.
if is_symlink_into_repo "$CLAUDE_DIR/statusline.sh"; then
  chmod +x "$CLAUDE_DIR/statusline.sh" 2>/dev/null || true
fi

echo ""
echo "Materializando settings.json (deja de distribuirse: solo se migra el symlink legacy si existe)..."
SETTINGS_DEST="$CLAUDE_DIR/settings.json"
if [ -L "$SETTINGS_DEST" ]; then
  if is_symlink_into_repo "$SETTINGS_DEST"; then
    TMP_SETTINGS="$(mktemp "$CLAUDE_DIR/settings.json.XXXXXX")"
    cp -L "$SETTINGS_DEST" "$TMP_SETTINGS"
    rm "$SETTINGS_DEST"
    mv "$TMP_SETTINGS" "$SETTINGS_DEST"
    echo "  MATERIALIZE: $SETTINGS_DEST (era symlink al repo, ahora archivo real desacoplado)"
  else
    echo "  SKIP: $SETTINGS_DEST es symlink a otra ubicación, no se toca"
  fi
else
  echo "  SKIP: $SETTINGS_DEST no es symlink al repo (ya es real, o no existe) — settings.json ya no se distribuye por install.sh"
fi

echo ""
echo "=== Instalación completa ==="
echo ""
echo "Pasos restantes manuales:"
echo "  - Reiniciá Claude Code para que los cambios tomen efecto."
echo "  - Terceros (no-autor): 'claude plugin marketplace add <owner>/claude-methodology' + 'claude plugin install methodology@claude-methodology' para agents/hooks/skills."
if [ "$CLAUDE_MD_REAL_SKIPPED" = true ]; then
  echo "  - Tu ~/.claude/CLAUDE.md es un archivo propio y se dejó intacto. Para integrar la metodología,"
  echo "    agregale una línea de import:  @$REPO_ROOT/global/CLAUDE.md"
  echo "    o hacé un merge manual con ese archivo."
fi
