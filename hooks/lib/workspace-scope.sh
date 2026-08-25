#!/bin/bash
# workspace-scope.sh — para un commit en un monorepo npm/pnpm, resuelve qué
# workspaces tocan los archivos con cambios locales y arma el comando para
# correr SOLO la suite de esos workspaces en vez de la del repo entero.
#
# Motivación: pre-commit-guard.sh corría "$PKG_MGR test" en la raíz para
# cualquier proyecto Node, sin importar qué workspace tocaba el commit. En un
# monorepo con `npm run test --workspaces --if-present` (o equivalente) eso
# corre TODAS las suites en cada commit — un commit que solo toca backend
# paga también la suite completa de frontend, y viceversa.
#
# A diferencia de guard-matching.sh, esta lib NO es fail-closed: si no puede
# resolver algo con confianza (falta el binario del package manager, el repo
# declara workspaces con un patrón que no sabemos resolver, hay cambios
# fuera de todos los workspaces declarados, git status falla, etc.) devuelve
# 1 y el caller cae a correr la suite completa — el comportamiento actual,
# nunca peor que hoy. Ningún modo de falla de esta lib bloquea un commit ni
# hace que se corran MENOS tests de los que se corrían antes de que existiera.
#
# Uso:
#   source hooks/lib/workspace-scope.sh
#   if workspace_scope_resolve "$PKG_MGR"; then
#     "${WORKSPACE_SCOPE_CMD[@]}"   # ej: npm test -w frontend --if-present
#   else
#     $PKG_MGR test                # comportamiento de siempre
#   fi
#
# Requiere jq (ya es dependencia dura de pre-commit-guard.sh, que sale
# fail-closed más arriba si falta — esta lib no lo vuelve a chequear).

# _WS_DIRS: directorios de workspace resueltos (relativos a la raíz del
# repo, sin slash inicial ni final). Puebla cada resolver
# (_workspace_scope_npm_dirs / _workspace_scope_pnpm_dirs).
# _WS_TOUCHED: subconjunto de _WS_DIRS que tocan los archivos con cambios
# locales. Puebla _workspace_scope_match.
# Ambos son variables globales de esta lib (mismo patrón que GUARD_ANCHOR en
# guard-matching.sh) — no hace falta pasarlas por nombre entre funciones.

# workspace_scope_resolve: punto de entrada. $1 = PKG_MGR ("npm" | "pnpm" |
# cualquier otra cosa). Devuelve 0 y puebla WORKSPACE_SCOPE_CMD (array) +
# WORKSPACE_SCOPE_LABEL (string, para logging) si pudo resolver un
# subconjunto no vacío de workspaces tocados con confianza. Devuelve 1 en
# cualquier otro caso.
workspace_scope_resolve() {
  local pkg_mgr="$1"
  WORKSPACE_SCOPE_CMD=()
  WORKSPACE_SCOPE_LABEL=""

  case "$pkg_mgr" in
    npm)
      _workspace_scope_npm_dirs || return 1
      ;;
    pnpm)
      _workspace_scope_pnpm_dirs || return 1
      ;;
    *)
      # yarn (y cualquier otro valor): no resuelto con confianza.
      #
      # yarn classic necesita el NOMBRE de paquete de cada workspace (no el
      # path) para "yarn workspace <name> run <script>", y a diferencia de
      # `npm ... --if-present` o `pnpm --filter ... run`, no hay forma de
      # pedirle que salga en silencio si el script no existe: hay que leer
      # el package.json de cada workspace primero para confirmar que el
      # script está antes de invocar, o la falta de un "test" en un
      # workspace tocado bloquearía el commit con un falso negativo. Yarn
      # Berry (v2+) cambia la sintaxis de nuevo ("yarn workspaces foreach",
      # requiere plugin) y "yarn.lock existe" no alcanza para distinguirlo
      # de yarn classic con confianza. Ninguna de las dos resoluciones vale
      # la complejidad sin un monorepo yarn real para validar contra él —
      # se deja corriendo todo, igual que hoy.
      return 1
      ;;
  esac

  _workspace_scope_match || return 1

  case "$pkg_mgr" in
    npm) _workspace_scope_npm_cmd ;;
    pnpm) _workspace_scope_pnpm_cmd ;;
  esac

  local d label=""
  for d in "${_WS_TOUCHED[@]}"; do
    if [ -z "$label" ]; then
      label="$d"
    else
      label="$label, $d"
    fi
  done
  # shellcheck disable=SC2034 # la usa pre-commit-guard.sh al sourcear este archivo
  WORKSPACE_SCOPE_LABEL="$label"
  return 0
}

# _workspace_scope_npm_dirs: puebla _WS_DIRS con los workspaces declarados
# en package.json ("workspaces": [...] o {"packages": [...]}).
#
# Resuelve con confianza: entradas literales ("frontend") y globs de un solo
# nivel al final ("packages/*", vía expansión de shell — mismo alcance que
# el propio soporte de globs de npm para ese patrón). Cualquier otra cosa
# (comodín en medio del path, "**", negación con "!") no se resuelve: se
# aborta toda la función (return 1) — si UNA entrada no se puede resolver,
# no sabemos si algún archivo cambiado cae bajo ese workspace no resuelto,
# así que no hay subconjunto confiable posible.
_workspace_scope_npm_dirs() {
  _WS_DIRS=()
  local globs
  globs=$(jq -r '
    (.workspaces // empty) as $w
    | if ($w | type) == "array" then $w[]
      elif ($w | type) == "object" then ($w.packages // [])[]
      else empty
      end
  ' package.json 2>/dev/null) || return 1
  [ -z "$globs" ] && return 1

  local glob base d
  while IFS= read -r glob; do
    [ -z "$glob" ] && continue
    glob="${glob#./}"
    glob="${glob%/}"
    case "$glob" in
      *'!'*|*'**'*)
        return 1
        ;;
      */'*')
        base="${glob%/*}"
        for d in "$base"/*/; do
          [ -d "$d" ] || continue
          d="${d%/}"
          [ -f "$d/package.json" ] && _WS_DIRS+=("$d")
        done
        ;;
      *'*'*|*'?'*|*'['*)
        return 1
        ;;
      *)
        _WS_DIRS+=("$glob")
        ;;
    esac
  done <<< "$globs"

  [ "${#_WS_DIRS[@]}" -eq 0 ] && return 1
  return 0
}

# _workspace_scope_pnpm_dirs: puebla _WS_DIRS preguntándole a pnpm mismo.
#
# pnpm no declara workspaces en package.json sino en pnpm-workspace.yaml
# (YAML) — parsearlo a mano en bash es frágil (comentarios, distintos
# estilos de lista, etc.). En cambio se usa `pnpm list -r --depth -1 --json`,
# que ya resuelve los globs sin importar dónde estén declarados y devuelve
# paths absolutos — no hace falta parsear YAML en absoluto. Requiere el
# binario pnpm en PATH y ningún npm install previo (verificado: corre igual
# contra un workspace recién creado, sin node_modules).
_workspace_scope_pnpm_dirs() {
  _WS_DIRS=()
  command -v pnpm > /dev/null 2>&1 || return 1

  local root_path list_json rels
  root_path=$(pwd -P) || return 1
  list_json=$(pnpm list -r --depth -1 --json 2>/dev/null) || return 1
  [ -z "$list_json" ] && return 1

  rels=$(printf '%s' "$list_json" | jq -r --arg root "$root_path" '
    .[]
    | .path
    | select(. != $root and startswith($root + "/"))
    | .[($root | length) + 1:]
  ' 2>/dev/null) || return 1
  [ -z "$rels" ] && return 1

  local rel
  while IFS= read -r rel; do
    [ -z "$rel" ] && continue
    _WS_DIRS+=("$rel")
  done <<< "$rels"

  [ "${#_WS_DIRS[@]}" -eq 0 ] && return 1
  return 0
}

# _workspace_scope_match: dado _WS_DIRS ya resuelto, calcula qué archivos
# tienen cambios locales (staged, sin stagear, o untracked — la unión que
# da `git status --porcelain`, no solo el índice) y en qué workspaces caen.
#
# Por qué no alcanza con `git diff --cached` solo: este hook es PreToolUse,
# corre ANTES de que el comando Bash interceptado se ejecute. Si ese comando
# es "git add -A && git commit -m '...'" (patrón común en un solo llamado),
# el "git add -A" todavía no corrió cuando este hook mira el índice — mirar
# solo lo ya stageado subestimaría qué se va a commitear. `git status
# --porcelain` ve también los cambios sin stagear y los untracked, que son
# exactamente los que un "git add" pendiente en el mismo comando va a
# stagear. Es una sobreestimación segura (algún archivo con cambios locales
# que NO forme parte de este commit puntual puede colar un workspace de
# más) — cae del lado de correr de más, nunca de menos.
#
# Regla conservadora (calca la de .github/workflows/ci.yml, PR #122 de
# easy-quotes): si algún archivo cambiado cae FUERA de todos los workspaces
# declarados, se aborta (return 1) y el caller corre todo.
#
# Nota sobre paths con espacios: git los C-quotea en la salida de
# `--porcelain` (ej. `?? "frontend/my dir/file.txt"`, comillas literales
# incluidas en el string — pasa sea cual sea core.quotepath, que solo
# afecta no-ASCII, no espacios; verificado). Esas comillas nunca matchean
# ningún "$dir"/*, así que el archivo cae como "outside" y toda la
# resolución aborta — comportamiento seguro (cae al fallback completo,
# nunca corre de menos) pero no evidente, así que queda anotado acá.
_workspace_scope_match() {
  _WS_TOUCHED=()
  [ "${#_WS_DIRS[@]}" -eq 0 ] && return 1

  local files
  files=$(git status --porcelain --no-renames --untracked-files=all 2>/dev/null) || return 1
  [ -z "$files" ] && return 1

  local line path dir matched outside=false
  local raw=()
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    path="${line:3}"
    matched=false
    for dir in "${_WS_DIRS[@]}"; do
      case "$path" in
        "$dir"/*)
          matched=true
          raw+=("$dir")
          ;;
      esac
    done
    [ "$matched" = false ] && outside=true
  done <<< "$files"

  [ "$outside" = true ] && return 1
  [ "${#raw[@]}" -eq 0 ] && return 1

  local d
  while IFS= read -r d; do
    [ -z "$d" ] && continue
    _WS_TOUCHED+=("$d")
  done < <(printf '%s\n' "${raw[@]}" | sort -u)

  # Red de seguridad: si el paso de dedup/orden no pobló nada (ej. "sort"
  # no disponible en PATH), no declarar éxito con un comando vacío — eso
  # terminaría en "npm test --if-present" sin ningún "-w", que en la raíz
  # puede salir con éxito sin haber corrido ningún test.
  [ "${#_WS_TOUCHED[@]}" -eq 0 ] && return 1

  return 0
}

# _workspace_scope_npm_cmd: `npm test -w <ws1> -w <ws2> ... --if-present`.
# --if-present es obligatorio: sin él, un workspace tocado que no declare
# script "test" hace fallar el comando entero (verificado) y bloquearía el
# commit por un falso negativo — no porque los tests fallaran, sino porque
# ese workspace no tiene tests.
_workspace_scope_npm_cmd() {
  WORKSPACE_SCOPE_CMD=(npm test)
  local d
  for d in "${_WS_TOUCHED[@]}"; do
    WORKSPACE_SCOPE_CMD+=(-w "$d")
  done
  WORKSPACE_SCOPE_CMD+=(--if-present)
}

# _workspace_scope_pnpm_cmd: `pnpm --filter ./<ws1> --filter ./<ws2> ... run
# test`. El prefijo "./" es obligatorio y no cosmético: `pnpm --filter
# packages/a` (sin "./") interpreta el string como patrón de NOMBRE de
# paquete, no como path — si ningún nombre matchea, pnpm imprime "No
# projects matched" y sale con código 0 (verificado), o sea que sin el
# prefijo el commit pasaría sin haber corrido ningún test, en silencio. Un
# workspace tocado sin script "test" no hace falta filtrarlo aparte: pnpm ya
# lo saltea en silencio con exit 0 (verificado), a diferencia de npm.
_workspace_scope_pnpm_cmd() {
  WORKSPACE_SCOPE_CMD=(pnpm)
  local d
  for d in "${_WS_TOUCHED[@]}"; do
    WORKSPACE_SCOPE_CMD+=(--filter "./$d")
  done
  WORKSPACE_SCOPE_CMD+=(run test)
}
