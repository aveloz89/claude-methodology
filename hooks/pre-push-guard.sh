#!/bin/bash
# Pre-push guard: Previene push directo a main — desde la rama main/master
# local, o con un refspec cuyo destino sea main/master desde cualquier rama
# (#112). Debe hacerse por PR.
#
# hooks.json filtra la invocación con "if": "Bash(git *)" — optimización de
# latencia, no reemplaza la validación de abajo, que sigue mirando el
# comando completo.
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
PUSH_RE="${GUARD_ANCHOR}((GIT_DIR|GIT_WORK_TREE)=\S*\s+)*git\s+${GUARD_GIT_OPTS}push\b"
if ! echo "$SANITIZED_COMMAND" | grep -qE "$PUSH_RE"; then
  exit 0
fi

# pre-push-guard no resuelve a qué árbol redirige el comando (D-07, punto
# 4): a diferencia de pre-commit-guard, este hook no tiene una allowlist de
# formas ("cd <ruta> && …" / "git -C <ruta> …") — el push lo hace el
# orchestrator desde el cwd de la sesión, no hay forma honesta que necesite
# pushear a OTRO árbol del que ya está trabajando. Cualquier redirección
# bloquea con este mensaje en vez de adivinar a qué árbol apunta.
REDIRECT_HELP="pre-push-guard no resuelve redirecciones; hacé el cd en una llamada previa (el hook sigue el cwd de la sesión)."
CD_PUSHD_RE="${GUARD_ANCHOR}(cd|pushd)(\s|;|&&|\$)"
if echo "$SANITIZED_COMMAND" | grep -qE "$CD_PUSHD_RE" \
  || echo "$SANITIZED_COMMAND" | grep -qE '(^|[[:space:]])-C([[:space:]=]|$)' \
  || echo "$SANITIZED_COMMAND" | grep -qE -- '--git-dir|--work-tree' \
  || echo "$SANITIZED_COMMAND" | grep -qE '(^|[[:space:]]|;|&&|\|)(GIT_DIR|GIT_WORK_TREE)=' \
  || [ -n "${GIT_DIR:-}" ] || [ -n "${GIT_WORK_TREE:-}" ]; then
  echo "BLOCKED: $REDIRECT_HELP" >&2
  exit 2
fi

# Branch desde ".cwd" del input (mismo criterio que pre-commit-guard, #73):
# BASE_DIR es el árbol de la SESIÓN, no el cwd del proceso del hook —
# ambos coinciden salvo que ".cwd" venga de una llamada Bash previa distinta
# del cwd real del proceso.
BASE_DIR=$(guard_session_dir) || BASE_DIR=$(pwd -P)

# Verificar si se está pusheando a main directamente (no como parte de un PR merge)
CURRENT_BRANCH=$(git -C "$BASE_DIR" branch --show-current 2>/dev/null)

if [ "$CURRENT_BRANCH" = "main" ] || [ "$CURRENT_BRANCH" = "master" ]; then
  # Permitir si es un merge desde dev (el último commit es un merge commit)
  if git -C "$BASE_DIR" log -1 --pretty=%s | grep -qiE '^Merge'; then
    exit 0
  fi
  echo "BLOCKED: No push directo a main. Usa un PR desde dev o feature branch." >&2
  exit 2
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
# (README, "Fuera de alcance"; misma clase que la flag quoted y la
# redirección en block-force-push.sh): el refspec entre comillas (el saneo
# vacía el span) y una redirección antes del refspec o pegada a él ("2>&1
# HEAD:main" corta el segmento en "&"; "HEAD:main>log" deja el ">" pegado
# al nombre y rompe el borde del token).
DST_MAIN_RE="(^|[[:space:]])\+?([^[:space:]:]*:)?(refs/heads/)?(main|master)${GUARD_TOKEN_END}"
if echo "$SANITIZED_COMMAND" | grep -oE "${PUSH_RE}${GUARD_SEGMENT_END}" | grep -qE "$DST_MAIN_RE"; then
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
if echo "$SANITIZED_COMMAND" | grep -oE "${PUSH_RE}${GUARD_SEGMENT_END}" | grep -qE "$GUARD_PUSH_ALL_RE"; then
  echo "BLOCKED: git push --all/--mirror empuja todas las ramas locales, incluida main. Empuja la rama explícita (git push origin <rama>) y usa un PR para main." >&2
  exit 2
fi

exit 0
