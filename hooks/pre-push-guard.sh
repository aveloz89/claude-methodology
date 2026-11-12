#!/bin/bash
# Pre-push guard: Previene push directo a main — desde la rama main/master
# local, o con un refspec cuyo destino sea main/master desde cualquier rama
# (#112). Debe hacerse por PR.
#
# hooks.json registra este guard SIN "if" (decisión del usuario, ronda 1 de
# review): corre en cada Bash. Con "Bash(git *)" el harness no lo invocaba para
# comandos que empiezan por un wrapper ("time git push origin HEAD:main" movía
# main, verificado en un sandbox con claude -p), un if/then ni un backtick. La
# validación de abajo mira el comando completo; sin "git" en el comando sale 0.
#
# Matching endurecido (D-07, #77): el match se sanea (spans quoted/heredoc)
# y se ancla a posición de comando en vez de "^\s*git\s+push" sobre el
# comando crudo — mismo helper que los demás guards de git. Ver
# hooks/lib/guard-matching.sh. Antes, "git commit -m x && git push origin
# main" o "npm test && git push" pasaban sin bloquear porque el match
# exigía "git push" al INICIO del string.
LIB="${0%/*}/lib/guard-matching.sh"
[ -r "$LIB" ] || { echo "BLOCKED: pre-push-guard no operativo: falta hooks/lib/guard-matching.sh" >&2; exit 2; }
# shellcheck source=lib/guard-matching.sh
source "$LIB"
guard_init "pre-push-guard"

# Solo interceptar git push (una mención quoted no cuenta, E2). Tolera
# opciones de árbol ("git -C <ruta> push") y prefijo de entorno
# ("GIT_DIR=... git push") entre el ancla y "push": esas formas SÍ son un
# push real y tienen que llegar al chequeo de redirección de abajo, no
# salir en 0 sin evaluarlas.
# GUARD_GIT_OPTS (D-07, review dual ronda 1 y 2) tolera, en cualquier
# orden, "-c <k=v>"/"--no-pager"/"-P" y opciones de árbol antes de "push"
# — sin esto, "git -c user.name=x push origin main" no matcheaba y un
# push real a main pasaba SIN EVALUAR (exit 0) en vez de bloquear por ser
# push directo a main; un orden distinto al fijo de antes ("git -C . -c
# a=b push") tampoco. Ver hooks/lib/guard-matching.sh.
PUSH_RE="${GUARD_ANCHOR}${GUARD_ENV_PREFIX}git\s+${GUARD_GIT_OPTS}push\b"
if ! echo "$SANITIZED_COMMAND" | grep -qE "$PUSH_RE"; then
  exit 0
fi

# Lib de suite (guard_suite_run): se verifica después de decidir que es un push
# para que una instalación rota bloquee los push y no cada Bash.
SUITE_LIB="${0%/*}/lib/suite-runner.sh"
[ -r "$SUITE_LIB" ] || { echo "BLOCKED: pre-push-guard no operativo: falta hooks/lib/suite-runner.sh" >&2; exit 2; }
# shellcheck source=lib/suite-runner.sh
source "$SUITE_LIB"

# Árbol del push (R1). Formas aceptadas, las mismas que tenía el commit:
#   1. "git push …" sin redirección: el árbol es el de la sesión (".cwd" del
#      input vía guard_session_dir, o el cwd del proceso si el harness no lo
#      manda).
#   2. "cd /ruta/absoluta && git push …": cd al inicio del comando crudo, una
#      sola mención de cd/pushd, ruta absoluta literal seguida de "&&".
# Todo lo demás bloquea (no se adivina a qué árbol apunta el push). Los
# chequeos de main de abajo leen la rama de BASE_DIR, no la del cwd de la
# sesión. Con cd, block-force-push.sh deja sin efecto la excepción de
# --force-with-lease.
TREE_FORM_HELP="Formas aceptadas: 'git push …' en el cwd de la sesión, o 'cd /ruta/absoluta && git push …' (cd al inicio, una sola vez, ruta absoluta literal). Alternativa: haz el cd en una llamada Bash previa."

_ppg_block_tree() {
  echo "BLOCKED: pre-push-guard no puede resolver en qué árbol va el push: $1. ${TREE_FORM_HELP}" >&2
  exit 2
}

# "-C"/"--git-dir"/"--work-tree"/"GIT_DIR="/"GIT_WORK_TREE=" nunca se
# resuelven: no hay forma de saber si valen para TODO el comando sin parsear
# de verdad el shell. Mismo criterio para el entorno DEL PROCESO del hook.
if [ -n "${GIT_DIR:-}" ] || [ -n "${GIT_WORK_TREE:-}" ]; then
  _ppg_block_tree "GIT_DIR/GIT_WORK_TREE en el entorno del hook"
fi
if echo "$SANITIZED_COMMAND" | grep -qE -- '--git-dir|--work-tree'; then
  _ppg_block_tree "--git-dir/--work-tree no se resuelven"
fi
if echo "$SANITIZED_COMMAND" | grep -qE '(^|[[:space:]]|;|&&|\|)(GIT_DIR|GIT_WORK_TREE)='; then
  _ppg_block_tree "GIT_DIR/GIT_WORK_TREE como prefijo de entorno en el comando no se resuelven"
fi
# Regex amplio (no solo "git -C"): cubre también "env -C" y "make -C".
if echo "$SANITIZED_COMMAND" | grep -qE '(^|[[:space:]])-C([[:space:]=]|$)'; then
  _ppg_block_tree "'-C' no se resuelve"
fi

CD_PUSHD_RE="${GUARD_ANCHOR}(cd|pushd)(\s|;|&&|\$)"
if echo "$SANITIZED_COMMAND" | grep -qE "$CD_PUSHD_RE"; then
  # Se valida sobre el comando CRUDO ($COMMAND, no el saneado, que colapsa
  # comillas): exactamente UNA mención de "cd"/"pushd" y "cd" al INICIO con
  # una ruta absoluta literal seguida directo de "&&".
  CD_COUNT=$(echo "$SANITIZED_COMMAND" | grep -oE "$CD_PUSHD_RE" | grep -c .)
  [ "$CD_COUNT" -eq 1 ] || _ppg_block_tree "más de una mención de 'cd'/'pushd', o 'pushd' en vez de 'cd'"
  [[ "$COMMAND" =~ ^cd[[:blank:]]+(/[A-Za-z0-9_./-]*)[[:blank:]]*\&\& ]] || _ppg_block_tree "'cd' no está al inicio del comando, o la ruta no es absoluta y literal seguida de '&&'"
  CD_PATH="${BASH_REMATCH[1]}"
  BASE_DIR=$(cd "$CD_PATH" 2>/dev/null && pwd -P) || _ppg_block_tree "la ruta '$CD_PATH' no existe"
  TARGET_DIR=$(git -C "$BASE_DIR" rev-parse --show-toplevel 2>/dev/null) || _ppg_block_tree "'$CD_PATH' no es un repo git"
else
  BASE_DIR=$(guard_session_dir) || _ppg_block_tree "el cwd del input no es un directorio ($INPUT_CWD)"
  TARGET_DIR=$(git -C "$BASE_DIR" rev-parse --show-toplevel 2>/dev/null) || TARGET_DIR="$BASE_DIR"
fi
SESSION_DIR="$BASE_DIR"

# Verificar si se está pusheando a main directamente (no como parte de un PR merge)
CURRENT_BRANCH=$(git -C "$BASE_DIR" branch --show-current 2>/dev/null)
PPG_MAIN_MERGE=0

if [ "$CURRENT_BRANCH" = "main" ] || [ "$CURRENT_BRANCH" = "master" ]; then
  # Permitir si es un merge desde dev (el último commit es un merge commit):
  # no hay más bloqueos de texto (PPG_MAIN_MERGE salta los chequeos de
  # refspec, como el exit 0 de antes) pero la suite SÍ corre al final.
  if git -C "$BASE_DIR" log -1 --pretty=%s | grep -qiE '^Merge'; then
    PPG_MAIN_MERGE=1
  else
    echo "BLOCKED: No push directo a main. Usa un PR desde dev o feature branch." >&2
    exit 2
  fi
fi

# #112: el destino del refspec también cuenta. Desde cualquier rama, "git
# push origin HEAD:main", "dev:main", "refs/heads/main" o el refspec pelado
# "main" (empuja la rama local main) son push directo a main aunque la rama
# actual sea feature/x; antes salían en 0 sin evaluarse. Se mira cada
# segmento "git push ..." del comando saneado (anclado con PUSH_RE, hasta el
# primer &, ; o |: GUARD_SEGMENT_END), no solo el primero, y de cada token su DESTINO: lo que
# sigue al ":" o el token entero si no lo tiene, con el "+" opcional
# del refspec forzado. "refs/heads/(main|master)" cuenta como main;
# "refs/tags/..." y un nombre de tag suelto no. Un refspec con main como
# ORIGEN (main:feature/x) no bloquea: su destino es otro. La excepción del
# merge commit de arriba es solo para la rama main local — un merge commit
# en HEAD de feature/x no habilita empujarlo a main. Fuera de alcance
# (README, "Fuera de alcance"): el refspec entero entre comillas (el saneo lo
# reemplaza por el placeholder Q). Una redirección con "&" antes del refspec
# ("2>&1 HEAD:main") SÍ bloquea desde #118: GUARD_SEGMENT_END no corta en el "&"
# de una redirección. "HEAD:main>log" y "HEAD:main</dev/null" SÍ bloquean: "<"
# y ">" cierran el token (GUARD_TOKEN_END).
# Segmentos "git push ..." del comando saneado, extraídos una sola vez para los
# chequeos de abajo (destino main, --all/--mirror, config, refspec vacío).
PUSH_SEGMENTS=$(echo "$SANITIZED_COMMAND" | grep -oE "${PUSH_RE}${GUARD_SEGMENT_END}")
if [ "$PPG_MAIN_MERGE" -ne 1 ]; then
  DST_MAIN_RE="(^|[[:space:]])\+?([^[:space:]:]*:)?(refs/heads/)?(main|master)${GUARD_TOKEN_END}"
  if echo "$PUSH_SEGMENTS" | grep -qE "$DST_MAIN_RE"; then
    echo "BLOCKED: No push directo a main: el refspec apunta a main/master (HEAD:main, dev:main, refs/heads/main o la rama local main). Usa un PR desde dev o feature branch." >&2
    exit 2
  fi

  # #117: "--all", "--mirror" y "--branches" (y cualquier prefijo único de ellas,
  # ver GUARD_PUSH_ALL_RE) empujan todas las ramas locales (incluida main)
  # sin nombrarla en el comando, así que el chequeo de destino de arriba no
  # los ve. Se bloquean desde cualquier rama, con el mismo regex y la misma
  # segmentación (GUARD_SEGMENT_END: hasta el primer &, ; o |) que usa
  # block-force-push.sh. El ")" y el backtick cierran el TOKEN (GUARD_TOKEN_END),
  # no el segmento: "(git push origin HEAD:main)" bloquea y una sustitución
  # dentro del push ("git push origin $(true) HEAD:main") no esconde lo que sigue.
  if echo "$PUSH_SEGMENTS" | grep -qE "$GUARD_PUSH_ALL_RE"; then
    echo "BLOCKED: git push --all/--mirror empuja todas las ramas locales, incluida main. Empuja la rama explícita (git push origin <rama>) y usa un PR para main." >&2
    exit 2
  fi

  # #117 ronda 2 (MEDIO): formas que empujan main sin nombrarla ni usar --all.
  # (a) "-c push.default=matching", "-c remote.<x>.mirror=true" y
  # "-c remote.<x>.push=..." (GUARD_PUSH_CONFIG_RE) vuelven "git push origin"
  # un push de todas las ramas coincidentes; (b) el refspec ":" suelto
  # (GUARD_PUSH_EMPTY_REFSPEC_RE) hace lo mismo. ":rama" borra una rama remota
  # y sigue pasando. Mismo segmento que el chequeo de --all.
  # Con refspec explícito ("git -c push.default=matching push origin feature/x")
  # el bloqueo es un falso positivo, en dirección segura: no se distingue si hay
  # refspec porque el config solo importa cuando falta.
  if echo "$PUSH_SEGMENTS" | grep -qiE "$GUARD_PUSH_CONFIG_RE"; then
    echo "BLOCKED: la config push.default=matching|upstream|tracking, remote.<x>.mirror o remote.<x>.push (por -c o --config-env) empuja main sin nombrarla. Empuja la rama explícita (git push origin <rama>) y usa un PR para main." >&2
    exit 2
  fi
  if echo "$PUSH_SEGMENTS" | grep -qE "$GUARD_PUSH_EMPTY_REFSPEC_RE"; then
    echo "BLOCKED: el refspec ':' suelto empuja las ramas coincidentes, incluida main. Empuja la rama explícita (git push origin <rama>) y usa un PR para main." >&2
    exit 2
  fi

  # #119: un refspec glob ("refs/heads/*:refs/heads/*", "*:*", "refs/heads/*")
  # empuja todas las ramas que casan, main incluida, sin nombrarla. Regla y
  # alcance (qué destinos cuentan, qué queda fuera) en guard-matching.sh.
  if guard_push_has_glob_dst "$PUSH_SEGMENTS"; then
    echo "BLOCKED: un refspec glob (destino con '*' bajo refs/heads/ o sin prefijo refs/) empuja todas las ramas que casan, incluida main. Empuja la rama explícita (git push origin <rama>) y usa un PR para main." >&2
    exit 2
  fi
fi

# Clasificación (R4): un push que solo borra refs no sube objetos, y uno que
# solo sube tags sube el mismo código que ya está en algún remoto, así que no
# corren la suite. Un tag sobre un commit que ningún remoto tiene SÍ publica
# código sin probar: ese push corre la suite (_ppg_tags_unpublished). Va DESPUÉS de todos los
# bloqueos de main (un borrado de main sigue bloqueando) y es una lista
# cerrada: solo clasifica un "git push" pelado (sin wrapper, prefijo de
# entorno ni opciones de git) con tokens de un charset acotado; todo lo que no
# se reconoce corre la suite. Tabla SKIP/SUITE: DESIGN 2.2 y los tests.
PPG_PLAIN_PUSH_RE='^(&&|\|\||;|\||&|\(|\{)?[[:space:]]*git[[:space:]]+push([[:space:]]+(.*))?$'
PPG_REDIR_RE='^([0-9]?>&[0-9]|[0-9]?>>?/dev/null|&>/dev/null)$'
PPG_TOKEN_RE='^[A-Za-z0-9._/:+@-]+$'
PPG_DEL_REF_RE='^\+?:[^:]+$'
PPG_TAG_REF_RE='^\+?refs/tags/[^:]+(:refs/tags/[^:]+)?$'
# Tags que el push sube (ORIGEN de cada refspec) y si usa --tags; los llena
# _ppg_segment_is_skip y los consume _ppg_tags_unpublished.
PPG_TAG_REFS=()
PPG_ALL_TAGS=0

# _ppg_segment_is_skip <segmento>: 0 si el segmento solo borra refs o solo
# sube tags; 1 en cualquier otro caso (incluido todo lo que no se reconoce).
_ppg_segment_is_skip() {
  local seg="$1" tok src prev_tag=0 first_pos=1 seg_tags=()
  local del=0 tags=0 delrefs=0 tagrefs=0 bare=0 other=0 pending_tag=0
  [[ "$seg" =~ $PPG_PLAIN_PUSH_RE ]] || return 1
  local rest="${BASH_REMATCH[3]}"
  # Sin glob: un token "*" no se expande contra el cwd.
  set -f
  # shellcheck disable=SC2086
  set -- $rest
  set +f
  for tok in "$@"; do
    if [[ "$tok" =~ $PPG_REDIR_RE ]]; then
      continue
    fi
    [ "$tok" = "Q" ] && return 1
    [[ "$tok" =~ $PPG_TOKEN_RE ]] || return 1
    case "$tok" in
      --delete|-d) del=1 ;;
      --tags) tags=1 ;;
      -n|--dry-run|-v|--verbose|-q|--quiet|--porcelain|--progress|--no-progress|--atomic|--no-verify) ;;
      -*) return 1 ;;
      *)
        if [ "$first_pos" -eq 1 ]; then
          first_pos=0 # el remoto
        elif [ "$prev_tag" -eq 1 ]; then
          tagrefs=$((tagrefs + 1)); prev_tag=0; pending_tag=0
          seg_tags+=("refs/tags/$tok")
        elif [ "$tok" = "tag" ]; then
          pending_tag=1; prev_tag=1
        elif [[ "$tok" =~ $PPG_DEL_REF_RE ]]; then
          delrefs=$((delrefs + 1))
        elif [[ "$tok" =~ $PPG_TAG_REF_RE ]]; then
          tagrefs=$((tagrefs + 1))
          src="${tok#+}"; seg_tags+=("${src%%:*}")
        elif [[ "$tok" != *:* ]]; then
          bare=$((bare + 1))
        else
          other=$((other + 1))
        fi
        ;;
    esac
  done
  [ "$pending_tag" -eq 0 ] && [ "$other" -eq 0 ] || return 1
  if [ "$del" -eq 1 ]; then
    # Borrado: no sube objetos, no registra tags que publicar.
    [ "$tags" -eq 0 ] && [ "$delrefs" -eq 0 ] && [ $((bare + tagrefs)) -ge 1 ]
  else
    [ "$bare" -eq 0 ] && { [ $((delrefs + tagrefs)) -ge 1 ] || [ "$tags" -eq 1 ]; } || return 1
    [ "$tags" -eq 1 ] && PPG_ALL_TAGS=1
    PPG_TAG_REFS+=(${seg_tags[@]+"${seg_tags[@]}"})
  fi
}

# _ppg_push_needs_suite <PUSH_SEGMENTS>: 1 (no hace falta la suite) solo si hay
# al menos un segmento y TODOS son borrado o solo-tags; 0 en cualquier otro caso.
_ppg_push_needs_suite() {
  local seg n=0
  while IFS= read -r seg; do
    [ -z "$seg" ] && continue
    n=$((n + 1))
    _ppg_segment_is_skip "$seg" || return 0
  done <<< "$1"
  [ "$n" -ge 1 ] && return 1
  return 0
}

# _ppg_tags_unpublished: 0 (hay que correr la suite) si algún tag que el push
# sube apunta a un commit que ningún remoto tiene, o si no se puede probar lo
# contrario (rev-list falla, la ref no resuelve a un commit); 1 si todos están
# publicados. Los borrados no suben objetos y no se registran.
_ppg_tags_unpublished() {
  local ref out
  if [ "$PPG_ALL_TAGS" -eq 1 ]; then
    out=$(git -C "$TARGET_DIR" rev-list -n1 --tags --not --remotes 2>/dev/null) || return 0
    [ -z "$out" ] || return 0
  fi
  for ref in ${PPG_TAG_REFS[@]+"${PPG_TAG_REFS[@]}"}; do
    out=$(git -C "$TARGET_DIR" rev-list -n1 "${ref}^{commit}" --not --remotes 2>/dev/null) || return 0
    [ -z "$out" ] || return 0
  done
  return 1
}

if ! _ppg_push_needs_suite "$PUSH_SEGMENTS" && ! _ppg_tags_unpublished; then
  echo "pre-push-guard: el push solo borra refs o sube tags; no corre la suite." >&2
  exit 0
fi

# La suite corre una sola vez, después de TODOS los bloqueos de texto (nada
# caro ocurre antes). Con marcador de runner entre la sesión y el toplevel
# corre ese directorio; sin él, la derivación por cambios locales; sin
# candidatos no corre nada.
cd "$TARGET_DIR" || _ppg_block_tree "no se pudo entrar al árbol resuelto ($TARGET_DIR)"
guard_suite_run "$SESSION_DIR" "$TARGET_DIR"

exit 0
