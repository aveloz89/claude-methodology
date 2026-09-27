#!/bin/bash
# Pre-commit guard: Detecta si Claude va a hacer git commit
# y verifica que los tests pasen primero.
# Recibe JSON en stdin con tool_input del comando Bash.
#
# hooks.json filtra la invocación con "if": "Bash(git *)" — optimización de
# latencia, no reemplaza la validación de abajo, que sigue mirando el
# comando completo.
#
# Matching endurecido (#47): el match se sanea (spans quoted/heredoc) y se
# ancla a posición de comando en vez de al string completo — mismo helper
# que usa pre-merge-check.sh. Ver hooks/lib/guard-matching.sh.
#
# Contrato de formas para resolver el ÁRBOL OBJETIVO del commit (#73): un
# commit interceptado se resuelve solo si calza en una de tres formas — lo
# que no calza, bloquea con el mensaje de "Formas aceptadas" (TREE_FORM_HELP
# más abajo), nunca se adivina ni se corre "por si acaso":
#   1. Sin redirección: el cwd de la sesión (".cwd" del input, o el cwd
#      del proceso si el harness no lo manda — ver punto (a) abajo).
#   2. "cd <ruta> && git commit …" / "cd <ruta>; …": "cd" al INICIO del
#      comando, una sola vez, ruta literal (sin comillas/variables/
#      espacios/"-"), seguida directo de "&&" o ";" (nunca newline). El
#      único caso de expansión permitido es el prefijo "~/" contra $HOME.
#   3. "git -C <ruta> commit …": la misma ruta en cada "git" del comando.
# Ver .planning/DESIGN-pre-commit-target-tree.md "Contrato 1" para el detalle regla por regla
# (B1-B6) y la tabla de tests (R1-R11, X1-X16) que fija cada forma.
#
# Verificaciones empíricas (hechas, no deducidas — Claude Code 2.1.283,
# macOS, `claude -p` en modo de permisos default, tres corridas):
#   a. El JSON de un PreToolUse/Bash trae ".cwd", y refleja el "cd"
#      persistido de una llamada Bash ANTERIOR (no el "cd" hecho dentro
#      del mismo comando interceptado). Implicación: los subagentes tienen
#      el cwd reseteado entre llamadas — su forma habitual de commit es
#      "cd <ruta absoluta> && git commit …" en una sola llamada (forma 2),
#      no una llamada previa de "cd". Un "cd" fuera de los directorios de
#      trabajo del proyecto la herramienta Bash lo rechaza en modo default
#      (no llega a ejecutarse; ".cwd" no cambia).
#   b. El proceso del hook corre con el MISMO cwd que ".cwd" del input —
#      por eso ".cwd" es la fuente de verdad de BASE_DIR, no un dato que
#      haya que reconciliar contra `pwd` del propio proceso.
#   c. `"if": "Bash(git *)"` de hooks.json dispara igual con "cd X && git
#      …", "git -C X …" y prefijo de entorno en el texto — el filtro de
#      hooks.json es una optimización de latencia, nunca reemplaza la
#      validación de este archivo.
#
# Contrato de #86 (monorepo sin marcador de runner en la raíz — ni
# package.json, ni pyproject.toml/setup.py/pytest.ini): ver
# .planning/DESIGN.md "G. pre-commit-guard — #86" para la decisión completa
# y la tabla de tests (G1-G11). Resumen de las cinco reglas:
#   1. Si HAY marcador entre SESSION_DIR y TARGET_DIR (contrato de #73 más
#      arriba), nada cambia: mismo camino de siempre, incluido
#      workspace-scope.sh.
#   2. Si NO hay marcador en ese camino, se deriva un runner por cada
#      archivo con cambios locales, subiendo desde su directorio hasta
#      TARGET_DIR — nunca al revés (no se adivina "todo el repo").
#   3. Un archivo sin marcador en su camino se descarta, nunca bloquea: "no
#      bloquear cuando no se encuentra ninguno" es la decisión de #86, no un
#      hueco — bloquear rompería cualquier repo sin runner, incluido este
#      mismo (sin package.json ni pyproject.toml en ningún lado).
#   4. Con más de un directorio derivado, corren TODOS (nunca se corta en el
#      primer fallo) y cualquier fallo bloquea nombrando el/los directorios.
#   5. El presupuesto de tiempo (PRECOMMIT_TEST_BUDGET) se COMPARTE entre
#      todas las corridas de una misma invocación del hook, no se resetea
#      por directorio — ver GUARD_BUDGET_LEFT más abajo.
#   Salvedad conocida (igual que hooks/lib/workspace-scope.sh, ver su
#   comentario ~241-245): un path con espacios u otros caracteres especiales
#   llega C-quoteado en `git status --porcelain` y no matchea ningún
#   directorio real — esa suite en particular no corre, nunca peor que el
#   comportamiento sin #86 (ningún archivo corría nada).
#
# Fuera de alcance (documentado, no parcheado — no confundir con un hueco
# no advertido):
#   - Evasión deliberada (wrappers "bash -c", funciones "git()", "\g\it"):
#     mismo modelo de amenaza que hooks/lib/guard-matching.sh:19-22. Estos
#     guards protegen errores honestos del flujo del orchestrator/dev, no
#     un adversario con control del comando.
#   - Huecos del saneo COMPARTIDO (comillas desbalanceadas, heredoc con
#     delimitador a medias) que borran el comando real antes de que este
#     hook lo vea: #77, no de este archivo.
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
INPUT_CWD=$(echo "$INPUT" | jq -r '.cwd // empty')

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

# NUL en el comando (#77 §3): ver guard_command_has_nul en guard-matching.sh
# para por qué se detecta sobre $INPUT y no sobre $COMMAND.
if guard_command_has_nul "$INPUT"; then
  echo "BLOCKED: pre-commit-guard: el comando trae un byte NUL" >&2
  exit 2
fi

SANITIZED_COMMAND=$(guard_sanitize "$COMMAND")

# Solo interceptar comandos git commit. GIT_COMMIT_RE (#73) amplía el match
# original ("git\s+commit" a secas) para que también detecte invocaciones
# con opciones de árbol entre "git" y "commit" ("git -C <ruta> commit",
# "git --git-dir=... commit") y con prefijo de entorno ("GIT_DIR=... git
# commit") — antes de esto, esas formas no llegaban ni a este punto y el
# hook salía sin evaluar nada (ver DESIGN-pre-commit-target-tree.md "Contrato 1, Etapa A"). Un
# "git log | grep commit" o "git log --grep commit" siguen sin matchear:
# solo tokens con forma de opción de árbol ("-C", "--git-dir", "--work-tree")
# o un commit real cuentan, no cualquier texto entre "git" y "commit". El
# "\S*" (no "\S+") tras cada opción es deliberado: una ruta entre comillas
# la colapsa guard_sanitize (deja la opción sin valor pegado), y el detector
# tiene que seguir disparando para que la Etapa B (abajo) BLOQUEE esa forma
# en vez de dejarla salir por este "exit 0" sin evaluar nada.
#
# Terminador de comando pegado (#73 ronda 1, security MEDIUM): "commit"
# puede venir seguido directo de ";", "&", "|" o ")" sin espacio de por
# medio ("git commit;", "git commit&&git push", "(git commit)") — antes
# solo "\s" o fin de string cerraban el match, y esas formas se colaban sin
# interceptar. El charset no agrega "-" ni letras, así que "commit-tree" y
# "commit-graph" siguen sin matchear (ninguno de sus caracteres siguientes
# cae en "\s|\$|[;&|)]").
GIT_COMMIT_RE="${GUARD_ANCHOR}((GIT_DIR|GIT_WORK_TREE)=\S*\s+)*git\s+${GUARD_GIT_TREE_OPTS}commit(\s|\$|[;&|)])"
if ! echo "$SANITIZED_COMMAND" | grep -qE "$GIT_COMMIT_RE"; then
  exit 0
fi

# Resolución del árbol objetivo del commit (#73): este guard evaluaba
# siempre el cwd del PROCESO del hook, sin importar a qué árbol redirige el
# comando interceptado ("cd <ruta> && git commit", "git -C <ruta> commit").
# Ver .planning/DESIGN-pre-commit-target-tree.md "Contrato 1" para el detalle completo del
# resolver; este bloque resuelve el caso sin redirección en el texto del
# comando (BASE_DIR = ".cwd" del input, o el cwd del proceso si el harness
# no lo manda — comportamiento actual) y su toplevel real, para que un
# commit lanzado desde un subdirectorio del repo (en vez de la raíz) siga
# encontrando el test runner en vez de pasar sin tests.
TREE_FORM_HELP="Formas aceptadas: 'git commit …' en el cwd de la sesión; 'cd <ruta> && git commit …' (cd al inicio, una sola vez, ruta literal sin comillas/variables/espacios); 'git -C <ruta> commit …' (la misma ruta en cada git del comando). Alternativa: hacé el cd en una llamada Bash previa — el hook sigue el cwd de la sesión. No se resuelven --git-dir/--work-tree, GIT_DIR/GIT_WORK_TREE, pushd, subshells ni rutas con expansión."

_guard_block_tree() {
  echo "BLOCKED: pre-commit-guard no puede resolver en qué árbol va el commit: $1. ${TREE_FORM_HELP}" >&2
  exit 2
}

if [ -n "$INPUT_CWD" ]; then
  if [ ! -d "$INPUT_CWD" ]; then
    _guard_block_tree "el cwd del input no es un directorio ($INPUT_CWD)"
  fi
  BASE_DIR=$(cd "$INPUT_CWD" && pwd -P)
else
  BASE_DIR=$(pwd -P)
fi

# _guard_toplevel_or_base: toplevel real de $1 si cae dentro de un repo git;
# si no (repo corrupto, cwd fuera de un repo, "git" ausente), $1 tal cual —
# nunca falla abierto ni bloquea por esto, mismo criterio conservador del
# resto del hook.
_guard_toplevel_or_base() {
  local toplevel
  if toplevel=$(git -C "$1" rev-parse --show-toplevel 2>/dev/null); then
    printf '%s' "$toplevel"
    return 0
  fi
  printf '%s' "$1"
}

# _guard_resolve_dash_c: forma "git -C <ruta> commit" (allowlist B4 de
# DESIGN-pre-commit-target-tree.md). Devuelve por stdout la única ruta candidata y sale 0, o sale 1
# (sin salida) si el comando no califica para esta regla — el caller
# bloquea. Condiciones, todas exigidas (allowlist: lo que no calza, falla):
#   - Ninguna mención de "cd"/"pushd" en el saneado (mezclar formas no se
#     adivina, se bloquea).
#   - Ninguna invocación de "git commit" SIN "-C" en el mismo comando (un
#     "git commit" local junto a un "git -C X" a otro árbol es OTRO árbol,
#     no el mismo — defensa en profundidad, ver X15/(j) en test-hooks.sh).
#   - Extraer todas las ocurrencias "git -C <ruta>" del saneado y quedarse
#     con las rutas únicas (sort -u): tiene que haber EXACTAMENTE una — dos
#     ocurrencias con rutas distintas es "a qué árbol" ambiguo.
#   - La ruta cumple TREE_PATH_RE (ver abajo): sin comillas, "$", espacios
#     ni otro carácter que el shell interpretaría — así el artefacto de un
#     guard_sanitize sobre una ruta quoted (que colapsa el valor) nunca pasa
#     como si fuera una ruta real.
CD_PUSHD_RE="${GUARD_ANCHOR}(cd|pushd)(\s|;|&&|\$)"
BARE_COMMIT_RE="${GUARD_ANCHOR}git\s+commit"
TREE_PATH_RE='^[A-Za-z0-9_./-]+$'

_guard_resolve_dash_c() {
  echo "$SANITIZED_COMMAND" | grep -qE "$CD_PUSHD_RE" && return 1
  echo "$SANITIZED_COMMAND" | grep -qE "$BARE_COMMIT_RE" && return 1

  local paths count candidate
  paths=$(echo "$SANITIZED_COMMAND" | grep -oE "${GUARD_ANCHOR}git\s+-C\s+[^[:space:]]+" | sed -E 's/^.*-C[[:space:]]+//' | sort -u)
  count=$(printf '%s\n' "$paths" | grep -c .)
  [ "$count" -eq 1 ] || return 1

  candidate="$paths"
  echo "$candidate" | grep -qE "$TREE_PATH_RE" || return 1
  printf '%s' "$candidate"
}

# _guard_resolve_cd: forma "cd <ruta> && git commit …" / "cd <ruta>; …"
# (allowlist B3 de DESIGN-pre-commit-target-tree.md). Devuelve por stdout la ruta candidata y sale
# 0, o sale 1 (sin salida) si el comando no califica — el caller bloquea.
# Se valida sobre el comando CRUDO ($COMMAND, no el saneado): el saneado
# colapsa comillas y no preserva la forma que ejecuta el shell de verdad
# (retro PR-76), así que la ruta que termina en `cd "$ruta"` sale del texto
# real tal cual, nunca de un `eval`. El ancla `^cd[[:blank:]]+` exige "cd"
# al INICIO del comando con al menos un espacio/tab de separación — así
# "pushd …", "cd" no al inicio ("npm ci && cd …") y "cd" pelado sin
# argumento (sin nada entre "cd" y el terminador) nunca matchean esta
# regla y caen al bloqueo genérico (B5): no se adivina a qué apunta un
# "cd" que no tiene esta forma exacta.
_guard_resolve_cd() {
  # Exactamente UNA ocurrencia de "cd"/"pushd" en el saneado: dos "cd" en
  # el mismo comando compuesto (o un "cd" + un "pushd") es "a qué árbol"
  # ambiguo — mezclar formas no se adivina, se bloquea. Mismo criterio que
  # _guard_resolve_dash_c con "-C" repetido (ahí sí se permite si es la
  # MISMA ruta; acá ni se llega a comparar rutas, ninguna forma real del
  # issue necesita dos "cd").
  local occurrences count
  occurrences=$(echo "$SANITIZED_COMMAND" | grep -oE "$CD_PUSHD_RE")
  count=$(printf '%s\n' "$occurrences" | grep -c .)
  [ "$count" -eq 1 ] || return 1

  [[ "$COMMAND" =~ ^cd[[:blank:]]+([^[:space:]]+)[[:blank:]]*(\&\&|\;) ]] || return 1
  local raw_path="${BASH_REMATCH[1]}"

  # "cd -" (destino implícito, el directorio anterior) no es una ruta: es
  # un alias que depende de $OLDPWD del proceso, no del texto del comando.
  # Rechazo explícito en vez de dejarlo caer solo: bash igual reconoce "-"
  # como especial dentro de "cd \"$ruta\"" (comillas no lo neutralizan), y
  # confiar en que eso "por las buenas" termine bloqueando sería frágil —
  # depende de un efecto colateral (que "cd -" imprime la ruta nueva por
  # stdout, ensuciando la variable con dos líneas) y no de una regla.
  [ "$raw_path" = "-" ] && return 1

  # Prefijo "~/" (único caso de expansión permitido): se expande contra
  # $HOME del ENTORNO del hook, nunca con "eval" ni sub-shell sobre el
  # resto de la ruta — un "~/" a secas (sin nada detrás) no matchea este
  # case (le falta el "/" final) y sigue de largo tal cual, así que
  # termina fallando TREE_PATH_RE/la existencia del directorio más abajo
  # en vez de resolver a "$HOME" entero.
  case "$raw_path" in
    "~/"*) raw_path="$HOME${raw_path#\~}" ;;
  esac

  # TREE_PATH_RE (charset sin comillas/"$"/espacios/etc.): la ruta que
  # termina en `cd "$raw_path"` tiene que ser literal — nunca el artefacto
  # de algo que el shell habría expandido o citado.
  echo "$raw_path" | grep -qE "$TREE_PATH_RE" || return 1

  printf '%s' "$raw_path"
}

# "--git-dir"/"--work-tree"/"GIT_DIR="/"GIT_WORK_TREE=" nunca se resuelven
# (fuera de alcance por diseño, documentado en TREE_FORM_HELP): a diferencia
# de "-C", no hay forma de saber si valen para TODO el comando o solo para
# la invocación de "git" a la que están pegados sin parsear de verdad el
# shell — así que siempre bloquean, sin importar si acompañan al "git
# commit" real o aparecen en otra invocación del mismo comando compuesto
# (defensa en profundidad, reemplaza (j) parte 2 en test-hooks.sh). Mismo
# criterio para el entorno DEL PROCESO del hook (no el texto del comando):
# "pre-merge-check.sh" ya bloquea igual ante "GIT_DIR"/"GIT_WORK_TREE"
# seteadas ahí.
if [ -n "${GIT_DIR:-}" ] || [ -n "${GIT_WORK_TREE:-}" ]; then
  _guard_block_tree "GIT_DIR/GIT_WORK_TREE en el entorno del hook"
fi
if echo "$SANITIZED_COMMAND" | grep -qE -- "--git-dir|--work-tree"; then
  _guard_block_tree "--git-dir/--work-tree no se resuelven"
fi
if echo "$SANITIZED_COMMAND" | grep -qE "(^|\s|;|&&|\|)(GIT_DIR|GIT_WORK_TREE)="; then
  _guard_block_tree "GIT_DIR/GIT_WORK_TREE como prefijo de entorno en el comando no se resuelven"
fi

# Más de un "-C" pegado a la MISMA invocación de "git" antes del "commit"
# real (#73 ronda 1, informativo/security): "git -C O -C R commit" — git de
# verdad interpreta "-C" repetido de forma acumulativa (cada uno relativo
# al anterior), pero _guard_resolve_dash_c extrae "git\s+-C\s+[^[:space:]]+"
# una sola vez por cada "git" del comando, así que solo veía el PRIMER "-C"
# de esta invocación y trataba esa ruta como si fuera la única candidata —
# si esa primera ruta resultaba ser un repo real sin runner, el hook salía
# en 0 sin haber corrido nada sobre "R", el árbol al que el commit iba de
# verdad. No choca con la forma ya soportada de repetir "-C" en INVOCACIONES
# SEPARADAS de "git" con la MISMA ruta (test "misma ruta" más abajo en este
# archivo): ahí cada "git" lleva un solo "-C", así que "{2,}" no matchea.
MULTI_DASH_C_RE="${GUARD_ANCHOR}git(\s+-C\s+\S+){2,}\s+commit(\s|\$|[;&|)])"
if echo "$SANITIZED_COMMAND" | grep -qE "$MULTI_DASH_C_RE"; then
  _guard_block_tree "más de un '-C' en la misma invocación de 'git'"
fi

# Etapa B (resto): sin "-C" ni "cd"/"pushd" en el texto → camino rápido
# sobre BASE_DIR (toplevel real o BASE_DIR tal cual). Con "-C" → se
# resuelve con _guard_resolve_dash_c; con "cd"/"pushd" (y ninguna mención
# de "-C") → se resuelve con _guard_resolve_cd. Ambos casos validan que la
# ruta exista y sea un repo git real; cualquier falla bloquea SIN correr
# suites (a diferencia del camino rápido, acá no hay "correr de más"
# posible: no se sabe en qué árbol correr).
# SESSION_DIR (#73 ronda 1, security HIGH): el directorio real de la sesión
# antes de subir a TARGET_DIR (el toplevel) — BASE_DIR en el camino rápido,
# RESOLVED_DIR en las formas "-C"/"cd". _guard_find_runner_dir, más abajo,
# busca el test runner empezando ACÁ y subiendo hasta TARGET_DIR inclusive,
# en vez de mirar solo el toplevel. Antes de este fix, un layout con el
# runner solo en un subdirectorio ("frontend/package.json", sin
# "package.json" en la raíz) hacía que el hook subiera SIEMPRE al toplevel
# antes de buscar, no encontrara nada ahí y saliera en 0 sin correr tests
# — regresión fail-open contra `dev`, hallada por security-reviewer en la
# ronda 1 de #73. TARGET_DIR sigue siendo el árbol donde se evalúan
# git status/el salto de .planning/ (sin cambios: esos chequeos necesitan
# rutas relativas a la raíz del repo, no al subdirectorio de la sesión).
if echo "$SANITIZED_COMMAND" | grep -qE "${GUARD_ANCHOR}git\s+-C\s"; then
  DASH_C_PATH=$(_guard_resolve_dash_c) || _guard_block_tree "no se pudo resolver una única ruta de 'git -C' en el comando"
  RESOLVED_DIR=$(cd "$BASE_DIR" 2>/dev/null && cd "$DASH_C_PATH" 2>/dev/null && pwd -P) || _guard_block_tree "la ruta '$DASH_C_PATH' no existe"
  TARGET_DIR=$(git -C "$RESOLVED_DIR" rev-parse --show-toplevel 2>/dev/null) || _guard_block_tree "'$DASH_C_PATH' no es un repo git"
  SESSION_DIR="$RESOLVED_DIR"
elif echo "$SANITIZED_COMMAND" | grep -qE "$CD_PUSHD_RE"; then
  CD_PATH=$(_guard_resolve_cd) || _guard_block_tree "no se pudo resolver una única ruta de 'cd' al inicio del comando"
  RESOLVED_DIR=$(cd "$BASE_DIR" 2>/dev/null && cd "$CD_PATH" 2>/dev/null && pwd -P) || _guard_block_tree "la ruta '$CD_PATH' no existe"
  TARGET_DIR=$(git -C "$RESOLVED_DIR" rev-parse --show-toplevel 2>/dev/null) || _guard_block_tree "'$CD_PATH' no es un repo git"
  SESSION_DIR="$RESOLVED_DIR"
else
  TARGET_DIR=$(_guard_toplevel_or_base "$BASE_DIR")
  SESSION_DIR="$BASE_DIR"
fi

cd "$TARGET_DIR" || _guard_block_tree "no se pudo entrar al árbol resuelto ($TARGET_DIR)"

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

# _guard_planning_only_change lee "git status" del cwd DEL HOOK — que a esta
# altura ya es TARGET_DIR (la Etapa B de arriba resolvió el árbol real del
# commit, para CUALQUIER forma de la allowlist — camino rápido, "-C" o
# "cd"/"pushd" — y ya hizo "cd" ahí, o bloqueó antes de llegar a este
# punto). Ya no hace falta un bypass especial para "cd"/"pushd": antes de
# este fix (#73, Lote 2) el resolver no entendía esa forma, así que el
# salto se evaluaba a ciegas sobre BASE_DIR mientras el comando en realidad
# redirigía a otro árbol (verificado con git worktree real: árbol
# principal sucio solo bajo .planning/, worktree con código sucio, "cd $WT
# && git commit -am x" → saltaba sin correr suites). Ahora TARGET_DIR
# siempre es el árbol real del commit cuando se llega hasta acá.
if _guard_planning_only_change; then
  echo "Solo cambios en .planning/: sin suites." >&2
  exit 0
fi

# _guard_find_runner_dir (#73 ronda 1, security HIGH): busca el test runner
# empezando en SESSION_DIR y subiendo directorio por directorio hasta
# TARGET_DIR (el toplevel) inclusive, quedándose con la PRIMERA coincidencia
# (la más cercana a la sesión). "$1" (dir) siempre parte siendo descendiente
# de "$2" (top) o igual — lo garantiza cómo se calculó SESSION_DIR/TARGET_DIR
# más arriba (el segundo siempre es el toplevel real que contiene al
# primero) — el "case" es una red de seguridad ante un cómputo futuro que
# rompiera esa garantía: si "dir" deja de ser descendiente de "top" antes de
# llegar a él, corta y devuelve "top" en vez de seguir subiendo sin límite.
_guard_find_runner_dir() {
  local dir="$1" top="$2"
  while :; do
    if [ -f "$dir/package.json" ] || [ -f "$dir/pyproject.toml" ] || [ -f "$dir/setup.py" ] || [ -f "$dir/pytest.ini" ]; then
      printf '%s' "$dir"
      return 0
    fi
    [ "$dir" = "$top" ] && { printf '%s' "$top"; return 0; }
    case "$dir" in
      "$top"/*) : ;;
      *) printf '%s' "$top"; return 0 ;;
    esac
    dir="${dir%/*}"
    [ -z "$dir" ] && dir="/"
  done
}

# _guard_has_marker: mismo charset de marcadores que _guard_find_runner_dir,
# extraído para poder distinguir "encontró un marcador de verdad" de "no
# encontró ninguno y devolvió top por default" — _guard_find_runner_dir
# devuelve el MISMO valor (top) en los dos casos cuando no hay marcador en
# el camino, así que no hay otra forma de distinguirlos sin repetir el
# chequeo sobre el resultado.
_guard_has_marker() {
  local dir="$1"
  [ -f "$dir/package.json" ] || [ -f "$dir/pyproject.toml" ] || [ -f "$dir/setup.py" ] || [ -f "$dir/pytest.ini" ]
}

# _guard_derive_runner_dirs (#86, decisión en .planning/DESIGN.md "G."):
# cuando NINGÚN directorio entre SESSION_DIR y TARGET_DIR tiene marcador
# (workspace-scope.sh resuelve workspaces DECLARADOS en un package.json
# raíz, no descubre runners en subdirectorios sin marcador arriba — V3 de
# DESIGN.md), correr por archivo tocado en vez de no correr nada. Por cada
# línea de `git status --porcelain --no-renames --untracked-files=all` (ya
# corrido en TARGET_DIR — mismo criterio de timing que
# _guard_planning_only_change: este hook es PreToolUse, corre antes de que
# un "git add" pendiente en el mismo comando se ejecute), sube desde el
# directorio de ese archivo hasta TARGET_DIR con el mismo
# _guard_find_runner_dir; si la subida termina en TARGET_DIR (ya se sabe sin
# marcador, por eso se llegó hasta acá) se descarta ese archivo — "no
# bloquear cuando no se encuentra ninguno" es la decisión de #86, no un
# hueco. --no-renames (a diferencia de _guard_planning_only_change, que sí
# necesita distinguir un rename): acá solo importa bajo qué directorio cae
# cada archivo.
#
# Salvedad conocida (igual que hooks/lib/workspace-scope.sh, ver su
# comentario ~241-245): un path con caracteres especiales llega C-quoteado
# en `git status --porcelain` y no matchea ningún directorio real — se
# degrada a "no corre esa suite en particular", nunca peor que el
# comportamiento sin #86 (ningún archivo corría nada).
#
# Exclusiones (#86 ronda 2, review dual, security MEDIUM): tres formas de
# descartar un candidato ANTES de resolverlo, nunca bloquean, solo
# restringen de dónde se deriva un runner —
#   1. Directorio sin trackear entero: `git status --porcelain
#      --untracked-files=all` emite una sola línea que termina en "/" para
#      un directorio que NO desciende — el caso real es un repo git
#      anidado sin trackear (su propio ".git" hace que git no lo recorra);
#      resolverlo como archivo terminaba corriendo el runner DE ESE OTRO
#      REPO con el comando del usuario.
#   2. Repo git anidado por path: red de seguridad además de (1) — si algún
#      directorio entre el archivo y TARGET_DIR tiene su propio ".git" (un
#      caso que --untracked-files=all no colapsó, ej. un submódulo
#      trackeado con estado sucio), tampoco se deriva un runner ahí; ese
#      repo tiene su propio ciclo de test, no el del usuario.
#   3. Segmento de path no confiable: node_modules, vendor, fixtures,
#      __fixtures__ o testdata en cualquier parte del path — dependencias
#      de terceros y fixtures de test no son código del proyecto, así que
#      un package.json ahí (real, ej. un fixture de test trackeado a
#      propósito) no es un runner del usuario.
_guard_path_ends_in_slash() {
  case "$1" in
    */) return 0 ;;
    *) return 1 ;;
  esac
}

_guard_path_has_excluded_segment() {
  local path="$1" segment
  local IFS=/
  for segment in $path; do
    case "$segment" in
      node_modules|vendor|fixtures|__fixtures__|testdata) return 0 ;;
    esac
  done
  return 1
}

_guard_dir_under_nested_git() {
  local dir="$1" top="$2"
  while [ "$dir" != "$top" ] && [ -n "$dir" ] && [ "$dir" != "/" ]; do
    [ -e "$dir/.git" ] && return 0
    dir="${dir%/*}"
    [ -z "$dir" ] && dir="/"
  done
  return 1
}

_guard_derive_runner_dirs() {
  local top="$1"
  local files
  files=$(git status --porcelain --no-renames --untracked-files=all 2>/dev/null) || return 0
  [ -z "$files" ] && return 0

  local line path filedir candidate
  local candidates=()
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    path="${line:3}"
    _guard_path_ends_in_slash "$path" && continue
    _guard_path_has_excluded_segment "$path" && continue
    case "$path" in
      */*) filedir="$top/${path%/*}" ;;
      *) filedir="$top" ;;
    esac
    _guard_dir_under_nested_git "$filedir" "$top" && continue
    candidate=$(_guard_find_runner_dir "$filedir" "$top")
    [ "$candidate" = "$top" ] && continue
    candidates+=("$candidate")
  done <<< "$files"

  [ "${#candidates[@]}" -eq 0 ] && return 0
  printf '%s\n' "${candidates[@]}" | sort -u
}

RUNNER_DIR=$(_guard_find_runner_dir "$SESSION_DIR" "$TARGET_DIR")

GUARD_RUN_DIRS=()
if _guard_has_marker "$RUNNER_DIR"; then
  GUARD_RUN_DIRS=("$RUNNER_DIR")
else
  while IFS= read -r _guard_dir; do
    [ -z "$_guard_dir" ] && continue
    GUARD_RUN_DIRS+=("$_guard_dir")
  done < <(_guard_derive_runner_dirs "$TARGET_DIR")
fi

if [ "${#GUARD_RUN_DIRS[@]}" -eq 0 ]; then
  exit 0
fi

# Watchdog fail-closed por tiempo (auditoría best-practices): sin esto, una
# suite colgada supera el timeout del harness (hooks.json), que DESCARTA la
# salida del hook y deja pasar el commit sin tests (doc "Timeouts") — el
# hook nunca falla abierto por diseño, así que un cuelgue no puede ser la
# excepción. PRECOMMIT_TEST_BUDGET (default 540, env sobreescribible) es
# menor que el timeout de hooks.json (600) para que el watchdog interno
# siempre gane. Reusa la FORMA del watchdog de hooks/lib/guard-matching.sh
# (un temporizador que corta lo que corre más de la cuenta), no la lib: ahí
# es un alarm(5) de perl sobre sí mismo; acá hace falta matar un PROCESO
# EXTERNO (pytest/npm y sus hijos), así que el mecanismo es un job de bash
# en su propio grupo de procesos (`set -m`) + kill del grupo completo
# (`kill -- -$pgid`), no una señal a sí mismo — matar solo el pid de arriba
# (`kill -9 "$pid"`) deja a los hijos del test runner huérfanos corriendo.
# _guard_resolve_test_budget: valida PRECOMMIT_TEST_BUDGET antes de usarlo
# como cap del watchdog. Sin esto, un valor no numérico (p. ej. "abc") rompe
# la comparación "[ "$SECONDS" -ge "$budget" ]" de más abajo ("integer
# expression expected", que en un "if" cuenta como falso) y el watchdog
# nunca corta — el hueco lo cierra el timeout del harness (600s en
# hooks.json), que DESCARTA la salida y deja pasar el commit sin tests.
#
# Tope <= 570 (revisión pre-push, ronda 2, security MEDIUM): antes el tope
# era < 600, el mismo número que el timeout del harness. Con un budget en
# 590-599, el watchdog "gana" en el papel, pero el margen real es de
# segundos: el corte no es instantáneo — mide en pasos de `sleep 1` (o de
# ida y vuelta de $SECONDS, ver más abajo) y encima corre `kill -TERM`, un
# `sleep 1` de gracia y `kill -KILL` antes de poder responder al harness. Un
# budget de 599 con ese overhead puede terminar respondiendo después de los
# 600s del harness, que ya descartó la salida del hook — el mismo hueco que
# esto existe para cerrar. 570 deja 30s de colchón para el overhead de
# corte + cleanup, nunca ajustado al límite exacto del timeout externo.
_guard_resolve_test_budget() {
  local raw="${PRECOMMIT_TEST_BUDGET:-}"
  if [ -z "$raw" ]; then
    echo 540
    return 0
  fi
  if [[ "$raw" =~ ^[0-9]+$ ]] && [ "$raw" -le 570 ]; then
    echo "$raw"
    return 0
  fi
  echo "PRECOMMIT_TEST_BUDGET=\"$raw\" inválido (debe ser un entero <= 570); usando el default 540." >&2
  echo 540
  return 0
}

# GUARD_BUDGET_LEFT (#86, T4): presupuesto COMPARTIDO entre corridas. Sin
# esto, un monorepo con dos runners que corren cada uno por debajo del
# budget individual (2s + 2s con PRECOMMIT_TEST_BUDGET=3) pasaba sin bloquear
# aunque el TOTAL (4s) superara el presupuesto — cada llamada resolvía su
# propio budget desde cero. Se resuelve una sola vez (la primera llamada de
# este hook, para cualquier directorio) y cada llamada posterior recibe lo
# que quedó, restando el tiempo real que tardó la corrida anterior
# ($SECONDS, ya medido más abajo con el mismo criterio del comentario de la
# ronda 2).
_guard_run_with_budget() {
  if [ -z "${GUARD_BUDGET_LEFT+x}" ]; then
    GUARD_BUDGET_LEFT=$(_guard_resolve_test_budget)
  fi
  local budget="$GUARD_BUDGET_LEFT"
  local outfile pgid_file
  outfile=$(mktemp)
  pgid_file=$(mktemp)

  (
    set -m
    "$@" > "$outfile" 2>&1 &
    job_pid=$!
    echo "$job_pid" > "$pgid_file"
    wait "$job_pid"
  ) &
  local runner_pid=$!

  # Ronda 2 (revisión pre-push, security MEDIUM): "waited" contaba VUELTAS de
  # loop, no segundos reales — cada vuelta es un "sleep 1" más lo que tarde
  # el propio "kill -0" y la comparación, así que con budget alto el drift
  # se acumula y el corte real llega más tarde que "budget" segundos. $SECONDS
  # es un contador de bash de tiempo real desde que se resetea (acá, desde
  # el inicio de este loop) — mide el reloj de pared en vez de vueltas, así
  # que el corte ocurre cuando realmente pasaron "budget" segundos, no
  # cuando pasaron "budget" iteraciones de un loop con overhead variable.
  SECONDS=0
  while kill -0 "$runner_pid" 2>/dev/null; do
    if [ "$SECONDS" -ge "$budget" ]; then
      local job_pgid
      job_pgid=$(cat "$pgid_file" 2>/dev/null)
      if [ -n "$job_pgid" ]; then
        kill -TERM -- "-$job_pgid" 2>/dev/null
        sleep 1
        kill -KILL -- "-$job_pgid" 2>/dev/null
      fi
      kill -KILL "$runner_pid" 2>/dev/null
      cat "$outfile"
      echo "BLOCKED: la suite superó ${budget}s; el hook no falla abierto. Acotá la suite o subí PRECOMMIT_TEST_BUDGET." >&2
      rm -f "$outfile" "$pgid_file"
      exit 2
    fi
    sleep 1
  done

  wait "$runner_pid" 2>/dev/null
  local rc=$?
  cat "$outfile"
  rm -f "$outfile" "$pgid_file"
  GUARD_BUDGET_LEFT=$((GUARD_BUDGET_LEFT - SECONDS))
  [ "$GUARD_BUDGET_LEFT" -lt 0 ] && GUARD_BUDGET_LEFT=0
  return "$rc"
}

# _guard_run_suite_in (#86, extraído de lo que antes era código inline que
# solo corría una vez, sobre RUNNER_DIR): detecta y corre el runner de UN
# directorio. Devuelve 0 si no hay nada que correr o si corrió y pasó, 1 si
# corrió y falló — nunca hace "exit" (salvo el watchdog de
# _guard_run_with_budget, que sí corta el hook entero por diseño): con más
# de un directorio (#86) el resto tiene que correr igual antes de decidir,
# mismo criterio de "correr de más, nunca de menos" que el resto del hook, y
# necesario para que el budget compartido (ver _guard_run_with_budget) cuente
# el tiempo real de TODAS las corridas, no solo la primera.
_guard_run_suite_in() {
  local dir="$1"
  local prev_pwd
  prev_pwd=$(pwd)
  cd "$dir" || return 1

  local rc=0
  if [ -f "package.json" ]; then
    # Node.js project — detectar package manager
    local pkg_mgr
    if [ -f "pnpm-lock.yaml" ]; then
      pkg_mgr="pnpm"
    elif [ -f "yarn.lock" ]; then
      pkg_mgr="yarn"
    else
      pkg_mgr="npm"
    fi

    if jq -e '.scripts.test' package.json > /dev/null 2>&1; then
      local test_cmd
      test_cmd=$(jq -r '.scripts.test' package.json)
      if [ "$test_cmd" != "null" ] && [ "$test_cmd" != "" ] && [ "$test_cmd" != "echo \"Error: no test specified\" && exit 1" ]; then
        # Scoping por workspace en monorepos: correr "$pkg_mgr test" en la
        # raíz de un monorepo dispara TODAS las suites en cada commit, aunque
        # el commit toque un solo workspace. hooks/lib/workspace-scope.sh
        # resuelve, con criterio conservador, si el commit se puede acotar a
        # los workspaces realmente tocados.
        #
        # A diferencia de guard-matching.sh más arriba, esta lib NO es
        # fail-closed: si no existe, no es legible, o no logra resolver un
        # subconjunto con confianza, simplemente no se activa el scoping y se
        # sigue el camino de siempre ($pkg_mgr test) — nunca bloquea el
        # commit por su ausencia.
        local scoped=false
        local ws_lib="${0%/*}/lib/workspace-scope.sh"
        if [ -r "$ws_lib" ]; then
          # shellcheck source=lib/workspace-scope.sh
          source "$ws_lib"
          workspace_scope_resolve "$pkg_mgr" && scoped=true
        fi

        if [ "$scoped" = true ]; then
          echo "Running tests before commit ($pkg_mgr, workspace(s): $WORKSPACE_SCOPE_LABEL) [$dir]..." >&2
          _guard_run_with_budget "${WORKSPACE_SCOPE_CMD[@]}"
        else
          echo "Running tests before commit ($pkg_mgr) [$dir]..." >&2
          _guard_run_with_budget "$pkg_mgr" test
        fi
        rc=$?
        [ "$rc" -eq 0 ] && echo "Tests passed [$dir]." >&2
      fi
    fi
  elif [ -f "pytest.ini" ] || [ -f "pyproject.toml" ] || [ -f "setup.py" ]; then
    # Python project
    if command -v pytest > /dev/null 2>&1; then
      echo "Running pytest before commit [$dir]..." >&2
      _guard_run_with_budget pytest
      rc=$?
      [ "$rc" -eq 0 ] && echo "Tests passed [$dir]." >&2
    fi
  fi

  cd "$prev_pwd" || true
  return "$rc"
}

# Corre cada directorio resuelto arriba (GUARD_RUN_DIRS): uno solo en el
# camino de siempre (marcador encontrado entre SESSION_DIR y TARGET_DIR), o
# varios derivados por archivo tocado cuando no había marcador (#86, T2).
# Cualquier fallo bloquea nombrando el/los directorio(s) — se corren TODOS
# antes de decidir, no se corta en el primer fallo (necesario para el budget
# compartido de T4).
GUARD_FAILED_DIRS=()
for _guard_dir in "${GUARD_RUN_DIRS[@]}"; do
  _guard_run_suite_in "$_guard_dir" || GUARD_FAILED_DIRS+=("$_guard_dir")
done

if [ "${#GUARD_FAILED_DIRS[@]}" -gt 0 ]; then
  echo "BLOCKED: Tests failed in: ${GUARD_FAILED_DIRS[*]}. Fix tests before committing." >&2
  exit 2
fi

exit 0
