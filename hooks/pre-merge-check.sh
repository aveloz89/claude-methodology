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
#      evasión adversarial. El saneo + ancla vive en hooks/lib/guard-
#      matching.sh — compartido con block-admin-merge.sh y pre-commit-
#      guard.sh, que tenían el mismo matching frágil (#47).
#   4. CI SIN CHECKS CONFIGURADOS: en un repo sin ningún check (gh pr checks
#      no reporta nada para esa PR), el guard bloqueaba con el mismo mensaje
#      que usa para un fallo real de la consulta. "Sin checks" es un pass
#      legítimo (0 fallando, 0 pendientes); ahora se distingue por el texto
#      que gh manda a stderr ("no checks reported"), el único indicador
#      disponible — no hay una salida --json para este caso. Limitación
#      aceptada: si gh cambia ese texto en una versión futura, este caso
#      vuelve a fail-closed (bloquea) en vez de pasar — es el fallback
#      seguro.
#
# Endurecido 2026-08-13 (fail-closed sin dependencias, #50):
#   5. Todo lo anterior depende de perl (saneo del comando), jq (parseo del
#      JSON de entrada y de las respuestas de gh) y grep (el gate del saneo
#      degradado y el camino dominante que decide "esto es una invocación
#      real"). Antes, si faltaba cualquiera de los dos primeros, la
#      sustitución/parseo devolvía vacío, el grep no matcheaba, y el hook
#      emitía {"continue":true} en silencio: cualquier gh pr merge pasaba
#      sin verificar — justo lo contrario del diseño fail-closed que este
#      header declara. grep se sumó al check en la retro del PR #60: sin
#      él, "command not found" hace que el `if !` de las líneas de match
#      de abajo se evalúe como éxito, con el mismo resultado de fail-open.
#      Ahora los tres se verifican al inicio, antes de leer stdin, y se
#      bloquea sin depender de jq (la propia herramienta que puede faltar).
if ! command -v perl > /dev/null 2>&1 || ! command -v jq > /dev/null 2>&1 || ! command -v grep > /dev/null 2>&1; then
  printf '{"decision":"block","reason":"pre-merge-check no operativo: falta perl, jq o grep"}\n'
  exit 0
fi

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Resolución del path del lib sin depender de un binario externo (dirname):
# "${0%/*}" es el idioma de shell para dirname cuando $0 trae al menos un
# "/" — siempre el caso dado cómo el harness invoca los hooks. Ver #50: la
# misma razón por la que el check de perl/jq de arriba no puede fallar
# abierto, un `source` de un path que dirname no pudo resolver tampoco.
LIB="${0%/*}/lib/guard-matching.sh"
if [ ! -r "$LIB" ]; then
  printf '{"decision":"block","reason":"pre-merge-check no operativo: falta hooks/lib/guard-matching.sh"}\n'
  exit 0
fi
# shellcheck source=lib/guard-matching.sh
source "$LIB"

SANITIZED_COMMAND=$(guard_sanitize "$COMMAND")
SANITIZE_STATUS=$?

# "perl falló en tiempo de ejecución" y "perl ausente" (chequeado arriba,
# antes de leer stdin) son el mismo estado para este guard: bloquea. Los
# otros dos guards que sanean (block-admin-merge.sh, pre-commit-guard.sh)
# toleran el fallback de guard_sanitize (comando sin sanear) porque solo
# BLOQUEAN de más sobre texto crudo — la dirección segura. Este guard es
# distinto: EXTRAE el número de PR del texto (abajo) para decidir A CUÁL
# PR validar, y esa extracción no está anclada con GUARD_ANCHOR como el
# check de "es una invocación real" — sobre texto sin sanear, un señuelo
# quoted con número (ej. un mensaje de commit que menciona "gh pr merge 7")
# le gana la extracción a la invocación real y el guard termina
# verificando el PR equivocado en vez de bloquear por "sin número
# explícito", que es lo que correspondería. Ver guard_sanitize() en
# hooks/lib/guard-matching.sh para el contrato de exit status. El status
# se captura en SANITIZE_STATUS en la línea de arriba, inmediatamente
# después de la asignación — no como un "$?" leído más abajo, que un
# comando insertado entre medio podría pisar en silencio.
#
# Gate permisivo sobre el texto CRUDO (no el saneado, que no es confiable
# acá) antes de bloquear: este guard corre sobre TODAS las llamadas Bash
# del harness, no solo sobre merges. Sin este gate, un saneo fallido
# bloqueaba cualquier comando — "ls -la", "cat README.md", "git status" —
# con un mensaje sobre extracción de números de PR que para esos comandos
# no significa nada (security, verificado empíricamente). Y es alcanzable
# sin trampas: el regex de heredocs sigue siendo ~O(n²) en aperturas
# "<<palabra" sin terminador — un comando legítimo lo bastante grande
# agota el alarm(5) él solo. Si el texto ni siquiera menciona gh/pr/merge
# no puede ser una invocación real de "gh pr merge" — no bloquea. Si SÍ
# los menciona, no se puede confiar en la extracción sobre texto sin
# sanear — bloquea igual que antes. Nota de security: este gate sobre
# crudo pierde invocaciones partidas con continuación de línea, pero esa
# limitación ya existe hoy en el camino de fallback de abajo (el check de
# "es una invocación real", más adelante en este archivo), así que acotar
# no empeora nada.
if [ "$SANITIZE_STATUS" -ne 0 ]; then
  if echo "$COMMAND" | grep -qi 'gh' && echo "$COMMAND" | grep -qi 'pr' && echo "$COMMAND" | grep -qi 'merge'; then
    printf '{"decision":"block","reason":"pre-merge-check no operativo: el saneo del comando falló (perl abortó en tiempo de ejecución) — no se puede confiar en la extracción del número de PR sobre texto sin sanear"}\n'
    exit 0
  fi
  echo '{"continue":true}'
  exit 0
fi

# Solo interceptar invocaciones reales de gh pr merge
if ! echo "$SANITIZED_COMMAND" | grep -qE "${GUARD_ANCHOR}gh\s+pr\s+merge\b"; then
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

# --repo <owner>/<name> (o --repo=<owner>/<name>) explícito en el comando
# interceptado: gana sobre el repo del cwd de la sesión. Antes, el guard
# detectaba el repo SIEMPRE con `gh repo view` sobre el cwd — un `gh pr
# merge <N> --repo otro/repo` real quedaba bloqueado fail-closed porque
# `gh pr view` corría contra el repo local, donde ese PR no existe (no hay
# "cd" posible al cwd del comando interceptado: este hook corre en la raíz
# de la sesión). Se extrae del comando YA SANEADO (mismo criterio que
# PR_NUMBER, arriba): sobre texto sin sanear, un --repo quoted dentro de un
# heredoc/mensaje de commit podría ganarle a la invocación real. Se valida
# la forma "owner/name" antes de usarlo en cualquier lado — el valor
# termina en comandos gh y en variables de una query GraphQL, y un --repo
# malformado (sin "/", con comillas o espacios) bloquea fail-closed en vez
# de intentar una consulta con un valor del que no se puede confiar.
REPO_FLAG_MATCH=$(echo "$SANITIZED_COMMAND" | grep -oE -- '--repo(=| +)[^ ]+' | head -1)
EXPLICIT_REPO=""
if [ -n "$REPO_FLAG_MATCH" ]; then
  EXPLICIT_REPO=$(echo "$REPO_FLAG_MATCH" | grep -oE '[^ =]+$')
  if ! echo "$EXPLICIT_REPO" | grep -qE '^[A-Za-z0-9][A-Za-z0-9._-]*/[A-Za-z0-9._-]+$'; then
    block "Blocked: --repo '${EXPLICIT_REPO}' no tiene forma owner/name válida — el guard no puede verificar un repo malformado."
  fi
fi

# Detectar owner/repo: el --repo explícito gana; si no hay, fail-closed
# sobre el remoto del cwd de la sesión (comportamiento previo a esta
# extensión, intacto para el caso sin --repo).
if [ -n "$EXPLICIT_REPO" ]; then
  REPO="$EXPLICIT_REPO"
else
  REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null)
  if [ -z "$REPO" ]; then
    block "Blocked: no pude detectar el repo (gh repo view falló). El guard no puede verificar el PR #${PR_NUMBER} — reintenta o revisa la conexión/auth de gh."
  fi
fi
OWNER="${REPO%%/*}"
NAME="${REPO##*/}"

ERRORS=""

# 1. Review decision (CHANGES_REQUESTED) — fail-closed si la consulta falla.
# Nota: reviewDecision es null legítimamente cuando no hay reviews requeridos,
# por eso se distingue "consulta falló" (exit code) de "campo null".
REVIEW_JSON=$(gh pr view "$PR_NUMBER" --repo "$REPO" --json reviewDecision 2>/dev/null)
if [ -z "$REVIEW_JSON" ]; then
  block "Blocked: no pude consultar el PR #${PR_NUMBER} (gh pr view falló). Reintenta — el guard no verifica a ciegas."
fi
REVIEW_DECISION=$(echo "$REVIEW_JSON" | jq -r '.reviewDecision // empty')
if [ "$REVIEW_DECISION" = "CHANGES_REQUESTED" ]; then
  ERRORS="${ERRORS}  - Review bloqueante: hay reviews con CHANGES_REQUESTED\n"
fi

# 2. Threads de review sin resolver (inline). GraphQL es la única API que
# expone isResolved; la REST de comments no distingue resuelto de abierto.
# OWNER/NAME viajan como variables GraphQL (-f, siempre string — sin la
# conversión de tipo "mágica" de -F, que rompería si un nombre fuera todo
# dígitos), no interpolados crudo en el string de la query: con --repo
# ahora aceptando un valor del comando interceptado, interpolar directo
# dejaría un carácter de escape de GraphQL (una comilla, por ejemplo)
# romper la query o alterar su significado. PR_NUMBER sigue interpolado —
# ya viene validado como solo-dígitos por la extracción de arriba.
THREADS_JSON=$(gh api graphql \
  -f owner="$OWNER" \
  -f name="$NAME" \
  -f query='query($owner: String!, $name: String!) { repository(owner: $owner, name: $name) { pullRequest(number: '"$PR_NUMBER"') { reviewThreads(first: 100) { nodes { isResolved } } } } }' \
  2>/dev/null)
if [ -z "$THREADS_JSON" ]; then
  block "Blocked: no pude consultar los threads de review del PR #${PR_NUMBER} (GraphQL falló). Reintenta — el guard no verifica a ciegas."
fi
# jq -e: exit no-cero si el jq falla (ej. .data.repository viene null —
# permisos, repo renombrado, error con HTTP 200 — e indexar .pullRequest
# sobre null revienta) o si el resultado final es null/false. Antes, un jq
# fallido dejaba UNRESOLVED vacío y "${UNRESOLVED:-0}" lo convertía en
# "cero threads sin resolver": el guard pasaba en silencio. `length`
# siempre produce un número (nunca null/false), así que el caso normal de
# 0 threads sin resolver sigue pasando igual.
UNRESOLVED=$(echo "$THREADS_JSON" | jq -e '[.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved == false)] | length' 2>/dev/null)
if [ $? -ne 0 ]; then
  block "Blocked: no pude parsear los threads de review del PR #${PR_NUMBER} (respuesta de GraphQL inesperada). Reintenta — el guard no verifica a ciegas."
fi
if [ "$UNRESOLVED" -gt 0 ]; then
  ERRORS="${ERRORS}  - Hay ${UNRESOLVED} thread(s) de review sin resolver. Resuélvelos o respóndelos antes de mergear\n"
fi

# 3. CI checks — gh pr checks sale con rc!=0 tanto si hay checks fallando,
# si la llamada falla, o si el repo no tiene ningún check configurado (caso
# legítimo: 0 fallando, 0 pendientes). Distinguimos "sin checks" de "la
# consulta falló de verdad" por el texto de stderr ("no checks reported"),
# el único indicador que expone gh para este caso.
CHECKS_STDERR_FILE=$(mktemp)
CHECKS_OUTPUT=$(gh pr checks "$PR_NUMBER" --repo "$REPO" 2>"$CHECKS_STDERR_FILE")
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
