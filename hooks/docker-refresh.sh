#!/bin/bash
# docker-refresh.sh — Detects when to restart/rebuild Docker services after push or PR creation.
# Logic:
#   - Hot reload (bind mounts detected) → no action needed
#   - No hot reload → restart service
#   - Dependency/Dockerfile changed → full rebuild
# Outputs instructions for the agent to execute.

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Only intercept git push and gh pr create
if ! echo "$COMMAND" | grep -qE '^\s*git\s+push|gh\s+pr\s+create'; then
  exit 0
fi

# Árbol de la sesión: ".cwd" del payload si viene no vacío (en una sesión de
# worktree el proceso corre en el checkout principal y ".cwd" es el worktree),
# el cwd del proceso si no (misma regla que post-pr-create, vía
# guard_session_dir). Un ".cwd" que no es directorio, o una lib ausente, deja
# el aviso sin emitir con el motivo en stderr — nunca se cae al árbol del
# proceso. El valor de ".cwd" no se interpola en ningún mensaje.
LIB_GM="${0%/*}/lib/guard-matching.sh"
# shellcheck source=lib/guard-matching.sh
[ -r "$LIB_GM" ] && . "$LIB_GM"
if ! type guard_session_dir > /dev/null 2>&1; then
  echo "docker-refresh: sin aviso de Docker: no se pudo resolver el árbol de la sesión (hooks/lib/guard-matching.sh falta o no define guard_session_dir)" >&2
  exit 0
fi
# shellcheck disable=SC2034 # la lee guard_session_dir (lib sourceada arriba)
INPUT_CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
if ! SESSION_DIR=$(guard_session_dir 2>/dev/null) || [ -z "$SESSION_DIR" ]; then
  echo "docker-refresh: sin aviso de Docker: no se pudo resolver el árbol de la sesión (el .cwd del payload no es un directorio)" >&2
  exit 0
fi
cd "$SESSION_DIR" || exit 0

# Check if a compose file exists
if [ ! -f "docker-compose.yml" ] && [ ! -f "docker-compose.yaml" ] \
  && [ ! -f "compose.yml" ] && [ ! -f "compose.yaml" ]; then
  exit 0
fi

# Get services
SERVICES=$(docker compose config --services 2>/dev/null)
if [ -z "$SERVICES" ]; then
  exit 0
fi

# Check what files changed in the last commit
CHANGED_FILES=$(git diff --name-only HEAD~1 HEAD 2>/dev/null || echo "")

# Detect if dependency/infra files changed (needs full rebuild)
REBUILD_NEEDED=false
if echo "$CHANGED_FILES" | grep -qiE '(package\.json|pnpm-lock\.yaml|yarn\.lock|package-lock\.json|requirements\.txt|Pipfile|poetry\.lock|pyproject\.toml|Dockerfile|\.dockerignore)'; then
  REBUILD_NEEDED=true
fi

# Get compose config as JSON for volume analysis
COMPOSE_JSON=$(docker compose config --format json 2>/dev/null)

OUTPUT=""
ACTIONS_NEEDED=false

for SERVICE in $SERVICES; do
  HAS_HOT_RELOAD=false

  if [ -n "$COMPOSE_JSON" ]; then
    # Bind mount volumes = local code mounted into container = hot reload likely
    # "docker compose config" resuelve los paths relativos a ABSOLUTOS
    # (./src -> /ruta/proyecto/src): un bind de código es el que cae dentro
    # del directorio del proyecto, no el que empieza con "./".
    BIND_COUNT=$(echo "$COMPOSE_JSON" | jq -r --arg svc "$SERVICE" --arg dir "$SESSION_DIR" '
      .services[$svc].volumes // [] |
      map(select(.type == "bind" and (.source | startswith($dir + "/")))) |
      length
    ' 2>/dev/null)
    [ "$BIND_COUNT" != "0" ] && [ -n "$BIND_COUNT" ] && HAS_HOT_RELOAD=true
  fi

  if $REBUILD_NEEDED; then
    OUTPUT="${OUTPUT}\n  - ${SERVICE}: rebuild necesario (dependencia o Dockerfile cambió) → docker compose up -d --build ${SERVICE}"
    ACTIONS_NEEDED=true
  elif ! $HAS_HOT_RELOAD; then
    OUTPUT="${OUTPUT}\n  - ${SERVICE}: sin hot reload → docker compose restart ${SERVICE}"
    ACTIONS_NEEDED=true
  else
    OUTPUT="${OUTPUT}\n  - ${SERVICE}: hot reload activo — no requiere acción"
  fi
done

if $ACTIONS_NEEDED; then
  echo ""
  echo "ACCIÓN REQUERIDA — Actualizar servicios Docker para que el usuario pueda probar:"
  echo -e "$OUTPUT"
  echo ""
  echo "Ejecuta los comandos indicados y confirma al usuario que los servicios están listos con la URL de acceso."
else
  echo ""
  echo "DOCKER: Todos los servicios tienen hot reload — los cambios ya son visibles. Confirma al usuario."
fi

exit 0
