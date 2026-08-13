#!/bin/bash
# Verifica que un PR no tenga threads de review sin resolver, reviews
# bloqueantes, ni CI checks fallando antes de permitir el merge.
#
# Endurecido 2026-08-11 tras el incidente de #821/#822:
#   1. FAIL-CLOSED: si una llamada a gh falla (rate limit, red), el hook
#      BLOQUEA explicando que no pudo verificar — antes fallaba abierto en
#      silencio, y por eso #821 se mergeó sin que el guard actuara.
#   2. PRECISIÓN: solo bloquean los threads de review SIN RESOLVER (inline,
#      via GraphQL isResolved). Los comentarios generales del PR no tienen
#      estado de resolución y son conversación legítima (resúmenes de ronda,
#      contexto) — contarlos todos obligaba a borrarlos para poder mergear.
#
# Endurecido 2026-08-13 (matching quirúrgico + CI sin checks configurados):
#   3. MATCHING: el gate ya no hace grep sobre el string crudo del comando.
#      Antes, un git commit con un heredoc que mencionaba la frase de merge
#      en su mensaje disparaba el gate como si fuera una invocación real
#      (falso positivo bloqueante), y si esa mención traía un número, el
#      guard terminaba validando un PR sin relación con el comando real
#      (falso positivo con blast radius). En sentido contrario, un merge
#      real dentro de un comando compuesto (cmd && gh pr merge N) pasaba
#      sin validar porque el gate solo miraba el inicio del string completo
#      (falso negativo). Ahora se sanean spans quoted ('...' y "...") y
#      cuerpos de heredoc antes de matchear, y el match se ancla a posición
#      de comando (inicio de string/línea, o justo después de &&, ||, ;, |,
#      $(). Limitación aceptada: es saneo heurístico de texto, no un parser
#      de shell real — un wrapper como bash -c "..." no se detecta porque
#      el comando real queda dentro de una string que este hook sanitiza.
#      Aceptable: el hook protege errores honestos del orchestrator, no
#      evasión adversarial.
#   4. CI SIN CHECKS CONFIGURADOS: en un repo sin ningún check (gh pr checks
#      no reporta nada para esa PR), el guard bloqueaba con el mismo mensaje
#      que usa para un fallo real de la consulta. "Sin checks" es un pass
#      legítimo (0 fallando, 0 pendientes); ahora se distingue por el texto
#      que gh manda a stderr ("no checks reported"), el único indicador
#      disponible — no hay una salida --json para este caso. Limitación
#      aceptada: si gh cambia ese texto en una versión futura, este caso
#      vuelve a fail-closed (bloquea) en vez de pasar — es el fallback
#      seguro.

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Antes de matchear, sacamos del texto los spans quoted ('...'/"...") y los
# cuerpos de heredoc: son contenido literal (ej. un mensaje de commit) que
# puede mencionar la frase de merge sin ser una invocación real. El match
# además se ancla a posición de comando (inicio de string/línea, o justo
# después de &&, ||, ;, |, $() para no perder invocaciones reales dentro de
# comandos compuestos.
SANITIZED_COMMAND=$(echo "$COMMAND" | perl -0777 -pe '
  s/<<-?[\x27"]?(\w+)[\x27"]?[^\n]*\n(?:(?!^[ \t]*\1$).*\n?)*[ \t]*\1(?:\n|$)/\n/gsm;
  s/\x27[^\x27]*\x27/ /g;
  s/"(?:[^"\\]|\\.)*"/ /g;
')

# Solo interceptar invocaciones reales de gh pr merge
if ! echo "$SANITIZED_COMMAND" | grep -qE '(^|&&|\|\||;|\||\$\()\s*gh\s+pr\s+merge\b'; then
  echo '{"continue":true}'
  exit 0
fi

# Extraer el número de PR de la invocación real (ya sin quotes/heredocs)
PR_NUMBER=$(echo "$SANITIZED_COMMAND" | grep -oE 'gh\s+pr\s+merge\s+([0-9]+)' | grep -oE '[0-9]+')

if [ -z "$PR_NUMBER" ]; then
  # Sin número explícito no podemos verificar el PR correcto → fail-closed
  echo '{"decision":"block","reason":"Blocked: gh pr merge sin número de PR explícito — el guard no puede verificar el PR implícito del branch. Usa gh pr merge <numero>."}'
  exit 0
fi

block() {
  local reason="$1"
  echo "{\"decision\":\"block\",\"reason\":$(printf '%s' "$reason" | jq -Rs .)}"
  exit 0
}

# Detectar owner/repo del remoto — fail-closed si no se puede
REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null)
if [ -z "$REPO" ]; then
  block "Blocked: no pude detectar el repo (gh repo view falló). El guard no puede verificar el PR #${PR_NUMBER} — reintenta o revisa la conexión/auth de gh."
fi
OWNER="${REPO%%/*}"
NAME="${REPO##*/}"

ERRORS=""

# 1. Review decision (CHANGES_REQUESTED) — fail-closed si la consulta falla.
# Nota: reviewDecision es null legítimamente cuando no hay reviews requeridos,
# por eso se distingue "consulta falló" (exit code) de "campo null".
REVIEW_JSON=$(gh pr view "$PR_NUMBER" --json reviewDecision 2>/dev/null)
if [ -z "$REVIEW_JSON" ]; then
  block "Blocked: no pude consultar el PR #${PR_NUMBER} (gh pr view falló). Reintenta — el guard no verifica a ciegas."
fi
REVIEW_DECISION=$(echo "$REVIEW_JSON" | jq -r '.reviewDecision // empty')
if [ "$REVIEW_DECISION" = "CHANGES_REQUESTED" ]; then
  ERRORS="${ERRORS}  - Review bloqueante: hay reviews con CHANGES_REQUESTED\n"
fi

# 2. Threads de review sin resolver (inline). GraphQL es la única API que
# expone isResolved; la REST de comments no distingue resuelto de abierto.
THREADS_JSON=$(gh api graphql -f query="query { repository(owner: \"${OWNER}\", name: \"${NAME}\") { pullRequest(number: ${PR_NUMBER}) { reviewThreads(first: 100) { nodes { isResolved } } } } }" 2>/dev/null)
if [ -z "$THREADS_JSON" ]; then
  block "Blocked: no pude consultar los threads de review del PR #${PR_NUMBER} (GraphQL falló). Reintenta — el guard no verifica a ciegas."
fi
UNRESOLVED=$(echo "$THREADS_JSON" | jq '[.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved == false)] | length')
if [ "${UNRESOLVED:-0}" -gt 0 ]; then
  ERRORS="${ERRORS}  - Hay ${UNRESOLVED} thread(s) de review sin resolver. Resuélvelos o respóndelos antes de mergear\n"
fi

# 3. CI checks — gh pr checks sale con rc!=0 tanto si hay checks fallando,
# si la llamada falla, o si el repo no tiene ningún check configurado (caso
# legítimo: 0 fallando, 0 pendientes). Distinguimos "sin checks" de "la
# consulta falló de verdad" por el texto de stderr ("no checks reported"),
# el único indicador que expone gh para este caso.
CHECKS_STDERR_FILE=$(mktemp)
CHECKS_OUTPUT=$(gh pr checks "$PR_NUMBER" 2>"$CHECKS_STDERR_FILE")
NO_CHECKS_CONFIGURED=false
grep -qi 'no checks reported' "$CHECKS_STDERR_FILE" && NO_CHECKS_CONFIGURED=true
rm -f "$CHECKS_STDERR_FILE"

if [ -z "$CHECKS_OUTPUT" ] && [ "$NO_CHECKS_CONFIGURED" = false ]; then
  block "Blocked: no pude consultar los CI checks del PR #${PR_NUMBER}. Reintenta — el guard no verifica a ciegas."
fi
FAILED_CHECKS=$(echo "$CHECKS_OUTPUT" | grep -cE '\bfail\b|\berror\b' || true)
PENDING_CHECKS=$(echo "$CHECKS_OUTPUT" | grep -cE '\bpending\b|\bqueued\b' || true)
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
