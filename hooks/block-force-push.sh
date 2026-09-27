#!/bin/bash
# Bloquea git push --force / -f que puede sobrescribir historia remota.
#
# hooks.json filtra la invocación con "if": "Bash(git *)" — optimización de
# latencia, no reemplaza la validación de abajo, que sigue mirando el
# comando completo.
LIB="${0%/*}/lib/guard-matching.sh"
[ -r "$LIB" ] || { echo "BLOCKED: block-force-push no operativo: falta hooks/lib/guard-matching.sh" >&2; exit 2; }
# shellcheck source=lib/guard-matching.sh
source "$LIB"
guard_init "block-force-push"

# #77 comentario 2: un refspec forzado (+<ref>, ej. "git push origin
# +main") es equivalente a --force y antes pasaba sin bloquear, igual que
# la flag -f dentro de un cluster corto (ej. "-fu", "-uf") y "git -C <ruta>
# push" (GUARD_GIT_TREE_OPTS detecta el mismo push real con esa opción de
# árbol entre "git" y "push").
#
# Borde izquierdo del cluster (review dual ronda 1, security LOW, falso
# bloqueo): sin "(^|[[:space:]])" antes del "-", el cluster matchea la "f"
# de un TOKEN que no es una flag, como el sufijo "-form"/"-flags" de un
# nombre de branch ("fix/login-form", "feature/add-feature-flags") —
# "push\s+" ya consumió el único espacio real antes del "-" de la flag,
# así que "push\b" (en vez de "push\s+") deja ese espacio disponible para
# que el propio cluster lo exija como borde.
#
# GUARD_GIT_OPTS (D-07, review dual ronda 1 y 2): tolera, en cualquier
# orden, "-c <k=v>" (una o varias), "--no-pager", "-P" y las opciones de
# árbol ("-C <ruta>", "--git-dir"/"--work-tree") antes de "push" — sin
# esto, "git -c user.name=x push --force" no matcheaba y el force push
# real pasaba SIN EVALUAR. Ver hooks/lib/guard-matching.sh.
#
# El ".*" entre "push\b" y la flag NO cruza un separador de comando real
# (&&, ;, |) — ronda 2, security LOW, falso bloqueo: antes, "git push
# origin feature/fix-flaky && echo -f" (sin --force) bloqueaba igual,
# porque el ".*" greedy se estiraba hasta la "-f" de "echo -f", un
# comando DISTINTO después del "&&". La invocación real de "push" termina
# en el primer separador de comando. Un salto de línea real no necesita
# entrar al charset: grep procesa línea por línea por defecto, así que
# ninguna de las dos partes del patrón puede cruzar uno sin ayuda extra.

# guard_force_with_lease_allowed: 0 (permitido) solo si el branch actual
# (de guard_session_dir) NO es main/master/dev y ningún token del segmento
# "push ... " (hasta el primer &&/;/|) es exactamente main/master/dev ni un
# refspec hacia/desde uno de esos tres (x:main, main:x). Fuera de un repo
# git, o sin poder resolver el branch, bloquea (fail-closed) — no hay forma
# segura de asumir "no es main".
guard_force_with_lease_allowed() {
  local dir branch push_segment
  dir=$(guard_session_dir) || return 1
  branch=$(git -C "$dir" rev-parse --abbrev-ref HEAD 2> /dev/null) || return 1
  case "$branch" in
    main | master | dev) return 1 ;;
  esac
  push_segment=$(echo "$SANITIZED_COMMAND" | grep -oE 'push\b[^&|;]*' | head -1)
  ! echo "$push_segment" | grep -qE '(^|[[:space:]:])(main|master|dev)([[:space:]:]|$)'
}

FORCE_PATTERN="${GUARD_ANCHOR}git\s+${GUARD_GIT_OPTS}push\b[^&|;]*((-f|--force)\b|(^|[[:space:]])-[a-zA-Z]*f[a-zA-Z]*(\s|$)|\s\+[^\s:]+)"

# --force-with-lease no puede reescribir un ref que otro ya movió (falla si
# el remoto no coincide con lo que el cliente esperaba) — a diferencia de
# --force/-f, permitirlo fuera de main/master/dev no reabre el riesgo que
# este guard existe para cortar. La excepción es angosta a propósito: si
# quitar "--force-with-lease(=valor)?" del comando SIGUE matcheando
# FORCE_PATTERN, hay una flag de force real e independiente (--force, -f,
# refspec "+x") en el mismo comando y esa sigue bloqueando siempre.
LEASE_STRIPPED_COMMAND=$(echo "$SANITIZED_COMMAND" | sed -E 's/--force-with-lease(=[^[:space:]]*)?//g')

if echo "$SANITIZED_COMMAND" | grep -qE "$FORCE_PATTERN"; then
  if echo "$LEASE_STRIPPED_COMMAND" | grep -qE "$FORCE_PATTERN" || ! guard_force_with_lease_allowed; then
    echo "BLOCKED: --force push can overwrite remote history and bypass branch protections. Use normal push." >&2
    exit 2
  fi
fi

exit 0
