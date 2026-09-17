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

# Endurecido 2026-09-16 (repo resuelto por el comando, no por el cwd de la
# sesión, PR #75, y reemplazado en la ronda 3 del mismo follow-up):
#   6. Sin --repo explícito, el guard SIEMPRE resolvía el repo con
#      `gh repo view` corriendo en el cwd de la SESIÓN, sin mirar el resto
#      del comando interceptado. Incidente real: un `cd claude-methodology
#      && gh pr merge 75` lanzado con la sesión parada en easy-quotes
#      resolvió easy-quotes#75 (un PR homónimo, mergeado en julio, con su
#      check de CI en rojo) y bloqueó con un motivo que no aplicaba al PR
#      real.
#
#      Dos rondas intentaron RESOLVER un `cd` inicial (extraer la ruta,
#      correr `gh repo view` ahí) interpretando formas de comando sobre el
#      texto saneado — cada ronda de review encontró una forma nueva que
#      el parser no cubría (separadores sueltos, comillas/backslash a
#      mitad de ruta, saltos de línea, envoltorios que no arrancan con la
#      palabra "cd", -R/--repo intercalado, un segundo merge en otra
#      línea, el valor de --repo truncado por el saneo — ver el historial
#      de commits de este archivo y `.planning/reviews/` de ese PR para el
#      detalle completo). Interpretar shell arbitrario es un problema
#      abierto: cada capa nueva sobre la interpretación de la anterior
#      dejaba un hueco distinto. Decisión del usuario: cortar el parseo.
#
#      Ahora el guard acepta UNA sola forma, anclada de punta a punta y
#      validada sobre el texto CRUDO (tool_input.command tal cual, antes
#      de guard_sanitize — el saneado solo se usa para decidir si el
#      comando MENCIONA una invocación de merge, ver el gate más abajo, no
#      para extraer nada de esta forma):
#
#        gh pr merge <N> [flag ...]
#
#      con <N> = [1-9][0-9]* (seguido de blank o fin) y cada flag EXACTA-
#      MENTE uno de: --merge, -m, --squash, -s, --rebase, -r,
#      --delete-branch, -d, --repo <owner/repo>, --repo=<owner/repo>,
#      -R <owner/repo> — un solo flag de repo por comando, no "gana el
#      último" como antes (repetirlo, aunque sea con el mismo valor,
#      bloquea). --repo/-R ausente resuelve con `gh repo view` en el cwd
#      de la SESIÓN (comportamiento previo a #75, intacto). Nada antes,
#      entre ni después de esa forma: sin cd, sin prefijo de variable de
#      entorno, sin &&/;/|, sin segunda línea. Cualquier otra cosa
#      bloquea explicando la forma aceptada — allowlist total de la
#      forma, no blocklist de construcciones: no hace falta enumerar qué
#      prefijos/separadores están prohibidos, se exige que el comando
#      completo sea exactamente esto. Ver el bloque bajo "Gramática única
#      del merge" más abajo para el detalle de cada chequeo.
#
#      Fuera de alcance (mismo modelo de amenaza que hooks/lib/guard-
#      matching.sh: errores honestos del orchestrator, no evasión
#      adversarial). El gate sin ancla (más abajo) encuentra "gh"/"pr"/
#      "merge" como substring en CUALQUIER posición del texto saneado, así
#      que casi cualquier prefijo SÍ llega a la gramática y bloquea —
#      verificado uno por uno contra el hook real, worktree limpio, sin
#      mocks: `command gh`, `env gh`, `FOO=1 gh`, `\gh` (backslash pegado
#      sin partir la palabra), una ruta absoluta al binario, y un wrapper
#      o una función `gh()` definidos en el MISMO comando que el merge
#      TODOS bloquean (el texto antes de la invocación real rompe "nada
#      antes de gh pr merge"). Solo evaden de verdad los casos donde el
#      saneo o la sintaxis rompen la palabra "gh" en el texto saneado, y
#      por lo tanto el gate sin ancla nunca la encuentra:
#        - El nombre completo entre comillas: `"gh"`, `'gh'` — el span
#          quoted se colapsa entero a un espacio, la palabra desaparece.
#        - Un backslash A MITAD de la palabra: `g\h` (distinto de `\gh`,
#          que bloquea — ahí la palabra "gh" sigue intacta).
#        - Un wrapper de intérprete con el comando entero entre comillas:
#          `zsh -c '...'`, `bash -c "..."`, `sh -c '...'` — el span
#          quoted que contiene "gh pr merge" se colapsa entero.
#        - Un comando ANTERIOR de la sesión que define una función/alias
#          `gh` (ver el punto siguiente: el entorno previo no es visible).
#        Dirección segura: el código bloquea MÁS de lo que este comentario
#        admite, nunca menos.
#      Aparte, el saneo COMPARTIDO de hooks/lib/guard-matching.sh (no se
#      toca en este PR) puede borrar el merge real junto con el texto que
#      lo rodea, dejando el comando sin ninguna mención de "gh"/"pr"/
#      "merge" — verificado, 0 llamadas a gh, continue en HEAD y en dev
#      por igual: un comentario con apóstrofo antes del merge en otra
#      línea (`echo x # don't`⏎`gh pr merge 5`), un `echo` con comillas
#      escapadas rodeando el merge (`echo \'; gh pr merge 5; echo \'`),
#      quoting ANSI-C con apóstrofo (`echo $'it\'s' && gh pr merge 5 &&
#      echo 'x'`), y un heredoc con el delimitador comillado a medias
#      (`cat <<E"OF"`⏎`EOF`⏎`gh pr merge 5`⏎`E`). Es el mismo emparejamiento
#      ciego de comillas documentado en guard-matching.sh:58-65 (un par de
#      comillas de spans DISTINTOS se emparejan entre sí y se tragan el
#      comando real de en medio) — no es un hueco nuevo de este archivo.
#      Tampoco se ensancha GH_PR_MERGE_RE (abajo) para tolerar más de 2
#      tokens entre gh/pr/merge y así detectar flags de repo repetidos
#      ANTES de "pr" o "merge" (ej. `gh pr -R o/a -R o/red merge 5`, que
#      hoy pasa sin validar, 0 llamadas): ensanchar el tope genérico a 4
#      tokens hace que `gh pr view 5 | grep merge` — un falso positivo que
#      tiene que seguir pasando — empiece a matchear también (4 tokens
#      arbitrarios entre "pr" y "merge", verificado con el hook real). Un
#      patrón más específico (solo tokens con forma de flag de repo)
#      evitaría ese choque puntual, pero es agregar una capa más de
#      interpretación de forma sobre un regex cuyo único trabajo es
#      decidir si vale la pena validar — exactamente el patrón que D-04
#      abandonó para la gramática misma. Se documenta en vez de parchear.
#        - El entorno inyectado por archivos de arranque del shell
#          (`.zshenv`, el snapshot de la herramienta Bash) o por un
#          comando previo de la sesión: el proceso de este hook solo ve
#          el texto del comando interceptado y su propio entorno — el que
#          sí se chequea explícitamente (GH_REPO/GH_HOST/GIT_DIR/
#          GIT_WORK_TREE, ver el bloque de "Gramática única del merge").

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

# [D-04] GH_PR_MERGE_RE decide, sobre el texto SANEADO, si el comando
# MENCIONA una invocación de merge — es todo lo que le queda a este
# regex: ya no se usa para extraer nada (eso lo hace la gramática única
# sobre el texto crudo, más abajo). Tolera hasta 2 tokens entre "gh"/"pr"
# y entre "pr"/"merge" (formas como "gh -R x pr merge N", que gh acepta
# de verdad) para que también SE RECONOZCAN como intento de merge: si no
# se reconocieran, el guard respondería {"continue":true} sin llegar a
# validar la forma, y esa forma — que la gramática de abajo rechaza —
# pasaría sin bloquear en vez de bloquear explicando.
#
# SIN anclar a posición de comando (a propósito, a diferencia del resto
# de este archivo y de otros guards que sourcean guard-matching.sh):
# anclar asume que lo que antecede a "gh" es un separador real o el
# inicio del string, pero guard_sanitize colapsa un span quoted A UN
# ESPACIO, no lo borra — un prefijo como GH_REP""O=x (concatenación de
# comillas adyacentes sin espacio, sintaxis de shell real para formar UNA
# sola palabra "GH_REPO=x") queda como "GH_REP O=x" en el texto saneado:
# ya no hay separador real antes de "gh", y un ancla de posición de
# comando dejaba pasar esto sin detectar (mismo problema con
# GH_REP\O=x — backslash intacto — y GH_REP${x}O=x — expansión intacta:
# guard_sanitize no toca ninguno de los dos). Sin ancla, alcanza con que
# "gh...pr...merge" aparezca en CUALQUIER posición del texto saneado.
# Sigue siendo seguro: guard_sanitize no solo colapsa comillas a un
# espacio, TAMBIÉN BORRA el cuerpo completo de un heredoc — un mensaje de
# commit que menciona la frase entre comillas o dentro de un heredoc
# desaparece del texto saneado, con o sin ancla, así que el falso
# positivo que motivó el ancla original (2026-08-13, punto 3 del header)
# sigue cubierto. El costo aceptado: un comando genuinamente ajeno que
# por coincidencia trae las palabras sueltas "gh"/"pr"/"merge" sin
# comillas entra a validar la gramática y bloquea con el mensaje de forma
# — sobre-bloqueo, no sub-bloqueo, la dirección segura de este archivo.
GH_PR_MERGE_RE='gh\s+(\S+\s+){0,2}pr\s+(\S+\s+){0,2}merge'

if ! echo "$SANITIZED_COMMAND" | grep -qE "${GH_PR_MERGE_RE}\b"; then
  echo '{"continue":true}'
  exit 0
fi

block() {
  local reason="$1"
  echo "{\"decision\":\"block\",\"reason\":$(printf '%s' "$reason" | jq -Rs .)}"
  exit 0
}

# ============================================================
# Gramática única del merge (D-04) — ver el punto 6 del header.
#
# Reemplaza TODO lo que antes interpretaba formas de comando (ventana
# anclada consciente de balance, tokenizer de --repo con "gana el
# último", extracción de un cd inicial): en vez de reconocer qué
# prefijos/separadores/envoltorios son peligrosos, se exige que el
# comando completo — el texto CRUDO, tool_input.command tal cual, nunca
# SANITIZED_COMMAND, que colapsa comillas/heredocs/continuaciones y por
# lo tanto no preserva la forma exacta que ejecutaría el shell real — sea
# EXACTAMENTE uno de los conocidos.
# ============================================================
MERGE_FORM_HELP='Forma aceptada: gh pr merge <N> [--merge|--squash|--rebase] [--delete-branch] [--repo owner/repo], sola en el comando y en una línea. Para un PR de otro repo usa --repo; no uses cd.'

# Una sola línea: un \n o \r en cualquier posición del crudo (incluida
# una continuación con backslash, que guard_sanitize normalmente uniría
# a un espacio para no romper un merge legítimo partido en líneas — pero
# acá se valida el crudo, sin ese saneo) significa que lo que sigue puede
# ser una línea/comando aparte que la gramática de abajo nunca vería.
case "$COMMAND" in
  *$'\n'*|*$'\r'*)
    block "Blocked: el comando trae más de una línea. ${MERGE_FORM_HELP}"
    ;;
esac

# read -ra sobre el crudo: seguro acá porque ya se descartó cualquier
# \n/\r (el IFS por default — espacio, tab, salto de línea — separa por
# blancos exactamente como [[:blank:]]+, sin que quede un salto de línea
# que pueda colarse como separador de token) y porque cada token se
# valida por CONTENIDO más abajo — ninguno se ejecuta ni se interpola en
# un comando propio sin pasar antes por una allowlist de caracteres.
read -ra MERGE_TOKENS <<< "$COMMAND"
MERGE_TOKEN_COUNT=${#MERGE_TOKENS[@]}

if [ "$MERGE_TOKEN_COUNT" -lt 3 ] || [ "${MERGE_TOKENS[0]}" != "gh" ] || [ "${MERGE_TOKENS[1]}" != "pr" ] || [ "${MERGE_TOKENS[2]}" != "merge" ]; then
  block "Blocked: el comando no empieza con 'gh pr merge' (nada antes, ningún flag intercalado entre gh/pr/merge). ${MERGE_FORM_HELP}"
fi

if [ "$MERGE_TOKEN_COUNT" -lt 4 ] || ! [[ "${MERGE_TOKENS[3]}" =~ ^[1-9][0-9]*$ ]]; then
  block "Blocked: gh pr merge sin número de PR explícito y válido (dígitos solos, sin sufijo/prefijo). ${MERGE_FORM_HELP}"
fi
PR_NUMBER="${MERGE_TOKENS[3]}"

# Flags: allowlist cerrada de 8 formas de un solo token más 3 formas de
# repo (--repo <slug>, --repo=<slug>, -R <slug>; NO -R<slug> pegado ni
# -R=<slug> — gh las acepta, pero D-04 angosta a propósito la superficie
# a las tres formas más comunes en vez de replicar todo lo que gh admite).
# Cualquier token que no calce ninguna de las dos bloquea — allowlist de
# la forma, no blocklist de lo peligroso.
SLUG_RE='^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'
REPO_FLAG_COUNT=0
EXPLICIT_REPO=""
IDX=4
while [ "$IDX" -lt "$MERGE_TOKEN_COUNT" ]; do
  TOKEN="${MERGE_TOKENS[$IDX]}"
  case "$TOKEN" in
    --merge | -m | --squash | -s | --rebase | -r | --delete-branch | -d)
      ;;
    --repo=*)
      REPO_FLAG_COUNT=$((REPO_FLAG_COUNT + 1))
      VALUE="${TOKEN#--repo=}"
      [[ "$VALUE" =~ $SLUG_RE ]] && EXPLICIT_REPO="$VALUE"
      ;;
    --repo | -R)
      REPO_FLAG_COUNT=$((REPO_FLAG_COUNT + 1))
      NEXT_IDX=$((IDX + 1))
      if [ "$NEXT_IDX" -lt "$MERGE_TOKEN_COUNT" ] && [[ "${MERGE_TOKENS[$NEXT_IDX]}" =~ $SLUG_RE ]]; then
        EXPLICIT_REPO="${MERGE_TOKENS[$NEXT_IDX]}"
        IDX=$NEXT_IDX
      fi
      ;;
    *)
      block "Blocked: flag no reconocida ('${TOKEN:0:64}'). ${MERGE_FORM_HELP}"
      ;;
  esac
  IDX=$((IDX + 1))
done

# Más de un flag de repo (aunque repitan el mismo valor) bloquea: no hay
# "gana el último" en esta gramática, a diferencia de gh real — este
# guard no adivina cuál de los dos usaría gh sin ejecutarlo.
if [ "$REPO_FLAG_COUNT" -gt 1 ]; then
  block "Blocked: más de un flag de repo (--repo/-R) en el comando. ${MERGE_FORM_HELP}"
fi
if [ "$REPO_FLAG_COUNT" -eq 1 ] && [ -z "$EXPLICIT_REPO" ]; then
  block "Blocked: --repo/-R sin un valor owner/name utilizable (dos segmentos, sin comillas ni caracteres fuera de [A-Za-z0-9_.-]). ${MERGE_FORM_HELP}"
fi

# GH_REPO/GH_HOST en el entorno del PROCESO DEL HOOK (no en el texto del
# comando — eso ya lo rechaza la gramática de arriba, que no permite nada
# antes de "gh"): "gh pr merge" los respeta, "gh repo view" —de donde
# este guard resuelve el repo sin --repo explícito— no siempre coincide
# (verificado contra gh real, ver ronda 2 de este follow-up). Bloquea
# siempre, con o sin --repo explícito presente: no se asume que un
# --repo explícito en el comando le gana a GH_REPO/GH_HOST sin
# verificarlo.
if [ -n "${GH_REPO:-}" ] || [ -n "${GH_HOST:-}" ]; then
  block "Blocked: el entorno del proceso de este hook tiene GH_REPO o GH_HOST seteado — gh pr merge podría resolver un repo/host distinto al que este guard verificaría. Quita esas variables del entorno, o usa --repo explícito y sin GH_HOST."
fi

# GIT_DIR/GIT_WORK_TREE en el entorno del proceso del hook: solo importan
# cuando el guard resuelve el repo con `gh repo view` sobre el cwd de la
# SESIÓN (sin --repo explícito) — con --repo explícito, el guard nunca
# corre gh repo view, así que estas variables no pueden desviar nada.
if [ -z "$EXPLICIT_REPO" ] && { [ -n "${GIT_DIR:-}" ] || [ -n "${GIT_WORK_TREE:-}" ]; }; then
  block "Blocked: el entorno del proceso de este hook tiene GIT_DIR o GIT_WORK_TREE seteado — gh repo view podría resolver un árbol distinto al de la sesión. Usa --repo explícito."
fi

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
