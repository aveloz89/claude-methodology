#!/bin/bash
# Pre-commit guard: Detecta si Claude va a hacer git commit
# y verifica que los tests pasen primero.
# Recibe JSON en stdin con tool_input del comando Bash.
#
# Matching endurecido (#47): el match se sanea (spans quoted/heredoc) y se
# ancla a posición de comando en vez de al string completo — mismo helper
# que usa pre-merge-check.sh. Ver hooks/lib/guard-matching.sh.
#
# Fail-closed sin jq (cierra #50 para este guard): sin jq, el parseo de
# COMMAND más abajo devuelve vacío, el grep nunca matchea, y el guard
# pasaba en silencio — un commit pasaba sin correr tests. CAMBIA el
# contrato de este hook: antes, sin jq, pasaba.
if ! command -v jq > /dev/null 2>&1; then
  echo "BLOCKED: pre-commit-guard no operativo: falta jq" >&2
  exit 2
fi

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Resolución del path del lib sin depender de un binario externo (dirname):
# "${0%/*}" es el idioma de shell para dirname cuando $0 trae al menos un
# "/" — siempre el caso dado cómo el harness invoca los hooks. Fail-closed si
# el lib no existe o no es legible: un `source` fallido dejaría el resto
# del script corriendo con guard_sanitize()/GUARD_ANCHOR indefinidos, y el
# guard pasaría en silencio (mismo fail-open que #50). Mismo mecanismo de
# bloqueo que usa este hook para tests fallando: stderr + exit 2.
LIB="${0%/*}/lib/guard-matching.sh"
if [ ! -r "$LIB" ]; then
  echo "BLOCKED: pre-commit-guard no operativo: falta hooks/lib/guard-matching.sh" >&2
  exit 2
fi
# shellcheck source=lib/guard-matching.sh
source "$LIB"

SANITIZED_COMMAND=$(guard_sanitize "$COMMAND")

# Solo interceptar comandos git commit
if ! echo "$SANITIZED_COMMAND" | grep -qE "${GUARD_ANCHOR}git\s+commit"; then
  exit 0
fi

# Salto para commits que solo tocan .planning/ (regla de 3 en easy-quotes:
# #212, #247, #253 — ver .planning/BRIEF.md de la feature que agregó esto).
# Un commit de puro estado de planning no arriesga código de producción sin
# test, y forzarlo a correr suites completas solo lo expone a un flake
# ajeno al propio commit (#247: un flake bloqueó un commit de puro
# markdown).
#
# _guard_planning_only_change calcula la unión de archivos con cambios
# locales (staged + sin stagear + untracked) con el mismo comando que
# _workspace_scope_match en hooks/lib/workspace-scope.sh salvo
# --no-renames (ver más abajo por qué acá sí importa) — mismas salvedades
# por lo demás (ver su comentario, líneas ~199-256, para el detalle
# verificado caso por caso de qué reporta `git status` y cómo se procesa
# cada línea — no se repite acá para que no se desincronice). En
# particular, por qué "git status --porcelain" y no "git diff --cached":
# este hook es PreToolUse y corre ANTES de que el comando Bash interceptado
# se ejecute; si ese comando es "git add -A && git commit -m '...'", el
# "git add -A" todavía no corrió cuando este hook mira el índice, así que
# mirar solo lo ya stageado subestimaría qué entra al commit.
#
# A diferencia de _workspace_scope_match (que usa --no-renames porque solo
# le importa bajo qué directorio cae cada lado), este chequeo sí necesita
# distinguir un rename: mover un archivo DE .planning/ hacia afuera (o al
# revés) no es un cambio "solo .planning/", así que no se pasa
# --no-renames y se evalúan ambos lados de una línea "R  old -> new".
#
# Devuelve 0 (sí, es un cambio solo-.planning/) solo si la lista de
# archivos con cambios locales no está vacía y CADA UNO cae bajo
# ".planning/" (ambos lados, si es rename). Lista vacía o cualquier archivo
# fuera → 1 (camino normal) — mismo criterio conservador que
# workspace-scope.sh: ante la duda, corre de más, nunca de menos.
#
# Salvedad conocida y aceptada (igual que en workspace-scope.sh, pero acá
# la consecuencia es mayor): un archivo gitignoreado que el propio comando
# interceptado agrega con "git add -f" (ej. "git add -f secreto.js &&
# git commit ...") no aparece en este "git status" porque el "add -f"
# todavía no corrió (mismo razonamiento de timing de arriba) — en
# workspace-scope.sh eso degrada a "corre menos workspaces de los
# necesarios"; acá degrada a "salta las suites por completo" si el resto
# del árbol solo tiene cambios en .planning/. No se resuelve en código
# (miraría también "git ls-files --others --ignored", sobreingeniería para
# un "add -f" deliberado); documentado para que quede a la vista.
_guard_planning_only_change() {
  local files
  files=$(git status --porcelain --untracked-files=all 2>/dev/null) || return 1
  [ -z "$files" ] && return 1

  local line path
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    path="${line:3}"
    case "$path" in
      *' -> '*)
        case "${path%% -> *}" in
          .planning/*) : ;;
          *) return 1 ;;
        esac
        case "${path##* -> }" in
          .planning/*) : ;;
          *) return 1 ;;
        esac
        ;;
      .planning/*) : ;;
      *) return 1 ;;
    esac
  done <<< "$files"

  return 0
}

# _guard_planning_only_change lee "git status" del cwd del hook — pero el
# comando interceptado puede commitear en OTRO árbol: "cd <ruta> && git
# commit", "git -C <ruta> commit", "git --git-dir=... --work-tree=...
# commit". En esos casos decidiría "solo .planning/" leyendo un árbol que
# no es el que se está commiteando, y el salto anularía el gate en
# silencio sobre un commit de código real (verificado con git worktree
# real: árbol principal sucio solo bajo .planning/, worktree con código
# sucio, comando "cd $WT && git commit -am x" → saltaba sin correr
# suites). Ante cualquiera de esos patrones en el comando, no se toma el
# salto: cae al camino normal exacto de antes de este salto (corre de más,
# nunca de menos). #212 (este guard no sigue al árbol real del commit en
# general) sigue fuera de alcance — esto solo evita que el salto nuevo lo
# agrave, de "gate corriendo contra el árbol equivocado" a "sin gate".
#
# "cd" se ancla a posición de comando con el mismo GUARD_ANCHOR que el
# resto del hook (no matchea como parte de otra palabra, y guard_sanitize
# ya quitó los spans quoted/heredoc antes de esto, así que un "cd" dentro
# de un mensaje de commit no llega ni siquiera a este punto). "-C" se
# ancla igual porque es una opción corta de una sola letra, más propensa a
# aparecer por casualidad; "--git-dir"/"--work-tree" son lo bastante
# específicas como para no necesitar el mismo anclaje — un falso positivo
# acá solo corre suites de más.
if echo "$SANITIZED_COMMAND" | grep -qE "${GUARD_ANCHOR}cd\s|${GUARD_ANCHOR}git\s+-C\s|--git-dir|--work-tree"; then
  : # comando redirige a otro árbol: camino normal, no se evalúa el salto
elif _guard_planning_only_change; then
  echo "Solo cambios en .planning/: sin suites." >&2
  exit 0
fi

# Detectar el test runner del proyecto
if [ -f "package.json" ]; then
  # Node.js project — detectar package manager
  if [ -f "pnpm-lock.yaml" ]; then
    PKG_MGR="pnpm"
  elif [ -f "yarn.lock" ]; then
    PKG_MGR="yarn"
  else
    PKG_MGR="npm"
  fi

  if jq -e '.scripts.test' package.json > /dev/null 2>&1; then
    TEST_CMD=$(jq -r '.scripts.test' package.json)
    if [ "$TEST_CMD" != "null" ] && [ "$TEST_CMD" != "" ] && [ "$TEST_CMD" != "echo \"Error: no test specified\" && exit 1" ]; then
      # Scoping por workspace en monorepos: correr "$PKG_MGR test" en la
      # raíz de un monorepo dispara TODAS las suites en cada commit, aunque
      # el commit toque un solo workspace. hooks/lib/workspace-scope.sh
      # resuelve, con criterio conservador, si el commit se puede acotar a
      # los workspaces realmente tocados.
      #
      # A diferencia de guard-matching.sh más arriba, esta lib NO es
      # fail-closed: si no existe, no es legible, o no logra resolver un
      # subconjunto con confianza, simplemente no se activa el scoping y se
      # sigue el camino de siempre ($PKG_MGR test) — nunca bloquea el
      # commit por su ausencia.
      SCOPED=false
      WS_LIB="${0%/*}/lib/workspace-scope.sh"
      if [ -r "$WS_LIB" ]; then
        # shellcheck source=lib/workspace-scope.sh
        source "$WS_LIB"
        workspace_scope_resolve "$PKG_MGR" && SCOPED=true
      fi

      if [ "$SCOPED" = true ]; then
        echo "Running tests before commit ($PKG_MGR, workspace(s): $WORKSPACE_SCOPE_LABEL)..." >&2
        "${WORKSPACE_SCOPE_CMD[@]}" 2>&1
      else
        echo "Running tests before commit ($PKG_MGR)..." >&2
        $PKG_MGR test 2>&1
      fi
      if [ $? -ne 0 ]; then
        echo "BLOCKED: Tests failed. Fix tests before committing." >&2
        exit 2
      fi
      echo "Tests passed." >&2
    fi
  fi
elif [ -f "pytest.ini" ] || [ -f "pyproject.toml" ] || [ -f "setup.py" ]; then
  # Python project
  if command -v pytest > /dev/null 2>&1; then
    echo "Running pytest before commit..." >&2
    pytest 2>&1
    if [ $? -ne 0 ]; then
      echo "BLOCKED: Tests failed. Fix tests before committing." >&2
      exit 2
    fi
    echo "Tests passed." >&2
  fi
fi

exit 0
