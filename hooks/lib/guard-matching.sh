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
#   - la palabra del binario alterada o disfrazada: "gh", env git …,
#     /usr/bin/git …, command git … (el "if" de hooks.json tampoco
#     dispara para las tres últimas: compara cada subcomando por prefijo
#     y solo descarta asignaciones VAR=x al frente; ver la tabla "Bash if
#     matching" de la doc de hooks);
#   - block-force-push.sh: la flag entre comillas (`git push origin
#     "--force"`, `git push '-f'`) y una redirección honesta (2>&1, >&2,
#     &>log) o un ";" escapado antes de la flag de force;
#   - pre-push-guard.sh: el refspec entre comillas (`git push origin
#     "HEAD:main"`: el saneo vacía el span antes del match del destino) y
#     una redirección con "&" antes del refspec (`git push origin 2>&1
#     HEAD:main`: el segmento se corta en "&"). Una redirección pegada al
#     refspec (`HEAD:main>log`, `HEAD:main</dev/null`) SÍ bloquea: "<" y ">"
#     sin comillas cierran el token (GUARD_TOKEN_END).
#   - pre-push-guard.sh: un refspec glob entre comillas (`git push origin
#     '*:*'`, `'refs/heads/*'`; el saneo deja el placeholder Q y el glob no se ve). El glob sin comillas SÍ bloquea cuando
#     su destino cuelga de refs/heads/, no lleva prefijo refs/ o su prefijo
#     literal es prefijo de refs/heads/ (`refs/*`, `refs/h*`; #119, ver
#     GUARD_PUSH_GLOB_RE); `refs/tags/*:refs/tags/*` pasa.
#   - pre-push-guard.sh y block-force-push.sh: push.default=matching o
#     remote.<x>.mirror/push fijados en el config del repo o global (solo se
#     ven los "-c" y "--config-env" literales y sin comillas del comando),
#     remote.pushDefault y un "-c" escrito en una variable;
#   - pre-push-guard.sh y block-force-push.sh: la config peligrosa dentro de un
#     "-c" con el valor entre comillas (`git -c 'push.default=matching' push
#     origin`): el saneo deja el placeholder "Q" y el contenido no se ve.
#     `git -c 'user.name=x' push origin main` SÍ bloquea desde #120 (antes el
#     saneo vaciaba el span y "-c\s+\S+" se tragaba "push");
#   - pre-push-guard.sh y block-force-push.sh: una sustitución que PRODUCE el
#     ref o la flag (git push origin $(git branch --show-current)) no se
#     evalúa; el guard solo ve tokens literales del comando;
#   - que el "if": "Bash(git *)" de hooks.json dispare el hook para
#     comandos que no empiezan por git (backtick, echo, "(") NO está
#     verificado de punta a punta: lo probado es el script con el comando
#     por stdin.
# Si una de estas formas bloquea o se cuela, no es un bug a arreglar acá:
# la salida es escribir el comando en su forma directa.

# Fragmento de regex ERE que ancla el match a posición de comando: inicio
# de string/línea, o justo después de un separador de comandos (&&, ||, ;,
# |, $(, backtick, "(", "{", &, ")" de un patrón de case).
# Tras el separador acepta, cero o más veces, las palabras clave de shell que
# abren otra posición de comando (then, do, else, elif, if, while, until y "!"),
# cada una como palabra completa seguida de espacio (#118): "if true; then git
# push origin HEAD:main; fi", "for b in x; do …", "! git push …". Van pegadas
# al separador, no sueltas: "echo then git push origin main" NO es un push
# ("then" ahí es un argumento de echo) y sigue sin anclar.
# shellcheck disable=SC2034 # se usa en los guards que sourcean este archivo
GUARD_ANCHOR='(^|&&|\|\||;|\||\$\(|`|\(|\{|&|\))\s*((then|do|else|elif|if|while|until|!)\s+)*'

# Fragmento de regex ERE que consume, cero o más veces y EN CUALQUIER ORDEN,
# las opciones de git que pueden aparecer entre "git" y el subcomando
# vigilado (push, reset --hard, commit): opciones de árbol ("-C <ruta>",
# "--git-dir"/"--work-tree" con o sin "="), "-c <clave=valor>",
# "--config-env=<clave>=<VAR>" (con o sin "="), "--no-pager" y "-P". Una sola alternancia repetida en vez de fragmentos concatenados en
# un orden fijo: "git -C /x -c a=b push --force" (árbol después de "-c") no
# matchearía un fragmento que solo tolerase un orden. git acepta estas
# opciones en cualquier orden antes del subcomando; el regex también.
# shellcheck disable=SC2034 # se usa en block-force-push.sh, block-hard-reset.sh, pre-push-guard.sh y pre-commit-guard.sh
GUARD_GIT_OPTS='(((-C|--git-dir|--work-tree|--config-env)(=\S*|\s+\S*)?|-c\s+\S+|--no-pager|-P)\s+)*'

# Prefijo de entorno antes de "git" ("VAR=valor git push ..."): cero o más
# asignaciones. Sin él, "X=matching git --config-env=push.default=X push
# origin" ni siquiera se reconocía como un push (el hook salía 0 sin evaluarlo).
# shellcheck disable=SC2034 # se usa en pre-push-guard.sh, block-force-push.sh y block-hard-reset.sh
GUARD_ENV_PREFIX='([A-Za-z_][A-Za-z0-9_]*=\S*\s+)*'

# Inventario de delimitadores (lo verificado, no un absoluto). Tres listas
# distintas, cada una con su propio papel:
#   - el ANCLA (GUARD_ANCHOR) ABRE un comando tras: inicio de string/línea,
#     "&&", "||", ";", "|", "$(", backtick, "(", "{" y "&";
#   - el SEGMENTO "git push ..." (GUARD_SEGMENT_END) CIERRA solo en "&", "|"
#     y ";". NO cierra en ")" ni en backtick: una sustitución DENTRO del push
#     ("git push origin $(true) HEAD:main", "git push origin `true` main")
#     esconde lo que sigue si el segmento se corta ahí (regresión de la
#     ronda 2 de #117, verificada contra dev). Coste asumido del trade-off:
#     un push dentro de "$(...)" absorbe lo que sigue al cierre en el mismo
#     comando simple ("echo $(git push origin feature/x) -f" bloquea, exit 2);
#   - el TOKEN (GUARD_TOKEN_END) se cierra en espacio, ")", backtick, "<", ">"
#     o fin de string ("<" y ">" sin comillas son siempre redirección). Así
#     "(git push origin HEAD:main)" y "`git push origin HEAD:main`" cierran
#     el borde del token "main" sin cortar el segmento.
# Van entre comillas simples: el backtick es literal en la asignación y al
# expandirlas dentro de comillas dobles no se vuelve a evaluar.
# shellcheck disable=SC2016,SC2034 # backtick literal; se usan en pre-push-guard.sh y block-force-push.sh
GUARD_SEGMENT_END='[^&|;]*'
# shellcheck disable=SC2016,SC2034
GUARD_TOKEN_END='([[:space:]]|[)`<>]|$)'

# Fragmento de regex ERE que reconoce las opciones de "git push" que empujan
# todas las ramas locales (incluida main) sin nombrarla: --all, --mirror y
# --branches (alias de --all), más CUALQUIER prefijo único de ellas, porque
# git acepta prefijos de opciones largas. Verificado contra un remoto bare
# (git 2.54): se aceptan --al, --all, --b..--branches y --m..--mirror; "--a"
# es ambiguo (all/atomic, exit 129) y "--all="/"--mirror=" se rechazan
# (129, "takes no value"), por eso el regex exige token completo (espacio,
# ")", backtick o fin) después.
# shellcheck disable=SC2034 # se usa en pre-push-guard.sh y block-force-push.sh
GUARD_PUSH_ALL_RE="(^|[[:space:]])--(al|all|b|br|bra|bran|branc|branch|branche|branches|m|mi|mir|mirr|mirro|mirror)${GUARD_TOKEN_END}"

# Fragmento de regex ERE que reconoce la configuración por línea de comando
# que vuelve un "git push" sin refspec equivalente a "--all"/"--mirror"
# (empuja main sin nombrarla). Cubre, con "-c <clave>=<valor>":
#   - push.default=matching, y también =upstream y =tracking (alias): empujan
#     al upstream de la rama actual, que puede ser main;
#   - remote.<x>.mirror verdadero: la clave SIN "=" (git la toma como true),
#     o =true/yes/on o un entero distinto de 0 (=2, =01); "=false/no/off/0" y
#     el valor vacío NO cuentan;
#   - remote.<x>.push=<algo>;
# y con "--config-env=<clave>=<VAR>" (o "--config-env <clave>=<VAR>") las mismas
# claves, sin mirar el valor: viene de una variable, así que se bloquea
# conservadoramente. Verificado en un sandbox (git 2.54, desde feature/x): con
# cada una, "git push origin" actualiza main del remoto. git no distingue
# mayúsculas en la clave (sección ni nombre): quien aplique este regex debe
# usar "grep -iE" (pre-push-guard.sh y block-force-push.sh lo hacen); con -i
# "push.default=MATCHING" también bloquea aunque git lo rechace (128):
# dirección segura. Se aplica al segmento "git ... push ..." ya extraído.
# Cubre solo la config literal del comando, no el config del repo ni el global
# (ver "Fuera de alcance" del README).
# shellcheck disable=SC2034 # se usa en pre-push-guard.sh y block-force-push.sh
GUARD_PUSH_CONFIG_RE="(^|[[:space:]])(-c[[:space:]]+(push\.default=(matching|upstream|tracking)|remote\.[^=[:space:]]+\.(mirror(=(true|yes|on|-?[0-9]*[1-9][0-9]*))?|push=[^[:space:]]*))${GUARD_TOKEN_END}|--config-env(=|[[:space:]]+)(push\.default|remote\.[^=[:space:]]+\.(mirror|push))=)"

# Refspec "git push origin :" (token exactamente ":", con "+" opcional):
# verificado en git 2.54, el ":" suelto empuja las ramas que coinciden en el
# remoto, incluida main, SIN configurar nada (no hace falta push.default=
# matching). ":rama" (borrar una rama remota) NO matchea: el ":" va seguido
# de un nombre.
# La usan pre-push-guard.sh y la excepción de --force-with-lease de
# block-force-push.sh (que nunca cubre pushes de todo).
# shellcheck disable=SC2034 # se usa en pre-push-guard.sh y block-force-push.sh
GUARD_PUSH_EMPTY_REFSPEC_RE="(^|[[:space:]])\+?:${GUARD_TOKEN_END}"

# Refspec glob (#119): un token cuyo DESTINO contiene "*" expande a todas las
# ramas que casan, main incluida, sin nombrarla. Verificado contra un remoto
# bare (git 2.54): 'refs/heads/*:refs/heads/*', '*:*' y el glob de un solo
# lado 'refs/heads/*' (el destino es el propio token) empujan main. El regex
# extrae el token con "*" en el destino (con "+" y origen opcionales);
# guard_push_has_glob_dst decide si ese destino cuenta: BLOQUEA el que cuelga
# de "refs/heads/" o no lleva prefijo "refs/" (git lo completa a refs/heads/);
# deja pasar el que cuelga de otro "refs/..." (refs/tags/*:refs/tags/*,
# refs/remotes/x/*). El "*" de un refspec cubre también "/", así que "refs/*",
# "refs/h*" y "refs/heads*" (cuyo prefijo literal es prefijo de "refs/heads/")
# también mueven main y bloquean (ronda 1 de review).
# Falso positivo asumido (dirección segura): refs/heads/feature/*:refs/heads/
# feature/* tampoco toca main, pero no se distingue de refs/heads/*. Fuera de
# alcance: el refspec entre comillas ('*:*', 'refs/heads/*'): el saneo lo
# reemplaza por el placeholder Q, que ya no se distingue de cualquier otro
# valor entre comillas; tratar un Q en posición de refspec como sospechoso
# daría falsos positivos (-m "msg", valores de -c) y se deja fuera de alcance.
# shellcheck disable=SC2034 # se usa en pre-push-guard.sh y block-force-push.sh
GUARD_PUSH_GLOB_RE="(^|[[:space:]])\+?([^[:space:]:]*:)?[^[:space:]:]*\*[^[:space:]:]*${GUARD_TOKEN_END}"

# guard_push_has_glob_dst <segmentos>: 0 si algún token del texto es un refspec
# glob peligroso (ver GUARD_PUSH_GLOB_RE), 1 si no. Los tokens que empiezan por
# "-" son opciones, no refspecs.
guard_push_has_glob_dst() {
  local tok dst prefix
  while IFS= read -r tok; do
    tok="${tok#"${tok%%[![:space:]]*}"}"
    case "$tok" in -*) continue ;; esac
    dst="${tok##*:}"
    dst="${dst#+}"
    prefix="${dst%%\**}"
    # Prefijo literal del destino antes del primer "*" (el "*" cubre también
    # "/"): bloquea si es prefijo de "refs/heads/" (incluye "", "refs/",
    # "refs/h", "refs/heads"), si cuelga de "refs/heads/" o si no lleva "refs/".
    [[ "refs/heads/" == "$prefix"* ]] && return 0
    case "$prefix" in
      refs/heads/*) return 0 ;;
      refs/*) ;;
      *) return 0 ;;
    esac
  done < <(printf '%s\n' "$1" | grep -oE "$GUARD_PUSH_GLOB_RE")
  return 1
}

# Fragmento de regex ERE que reconoce "gh ... pr ... merge" tolerando hasta
# 2 tokens entre "gh"/"pr" y entre "pr"/"merge" (formas como "gh -R x pr
# merge N", que gh acepta de verdad). Antes vivía inline en
# pre-merge-check.sh como GH_PR_MERGE_RE; solo decide si el comando
# MENCIONA una invocación de merge, nunca extrae nada de él (ver el punto
# 6 del header de pre-merge-check.sh).
# shellcheck disable=SC2034 # se usa en los guards que sourcean este archivo
GUARD_GH_PR_MERGE_RE='gh\s+(\S+\s+){0,2}pr\s+(\S+\s+){0,2}merge'

# guard_sanitize: recibe el comando crudo como $1 y devuelve por stdout el
# texto saneado (spans quoted reemplazados por $2, un espacio si se omite, y
# sin cuerpos de heredoc). Exit status: 0
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
    # Cada span quoted se reemplaza por $2 (por defecto un espacio). Los
    # guards de git pasan "Q" vía guard_init (#120): un placeholder PEGADO, sin
    # espacios alrededor, que sigue siendo UN token. Con el span vacío, "git -c
    # 'user.name=x' push origin main" quedaba como "git -c push origin main" y
    # "-c\s+\S+" (GUARD_GIT_OPTS) se tragaba "push" como valor de -c: el guard
    # salía 0 sin ver el push. Con "Q", "-c" consume el placeholder y "push"
    # queda como subcomando. El contenido quoted sigue invisible (un "main" o
    # "--force" entre comillas no se ve; ver "Fuera de alcance"): "Q" no es
    # ningún token vigilado. Los guards de gh (block-admin-merge,
    # pre-merge-check) conservan el espacio: GUARD_GH_PR_MERGE_RE tolera solo 2
    # tokens entre "gh"/"pr"/"merge", y con "Q" cada valor quoted cuenta como
    # token ('gh -R "a/b" -R "c/d" pr merge 5 --admin' dejaba de bloquear;
    # verificado ejecutando block-admin-merge con el placeholder).
    # El reemplazo depende de la PALABRA entera, porque el shell une las
    # comillas pegadas con el texto vecino (--force'' es --force, ""git es git,
    # g''it es git): una racha de spans quoted contiguos que es la palabra
    # completa (delimitada por espacio, ; & | ( ) { } < > backtick, el inicio o
    # el fin) va como el placeholder; si va pegada a texto sin comillas, se
    # borra sin poner nada, como el shell (#120, ronda 1 de review: con "Q"
    # pegado, "git push origin feature/x --force''" quedaba "--forceQ" y pasaba).
    # Solo se borra si los spans están VACÍOS ('' o ""): con contenido, pegado
    # a texto, el placeholder queda y marca que la palabra cambió (+"feature/x"
    # sigue siendo "+Q", un refspec forzado; "--force"x"" no es --force).
    # Con el placeholder " " (guards de gh) el reemplazo no cambia: ya separa.
    # Después de las comillas, la barra invertida SIN comillas se quita como
    # hace el shell: \X pasa a X cuando X es alfanumérico o uno de ._/:+-
    # (HEAD:ma\in es HEAD:main, --forc\e es --force, g\it es git). No toca
    # \; \& \| ni \' (documentados en "Fuera de alcance"). Los guards de gh
    # lo reciben igual: g\h pr merge --admin ahora bloquea, como en el shell.
    local sanitized status placeholder="${2:- }"
    sanitized=$(printf '%s' "$1" | GUARD_SANITIZE_PH="$placeholder" perl -0777 -pe '
      BEGIN { alarm 5 }
      s/\\\n\s*/ /g;
      s/<<-?[ \t]*[\x27"]?([A-Za-z0-9_-]+)[\x27"]?[^\n]*\n(?:(?!^[ \t]*\1[ \t]*$)[^\n]*\n)*?[ \t]*\1(?:\n|$)/\n/gsm;
      s{((?:\x27[^\x27]*\x27|"(?:[^"\\]|\\.)*")+)}{
        my ($run, $ph, $d) = ($1, $ENV{GUARD_SANITIZE_PH}, q{[\s;&|(){}<>\x60]});
        my $pre = $-[0] > 0 ? substr($_, $-[0] - 1, 1) : q{};
        my $post = $+[0] < length($_) ? substr($_, $+[0], 1) : q{};
        my $attached = ($pre ne q{} && $pre !~ m{$d}) || ($post ne q{} && $post !~ m{$d});
        ($ph eq q{ } || !$attached || $run !~ m{\A(?:\x27\x27|"")+\z}) ? $ph : q{};
      }ge;
      s{\\([A-Za-z0-9._/:+-])}{$1}g;
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

# guard_init <nombre-del-guard> [placeholder]: preámbulo común de los guards PreToolUse.
# Se llama DESPUÉS de sourcear esta lib (el caller ya verificó que la lib
# existe; sin lib no hay guard_init que llamar — ese check queda en el
# guard). Fail-closed sin jq ni grep (las dependencias de binarios del
# preámbulo y de los fragmentos que cada guard consume con "grep -qE": un grep
# ausente haría que "! … | grep -qE" invirtiera el 127 y el guard saliera 0
# sin evaluar nada). Deja definidas GUARD_NAME, INPUT, COMMAND, INPUT_CWD,
# SANITIZED_COMMAND, GUARD_SANITIZE_STATUS. Nunca imprime en stdout.
guard_init() {
  GUARD_NAME="$1"
  command -v jq > /dev/null 2>&1 || { echo "BLOCKED: ${GUARD_NAME} no operativo: falta jq" >&2; exit 2; }
  command -v grep > /dev/null 2>&1 || { echo "BLOCKED: ${GUARD_NAME} no operativo: falta grep" >&2; exit 2; }
  INPUT=$(cat)
  COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
  INPUT_CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
  guard_command_has_nul "$INPUT" && guard_block "el comando trae un byte NUL"
  SANITIZED_COMMAND=$(guard_sanitize "$COMMAND" "${2-Q}")
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
