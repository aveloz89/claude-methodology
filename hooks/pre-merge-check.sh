#!/bin/bash
# Verifica que un PR no tenga comentarios sin resolver, reviews bloqueantes,
# ni CI checks fallando antes de permitir el merge.

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Solo interceptar comandos gh pr merge
if ! echo "$COMMAND" | grep -qE '^\s*gh\s+pr\s+merge\b'; then
  echo '{"continue":true}'
  exit 0
fi

# Extraer el número de PR del comando
PR_NUMBER=$(echo "$COMMAND" | grep -oE 'gh\s+pr\s+merge\s+([0-9]+)' | grep -oE '[0-9]+')

if [ -z "$PR_NUMBER" ]; then
  # Si no hay número explícito, dejar pasar (gh usará el PR del branch actual)
  echo '{"continue":true}'
  exit 0
fi

# Detectar owner/repo del remoto
REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null)
if [ -z "$REPO" ]; then
  echo '{"continue":true}'
  exit 0
fi

ERRORS=""

# 1. Verificar review decision (changes_requested)
REVIEW_DECISION=$(gh pr view "$PR_NUMBER" --json reviewDecision --jq '.reviewDecision' 2>/dev/null)
if [ "$REVIEW_DECISION" = "CHANGES_REQUESTED" ]; then
  ERRORS="${ERRORS}  - Review bloqueante: hay reviews con CHANGES_REQUESTED\n"
fi

# 2. Verificar comentarios sin resolver en el PR
# Contamos review comments (inline en código) que no son replies (son threads raíz)
PENDING_COMMENTS=$(gh api "repos/${REPO}/pulls/${PR_NUMBER}/comments" --jq '[.[] | select(.in_reply_to_id == null)] | length' 2>/dev/null)
# Contamos también issue comments (comentarios generales del PR)
ISSUE_COMMENTS=$(gh api "repos/${REPO}/issues/${PR_NUMBER}/comments" --jq 'length' 2>/dev/null)

TOTAL_COMMENTS=$(( ${PENDING_COMMENTS:-0} + ${ISSUE_COMMENTS:-0} ))
if [ "$TOTAL_COMMENTS" -gt 0 ]; then
  ERRORS="${ERRORS}  - Hay ${TOTAL_COMMENTS} comentario(s) en el PR. Verifica que estén resueltos antes de mergear\n"
fi

# 3. Verificar CI checks
FAILED_CHECKS=$(gh pr checks "$PR_NUMBER" 2>/dev/null | grep -cE 'fail|error' || true)
PENDING_CHECKS=$(gh pr checks "$PR_NUMBER" 2>/dev/null | grep -cE 'pending|queued' || true)
if [ "$FAILED_CHECKS" -gt 0 ]; then
  ERRORS="${ERRORS}  - Hay ${FAILED_CHECKS} CI check(s) fallando\n"
fi
if [ "$PENDING_CHECKS" -gt 0 ]; then
  ERRORS="${ERRORS}  - Hay ${PENDING_CHECKS} CI check(s) pendientes\n"
fi

# Si hay errores, bloquear
if [ -n "$ERRORS" ]; then
  REASON=$(printf "Blocked: PR #${PR_NUMBER} no está listo para merge:\n${ERRORS}Resuelve estos issues antes de mergear.")
  echo "{\"decision\":\"block\",\"reason\":$(echo "$REASON" | jq -Rs .)}"
  exit 0
fi

echo '{"continue":true}'
