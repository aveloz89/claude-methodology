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

# Un refspec forzado (+<ref>, ej. "git push origin +main") equivale a
# --force, igual que -f dentro de un cluster corto ("-fu", "-uf").
# GUARD_GIT_OPTS (guard-matching.sh) tolera, en cualquier orden, las
# opciones de git ("-c k=v", "--no-pager", "-P", "-C"/"--git-dir"/
# "--work-tree") entre "git" y "push", para seguir detectando el mismo
# push real con esas opciones de por medio.
#
# El cluster corto exige "(^|espacio)" a su izquierda: sin ese borde,
# matchea la "f" de un token que no es una flag, como el sufijo de
# "fix/login-form" o "feature/add-feature-flags".
#
# El "[^&|;]*" entre "push\b" y la flag no cruza un separador de comando
# real (&&, ;, |): sin esto, "git push origin x && echo -f" (sin
# --force) bloquearía igual, porque el charset se estiraría hasta la
# "-f" de un comando distinto después del separador.

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
