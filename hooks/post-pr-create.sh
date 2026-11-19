#!/bin/bash
# Post PR create (v2): checkpoint de respaldo al detectar `gh pr create`.
# El review dual ocurre ANTES del push (Fase 2.6), así que este hook ya no
# instruye lanzarlo por default — verifica evidencia en .planning/state.json:
#   CASO A — PR del flujo, ya revisado. Tres señales obligatorias:
#     phases.review=done, branch igual al actual, y review_sha (SHA de HEAD
#     al cerrar la Fase 2.6 con veredictos limpios) ancestro de HEAD **sin
#     delta posterior** (.planning/ no se versiona: cualquier commit después
#     del review es código sin revisar). No se relanzan reviewers.
#   CASO B — sin evidencia de review pre-push (todo lo demás, incluido un
#     review_sha ausente/inválido o que no cubre los commits actuales): PR
#     fuera del flujo — instruye lanzar el review dual (comportamiento v1
#     conservado).
# Ante cualquier ambigüedad falla hacia CASO B (el costo del falso negativo
# es un review redundante; el del falso positivo sería un PR sin review).
# Recibe JSON en stdin con tool_input y tool_response: la salida del comando
# vive en tool_response.stdout (PostToolUse de Bash: stdout, stderr,
# interrupted, isImage), no en la raíz. #111: leer ".stdout" en la raíz
# dejaba PR_URL vacío siempre y el hook caía al WARNING en cada PR real
# (4 de 4 en la sesión del 2026-10-28). Se acepta también ".stdout" en la
# raíz por compatibilidad con un harness que mande la salida así.
# Árbol de la sesión: el repo (toplevel, branch actual, .planning/state.json)
# se resuelve con guard_session_dir (hooks/lib/guard-matching.sh), la
# función que usan pre-push-guard y block-force-push:
# ".cwd" de la raíz del payload si viene con un valor no vacío, y el cwd
# del proceso si no viene o viene vacío/null (".cwd // empty", como
# guard_init). Un ".cwd" no vacío que no es un directorio → CASO B, nunca
# el árbol del proceso (en ese caso pre-push-guard y block-force-push
# bloquean). Antes se
# resolvía siempre desde el cwd del PROCESO del hook (hallazgo fuera de
# scope del review de #114): en una sesión de worktree de la app de
# escritorio el proceso del hook corre en el checkout principal y ".cwd"
# es el worktree (observado al mergear #114, cuando pre-merge-check
# bloqueó por esa misma discrepancia), así que el checkpoint leía el
# state.json y el branch de otro árbol y podía emitir CASO A/B del repo
# equivocado. Esa discrepancia NO es ambigüedad acá: git -C actúa sobre
# ".cwd" igual que en esos guards; el fail-closed ante la discrepancia
# (ARCHITECTURE 2026-09-26) es el de pre-merge-check, que no puede
# redirigir "gh repo view" (ARCHITECTURE 2026-10-29). La lib se sourcea
# solo cuando hay un PR que evaluar, y sourcearla solo define constantes y
# funciones — no corre guard_init, que es fail-closed sin jq y lo llama
# cada guard por su cuenta —, así que el no-op sin jq de este hook se
# conserva. Cuando el árbol no se puede resolver (lib ausente o sin la
# función, ".cwd" que no es un directorio, directorio fuera de un repo
# git), CASO B con un diagnóstico que nombra la causa en vez del genérico
# "no hay evidencia" (degradación visible, no silenciosa).
# Redirección en el TEXTO del comando (#125): "cd/pushd X" antes de "gh pr
# create", "-R/--repo" o "GH_REPO=" crean el PR en otro repo y la evidencia
# de ".cwd" no aplica → CASO B con diagnóstico propio. La detección corre
# sobre el comando saneado (guard_sanitize) y aplanado, así que un "cd" en
# un --title o en el body no cuenta. Falso positivo asumido: el "-R" de
# otro comando de la cadena ("ls -R . && gh pr create") cae a CASO B (un
# review redundante, la dirección segura). Cubre también "builtin/command cd",
# "VAR=x cd" (GUARD_ENV_PREFIX) y "env -C/--chdir X gh pr create". Fuera de
# alcance (CASO A, no se detectan): un flag entero entre comillas ("--repo",
# '-R': el saneo lo borra), la palabra del comando entre comillas
# ('cd' /x && gh pr create: el saneo la borra), "GIT_DIR=", "bash -c '...'"
# (el saneo borra el wrapper entero, igual que en la lib) y "env" con la
# opcion en cluster o abreviada (env -iC /x, env --chd /x en GNU). Fuera de
# alcance tambien, en sentido inverso (el hook sale sin checkpoint): un flag
# de gh con valor que empieza con "-" o de varias palabras entre gh/pr/create
# (gh -R "o/x y" pr create), que el prefiltro no reconoce.
# Saneo degradado (sin perl, o perl abortado): guard_sanitize devuelve el
# comando crudo y los patrones no son confiables, así que no se evalúan →
# CASO B con el diagnóstico de saneo.
# Siempre exit 0 (checkpoint, no guard). Sin jq en PATH: no-op limpio
# (degradación estándar de hooks de observabilidad, ARCHITECTURE 2026-08-14).
# NOTA: Este hook NO ejecuta agentes directamente — emite instrucciones en stdout
# que el agente orquestador lee y actúa en consecuencia.

command -v jq > /dev/null 2>&1 || exit 0

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Solo interceptar gh pr create. Tolera flags (con su valor) entre gh, pr y
# create ("gh -R o/x pr create", "gh pr --repo o/x create"): entran al hook y
# la redirección los manda a CASO B. "gh pr list --search create" no entra.
GH_FLAGS='(\s+-[^[:space:]]+(\s+[^-[:space:]][^[:space:]]*)?)*'
GH_PR_CREATE_RE="gh${GH_FLAGS}\s+pr${GH_FLAGS}\s+create"
if ! echo "$COMMAND" | grep -qE "$GH_PR_CREATE_RE"; then
  exit 0
fi

# Extraer la URL del PR del stdout del comando (head -1: si el stdout trae
# más de una URL de PR, solo la primera es la del comando recién ejecutado)
# El "?" evita que un tool_response que no sea objeto (otra tool, otro
# harness) corte jq con error: cae a la alternativa y, sin URL, al WARNING.
# owner y repo se acotan a [A-Za-z0-9._-] (review de seguridad): la URL se
# interpola en el texto del checkpoint, y "[^ ]+" dejaba pasar comillas o
# tabs; una URL con otro carácter no se extrae y el hook cae al WARNING.
PR_URL=$(echo "$INPUT" | jq -r '.tool_response.stdout? // .stdout? // empty' | grep -oE 'https://github.com/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+/pull/[0-9]+' | head -1)

if [ -n "$PR_URL" ]; then
  # La lib y ".cwd" se cargan acá y no junto a COMMAND: el hook corre en
  # CADA PostToolUse de Bash y solo los necesita cuando hay un PR que
  # evaluar. guard_session_dir toma INPUT_CWD (la misma variable que deja
  # guard_init en los guards) y devuelve 1 sin imprimir si vino y no es un
  # directorio. Cuando el árbol no se puede resolver — lib ausente, lib sin
  # la función, ".cwd" que no es un directorio, directorio fuera de un repo
  # git — el checkpoint cae a CASO B con un diagnóstico que nombra la
  # causa: el genérico "no hay evidencia de review" mandaría al orchestrator
  # a buscar una evidencia que el hook nunca miró. Cada git lleva -C
  # explícito sobre una ruta ya resuelta y no vacía: con la ruta vacía,
  # "git -C ''" deja el cwd del proceso sin cambiar (documentado y
  # verificado en git 2.54), justo el árbol al que no hay que caer.
  LIB="${0%/*}/lib/guard-matching.sh"
  CASO_B_DIAG="No hay evidencia de review dual pre-push para este branch — se trata como PR fuera del flujo."
  if [ -r "$LIB" ]; then
    # shellcheck source=lib/guard-matching.sh
    . "$LIB"
  else
    CASO_B_DIAG="No se pudo resolver el árbol de la sesión (falta hooks/lib/guard-matching.sh) — se trata como PR fuera del flujo."
  fi
  # Redirección en el TEXTO del comando (#125): cd/pushd en posición de
  # comando antes de gh pr create, -R/--repo o GH_REPO= crean el PR en otro
  # repo; la evidencia de .cwd no aplica. Se detecta sobre el comando
  # saneado (guard_sanitize borra strings y heredocs: un "cd" dentro de un
  # --title o un body no cuenta) y aplanado (un cd en una línea anterior
  # también es "antes"). Sin guard_sanitize (lib ausente o desactualizada)
  # no se evalúa: ya hay un diagnóstico de lib arriba y es CASO B.
  REDIRECT=false
  SANITIZE_FAILED=false
  if type guard_sanitize > /dev/null 2>&1; then
    # Saneo degradado (sin perl, o perl abortado por timeout): guard_sanitize
    # devuelve el comando crudo con estado 1. Los patrones sobre texto sin
    # sanear no son confiables (un "cd" en un --title cuenta), así que no se
    # evalúan: CASO B con el diagnóstico de saneo.
    if ! SANITIZED=$(guard_sanitize "$COMMAND" 2>/dev/null); then
      SANITIZE_FAILED=true
    fi
    FLAT=$(printf '%s' "$SANITIZED" | tr '\n' ';')
    # Con el saneo degradado no se evalúa ningún patrón (texto crudo).
    if [ "$SANITIZE_FAILED" = false ]; then
      if printf '%s' "$FLAT" | grep -qE "${GUARD_ANCHOR}${GUARD_ENV_PREFIX}(builtin\s+)?(cd|pushd)(\s|;|&&|\$).*${GH_PR_CREATE_RE}" \
        || printf '%s' "$FLAT" | grep -qE "${GUARD_ANCHOR}env\s+([^;&|]*\s)?(-C|--chdir)[^;&|]*${GH_PR_CREATE_RE}" \
        || printf '%s' "$FLAT" | grep -qE '(^|[[:space:]])(-R|--repo)([[:space:]=]|$)|(^|[[:space:]])-R[^[:space:]-]' \
        || printf '%s' "$FLAT" | grep -qE '(^|[^A-Za-z0-9_])GH_REPO='; then
        REDIRECT=true
      fi
    fi
  fi
  # shellcheck disable=SC2034 # la lee guard_session_dir (lib sourceada arriba)
  INPUT_CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
  SESSION_DIR=""
  TOPLEVEL=""
  CURRENT_BRANCH=""
  if ! type guard_session_dir > /dev/null 2>&1; then
    # Lib legible pero sin la función: lib anterior a guard_session_dir, no
    # un archivo ausente (ese caso ya dejó su diagnóstico arriba).
    [ -r "$LIB" ] && CASO_B_DIAG="No se pudo resolver el árbol de la sesión (hooks/lib/guard-matching.sh no define guard_session_dir: lib desactualizada) — se trata como PR fuera del flujo."
  elif ! SESSION_DIR=$(guard_session_dir 2>/dev/null) || [ -z "$SESSION_DIR" ]; then
    SESSION_DIR=""
    CASO_B_DIAG="No se pudo resolver el árbol de la sesión (el .cwd del payload no es un directorio) — se trata como PR fuera del flujo."
  elif ! TOPLEVEL=$(git -C "$SESSION_DIR" rev-parse --show-toplevel 2>/dev/null) || [ -z "$TOPLEVEL" ]; then
    TOPLEVEL=""
    CASO_B_DIAG="No se pudo resolver el árbol de la sesión (el directorio no está dentro de un repo git) — se trata como PR fuera del flujo."
  else
    CURRENT_BRANCH=$(git -C "$TOPLEVEL" branch --show-current 2>/dev/null)
  fi
  STATE_FILE="$TOPLEVEL/.planning/state.json"
  REVIEW_PHASE=""
  if [ "$REDIRECT" = true ]; then
    # Con redirección no se lee la evidencia (TOPLEVEL vacío: sin state.json
    # ni CASO A); el diagnóstico de redirección gana sobre el de árbol.
    TOPLEVEL=""
    CASO_B_DIAG="El PR se creó con una redirección en el comando; la evidencia de .cwd no aplica (cd/pushd antes de gh pr create, -R/--repo o GH_REPO=) — se trata como PR fuera del flujo."
  fi
  if [ "$SANITIZE_FAILED" = true ]; then
    # Mismo tratamiento que la redirección: sin lectura de evidencia.
    TOPLEVEL=""
    CASO_B_DIAG="No se pudo sanear el comando para descartar una redirección (falta perl o el saneo falló) — se trata como PR fuera del flujo."
  fi
  STATE_BRANCH=""
  REVIEW_SHA=""
  if [ -n "$TOPLEVEL" ] && [ -f "$STATE_FILE" ]; then
    # 2>/dev/null: un state.json malformado degrada a CASO B sin filtrar
    # el error de parseo de jq al output del checkpoint.
    REVIEW_PHASE=$(jq -r '.phases.review // empty' "$STATE_FILE" 2>/dev/null)
    STATE_BRANCH=$(jq -r '.branch // empty' "$STATE_FILE" 2>/dev/null)
    REVIEW_SHA=$(jq -r '.review_sha // empty' "$STATE_FILE" 2>/dev/null)
  fi
  if [ "$REVIEW_PHASE" = "done" ] && [ -n "$CURRENT_BRANCH" ] && [ "$STATE_BRANCH" = "$CURRENT_BRANCH" ]; then
    # Tercera señal (anclaje): review_sha debe ser hex plausible (state.json
    # es input no confiable — nunca se interpola sin validar), ancestro de
    # HEAD, y sin delta posterior (git diff --quiet): cualquier commit
    # después de review_sha es código que el review nunca vio, o el campo
    # ausente/inválido → CASO B.
    SHA_ANCHOR_OK=false
    case "$REVIEW_SHA" in
      *[!0-9a-f]* | '') : ;;
      *)
        if git -C "$TOPLEVEL" merge-base --is-ancestor "$REVIEW_SHA" HEAD 2>/dev/null \
          && git -C "$TOPLEVEL" diff --quiet "$REVIEW_SHA" HEAD 2>/dev/null; then
          SHA_ANCHOR_OK=true
        fi
        ;;
    esac
    if [ "$SHA_ANCHOR_OK" = true ]; then
      # CASO A: PR del flujo, ya revisado en Fase 2.6 (exige las tres
      # señales: fase, branch Y anclaje — cualquier otra combinación cae
      # a CASO B)
      PR_NUMBER=${PR_URL##*/}
      FEATURE_SLUG=$(jq -r '.feature // empty' "$STATE_FILE" 2>/dev/null)
      # Interpolar solo bajo allowlist: state.json y el nombre del branch
      # son input no confiable para el output del checkpoint. Fuera de la
      # allowlist (o vacío), label genérico — el CASO A no cambia, solo la
      # presentación. Los patrones case atrapan cualquier carácter fuera
      # de la allowlist, incluidos newlines (a diferencia de grep, que
      # matchea línea por línea).
      case "$FEATURE_SLUG" in
        *[!a-z0-9-]* | '') SLUG_LABEL="<feature-slug>" ;;
        *) SLUG_LABEL="$FEATURE_SLUG" ;;
      esac
      case "$CURRENT_BRANCH" in
        *[!A-Za-z0-9/_-]*) BRANCH_LABEL="<branch actual>" ;;
        *) BRANCH_LABEL="$CURRENT_BRANCH" ;;
      esac
      echo "PR creado: $PR_URL"
      echo ""
      echo "Review dual pre-push verificado (state.json: phases.review=done, branch $BRANCH_LABEL)."
      echo "PR #$PR_NUMBER ($SLUG_LABEL) nació revisado. No relances reviewers: re-review solo si CI"
      echo "obliga fixes sobre código ya revisado (Fase 3)."
      exit 0
    fi
    CASO_B_DIAG="La evidencia de review no cubre los commits actuales (review_sha ausente/inválido, no-ancestro de HEAD, o con delta posterior) — se trata como PR fuera del flujo."
  fi
  # CASO B: sin evidencia de review dual pre-push — PR fuera del flujo
  echo "PR creado: $PR_URL"
  echo ""
  echo "$CASO_B_DIAG"
  echo "ACCIÓN REQUERIDA: Revisa este PR: $PR_URL"
  echo "1. Obtén el contexto con 'gh pr diff' y 'gh pr view'."
  echo "2. Clasifica los archivos del diff por capa (frontend / backend)."
  echo "3. Lanza en paralelo los reviewers aplicables:"
  echo "   - security-reviewer (subagent_type=security-reviewer) — siempre"
  echo "   - qa-frontend (subagent_type=qa-frontend) — si el diff tiene archivos de UI"
  echo "   - qa-backend  (subagent_type=qa-backend)  — si el diff tiene archivos de servidor"
  echo "Consulta rulebooks/orchestrator-runbook.md (sección 'Clasificación del diff por capa') para la heurística por extensión y ruta."
else
  echo "WARNING: Se detectó 'gh pr create' pero no se pudo extraer la URL del PR del output."
  echo "Verifica manualmente si el PR fue creado y ejecuta el review (security-reviewer + qa-frontend/qa-backend según aplique)."
fi

exit 0
