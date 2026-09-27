## Diseño: #73 — el pre-commit-guard valida el árbol al que va el commit, no el cwd de la sesión

### Resumen

`hooks/pre-commit-guard.sh` resuelve el árbol objetivo del `git commit` a partir de una **allowlist de tres formas** (cwd del input, `cd <ruta> &&` al inicio, `git -C <ruta>`), corre `git status` y el runner ahí, y bloquea con mensaje accionable ante cualquier otra redirección. `hooks/pre-merge-check.sh` deja de confiar a ciegas en el cwd del proceso: si el `cwd` del input no coincide, exige `--repo`. El saneo compartido (`guard-matching.sh`) no se toca (es de #77).

### Verificaciones empíricas (hechas, no deducidas)

Entorno: Claude Code 2.1.283, macOS, `claude -p` en modo de permisos **default** (sin `--dangerously-skip-permissions`), proyecto temporal en el scratchpad con un hook `PreToolUse` sobre `Bash` que vuelca stdin, `pwd -P` y `CLAUDE_PROJECT_DIR` a un log. Doc consultada: `https://code.claude.com/docs/en/hooks.md` (campo `cwd` en "Common input fields"; nota "Worktrees are different: `cwd` follows Claude"; "Handlers run in the current directory").

| # | Pregunta | Resultado |
|---|----------|-----------|
| a1 | ¿El JSON de un `PreToolUse`/`Bash` trae `cwd`? | **Sí.** Campos observados: `session_id, transcript_path, cwd, scratchpad_dir, prompt_id, permission_mode, effort, hook_event_name, tool_name, tool_input{command,description}, tool_use_id`. |
| a2 | ¿`cwd` refleja el `cd` persistido de una llamada Bash anterior? | **Sí.** Llamada 1 `cd <proyecto>/other && pwd`, llamada 2 `pwd`: en la 2 el hook recibió `cwd=<proyecto>/other`. Mismo resultado hacia un directorio fuera del proyecto agregado con `--add-dir`. |
| a3 | ¿Y `cd` fuera de los directorios de trabajo? | La herramienta Bash lo **rechaza** en modo default ("cd in '…' was blocked. For security, Claude Code may only change directories to the allowed working directories"); `cwd` no cambia. Un `cd` a otro repo solo persiste si ese directorio es de trabajo (`--add-dir`, `/add-dir`) o si el usuario lo aprueba interactivamente. |
| b | ¿Con qué cwd corre el proceso del hook? | **El mismo valor que `cwd` del input**, en las tres corridas (`pwd -P` del hook == `.cwd`). `CLAUDE_PROJECT_DIR` se queda en la raíz de la sesión aunque el cwd cambie. |
| c | ¿`if: "Bash(git *)"` de `hooks.json` dispara con prefijo de variable / `cd` / `-C`? | **Sí** para `git --version`, `FOO=1 git --version`, `cd X && git --version` y `git -C X --version` (hook con `if` y hook sin `if` registraron los mismos 4 comandos). Un chequeo de `GIT_DIR=… git commit` en el texto sí llega a ejecutarse. |

Implicación para el diseño: `.cwd` es la fuente de verdad del directorio de la sesión; el proceso ya corre ahí. Los subagentes tienen el cwd reseteado entre llamadas, así que su forma habitual de commit es `cd <ruta absoluta> && git commit …` en una sola llamada: esa forma **tiene** que estar en la allowlist.

### Search-first

Se salta: es un fix sobre hooks existentes (bash), sin dependencias nuevas. El patrón a seguir ya está decidido en el repo: allowlist de formas sobre texto crudo (retro PR-76, gramática única de `pre-merge-check.sh`), y cada fix de guard con sus casos negativos (retro PR-79).

### Arquitectura

Sin cambio. Hooks bash `PreToolUse` fail-closed (stderr + `exit 2`), tests en `tests/adversarial/test-hooks.sh` con binarios reales en directorios temporales.

### Archivos afectados

- `hooks/pre-commit-guard.sh` — resolución del árbol objetivo (reemplaza el bloque "comando redirige a otro árbol: camino normal" de las líneas 118-152), detector de commit ampliado, chequeo de `GIT_DIR`/`GIT_WORK_TREE`, `cd` al árbol resuelto antes del salto `.planning/` y del runner. Header y comentarios que hoy afirman "status quo #212" se reescriben (verificar antes de afirmar).
- `hooks/pre-merge-check.sh` — punto 7 del header (evidencia de a/b) + chequeo `cwd` del input vs cwd del proceso cuando no hay `--repo`. La gramática única (D-04) no cambia.
- `tests/adversarial/test-hooks.sh` — helpers con `cwd` opcional en el JSON, marcador con `pwd` del runner, segundo repo temporal, casos nuevos y expectativas actualizadas (lista abajo).
- `README.md` — fila de `pre-commit-guard` y `pre-merge-check` (lo hace `docs` en Fase 2.5, no los lotes).
- **No se toca:** `hooks/lib/guard-matching.sh` (saneo compartido, #77), `hooks/lib/workspace-scope.sh` (sigue corriendo desde el cwd que el hook ya fijó), `hooks/hooks.json`.

### Contrato 1 — `pre-commit-guard.sh`: resolución del árbol objetivo

#### Directorio base

```bash
INPUT_CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
if [ -n "$INPUT_CWD" ]; then
  [ -d "$INPUT_CWD" ] || block "…el cwd del input ($INPUT_CWD) no es un directorio…"
  BASE_DIR=$(cd "$INPUT_CWD" && pwd -P)
else
  BASE_DIR=$(pwd -P)          # JSON sin cwd (tests, versiones viejas del CLI): comportamiento actual
fi
```

`BASE_DIR` es el cwd persistido de la sesión (verificado a2/b). Un `cd` hecho en una llamada Bash **anterior** llega por acá sin parsear nada: es el escape que recomienda el mensaje de bloqueo.

#### Etapa A — ¿el comando commitea? (detector, sobre `SANITIZED_COMMAND`)

Reemplaza `${GUARD_ANCHOR}git\s+commit` por un detector que también ve las invocaciones con opciones de árbol y prefijo de entorno, para que esas formas lleguen a la etapa B en vez de salir por `exit 0` (hoy `git -C X commit` y `git --git-dir=… commit` **no se interceptan**, tests (h)/(i)):

```bash
GIT_COMMIT_RE="${GUARD_ANCHOR}((GIT_DIR|GIT_WORK_TREE)=\S*\s+)*git\s+((-C|--git-dir|--work-tree)(=\S*|\s+\S*)?\s+)*commit(\s|\$)"
```

- Solo tokens con forma de opción de árbol entre `git` y `commit`: `git log | grep commit`, `git log --grep commit` no matchean (no bloquear lecturas de git es un caso negativo obligatorio).
- `\S*` (no `\S+`) tras `-C`: una ruta entre comillas la colapsa el saneo (`git -C "/a b" commit` → `git -C   commit`) y el detector igual tiene que dispararse para que la etapa B **bloquee**; con `\S+` esa forma saldría por `exit 0` sin tests.
- Sigue usando `guard_sanitize` y `GUARD_ANCHOR` tal cual: una mención en mensaje/heredoc no cuenta (tests existentes).

#### Etapa B — ¿a qué árbol? (resolver, allowlist)

Primero, entorno del proceso del hook (mismo criterio que `pre-merge-check.sh`):

```bash
[ -n "${GIT_DIR:-}" ] || [ -n "${GIT_WORK_TREE:-}" ] → block (GIT_DIR/GIT_WORK_TREE en el entorno del hook)
```

Luego, ¿hay redirección en el texto saneado?

```bash
REDIRECT_RE="${GUARD_ANCHOR}(cd|pushd)(\s|;|&&|\$)|${GUARD_ANCHOR}git\s+-C(\s|=|\$)|--git-dir|--work-tree|(^|\s|;|&&|\|)(GIT_DIR|GIT_WORK_TREE)="
```

- **Sin redirección → `TARGET_DIR=$BASE_DIR`.** Camino rápido: es el commit normal en el cwd de la sesión, y tiene que comportarse **exactamente como hoy** (salto `.planning/`, runner, workspace-scope, fake git que falla → corre suites).
- **Con redirección →** `_guard_resolve_target` devuelve un directorio o falla, y un fallo bloquea con `TREE_FORM_HELP` (abajo) **sin correr suites** — no hay "corre de más" posible cuando no se sabe en qué árbol correr.

`_guard_resolve_target`, en este orden (cada regla es allowlist; lo que no calza, falla):

| Regla | Condición (texto) | Resultado |
|-------|-------------------|-----------|
| B1 | `--git-dir` / `--work-tree` / `GIT_DIR=` / `GIT_WORK_TREE=` en el saneado | falla (siempre) |
| B2 | `pushd` en el saneado | falla |
| B3 `cd` prefijo | **Crudo** `[[ "$COMMAND" =~ ^cd[[:blank:]]+([^[:space:]]+)[[:blank:]]*(\&\&|\;) ]]`; la ruta capturada cumple `TREE_PATH_RE` tras expandir solo el prefijo `~/`→`$HOME/`; no es `-`; en el **saneado** hay exactamente **una** ocurrencia de `${GUARD_ANCHOR}(cd|pushd)(\s|;|&&|$)` y **ninguna** de `git -C` | candidato = ruta, relativa a `BASE_DIR` |
| B4 `git -C` | Ninguna ocurrencia de `cd`/`pushd` en el saneado; `grep -oE "${GUARD_ANCHOR}git[[:blank:]]+-C[[:blank:]]+[^[:space:]]+"` sobre el saneado → rutas; `sort -u` deja **exactamente una**; cumple `TREE_PATH_RE`; el saneado **no** tiene `${GUARD_ANCHOR}git\s+commit` (un commit sin `-C` en el mismo comando sería otro árbol) | candidato = ruta, relativa a `BASE_DIR` |
| B5 | cualquier otra cosa (`cd` no al inicio, dos `cd`, `(cd X && …)`, `cd X \n git commit`, `cd` pelado, `cd -`, ruta con comillas/`$`/espacios/globs, `-C` con rutas distintas) | falla |
| B6 | candidato: `dir=$(cd "$BASE_DIR" && cd "$ruta" && pwd -P)` existe; `git -C "$dir" rev-parse --show-toplevel` responde | `TARGET_DIR` = ese toplevel; si no, falla (ruta inexistente / no es repo) |

```bash
TREE_PATH_RE='^[A-Za-z0-9_./-]+$'   # literal: sin comillas, $, `, \, espacios, ~ (salvo ~/ inicial), * ? [ { !
```

Por qué así:

- La forma `cd` se valida sobre el **crudo** (retro PR-76: el saneado colapsa comillas y no preserva la forma que ejecuta el shell); el charset excluye todo lo que el shell expandiría o citaría, así que la ruta que se usa en `cd "$ruta"` es literal. Nunca `eval`.
- La forma `-C` se extrae del **saneado** (el mensaje de commit puede mencionar `-C`), y el charset garantiza que un artefacto del saneo (ruta colapsada, token pegado) no pase: falla la regla, bloquea.
- "Un árbol por comando": mezclar `git -C X` con un `git commit` sin `-C`, o dos `cd`, no se adivina — se bloquea con el mensaje. Cambia el resultado de tres tests contrivados (ver lista), no de un flujo real.
- No se interpretan `cd` en medio del comando, subshells, `pushd`, variables ni `cd -`: es exactamente la carrera que perdió el PR #76.

Con `TARGET_DIR` resuelto:

```bash
cd "$TARGET_DIR" || block "…"
```

y **todo lo que sigue queda igual** (`_guard_planning_only_change`, detección del runner, `workspace_scope_resolve`, `_guard_run_with_budget`): opera sobre el árbol resuelto porque corre desde él. El salto "solo `.planning/`" se evalúa sobre `TARGET_DIR`, que es el caso del issue (worktree con código sucio + árbol principal sucio solo en `.planning/`, y su inverso).

Toplevel también en el camino rápido: si `git -C "$BASE_DIR" rev-parse --show-toplevel` responde, `TARGET_DIR` es ese toplevel; si falla (no es repo, `git` falso de los tests), `TARGET_DIR=$BASE_DIR` como hoy. Cierra un hueco hermano de #73 con una línea: con la sesión parada en un subdirectorio, hoy `[ -f package.json ]` no encuentra el runner y el commit pasa sin tests.

#### Mensaje de bloqueo (contrato: los tests hacen `grep -F` de "Formas aceptadas")

```
BLOCKED: pre-commit-guard no puede resolver en qué árbol va el commit. Formas aceptadas: 'git commit …' en el cwd de la sesión; 'cd <ruta> && git commit …' (cd al inicio, una sola vez, ruta literal sin comillas/variables/espacios); 'git -C <ruta> commit …' (la misma ruta en cada git del comando). Alternativa: hacé el cd en una llamada Bash previa — el hook sigue el cwd de la sesión. No se resuelven --git-dir/--work-tree, GIT_DIR/GIT_WORK_TREE, pushd, subshells ni rutas con expansión.
```

Variantes con la razón concreta al inicio (`ruta no existe: <ruta>`, `no es un repo git: <dir>`, `GIT_DIR/GIT_WORK_TREE en el entorno del hook`, `el cwd del input no es un directorio`) seguidas del mismo texto de formas.

#### Fuera de alcance (documentado en el header, no parcheado)

- Evasión deliberada (wrappers `bash -c`, funciones `git()`, `\g\it`): mismo modelo de amenaza que `guard-matching.sh:19-22`.
- Huecos del saneo compartido (comillas desbalanceadas, heredoc con delimitador a medias): #77.

### Contrato 2 — `pre-merge-check.sh` sin `--repo`

No cambia la forma única. Se agrega, junto al chequeo de `GIT_DIR`/`GIT_WORK_TREE` (que ya tiene la misma semántica "con `--repo` explícito no aplica"):

```bash
INPUT_CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
if [ -z "$EXPLICIT_REPO" ] && [ -n "$INPUT_CWD" ]; then
  PROC_CWD=$(pwd -P)
  IN_CWD=$(cd "$INPUT_CWD" 2>/dev/null && pwd -P)
  if [ -z "$IN_CWD" ] || [ "$IN_CWD" != "$PROC_CWD" ]; then
    block "Blocked: el cwd del comando (${INPUT_CWD}) no coincide con el directorio donde corre este hook (${PROC_CWD}); sin --repo explícito el guard no sabe qué repo verificar. Usa --repo owner/repo. ${MERGE_FORM_HELP}"
  fi
fi
```

- Coinciden (lo verificado en b): `gh repo view` corre donde siempre. Cero cambio de comportamiento en el caso normal.
- No coinciden o `.cwd` no es un directorio: bloquea con 0 consultas y pide `--repo` — fail-closed sobre la discrepancia que #77 §4 dejó sin verificar.
- `.cwd` ausente: comportamiento actual.
- Header, punto 7: registrar la evidencia de a/b (CLI 2.1.283, tres corridas) y marcar cerrado el §4 de #77 en lo que respecta a este hook.

### Schemas de validación

No aplica (bash; los contratos son las regex, el charset y los mensajes de arriba).

### Esquema DB

No aplica.

### Frontend

No aplica.

### Tests (`tests/adversarial/test-hooks.sh`)

**Infra:**

- `assert_blocked_cmd` / `assert_allowed_cmd` (y los asserts de pre-merge) aceptan un `cwd` opcional para el JSON (sugerido: variable `HOOK_JSON_CWD`; si está seteada, `jq … + {cwd: $cwd}`). Sin ella el JSON queda como hoy.
- `_pskip_setup`: el script `test` escribe `pwd -P` en `$PSKIP_MARK/test.ran` (hoy escribe `ran`). Nuevo `_pskip_assert_marker_tree <esperado>`: existe **y** su contenido es el toplevel esperado. Sin esto (g) pasa aunque el runner corra en el árbol equivocado — es la señal que distingue el fix (retro PR-76: cada test afirma qué consultó el hook).
- `_pskip_setup_other`: segundo repo temporal, hermano de `PSKIP_DIR` (mismo `mktemp` padre, para `cd ../<nombre>`), con runner que siempre falla y escribe `pwd -P` al mismo marcador; `src/` sucio.
- Además del exit code, cada caso "bloquea sin correr" afirma `test.ran` ausente **y** que stderr contiene `Formas aceptadas`.

**pre-commit-guard — resuelven (runner corre en el árbol correcto, o salto evaluado ahí):**

| Caso | Setup | Comando (cwd proceso = árbol principal) | Esperado |
|------|-------|------------------------------------------|----------|
| R1 worktree, `cd` | principal sucio solo `.planning/`, WT con `src/` sucio | `cd $WT && git commit -am x` | exit 2, marcador = `$WT` (reemplaza (g), que hoy solo mira que corrió) |
| R2 inverso | principal con `src/` sucio, WT sucio solo `.planning/` | `cd $WT && git commit -am x` | exit 0, sin runner (salto evaluado en el WT) |
| R3 `;` y `add` | como R1 | `cd $WT; git add -A && git commit -m x` | exit 2, marcador = `$WT` |
| R4 heredoc | como R1 | `cd $WT && git commit -m "$(cat <<'EOF'\nmsg con cd /x && git commit\nEOF\n)"` | exit 2, marcador = `$WT` |
| R5 `git -C` | como R1 | `git -C $WT commit -am x` | exit 2, marcador = `$WT` (reemplaza (h)) |
| R6 `-C` repetido | como R1 | `git -C $WT add -A && git -C $WT commit -m x` | exit 2, marcador = `$WT` |
| R7 `-C` inverso | como R2 | `git -C $WT commit -am x` | exit 0, sin runner |
| R8 `.cwd` del input | como R1, `HOOK_JSON_CWD=$WT`, proceso en principal | `git commit -am x` | exit 2, marcador = `$WT` |
| R9 otro repo, relativo | `OTHER` hermano con `src/` sucio | `cd ../$(basename $OTHER) && git commit -am x` | exit 2, marcador = `$OTHER` |
| R10 `~/` | `HOME=<tmp>` con `OTHER` adentro | `cd ~/$(basename $OTHER) && git commit -am x` | exit 2, marcador = `$OTHER` |
| R11 subdirectorio | proceso en `$PSKIP_DIR/src`, `src/` sucio | `git commit -am x` | exit 2, marcador = `$PSKIP_DIR` (hoy pasa sin tests) |

**pre-commit-guard — bloquean sin correr suites (exit 2, sin marcador, stderr con `Formas aceptadas`):**

| Caso | Comando |
|------|---------|
| X1 `--git-dir`/`--work-tree` | `git --git-dir=$WT/.git --work-tree=$WT commit -am x` (reemplaza (i)); también con espacio `--work-tree $WT` y solo `--work-tree` |
| X2 entorno en texto | `GIT_DIR=$WT/.git git commit -am x` |
| X3 entorno del proceso | `env GIT_WORK_TREE=$WT` al hook, comando `git commit -am x` |
| X4 `pushd` | `pushd $WT && git commit -am x` (reemplaza (g2)) |
| X5 `cd` pelado | `cd; git commit -am x`, `cd&&git commit -am x`, `cd\ngit commit -am x`, `cd && git commit -am x` (reemplazan (g3)-(g6)) |
| X6 `cd -` | `cd - && git commit -am x` |
| X7 subshell | `(cd $WT && git commit -am x)` |
| X8 `cd` no al inicio | `npm ci && cd $WT && git commit -am x` |
| X9 dos `cd` | `cd $WT && git commit -am x && cd -` |
| X10 `cd` + newline | `cd $WT\ngit commit -am x` |
| X11 ruta con `$` | `cd $WT_VAR && git commit -am x` (literal `$WT_VAR`) |
| X12 ruta entre comillas | `cd "$WT" && git commit -am x` (comillas literales) y `git -C "$WT" commit -am x` (el artefacto del saneo tiene que bloquear, no salir por exit 0) |
| X13 ruta con espacio | `cd "/a b" && git commit -am x` |
| X14 ruta inexistente / no repo | `git -C /nonexistent commit -am x`; `cd <tmp vacío> && git commit -am x` |
| X15 mezcla de árboles | `git -C $WT status; git commit -am x` (reemplaza (j)); `git -C $WT add -A && git -C $OTHER commit -m x` |
| X16 `.cwd` inválido | `HOOK_JSON_CWD=/nonexistent`, `git commit -am x` |

**pre-commit-guard — negativos (sin cambio de comportamiento; los existentes siguen verdes y se agregan los que faltan):**

- Commit normal en el cwd: salto `.planning/`, `.planning/` + código, untracked, renames, `--allow-empty`, `git status` falso que falla → corre suites (todos existentes).
- `echo "cd x" && git commit -am x` sigue saltando (existente, (g6b)); `git commit -m "cd /tmp && git commit"` y `git commit -m "git -C /x commit"` van por el camino rápido (nuevos).
- Mención en heredoc no se intercepta (existente).
- `git log | grep commit`, `git log --grep commit`, `git show HEAD` → exit 0 sin runner (nuevos).
- Watchdog, budget inválido, fail-closed sin jq, workspace-scope (existentes, sin tocar).

**pre-merge-check (gh falso con log, sin red):**

| Caso | JSON `cwd` | Comando | Esperado |
|------|------------|---------|----------|
| M1 | = cwd del proceso (`pwd -P`, por symlink de macOS) | `gh pr merge 5` | continúa, log con `repo view` y `--repo session/repo` |
| M2 | otro directorio existente | `gh pr merge 5` | bloquea, 0 consultas, stderr con `--repo` |
| M3 | inexistente | `gh pr merge 5` | bloquea, 0 consultas |
| M4 | otro directorio | `gh pr merge 5 --repo o/r` | continúa consultando `o/r` (el `--repo` es el remedio) |
| M5 | ausente | `gh pr merge 5` | continúa (comportamiento actual; ya cubierto, se deja explícito) |

**Expectativas existentes que cambian** (para que QA compare contra `dev` y no las dé por borradas): (g) pasa a afirmar el árbol del marcador; (g2)-(g6) pasan de "bloquea y corre" a "bloquea sin correr"; (h) pasa de "no intercepta" a "bloquea y corre en el WT"; (i) pasa de "no intercepta" a "bloquea sin correr"; (j) pasa de "bloquea y corre" a "bloquea sin correr". Los comentarios de esos tests que citan "#212 status quo" se reescriben.

**Rojo→verde:** cada tarea nombra el hunk que revierte y el test que se pone rojo. Ejemplo: quitar `cd "$TARGET_DIR"` deja R1 verde por exit pero rojo por el marcador (`$PSKIP_DIR` en vez de `$WT`).

### Plan de implementación

**Estrategia de PR:** single-PR (branch `fix/pre-commit-target-tree`, base `dev`). Los tres lotes tocan `test-hooks.sh`; secuenciales, mismo dev.

**Verificación en cada lote:** `bash tests/adversarial/test-hooks.sh` completo (no solo la sección tocada: issue #77, "Criterio de cierre") + `bash tests/adversarial/test-plugin-manifest.sh` + `claude plugin validate --strict .`. Reglas `~/.claude/rules/bash.md` (fail-closed, quoting, `$?` inmediato, portabilidad macOS).

#### Lote 1 — pre-commit-guard: árbol base y forma `git -C` (backend-dev)
**Depende de:** ninguno

- [ ] Tarea 1: infra + árbol base. Marcador con `pwd -P` y `_pskip_assert_marker_tree`; `HOOK_JSON_CWD` en los asserts; `BASE_DIR` desde `.cwd` del input (R8, X16) y toplevel en el camino rápido (R11). Rojo→verde: sin `.cwd` → R8 corre en el principal.
- [ ] Tarea 2: detector `GIT_COMMIT_RE` + forma `git -C <ruta>` resuelta con worktree real (R5, R6, R7). Revertir el detector deja R5 en `exit 0` sin runner.
- [ ] Tarea 3: `git -C` irresoluble bloquea sin correr, con `Formas aceptadas` en stderr: ruta inexistente (X14), `$` (X11), entre comillas (X12 `-C`), rutas distintas y mezcla con `git commit` sin `-C` (X15; reemplaza (j)).
- [ ] Tarea 4: `--git-dir`/`--work-tree` en texto (X1, reemplaza (i)), `GIT_DIR=`/`GIT_WORK_TREE=` en texto (X2) y en el entorno del proceso (X3) bloquean sin correr.
- [ ] Tarea 5: negativos del lote: `git log | grep commit`, `git log --grep commit`, `git show HEAD` no se interceptan; `git commit -m "git -C /x commit"` va por el camino rápido; toda la sección existente de `.planning/` sigue verde sin cambios de expectativa salvo (h), (i), (j).

#### Lote 2 — pre-commit-guard: forma `cd <ruta> &&` (backend-dev)
**Depende de:** Lote 1 (mismo resolver)

- [ ] Tarea 1: `cd <ruta> && git commit` y `cd <ruta>; …` resuelven sobre worktree real (R1 con marcador de árbol, R2 inverso, R3, R4 heredoc).
- [ ] Tarea 2: ruta relativa contra `BASE_DIR` y prefijo `~/` contra `HOME` (R9, R10 con `HOME` temporal; segundo repo `_pskip_setup_other`).
- [ ] Tarea 3: formas fuera de la allowlist bloquean sin correr, con `Formas aceptadas`: `pushd` (X4), `cd` pelado en sus cuatro variantes (X5, reemplazan (g2)-(g6)), `cd -` (X6), subshell (X7), `cd` no al inicio (X8), dos `cd` (X9), newline (X10), `$`/comillas/espacio en la ruta (X11-X13), destino inexistente o no repo (X14).
- [ ] Tarea 4: negativos: `echo "cd x" && git commit` sigue saltando; `git commit -m "cd /tmp && git commit"` va por el camino rápido; el mensaje de bloqueo nombra las tres formas y el escape ("cd en una llamada previa"). Header del hook reescrito: contrato de formas, verificaciones a/b/c con versión del CLI, fuera de alcance (#77, evasión).

#### Lote 3 — pre-merge-check: `cwd` del input (backend-dev)
**Depende de:** Lote 2 (mismo archivo de tests; secuencial por conflicto, no por lógica)

- [ ] Tarea 1: `.cwd` igual al cwd del proceso → continúa y consulta `session/repo` (M1; comparar con `pwd -P` para que el symlink `/var`→`/private/var` de macOS no dé falso bloqueo).
- [ ] Tarea 2: `.cwd` distinto o inexistente sin `--repo` → bloquea con 0 consultas y el mensaje pide `--repo` (M2, M3). Revertir el chequeo deja M2 consultando `session/repo`.
- [ ] Tarea 3: `.cwd` distinto con `--repo o/r` → continúa consultando `o/r` (M4); `.cwd` ausente → comportamiento actual (M5). Header punto 7 con la evidencia de a/b y referencia a #77 §4.

### Riesgos

- **Cambio de contrato visible:** formas que hoy corren suites (`pushd`, `cd` pelado, `-C` mezclado) pasan a bloquear sin correr. Es lo que pide el issue (bloqueo accionable) y ninguna es un flujo real del orchestrator; el mensaje trae el escape. → Listadas arriba con su test para que QA las contraste contra `dev` en vez de tratarlas como borradas.
- **`cd` a otro repo en la misma llamada:** en modo default la herramienta Bash lo rechaza si el destino no es directorio de trabajo (a3). El hook igual lo resuelve (si el `cd` no corre, git tampoco). Los flujos reales quedan cubiertos: subagentes (`cd <abs> && git commit` en una llamada, forma B3), reviewers (`git -C <worktree>`, forma B4), sesión principal (`cd` previo → `.cwd`).
- **Rutas del texto usadas en `cd`:** solo tras pasar `TREE_PATH_RE`; nunca `eval` ni `sh -c`. Un `.cwd` del input es un dato del harness, se usa con comillas y `[ -d ]`.
- **Symlinks (macOS `/var`):** todas las comparaciones y marcadores con `pwd -P` (la suite ya lo hace en `sandbox_create`).
- **Dependencia de `.cwd`:** en un CLI que no lo mande, ambos hooks caen al proceso (comportamiento actual), nunca fallan abiertos.
- **Costo:** dos llamadas a git extra (`rev-parse`) solo cuando hay redirección; despreciable frente al runner.
- **Lo que sigue abierto (#77):** huecos del saneo compartido que borran el comando real; cambian la etapa A de este hook igual que a los demás guards, y se arreglan ahí.
