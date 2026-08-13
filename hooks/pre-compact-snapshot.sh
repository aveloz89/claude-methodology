#!/bin/bash
# Pre-compact snapshot: guarda una copia completa de .planning/ antes de que
# el contexto se compacte (evento PreCompact), para poder recuperar
# STATE/HANDOFF/DESIGN si el compact deja el estado inconsistente. No
# bloqueante — PreCompact es observabilidad, nunca bloquea el evento.

INPUT=$(cat 2>/dev/null)

# stdin vacío o JSON malformado: no-op limpio. Sin un payload confiable no
# hay trigger del que fiarse, así que no se crea ningún snapshot.
[ -n "$INPUT" ] || exit 0
echo "$INPUT" | jq empty > /dev/null 2>&1 || exit 0

TOPLEVEL=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
[ -d "$TOPLEVEL/.planning" ] || exit 0

TRIGGER=$(echo "$INPUT" | jq -r '.trigger // "unknown"' 2>/dev/null)
[ -n "$TRIGGER" ] && [ "$TRIGGER" != "null" ] || TRIGGER="unknown"
# Mismo tratamiento que el slug: nunca dejar que el trigger introduzca un
# separador de path en el nombre del directorio de destino.
TRIGGER=$(echo "$TRIGGER" | tr '/' '-')

SLUG=$(echo "$TOPLEVEL" | tr '/' '-')
TS=$(date -u +%Y%m%d-%H%M%S)
SNAPSHOT_DIR="$HOME/.claude/methodology/snapshots/$SLUG/${TS}-${TRIGGER}"

mkdir -p "$SNAPSHOT_DIR" 2>/dev/null
cp -R "$TOPLEVEL/.planning/." "$SNAPSHOT_DIR/" 2>/dev/null

BRANCH=$(git branch --show-current 2>/dev/null)
HEAD=$(git rev-parse --short HEAD 2>/dev/null)
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)

jq -n \
  --arg ts "$NOW" \
  --arg trigger "$TRIGGER" \
  --arg branch "$BRANCH" \
  --arg head "$HEAD" \
  --arg repo "$TOPLEVEL" \
  '{ts: $ts, trigger: $trigger, branch: $branch, head: $head, repo: $repo}' \
  > "$SNAPSHOT_DIR/meta.json" 2>/dev/null

# Retención: conservar solo los 5 snapshots más recientes de este repo.
# Orden lexicográfico del nombre = cronológico por el prefijo timestamp.
# tail -n +6 (no head -n -5: no existe en macOS/BSD).
SNAPSHOTS_ROOT="$HOME/.claude/methodology/snapshots/$SLUG"
(cd "$SNAPSHOTS_ROOT" 2>/dev/null && ls -1 | sort -r | tail -n +6 | xargs rm -rf)

exit 0
