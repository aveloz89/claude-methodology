#!/bin/bash
# Pre-compact snapshot: guarda una copia completa de .planning/ antes de que
# el contexto se compacte (evento PreCompact), para poder recuperar
# STATE/HANDOFF/DESIGN si el compact deja el estado inconsistente. No
# bloqueante — PreCompact es observabilidad, nunca bloquea el evento.

# Los artefactos bajo ~/.claude/methodology/ contienen planificación y
# session ids: nunca legibles por otros usuarios de la máquina.
umask 077

INPUT=$(cat 2>/dev/null)

# stdin vacío o JSON malformado: no-op limpio. Sin un payload confiable no
# hay trigger del que fiarse, así que no se crea ningún snapshot.
[ -n "$INPUT" ] || exit 0
echo "$INPUT" | jq empty > /dev/null 2>&1 || exit 0

# Árbol de la sesión: ".cwd" del payload si viene no vacío (en una sesión de
# worktree de la app de escritorio el proceso corre en el checkout principal
# y ".cwd" es el worktree), el cwd del proceso si no viene o viene vacío/null
# (misma regla que post-pr-create, vía guard_session_dir). Un ".cwd" no
# vacío que no es directorio, o una lib ausente, deja la sesión sin snapshot
# con el motivo en stderr — nunca se cae al árbol del proceso. El valor de
# ".cwd" no se interpola en ningún mensaje.
LIB_GM="${0%/*}/lib/guard-matching.sh"
# shellcheck source=lib/guard-matching.sh
[ -r "$LIB_GM" ] && . "$LIB_GM"
if ! type guard_session_dir > /dev/null 2>&1; then
  echo "pre-compact-snapshot: sin snapshot: no se pudo resolver el árbol de la sesión (hooks/lib/guard-matching.sh falta o no define guard_session_dir)" >&2
  exit 0
fi
# shellcheck disable=SC2034 # la lee guard_session_dir (lib sourceada arriba)
INPUT_CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
if ! SESSION_DIR=$(guard_session_dir 2>/dev/null) || [ -z "$SESSION_DIR" ]; then
  echo "pre-compact-snapshot: sin snapshot: no se pudo resolver el árbol de la sesión (el .cwd del payload no es un directorio)" >&2
  exit 0
fi

# git -C siempre sobre una ruta resuelta y no vacía (con '' git -C deja el
# cwd del proceso). Fuera de un repo git: no-op silencioso, no es un fallo.
TOPLEVEL=$(git -C "$SESSION_DIR" rev-parse --show-toplevel 2>/dev/null) || exit 0
[ -n "$TOPLEVEL" ] && [ -d "$TOPLEVEL/.planning" ] || exit 0

TRIGGER=$(echo "$INPUT" | jq -r '.trigger // "unknown"' 2>/dev/null)
[ -n "$TRIGGER" ] && [ "$TRIGGER" != "null" ] || TRIGGER="unknown"
# Allowlist alfanumérica: un trigger con espacios, comillas o saltos de
# línea rompería el word splitting del `ls | xargs rm -rf` de retención
# más abajo si se cuela en el nombre del directorio de destino.
TRIGGER=$(echo "$TRIGGER" | tr -cd 'A-Za-z0-9_-')
[ -n "$TRIGGER" ] || TRIGGER="unknown"

# Modo degradado: sin hooks/lib/slug.sh o sin ninguna herramienta de hash
# disponible, no-op limpio — PreCompact es observabilidad, nunca bloquea.
LIB="${0%/*}/lib/slug.sh"
[ -r "$LIB" ] || exit 0
# shellcheck source=lib/slug.sh
source "$LIB"
SLUG=$(repo_slug "$TOPLEVEL") || exit 0
TS=$(date -u +%Y%m%d-%H%M%S)
SNAPSHOT_DIR="$HOME/.claude/methodology/snapshots/$SLUG/${TS}-${TRIGGER}"

mkdir -p "$SNAPSHOT_DIR" 2>/dev/null
cp -R "$TOPLEVEL/.planning/." "$SNAPSHOT_DIR/" 2>/dev/null

BRANCH=$(git -C "$TOPLEVEL" branch --show-current 2>/dev/null)
HEAD=$(git -C "$TOPLEVEL" rev-parse --short HEAD 2>/dev/null)
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Escritura atómica: si jq falla a mitad de camino, el redirect ya truncó
# el archivo destino a 0 bytes. Se escribe primero a un .tmp.$$ y se mueve
# solo si jq tuvo éxito, para nunca dejar meta.json truncado.
META_TMP="$SNAPSHOT_DIR/meta.json.tmp.$$"
if jq -n \
  --arg ts "$NOW" \
  --arg trigger "$TRIGGER" \
  --arg branch "$BRANCH" \
  --arg head "$HEAD" \
  --arg repo "$TOPLEVEL" \
  '{ts: $ts, trigger: $trigger, branch: $branch, head: $head, repo: $repo}' \
  > "$META_TMP" 2>/dev/null; then
  mv -f "$META_TMP" "$SNAPSHOT_DIR/meta.json"
else
  rm -f "$META_TMP"
fi

# Retención: conservar solo los 5 snapshots más recientes de este repo.
# Orden lexicográfico del nombre = cronológico por el prefijo timestamp.
# tail -n +6 (no head -n -5: no existe en macOS/BSD).
SNAPSHOTS_ROOT="$HOME/.claude/methodology/snapshots/$SLUG"
(cd "$SNAPSHOTS_ROOT" 2>/dev/null && ls -1 | sort -r | tail -n +6 | xargs rm -rf)

exit 0
