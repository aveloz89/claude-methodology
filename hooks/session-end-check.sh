#!/bin/bash
# Session end check: heurística de staleness de STATE.md/state.json al
# cerrar sesión (evento SessionEnd). No bloqueante — la sesión ya terminó,
# no hay modelo que lea la salida; el efecto es un marker que
# session-start-context.sh consume (aviso consume-once) en la siguiente
# sesión.

# Los artefactos bajo ~/.claude/methodology/ contienen planificación y
# session ids: nunca legibles por otros usuarios de la máquina.
umask 077

INPUT=$(cat 2>/dev/null)

# Sin jq no hay forma segura de construir el marker JSON.
command -v jq > /dev/null 2>&1 || exit 0

TOPLEVEL=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
STATE_FILE="$TOPLEVEL/.planning/STATE.md"
[ -f "$STATE_FILE" ] || exit 0

# mtime portable: stat -f%m (BSD/macOS) con fallback stat -c%Y (GNU/Linux).
# Forma pegada (sin espacio tras -f): en GNU coreutils, "-f" con espacio es
# --file-system y devuelve info multilínea del filesystem en vez del mtime,
# lo que rompe las comparaciones -gt en silencio en Linux.
mtime_of() {
  stat -f%m "$1" 2>/dev/null || stat -c%Y "$1" 2>/dev/null
}

STATE_MTIME=$(mtime_of "$STATE_FILE")
[ -n "$STATE_MTIME" ] || exit 0

# STATE_MTIME = max(mtime de STATE.md, mtime de state.json si existe).
STATE_JSON="$TOPLEVEL/.planning/state.json"
if [ -f "$STATE_JSON" ]; then
  JSON_MTIME=$(mtime_of "$STATE_JSON")
  if [ -n "$JSON_MTIME" ] && [ "$JSON_MTIME" -gt "$STATE_MTIME" ] 2>/dev/null; then
    STATE_MTIME="$JSON_MTIME"
  fi
fi

SIGNALS=()

# S1: hubo commits después de la última actualización de estado.
LAST_COMMIT_TS=$(cd "$TOPLEVEL" && git log -1 --format=%ct 2>/dev/null)
if [ -n "$LAST_COMMIT_TS" ] && [ "$LAST_COMMIT_TS" -gt "$STATE_MTIME" ] 2>/dev/null; then
  SIGNALS+=("commits_after_state")
fi

# S2: hubo trabajo sin commitear (fuera de .planning/) posterior al STATE.
while IFS= read -r LINE; do
  [ -n "$LINE" ] || continue
  DIRTY_PATH="${LINE:3}"
  case "$DIRTY_PATH" in
    *" -> "*) DIRTY_PATH="${DIRTY_PATH#*-> }" ;;
  esac
  case "$DIRTY_PATH" in
    .planning/*) continue ;;
  esac
  DIRTY_MTIME=$(mtime_of "$TOPLEVEL/$DIRTY_PATH")
  if [ -n "$DIRTY_MTIME" ] && [ "$DIRTY_MTIME" -gt "$STATE_MTIME" ] 2>/dev/null; then
    SIGNALS+=("dirty_files_after_state")
    break
  fi
done < <(cd "$TOPLEVEL" && git status --porcelain 2>/dev/null)

[ "${#SIGNALS[@]}" -gt 0 ] || exit 0

REASON=$(echo "$INPUT" | jq -r '.reason // "other"' 2>/dev/null)
[ -n "$REASON" ] && [ "$REASON" != "null" ] || REASON="other"

BRANCH=$(cd "$TOPLEVEL" && git branch --show-current 2>/dev/null)
HEAD=$(cd "$TOPLEVEL" && git rev-parse --short HEAD 2>/dev/null)
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
# shellcheck source=lib/slug.sh
source "${0%/*}/lib/slug.sh"
SLUG=$(repo_slug "$TOPLEVEL")

MARKER_DIR="$HOME/.claude/methodology/session-end"
mkdir -p "$MARKER_DIR" 2>/dev/null

SIGNALS_JSON=$(printf '%s\n' "${SIGNALS[@]}" | jq -R . | jq -s . 2>/dev/null)

# Sobrescribe siempre (>, nunca >>): solo importa el último cierre de sesión.
# Escritura atómica: si jq falla a mitad de camino, el redirect ya truncó
# el archivo destino a 0 bytes. Se escribe primero a un .tmp.$$ y se mueve
# solo si jq tuvo éxito, para nunca dejar el marker truncado.
MARKER_TMP="$MARKER_DIR/$SLUG.json.tmp.$$"
if jq -n \
  --arg ts "$NOW" \
  --arg reason "$REASON" \
  --arg branch "$BRANCH" \
  --arg head "$HEAD" \
  --argjson signals "$SIGNALS_JSON" \
  '{ts: $ts, reason: $reason, branch: $branch, head: $head, signals: $signals}' \
  > "$MARKER_TMP" 2>/dev/null; then
  mv -f "$MARKER_TMP" "$MARKER_DIR/$SLUG.json"
else
  rm -f "$MARKER_TMP"
fi

exit 0
