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

block() {
  local reason="$1"
  echo "{\"decision\":\"block\",\"reason\":$(printf '%s' "$reason" | jq -Rs .)}"
  exit 0
}

# [security, ronda 3] Ventana de la invocación anclada, consciente de
# balance. La ronda 2 cortaba la ventana en el primer ";", "|", "&", ")",
# "}" o backtick que aparecía — sin distinguir un separador de comando real
# de un delimitador de expansión que ABRE adentro de la propia ventana:
# "gh pr merge 45 --match-head-commit $(git rev-parse HEAD) --repo real/repo"
# cortaba en el ")" que cierra el $(...), perdiendo el --repo real que
# viene después — el guard caía al repo del cwd sin verificar nada
# (fail-open real, reproducido con gh falso: mismo patrón que el HIGH #1
# de la ronda anterior, esta vez introducido por el propio fix). Pasaba
# igual con "${VAR}" y con backticks que abren a mitad de la ventana
# (--subject `date`).
#
# Fix: en vez de una clase de caracteres plana, se tokeniza la ventana
# llevando la cuenta de paréntesis y llaves abiertas DENTRO de la ventana
# (sin contar el "(", "{" o backtick que pudo haber abierto el GUARD_ANCHOR,
# que arranca en cero porque el conteo empieza justo en "gh", no antes) y
# de si hay un backtick pendiente. Un ")"/"}"/backtick con el contador
# correspondiente en cero es lo único que corta la ventana — cierra algo
# que se abrió ANTES de este comando (el propio anchor, o un grupo/
# subshell que ya envolvía todo desde afuera), nunca algo que se abrió
# adentro. Mismo criterio para ";"/"|"/"&": solo cortan si ningún
# paréntesis/llave/backtick sigue abierto — un separador real DENTRO de
# un $(cmd1; cmd2) no es un separador para ESTE comando.
#
# Implementado en perl (no en un loop de bash carácter por carácter): un
# loop de bash con "${s:$i:1}" sobre un solo carácter a la vez resultó
# CUADRÁTICO en este intérprete — 100 KB ya no terminaba en 2 minutos.
# perl con \G/pos() en modo scalar consume corridas enteras de texto
# "aburrido" en una sola operación de regex (compilada, sin el overhead
# de iterar carácter por carácter a nivel de intérprete): medido, 1 MB
# en 0.05s, 20 MB en 0.95s — lineal, no cuadrático (y sin backtracking
# ambiguo: cada alternativa del regex consume un conjunto de caracteres
# disjunto del resto, igual razonamiento de guard_sanitize). alarm(5)
# como red de seguridad ante cualquier patológico no anticipado, igual
# que en guard_sanitize — si perl no vuelve a tiempo (o falla por
# cualquier otro motivo), NO se puede confiar en una ventana parcial o
# vacía: bloquea en vez de adivinar cuál mitad del comando es la real.
ANCHORED_TO_END=$(echo "$SANITIZED_COMMAND" | grep -oE "${GUARD_ANCHOR}"'gh\s+pr\s+merge\b.*' | head -1)
# Recorta el prefijo del anchor (separador, o el "(", "{" o backtick que
# lo empieza) buscando "gh pr merge" DENTRO del texto ya anclado — seguro
# porque ANCHORED_TO_END ya está acotado a partir del match real, no
# vuelve a buscar sobre el comando completo.
MERGE_WINDOW_FULL=$(echo "$ANCHORED_TO_END" | grep -oE 'gh\s+pr\s+merge\b.*' | head -1)
# Si lo que abrió el anchor fue justo un backtick, el contador de
# paréntesis/llaves no alcanza para reconocerlo (backtick usa el MISMO
# carácter para abrir y cerrar) — se pasa aparte para que el primer
# backtick que aparezca escaneando se trate como su cierre, no como la
# apertura de uno nuevo.
ANCHOR_STARTS_BACKTICK=false
[ "${ANCHORED_TO_END:0:1}" = '`' ] && ANCHOR_STARTS_BACKTICK=true

# [security, ronda 4] El contador cortaba SOLO al llegar a un cierre con
# profundidad cero — nunca miraba su propio estado al llegar a fin de
# ventana. Un abridor que sobrevive a guard_sanitize sin su cierre (un
# "\(" escapado, o una llave suelta como "a{b" — ninguno de los dos es
# heredoc, quoted span ni continuación, así que guard_sanitize los deja
# intactos) dejaba paren_depth/brace_depth en >0 para SIEMPRE: ";"/"|"/"&"
# dejaban de cortar (exigen los tres contadores en cero) y la ventana se
# comía la invocación siguiente completa — con "gana la última" del
# tokenizer de --repo, el --repo del vecino le ganaba al real. Fix: al
# salir del while (por "last" o por agotar el string), si algún contador
# quedó > 0 o el backtick sigue abierto, la ventana no tiene límites
# determinables — sale con status != 0 y el caller bloquea (mismo camino
# que ya existía para el timeout de alarm(5)). Una ventana indeterminada
# no es una ventana: no se adivina ni de más ni de menos.
MERGE_WINDOW=$(printf '%s' "$MERGE_WINDOW_FULL" | perl -0777 -e '
BEGIN { alarm 5 }
my $anchor_backtick = $ARGV[0];
my $s = <STDIN>;
my $paren_depth = 0;
my $brace_depth = 0;
my $backtick_state = ($anchor_backtick eq "true") ? "outer" : "none";
my $stop_pos = length($s);
while ($s =~ /\G(\$\(|\$\{|[(){}`;|&]|[^(){}`;|&]+)/gc) {
  my $tok = $1;
  if ($tok eq "\$(" || $tok eq "(") {
    $paren_depth++;
  } elsif ($tok eq "\${" || $tok eq "{") {
    $brace_depth++;
  } elsif ($tok eq ")") {
    if ($paren_depth > 0) { $paren_depth--; }
    else { $stop_pos = pos($s) - length($tok); last; }
  } elsif ($tok eq "}") {
    if ($brace_depth > 0) { $brace_depth--; }
    else { $stop_pos = pos($s) - length($tok); last; }
  } elsif ($tok eq "`") {
    if ($backtick_state eq "outer") { $backtick_state = "none"; $stop_pos = pos($s) - length($tok); last; }
    elsif ($backtick_state eq "mid") { $backtick_state = "none"; }
    else { $backtick_state = "mid"; }
  } elsif ($tok eq ";" || $tok eq "|" || $tok eq "&") {
    if ($paren_depth == 0 && $brace_depth == 0 && $backtick_state eq "none") {
      $stop_pos = pos($s) - length($tok);
      last;
    }
  }
}
if ($paren_depth != 0 || $brace_depth != 0 || $backtick_state ne "none") {
  exit 1;
}
print substr($s, 0, $stop_pos);
' "$ANCHOR_STARTS_BACKTICK")
MERGE_WINDOW_STATUS=$?
if [ "$MERGE_WINDOW_STATUS" -ne 0 ]; then
  block "Blocked: no pude determinar los límites de la invocación real de gh pr merge (el cálculo de la ventana falló, superó el tiempo límite, o quedó indeterminada por un paréntesis/llave/backtick sin cerrar) — el guard no verifica a ciegas."
fi

# [security, ronda 3] PR_NUMBER se extrae de la MISMA ventana que --repo
# (antes salía del comando completo, sin anclar y sin head -1): con
# "gh pr merge 1 --repo a/b || gh pr merge 45 --repo real/repo", el número
# podía salir de una invocación distinta a la que --repo ya resolvía desde
# la ronda 2 — hoy dos invocaciones así terminan fail-closed contra gh
# real (la extracción multilínea revienta la query GraphQL), pero conviene
# que ambos salgan siempre de la misma invocación en vez de depender de
# ese efecto colateral. head -1 al final por determinismo: si igual
# apareciera más de un match dentro de la ventana (no debería, dado el
# balance de arriba), se toma el primero de forma explícita en vez de
# dejar que la asignación de PR_NUMBER termine multilínea.
PR_NUMBER=$(echo "$MERGE_WINDOW" | grep -oE 'gh\s+pr\s+merge\s+([0-9]+)' | head -1 | grep -oE '[0-9]+')

if [ -z "$PR_NUMBER" ]; then
  # Sin número explícito no podemos verificar el PR correcto → fail-closed.
  # Nota: "gh pr merge --repo o/r 45" (flag antes del número) es forma
  # válida de gh y cae acá — fail-closed, no es un hueco, solo una
  # invocación válida que el guard no resuelve. No se generaliza la
  # extracción a "cualquier token numérico de la ventana" para no ampliar
  # el scope de este fix; ver reporte del PR para la nota completa.
  echo '{"decision":"block","reason":"Blocked: gh pr merge sin número de PR explícito — el guard no puede verificar el PR implícito del branch. Usa gh pr merge <numero>."}'
  exit 0
fi

# --repo <owner>/<name> (o --repo=<owner>/<name>, -R <owner>/<name>,
# -R<owner>/<name> pegado sin espacio, o -R=<owner>/<name> — las formas
# que gh realmente acepta, verificado contra `gh help pr merge` y contra
# GitHub real) explícito en el comando interceptado: gana sobre el repo
# del cwd de la sesión. Antes, el guard detectaba el repo SIEMPRE con
# `gh repo view` sobre el cwd — un `gh pr merge <N> --repo otro/repo`
# real quedaba bloqueado fail-closed porque `gh pr view` corría contra el
# repo local, donde ese PR no existe (no hay "cd" posible al cwd del
# comando interceptado: este hook corre en la raíz de la sesión). Se
# busca dentro de MERGE_WINDOW (calculada arriba, anclada y consciente de
# balance) — no en el comando completo.
#
# gh no trata --repo como "una flag, un token": acepta -R en tres formas
# (con espacio, pegado "-Rvalor", con "=") y, si se repite, gana la
# ÚLTIMA ocurrencia (verificado contra GitHub real con --repo duplicado y
# con --repo/-R mezclados). Un regex de un solo shot no modela esto con
# confianza — se tokeniza la ventana (misma noción de "palabras
# separadas por espacio" que ve gh en argv, ya que guard_sanitize corrió
# antes) y se recorre de izquierda a derecha pisando el valor cada vez
# que aparece la flag, para que gane la última igual que en gh real.
#
# [security, ronda 3, LOW] "Gana la última" asume que TODO lo que quedó
# dentro de MERGE_WINDOW es confiable por igual, incluida la cola: un
# decoy después del --repo real pero antes de cualquier separador real
# también gana, por ejemplo un comentario en la misma línea
# ("gh pr merge 45 --repo real/repo # ojo con --repo evil/x" usa
# evil/x) — guard_sanitize no sabe de comentarios "#" de shell, así que
# ese texto no se distingue de una flag real. Fidelidad correcta a gh
# (así prioriza gh de verdad) pero vale dejarlo escrito: NO es "se
# ignora lo sospechoso", es "gana lo último, punto", y ese supuesto
# depende de que nada dentro de la ventana sea contenido inerte que
# guard_sanitize no supo reconocer.
#
# Un valor entre comillas queda destruido por guard_sanitize (colapsa el
# span quoted a un solo espacio) ANTES de que esta extracción corra —
# comillar el argumento es una forma normal de escribir el comando, no
# evasión, así que no se puede ignorar sin más. Si la flag aparece pero no
# queda un token utilizable después (vacío, o el siguiente token es otra
# flag que empieza con "-"), NO se adivina el repo del cwd: se bloquea más
# abajo. Esto también evita culpar a la flag equivocada: en
# "--repo 'a/b' --squash", el único token que sobrevive al saneo después
# de --repo es "--squash" — se descarta por empezar con "-" (no se toma
# como valor), en vez de terminar bloqueando con un mensaje que responsabiliza
# a --squash de una forma inválida que no es suya.
REPO_FLAG_SEEN=false
REPO_FLAG_VALUE=""
read -ra MERGE_WINDOW_TOKENS <<< "$MERGE_WINDOW"
TOKEN_IDX=0
TOKEN_COUNT=${#MERGE_WINDOW_TOKENS[@]}
while [ "$TOKEN_IDX" -lt "$TOKEN_COUNT" ]; do
  TOKEN="${MERGE_WINDOW_TOKENS[$TOKEN_IDX]}"
  case "$TOKEN" in
    --repo=*)
      REPO_FLAG_SEEN=true
      REPO_FLAG_VALUE="${TOKEN#--repo=}"
      ;;
    --repo|-R)
      REPO_FLAG_SEEN=true
      NEXT_IDX=$((TOKEN_IDX + 1))
      if [ "$NEXT_IDX" -lt "$TOKEN_COUNT" ] && [ -n "${MERGE_WINDOW_TOKENS[$NEXT_IDX]}" ] \
        && [[ "${MERGE_WINDOW_TOKENS[$NEXT_IDX]}" != -* ]]; then
        REPO_FLAG_VALUE="${MERGE_WINDOW_TOKENS[$NEXT_IDX]}"
        TOKEN_IDX=$NEXT_IDX
      else
        REPO_FLAG_VALUE=""
      fi
      ;;
    -R=*)
      REPO_FLAG_SEEN=true
      REPO_FLAG_VALUE="${TOKEN#-R=}"
      ;;
    -R?*)
      REPO_FLAG_SEEN=true
      REPO_FLAG_VALUE="${TOKEN#-R}"
      ;;
  esac
  TOKEN_IDX=$((TOKEN_IDX + 1))
done

EXPLICIT_REPO=""
if [ "$REPO_FLAG_SEEN" = true ]; then
  # Forma validada: "owner/name" (dos segmentos, sin "/" adicional en
  # ninguno de los dos gracias a la clase de caracteres). Esto rechaza a
  # propósito la forma de tres segmentos "[HOST/]OWNER/REPO" que gh
  # documenta para GitHub Enterprise — fail-closed (bloquea en vez de
  # adivinar cuál segmento es el host), no una vulnerabilidad, pero
  # que no sorprenda al próximo: un --repo apuntando a un host Enterprise
  # real bloquea igual que uno malformado.
  if echo "$REPO_FLAG_VALUE" | grep -qE '^[A-Za-z0-9][A-Za-z0-9._-]*/[A-Za-z0-9._-]+$'; then
    EXPLICIT_REPO="$REPO_FLAG_VALUE"
  else
    # [security LOW] El valor reflejado en el mensaje se trunca: viene del
    # comando (un token sin cota de tamaño), y jq -Rs escapa bien pero no
    # acota longitud — sin esto, un token de cientos de KB vuelve entero
    # al usuario en el reason.
    REPO_VALUE_FOR_REASON="$REPO_FLAG_VALUE"
    if [ "${#REPO_VALUE_FOR_REASON}" -gt 64 ]; then
      REPO_VALUE_FOR_REASON="${REPO_VALUE_FOR_REASON:0:64}..."
    fi
    block "Blocked: --repo/-R sin un valor owner/name utilizable ('${REPO_VALUE_FOR_REASON}') — puede ser una comilla saneada (guard_sanitize colapsa comillas a un espacio) o una forma inválida/incompleta. El guard no puede verificar un repo sin confirmar cuál es."
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
