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

# "docker compose" sube por los directorios padres buscando el compose: se
# replica la búsqueda desde el dir de la sesión hasta el toplevel de git
# (incluido). Sin repo git solo cuenta el dir de la sesión. El compose corre
# en el dir donde se encontró.
SESSION_PHYS=$(pwd -P)
GIT_TOP=$(git rev-parse --show-toplevel 2>/dev/null)
COMPOSE_DIR=""
SEARCH_DIR="$SESSION_PHYS"
while :; do
  for NAME in compose.yaml compose.yml docker-compose.yaml docker-compose.yml; do
    if [ -f "$SEARCH_DIR/$NAME" ]; then
      COMPOSE_DIR="$SEARCH_DIR"
      break 2
    fi
  done
  # Corte: sin repo, o al llegar al toplevel, o a la raíz del filesystem.
  [ -z "$GIT_TOP" ] || [ "$SEARCH_DIR" = "$GIT_TOP" ] || [ -z "$SEARCH_DIR" ] && break
  SEARCH_DIR="${SEARCH_DIR%/*}"
done
if [ -z "$COMPOSE_DIR" ]; then
  exit 0
fi
cd "$COMPOSE_DIR" || exit 0

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

# Compose config como JSON para analizar los volúmenes. --no-path-resolution
# devuelve los .source tal como se declararon ("." , "../shared", "./src"); un
# compose viejo sin el flag falla y se cae al modo absoluto (paths resueltos).
BIND_MODE=relative
COMPOSE_JSON=$(docker compose config --no-path-resolution --format json 2>/dev/null)
if [ -z "$COMPOSE_JSON" ]; then
  BIND_MODE=absolute
  COMPOSE_JSON=$(docker compose config --format json 2>/dev/null)
fi

OUTPUT=""
ACTIONS_NEEDED=false

for SERVICE in $SERVICES; do
  HAS_HOT_RELOAD=false

  if [ -n "$COMPOSE_JSON" ]; then
    # Bind mount volumes = local code mounted into container = hot reload likely.
    # relative: el source declarado es "." / ".." / "./x" / "../x".
    # absolute: el source es el dir del compose o cae dentro de él.
    BIND_COUNT=$(echo "$COMPOSE_JSON" | jq -r --arg svc "$SERVICE" --arg dir "$COMPOSE_DIR" --arg mode "$BIND_MODE" '
      def local_src:
        if $mode == "relative" then
          . == "." or . == ".." or startswith("./") or startswith("../")
        else
          . == $dir or startswith($dir + "/")
        end;
      .services[$svc].volumes // [] |
      map(select(.type == "bind" and (.source | local_src))) |
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
