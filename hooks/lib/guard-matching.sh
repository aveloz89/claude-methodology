#!/bin/bash
# Helper compartido por los guards que interceptan comandos Bash
# (pre-merge-check.sh, block-admin-merge.sh, pre-commit-guard.sh). Antes de
# matchear el comando vigilado de cada guard, se sanean
# los spans quoted ('...'/"...") y los cuerpos de heredoc: son contenido
# literal (ej. un mensaje de commit) que puede mencionar la frase vigilada
# sin ser una invocación real. El match además se ancla a posición de
# comando (inicio de string/línea, o justo después de &&, ||, ;, |, $(,
# backtick, "(", "{", &) — no al string completo — para no perder
# invocaciones reales dentro de comandos compuestos en una sola línea.
#
# Uso: sourcear este archivo y usar guard_sanitize junto con la constante
# GUARD_ANCHOR (fragmento de regex ERE) al armar el patrón del comando
# vigilado:
#
#   SANITIZED=$(guard_sanitize "$COMMAND")
#   if echo "$SANITIZED" | grep -qE "${GUARD_ANCHOR}gh\s+pr\s+merge\b"; then ...
#
# Limitación aceptada: es saneo heurístico de texto, no un parser de shell
# real — un wrapper como bash -c "..." no se detecta porque el comando real
# queda dentro de una string que este helper sanitiza. Aceptable: los guards
# protegen errores honestos del orchestrator, no evasión adversarial.
#
# Fuera de alcance de los guards (documentado, no parcheado — #77, D-05).
# Los guards de hooks/ protegen errores honestos del orchestrator y los
# devs: formas que alguien escribe de buena fe. No son un parser de shell
# ni un control de evasión. Verificado contra los hooks reales
# (2026-09-27), estas formas pasan sin bloquear y quedan así por decisión:
#   - comillas partidas o escapadas que rompen el emparejamiento del
#     saneo: echo \'; gh pr merge 5; echo \', $'it\'s' && gh pr merge 5;
#   - heredoc con delimitador comillado a medias (<<E"OF"), delimitador
#     con caracteres fuera de [A-Za-z0-9_-], o una línea del cuerpo que
#     termina en \ justo antes del terminador;
#   - la flag o el subcomando en una variable (F=--force; git push $F),
#     eval, bash -c '...'/sh -c, alias y funciones de git/gh definidas en
#     el mismo comando o en uno anterior (w() { gh "$@"; }; w pr merge 5
#     pasa);
#   - la palabra del binario alterada o disfrazada: "gh", g\h, env git …,
#     /usr/bin/git …, command git … (el "if" de hooks.json tampoco
#     dispara para las tres últimas: compara cada subcomando por prefijo
#     y solo descarta asignaciones VAR=x al frente; ver la tabla "Bash if
#     matching" de la doc de hooks).
# Si una de estas formas bloquea o se cuela, no es un bug a arreglar acá:
# la salida es escribir el comando en su forma directa.

# Fragmento de regex ERE que ancla el match a posición de comando: inicio
# de string/línea, o justo después de un separador de comandos (&&, ||, ;,
# |, $(, backtick, "(", "{", &).
# shellcheck disable=SC2034 # se usa en los guards que sourcean este archivo
GUARD_ANCHOR='(^|&&|\|\||;|\||\$\(|`|\(|\{|&)\s*'

# Fragmento de regex ERE que consume, cero o más veces, una opción de árbol
# de git ("-C <ruta>"/"-C=<ruta>", "--git-dir"/"--work-tree" con o sin "=")
# seguida de su valor y un separador — usado entre "git" y el subcomando
# vigilado (commit) para detectar "git -C <ruta> <subcomando>" como la
# misma invocación. Antes vivía inline en GIT_COMMIT_RE
# (pre-commit-guard.sh); un guard nuevo que necesite el mismo fragmento no
# tiene que copiarlo a mano.
#
# Los guards de push/reset (block-force-push, block-hard-reset,
# pre-push-guard) usan GUARD_GIT_OPTS en vez de este fragmento — ver abajo.
# shellcheck disable=SC2034 # se usa en pre-commit-guard.sh
GUARD_GIT_TREE_OPTS='((-C|--git-dir|--work-tree)(=\S*|\s+\S*)?\s+)*'

# Fragmento de regex ERE que consume, cero o más veces y EN CUALQUIER ORDEN,
# las opciones de git que pueden aparecer entre "git" y el subcomando
# vigilado (push, reset --hard): opciones de árbol ("-C <ruta>",
# "--git-dir"/"--work-tree" con o sin "="), "-c <clave=valor>", "--no-pager"
# y "-P". Una sola alternancia repetida en vez de dos fragmentos
# concatenados (GUARD_GIT_TREE_OPTS + una versión anterior de esto, "global
# opts"): la concatenación solo reconocía UN orden fijo entre ambos grupos
# — "git -C /x -c a=b push --force" (árbol después de "-c") no matcheaba
# ninguno de los dos fragmentos, y el force push real pasaba SIN EVALUAR.
# git acepta estas opciones en cualquier orden antes del subcomando; el
# regex ahora también.
# shellcheck disable=SC2034 # se usa en block-force-push.sh, block-hard-reset.sh y pre-push-guard.sh
GUARD_GIT_OPTS='(((-C|--git-dir|--work-tree)(=\S*|\s+\S*)?|-c\s+\S+|--no-pager|-P)\s+)*'

# Fragmento de regex ERE que reconoce "gh ... pr ... merge" tolerando hasta
# 2 tokens entre "gh"/"pr" y entre "pr"/"merge" (formas como "gh -R x pr
# merge N", que gh acepta de verdad). Antes vivía inline en
# pre-merge-check.sh como GH_PR_MERGE_RE; solo decide si el comando
# MENCIONA una invocación de merge, nunca extrae nada de él (ver el punto
# 6 del header de pre-merge-check.sh).
# shellcheck disable=SC2034 # se usa en los guards que sourcean este archivo
GUARD_GH_PR_MERGE_RE='gh\s+(\S+\s+){0,2}pr\s+(\S+\s+){0,2}merge'

# guard_sanitize: recibe el comando crudo como $1 y devuelve por stdout el
# texto saneado (sin spans quoted ni cuerpos de heredoc). Exit status: 0
# si saneó de verdad, 1 si degradó al fallback (perl ausente o perl falló
# en tiempo de ejecución) — los guards que solo BLOQUEAN sobre el
# resultado (block-admin-merge.sh, pre-commit-guard.sh) pueden ignorar el
# status, porque para ellos texto sin sanear es la dirección segura (más
# falsos positivos, nunca menos). pre-merge-check.sh sí lo chequea: ese
# guard EXTRAE datos del texto (el número de PR) en vez de solo bloquear,
# y sobre texto sin sanear esa extracción puede agarrar un señuelo quoted
# — ahí "más bloqueo" no es la dirección segura, es "verificar el PR
# equivocado". Ver hooks/pre-merge-check.sh.
#
# Si perl no está disponible, se devuelve el comando sin sanear (fallback
# al comportamiento que block-admin-merge.sh y pre-commit-guard.sh tenían
# antes de este helper, que nunca dependió de perl). Es la dirección
# segura para un guard que solo bloquea: sin perl hay más falsos positivos
# posibles (texto quoted que menciona la frase vigilada), pero nunca un
# falso negativo silencioso por dependencia ausente. Se anuncia por stderr
# para que el modo degradado sea visible en vez de un fallback silencioso.
guard_sanitize() {
  if command -v perl > /dev/null 2>&1; then
    # Orden importa: primero unir continuaciones de línea (backslash-
    # newline) — un comando real partido en dos líneas (ej. "gh pr merge 5
    # \" + "  --admin") no debe evadir el match por quedar partido antes de
    # que corra cualquier otra regla. Los spans single-quoted y double-quoted
    # se sanean en UNA sola pasada con alternancia (no dos reglas
    # secuenciales): el span que abre primero consume el texto hasta su
    # propio cierre, sin importar qué tipo de comilla sea — así es como el
    # shell realmente parsea. Una secuencia de dos reglas separadas rompe
    # esto en ambas direcciones: sanear "..." antes que '...' hace que dos
    # apóstrofes en spans double-quoted DISTINTOS (ej. "it's fine" ...
    # "that's all") se emparejen entre sí; sanear '...' antes que "..." hace
    # lo mismo con comillas dobles sueltas dentro de spans single-quoted
    # DISTINTOS (ej. 'quote the " char' ... 'end " here'). Ambos casos se
    # tragan el comando real de en medio como si fuera contenido quoted.
    # La regla de heredocs consume el cuerpo línea por línea con
    # "(?:(?!^[ \t]*\1[ \t]*$)[^\n]*\n)*?" — dos propiedades DISTINTAS,
    # cada una resolviendo un problema distinto de la versión anterior
    # (".*\n?", con /s, "." matchea salto de línea):
    #
    #   1. [^\n] en vez de "." elimina la AMBIGÜEDAD DE PARTICIÓN: cada
    #      iteración avanza exactamente un salto de línea, sin poder
    #      solaparse con el "\n" que la cierra, así que el motor nunca
    #      tiene más de una forma de repartir el texto entre iteraciones.
    #      Es lo que garantiza TERMINACIÓN en tiempo lineal — sin esto,
    #      ".*\n?" dejaba que cada iteración consumiera un número variable
    #      de líneas, y sin terminador real el motor probaba todas las
    #      formas de partir el texto: backtracking catastrófico (con 8
    #      líneas de relleno sin cerrar, >3s; crece sin cota visible).
    #   2. El cuantificador no-greedy ("*?" en vez de "*") elige CUÁL
    #      terminador cierra el heredoc cuando hay más de uno disponible
    #      con el mismo nombre de delimitador: el PRIMERO, igual que bash
    #      de verdad. La versión greedy elegía el ÚLTIMO — dos heredocs
    #      bien formados con el mismo delimitador (ambos "<<EOF") y un
    #      comando real en el medio hacían que el greedy se tragara TODO
    #      lo de en medio (incluido el comando real y el terminador
    #      legítimo del primer heredoc) en un solo span reemplazado por un
    #      salto de línea — un fail-open real y explotable sin necesidad
    #      de colgar nada (ver test [security] en test-hooks.sh). Esto es
    #      independiente de la propiedad 1: un futuro refactor podría
    #      volver a poner "*" greedy creyendo que solo afecta performance,
    #      sin tocar [^\n], y reintroduciría la evasión sin reintroducir
    #      el ReDoS.
    local sanitized status
    sanitized=$(printf '%s' "$1" | perl -0777 -pe '
      BEGIN { alarm 5 }
      s/\\\n\s*/ /g;
      s/<<-?[ \t]*[\x27"]?([A-Za-z0-9_-]+)[\x27"]?[^\n]*\n(?:(?!^[ \t]*\1[ \t]*$)[^\n]*\n)*?[ \t]*\1(?:\n|$)/\n/gsm;
      s/\x27[^\x27]*\x27|"(?:[^"\\]|\\.)*"/ /g;
    ')
    status=$?
    # Red de seguridad para cualquier patológico futuro no anticipado por
    # el fix de arriba: si perl no vuelve a tiempo, alarm(5) lo mata (sin
    # $SIG{ALRM} instalado, la señal termina el proceso — perl sale con
    # 128+14). 5s da margen contra degradaciones espurias por máquina
    # cargada sin debilitar la protección: medido, un caso lineal de
    # 348 KB tarda 0s. Si perl falla por cualquier motivo (timeout o
    # error), NO se puede devolver su stdout (vacío o parcial): eso
    # equivaldría a sanear todo el comando a la nada, y el grep de cada
    # guard nunca matchearía nada — fail-open silencioso. Se cae al mismo
    # fallback que "perl no disponible": comando sin sanear (más falsos
    # positivos, la dirección segura), avisado por stderr.
    if [ "$status" -ne 0 ]; then
      echo "guard-matching: saneo abortado (perl salió con estado $status, posible timeout), matching sin saneo (posibles falsos positivos)" >&2
      printf '%s' "$1"
      return 1
    else
      printf '%s' "$sanitized"
      return 0
    fi
  else
    echo "guard-matching: perl no disponible, matching sin saneo (posibles falsos positivos)" >&2
    printf '%s' "$1"
    return 1
  fi
}

# guard_command_has_nul: recibe por $1 el JSON crudo leído de stdin (el
# mismo $INPUT que cada guard ya guardó antes de extraer .tool_input.command
# con jq) y devuelve 0 si ese campo contiene un byte NUL, 1 en caso
# contrario. El NUL nunca llega como byte real a este punto — jq lo expone
# como el escape "\u0000" dentro del string JSON, porque INPUT=$(cat) ya lo
# descartó de la variable bash (los strings de bash no pueden contener un
# NUL) sin descartar el resto del comando a los dos lados. Esa es la razón
# por la que hace falta detectarlo ACÁ, sobre $INPUT, y no más abajo sobre
# $COMMAND: para cuando $COMMAND existe como variable, el guard ya perdió
# la señal de que el comando original traía un NUL, y el texto que queda
# (con el NUL simplemente borrado, no el comando cortado ahí) decide el
# veredicto sin que quien lo escribió sepa que una parte de su comando es
# invisible para el guard.
guard_command_has_nul() {
  echo "$1" | jq -e '.tool_input.command // "" | contains("\u0000")' > /dev/null 2>&1
}

# guard_block <motivo>: escribe "BLOCKED: <GUARD_NAME>: <motivo>" en stderr y
# sale con 2. Requiere GUARD_NAME seteado por guard_init.
guard_block() {
  echo "BLOCKED: ${GUARD_NAME}: $1" >&2
  exit 2
}

# guard_init <nombre-del-guard>: preámbulo común de los guards PreToolUse.
# Se llama DESPUÉS de sourcear esta lib (el caller ya verificó que la lib
# existe; sin lib no hay guard_init que llamar — ese check queda en el
# guard). Deja definidas GUARD_NAME, INPUT, COMMAND, INPUT_CWD,
# SANITIZED_COMMAND, GUARD_SANITIZE_STATUS. Nunca imprime en stdout.
guard_init() {
  GUARD_NAME="$1"
  command -v jq > /dev/null 2>&1 || { echo "BLOCKED: ${GUARD_NAME} no operativo: falta jq" >&2; exit 2; }
  INPUT=$(cat)
  COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
  INPUT_CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
  guard_command_has_nul "$INPUT" && guard_block "el comando trae un byte NUL"
  SANITIZED_COMMAND=$(guard_sanitize "$COMMAND")
  GUARD_SANITIZE_STATUS=$?
}

# guard_session_dir: imprime el directorio de la sesión resuelto con
# pwd -P (INPUT_CWD si vino en el JSON, el cwd del proceso si no). Devuelve
# 1 sin imprimir nada si INPUT_CWD vino y no es un directorio — el caller
# decide bloquear (guards de árbol) o seguir.
guard_session_dir() {
  if [ -n "$INPUT_CWD" ]; then
    [ -d "$INPUT_CWD" ] || return 1
    (cd "$INPUT_CWD" && pwd -P)
  else
    pwd -P
  fi
}
