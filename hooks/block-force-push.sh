#!/bin/bash
# Bloquea git push --force / -f que puede sobrescribir historia remota.
#
# hooks.json registra este guard SIN "if" (decisión del usuario, ronda 1 de
# review): corre en cada Bash. Con "Bash(git *)" el harness no lo invocaba para
# comandos que empiezan por un wrapper ("time git push origin HEAD:main" movía
# main, verificado en un sandbox con claude -p), un if/then ni un backtick. La
# validación de abajo mira el comando completo; sin "git" en el comando sale 0.
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
# El GUARD_SEGMENT_END entre "push\b" y la flag no cruza un separador de
# comando real (&, ; ni |; el ")" y el backtick cierran el token, no el
# segmento, ver GUARD_TOKEN_END en la lib): sin esto, "git push origin x && echo -f" (sin
# --force) bloquearía igual, porque el charset se estiraría hasta la
# "-f" de un comando distinto después del separador.

# El branch se decide por el cwd DE LA SESIÓN (guard_session_dir), no por lo
# que diga el propio comando: un "cd"/"git -C" junto al "git push" en el
# mismo comando no lo redirige acá, lo bloquea pre-push-guard.sh (mismo
# criterio que ese guard) antes de que este código corra.
#
# guard_raw_push_has_quote: 0 si algún trozo del comando CRUDO que es un "git
# push" lleva una comilla, una barra invertida o un "$". No depende del ancla
# literal "git" sobre el texto crudo (g''it, g\it o "git" partido por una
# continuación de línea no la matchean): cada trozo se limpia de comillas,
# barras y "$" y se busca el push sobre el texto limpio. Se parte en ";", "&&",
# "||", "|" (no en ">|") y newline; un "&" suelto NO parte, para que una
# redirección (2>&1) no corte el segmento a la mitad: partir de menos solo
# agranda el trozo (más bloqueo, dirección segura). Una barra+newline se une
# antes de partir.
guard_raw_push_has_quote() {
  local joined="${COMMAND//\\$'\n'/}" piece clean
  joined="${joined//>|/>$'\001'}"
  joined="${joined//&&/;}"
  joined="${joined//||/;}"
  while IFS= read -r piece; do
    clean=$(printf '%s' "$piece" | tr -d "'\"\\\\\$")
    [ "$clean" = "$piece" ] && continue
    printf '%s' "$clean" | grep -qE "${GUARD_ANCHOR}${GUARD_ENV_PREFIX}git\s+${GUARD_GIT_OPTS}push\b" && return 0
  done < <(printf '%s\n' "$joined" | tr ';|' '\n')
  return 1
}

# guard_force_with_lease_allowed: 0 (permitido) solo si el branch actual
# (de guard_session_dir) NO es main/master/dev y el segmento del "git ...
# push ..." real (anclado a posición de comando con GUARD_ANCHOR, hasta el
# primer &, ; o |: GUARD_SEGMENT_END) no lleva --all/--mirror ni menciona main/master/dev como
# token, refspec (x:main, main:x) o destino "refs/heads/(main|master|dev)".
# Fuera de un repo git, o sin poder resolver el branch, bloquea
# (fail-closed) — no hay forma segura de asumir "no es main".
#
# El segmento se toma del match ANCLADO de FORCE_PATTERN (mismo prefijo
# "git\s+${GUARD_GIT_OPTS}push\b"), no del primer "push\b" suelto del
# comando: un "git stash push" antes del push real, o un directorio/branch
# que contiene la palabra "push" (ej. "push-service"), capturaban ese
# "push\b" ajeno y dejaban el "main"/"dev" del git push real afuera del
# segmento evaluado — coló un push a rama protegida (review ronda 1,
# security MEDIUM).
guard_force_with_lease_allowed() {
  local dir branch push_segment push_segments
  dir=$(guard_session_dir) || return 1
  branch=$(git -C "$dir" rev-parse --abbrev-ref HEAD 2> /dev/null) || return 1
  case "$branch" in
    main | master | dev) return 1 ;;
  esac
  # El saneo (guard_sanitize) reemplaza los spans quoted por el placeholder Q:
  # "origin 'main'" queda como "origin Q" y el token "main" desaparece del
  # segmento, así que el check de abajo (que busca "main"/"dev" como palabra
  # suelta) no lo ve y la excepción de --force-with-lease se cuela. El comando
  # CRUDO sí conserva las comillas: si el push con lease lleva cualquiera, no
  # hay forma barata de saber qué token queda adentro sin parsear el shell de
  # verdad — la excepción no aplica y bloquea fail-closed (guard_raw_push_has_quote).
  guard_raw_push_has_quote && return 1
  push_segments=$(echo "$SANITIZED_COMMAND" | grep -oE "${GUARD_ANCHOR}${GUARD_ENV_PREFIX}git\s+${GUARD_GIT_OPTS}push\b${GUARD_SEGMENT_END}")
  # La excepción aplica a los segmentos que llevan --force-with-lease: cada
  # uno tiene que cumplirla; si cualquiera falla, bloquea. Un segmento sin
  # la flag no es force por sí mismo (si lo fuera, LEASE_STRIPPED_COMMAND
  # ya habría bloqueado antes de llegar acá).
  while IFS= read -r push_segment; do
    echo "$push_segment" | grep -q -- '--force-with-lease' || continue
    # --all y --mirror (y --branches y los prefijos únicos, GUARD_PUSH_ALL_RE)
    # empujan TODOS los refs remotos (o los espejan) sin importar qué otro ref
    # aparezca en el resto del comando: la excepción nunca los cubre.
    echo "$push_segment" | grep -qE "$GUARD_PUSH_ALL_RE" && return 1
    # Los "-c" que vuelven el push un push de todo (GUARD_PUSH_CONFIG_RE) tampoco
    # los cubre la excepción: empujarían main sin nombrarla.
    echo "$push_segment" | grep -qiE "$GUARD_PUSH_CONFIG_RE" && return 1
    # El refspec ":" / "+:" suelto empuja las ramas coincidentes (incluida
    # main) sin nombrarla: tampoco lo cubre la excepción.
    echo "$push_segment" | grep -qE "$GUARD_PUSH_EMPTY_REFSPEC_RE" && return 1
    # Un refspec glob (#119) empuja main sin nombrarla: tampoco lo cubre.
    guard_push_has_glob_dst "$push_segment" && return 1
    echo "$push_segment" | grep -qE "(^|[[:space:]:])(main|master|dev)(:|${GUARD_TOKEN_END})|refs/heads/(main|master|dev)(:|${GUARD_TOKEN_END})" && return 1
  done <<< "$push_segments"
  return 0
}

# El ref del refspec forzado se cierra con "[^[:space:]:]+", no con
# "[^\s:]+": dentro de una expresión de corchetes POSIX "\s" no significa
# "espacio" sino los caracteres "\" y "s", así que un ref que empieza con
# "s" (+staging, +stable, +support/x) no matcheaba y pasaba sin bloqueo;
# +main, +dev y +feature/x sí bloqueaban, por eso no se notó (#112).
FORCE_PATTERN="${GUARD_ANCHOR}${GUARD_ENV_PREFIX}git\s+${GUARD_GIT_OPTS}push\b${GUARD_SEGMENT_END}((-f|--force)\b|(^|[[:space:]])-[a-zA-Z]*f[a-zA-Z]*${GUARD_TOKEN_END}|\s\+[^[:space:]:]+|\s\+:${GUARD_TOKEN_END})"

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
