#!/bin/bash
# Subagent stop log: appendea una línea JSONL por cada invocación de
# subagente que termina (evento SubagentStop), para medir el budget de
# agent-budget.md en la retro de Fase 4. No bloqueante — observabilidad pura,
# nunca interfiere con el evento. A diferencia de PreCompact/SessionEnd, no
# exige repo git ni .planning/: loguea siempre, con repo/branch en null si no
# hay repo (D2).

INPUT=$(cat 2>/dev/null)

# Sin jq no hay forma segura de parsear el stdin ni de serializar la línea.
command -v jq > /dev/null 2>&1 || exit 0

# stdin vacío o JSON malformado: no-op limpio. Nunca appendear una línea
# corrupta al log.
[ -n "$INPUT" ] || exit 0
echo "$INPUT" | jq empty > /dev/null 2>&1 || exit 0

AGENT=$(echo "$INPUT" | jq -r '.agent_type // .subagent_type // "unknown"' 2>/dev/null)
[ -n "$AGENT" ] && [ "$AGENT" != "null" ] || AGENT="unknown"

SESSION=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
TRANSCRIPT=$(echo "$INPUT" | jq -r '.agent_transcript_path // .transcript_path // empty' 2>/dev/null)

# Sin gate de repo: puede correr fuera de cualquier repo git (D2). Si no hay
# repo, TOPLEVEL/BRANCH quedan vacíos y se serializan como null más abajo.
TOPLEVEL=$(git rev-parse --show-toplevel 2>/dev/null)
BRANCH=$(git branch --show-current 2>/dev/null)

NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)

LOG_DIR="$HOME/.claude/methodology/logs"
LOG_FILE="$LOG_DIR/subagent-invocations.jsonl"
mkdir -p "$LOG_DIR" 2>/dev/null

LINE=$(jq -n \
  --arg ts "$NOW" \
  --arg agent "$AGENT" \
  --arg session "$SESSION" \
  --arg repo "$TOPLEVEL" \
  --arg branch "$BRANCH" \
  --arg transcript "$TRANSCRIPT" \
  '{
    ts: $ts,
    agent: $agent,
    session: (if $session == "" then null else $session end),
    repo: (if $repo == "" then null else $repo end),
    branch: (if $branch == "" then null else $branch end),
    transcript: (if $transcript == "" then null else $transcript end)
  }' 2>/dev/null)

[ -n "$LINE" ] && echo "$LINE" >> "$LOG_FILE" 2>/dev/null

exit 0
