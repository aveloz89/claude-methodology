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
# se resuelve con guard_session_dir (hooks/lib/guard-matching.sh), la misma
# regla que pre-push-guard, pre-commit-guard y block-force-push: ".cwd" de
# la raíz del payload si viene con un valor no vacío — tiene que ser un
# directorio; si no lo es, CASO B, nunca el árbol del proceso —, y el cwd
# del proceso si no viene o viene vacío/null (".cwd // empty", como
# guard_init). Antes se resolvía siempre desde el cwd del PROCESO del hook
# (hallazgo fuera de scope del review de #114): en una sesión de worktree
# de la app de escritorio el proceso del hook corre en el checkout
# principal y ".cwd" es el worktree (observado al mergear #114, cuando
# pre-merge-check bloqueó por esa misma discrepancia), así que el checkpoint
# leía el state.json y el branch de otro árbol y podía emitir CASO A/B del
# repo equivocado. Esa discrepancia NO es ambigüedad acá: git -C actúa
# sobre ".cwd" igual que en esos guards; el fail-closed ante la
# discrepancia (ARCHITECTURE 2026-09-26) es el de pre-merge-check, que no
# puede redirigir "gh repo view" (ARCHITECTURE 2026-10-29). Sourcear la
# lib solo define constantes y funciones — no corre guard_init, que es
# fail-closed sin jq y lo llama cada guard por su cuenta —, así que el
# no-op sin jq de este hook se conserva; sin la lib no hay con qué
# resolver el árbol → CASO B (dirección segura). Fuera de alcance (#125):
# una redirección en el TEXTO del comando ("cd X && gh pr create",
# "gh pr create -R o/r", "GH_REPO=o/r gh …") crea el PR desde otro repo y
# la evidencia se sigue evaluando sobre ".cwd".
# Siempre exit 0 (checkpoint, no guard). Sin jq en PATH: no-op limpio
# (degradación estándar de hooks de observabilidad, ARCHITECTURE 2026-08-14).
# NOTA: Este hook NO ejecuta agentes directamente — emite instrucciones en stdout
# que el agente orquestador lee y actúa en consecuencia.

command -v jq > /dev/null 2>&1 || exit 0

# guard_session_dir (ver header). Sin la lib el hook sigue: la resolución
# del árbol cae a CASO B más abajo.
LIB="${0%/*}/lib/guard-matching.sh"
if [ -r "$LIB" ]; then
  # shellcheck source=lib/guard-matching.sh
  . "$LIB"
fi

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Solo interceptar gh pr create
if ! echo "$COMMAND" | grep -qE 'gh\s+pr\s+create'; then
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
  # ".cwd" se lee acá y no junto a COMMAND: el hook corre en CADA
  # PostToolUse de Bash y solo lo necesita cuando hay un PR que evaluar.
  # guard_session_dir lo toma de INPUT_CWD (la misma variable que deja
  # guard_init en los guards) y devuelve 1 sin imprimir si vino y no es un
  # directorio; sin la función (lib ausente) o con status 1, SESSION_DIR
  # queda vacío → TOPLEVEL vacío → CASO B. Cada git lleva -C explícito
  # gateado por -n: con la ruta vacía, "git -C ''" deja el cwd del proceso
  # sin cambiar (documentado y verificado en git 2.54), justo el árbol al
  # que no hay que caer.
  # shellcheck disable=SC2034 # la lee guard_session_dir (lib sourceada arriba)
  INPUT_CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
  SESSION_DIR=""
  if type guard_session_dir > /dev/null 2>&1; then
    SESSION_DIR=$(guard_session_dir 2>/dev/null) || SESSION_DIR=""
  fi
  TOPLEVEL=""
  CURRENT_BRANCH=""
  if [ -n "$SESSION_DIR" ]; then
    TOPLEVEL=$(git -C "$SESSION_DIR" rev-parse --show-toplevel 2>/dev/null)
  fi
  if [ -n "$TOPLEVEL" ]; then
    CURRENT_BRANCH=$(git -C "$TOPLEVEL" branch --show-current 2>/dev/null)
  fi
  STATE_FILE="$TOPLEVEL/.planning/state.json"
  REVIEW_PHASE=""
  STATE_BRANCH=""
  REVIEW_SHA=""
  if [ -n "$TOPLEVEL" ] && [ -f "$STATE_FILE" ]; then
    # 2>/dev/null: un state.json malformado degrada a CASO B sin filtrar
    # el error de parseo de jq al output del checkpoint.
    REVIEW_PHASE=$(jq -r '.phases.review // empty' "$STATE_FILE" 2>/dev/null)
    STATE_BRANCH=$(jq -r '.branch // empty' "$STATE_FILE" 2>/dev/null)
    REVIEW_SHA=$(jq -r '.review_sha // empty' "$STATE_FILE" 2>/dev/null)
  fi
  CASO_B_DIAG="No hay evidencia de review dual pre-push para este branch — se trata como PR fuera del flujo."
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
