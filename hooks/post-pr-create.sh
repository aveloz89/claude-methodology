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
# se resuelve desde ".cwd" de la raíz del payload cuando viene y es un
# directorio, y desde el cwd del proceso solo cuando no viene — la misma
# regla que guard_session_dir (hooks/lib/guard-matching.sh) aplica en los
# guards PreToolUse (ARCHITECTURE 2026-09-26). Antes se resolvía siempre
# desde el cwd del PROCESO del hook (hallazgo fuera de scope del review de
# #114): si difería del de la sesión, el checkpoint leía el state.json y el
# branch de otro árbol y podía emitir CASO A/B del repo equivocado. Un
# ".cwd" presente pero inválido cae a CASO B, nunca al árbol del proceso.
# La regla se replica acá en vez de sourcear la lib: su preámbulo
# guard_init es fail-closed sin jq (exit 2) y este hook es no-op limpio
# sin jq; y una lib ausente le sumaría un modo de falla a un checkpoint
# que no necesita nada más de ella.
# Siempre exit 0 (checkpoint, no guard). Sin jq en PATH: no-op limpio
# (degradación estándar de hooks de observabilidad, ARCHITECTURE 2026-08-14).
# NOTA: Este hook NO ejecuta agentes directamente — emite instrucciones en stdout
# que el agente orquestador lee y actúa en consecuencia.

command -v jq > /dev/null 2>&1 || exit 0

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
INPUT_CWD=$(echo "$INPUT" | jq -r '.cwd // empty')

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
  # Árbol de la SESIÓN (ver header): ".cwd" del payload si vino y es un
  # directorio, cwd del proceso solo si no vino. Un ".cwd" presente pero
  # inválido deja SESSION_DIR vacío → TOPLEVEL vacío → CASO B. Cada git
  # lleva -C explícito y va gateado por -n: con la ruta vacía, "git -C ''"
  # deja el cwd del proceso sin cambiar (documentado y verificado en git
  # 2.54) — justo el árbol al que no hay que caer.
  SESSION_DIR=""
  if [ -z "$INPUT_CWD" ]; then
    SESSION_DIR=$(pwd -P)
  elif [ -d "$INPUT_CWD" ]; then
    SESSION_DIR=$(cd "$INPUT_CWD" 2>/dev/null && pwd -P)
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
