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

# Check if docker-compose exists
if [ ! -f "docker-compose.yml" ] && [ ! -f "compose.yml" ]; then
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
    BIND_COUNT=$(echo "$COMPOSE_JSON" | jq -r --arg svc "$SERVICE" '
      .services[$svc].volumes // [] |
      map(select(.type == "bind" and (.source | test("^\\./|^\\.\\./"))))  |
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
