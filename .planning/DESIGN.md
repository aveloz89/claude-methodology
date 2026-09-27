## Diseño: PR final de guards — #77 (errores honestos, D-05) + #86 (D-06, un solo PR)

> El `DESIGN.md` anterior era el de #73 (`hooks/pre-commit-guard.sh` lo cita como `.planning/DESIGN.md "Contrato 1"`). Antes del Lote 1 el orchestrator hace `git mv .planning/DESIGN.md .planning/DESIGN-pre-commit-target-tree.md` — si este archivo ya lo reemplazó, lo recupera de `git show a37e8c2:.planning/DESIGN.md`. El Lote 5 actualiza la cita del header.

### Resumen

Cerrar #77 dentro del modelo de errores honestos (`hooks/lib/guard-matching.sh:19-22`) y #86, más los defectos fail-open encontrados al verificar (D-07), en un solo PR sobre `fix/guards-honest-errors` → `dev`. Nada de interpretar shell: regex de detección ampliados a formas literales conocidas, allowlists donde hace falta resolver algo, y todo lo disfrazado documentado como fuera de alcance.

### Verificaciones empíricas (hechas en `mktemp -d`, hooks corridos directo con el JSON de input, CLI 2.1.283, macOS)

| # | Qué | Resultado |
|---|-----|-----------|
| V1 | Bloqueo falso con heredoc (#77 §2) | **Reproducido.** Caso mínimo: `cat > r.md << 'EOF'` (espacio entre `<<` y el delimitador) con `` `gh pr merge 5` `` en el cuerpo → `pre-merge-check` bloquea con "más de una línea". Causa: `guard_sanitize` exige `<<-?['"]?(\w+)` sin espacio, no reconoce el heredoc, no borra el cuerpo, y el backtick de markdown es posición de comando para el gate. Segunda variante: delimitador con guion (`<<'END-1'`): `\w+` no lo acepta. Con `<<'EOF'` pegado el mismo cuerpo pasa (también con comillas anidadas y apóstrofos en prosa: el cuerpo entero se borra). Me pasó en vivo dos veces durante este diseño con la misma forma |
| V2 | `if` de `hooks.json` vs `env git …`, `/usr/bin/git …` | **Por doc oficial** (hooks.md, tabla "Bash if matching"): solo se quitan asignaciones `VAR=x` al frente; cada subcomando se compara por prefijo; `$TOOL git push` corre el hook por no poder resolverlo. `env git push` y `/usr/bin/git push` no matchean `Bash(git *)`. Los regex de los guards (`${GUARD_ANCHOR}git\s+…`) tampoco los matchean: filtro y script son consistentes (superconjunto, ARCHITECTURE 2026-09-26). **Prueba en vivo NO VERIFICADA**: `claude -p` falló por OAuth expirado; además los hooks de `.claude/settings.json` de una carpeta temporal no corren sin trust |
| V3 | #86 con `workspace-scope.sh` | Sin `package.json` en la raíz, `workspace_scope_resolve npm` devuelve 1: la lib resuelve workspaces **declarados** en un `package.json` raíz, no descubre runners en subdirectorios. Baseline: monorepo `frontend/package.json` + `backend/pyproject.toml`, sesión en la raíz, cambios en ambos → `git commit -am x` sale 0 sin correr nada; lo mismo en un worktree del mismo repo. Con la sesión en `frontend/` o con `cd frontend && git commit` sí corre |
| V4 | NUL | El JSON trae `\u0000` como escape (sin byte NUL); el NUL aparece al decodificar con `jq -r` y bash lo descarta en `$(…)`. `echo "$INPUT" \| jq -e '.tool_input.command \| contains("\u0000")'` sobre el `INPUT` ya leído lo detecta (verificado): no hace falta archivo temporal |
| V5 | Formas de #77 que hoy pasan (baseline, todas rc=0) | `git push origin +main`, `git push -fu origin x`, `git push -uf origin x`, `git -C repo push --force`, `gh -R o/r pr merge 5 --admin`, `gh pr -R o/r merge 5 --admin`, `cd x && gh pr create --base main` |
| V6 | Formas disfrazadas de #77 §1 (baseline) | `echo \'; gh pr merge 5; echo \'`, `$'it\'s' && gh pr merge 5`, heredoc `<<E"OF"`: pasan (rc=0). Comentario con apóstrofo + merge en otra línea: **bloquea** (regla de una sola línea). Se documentan, no se arreglan (D-05) |
| V7 | Defectos nuevos (D-07) | `pre-push-guard` en repo en `main`: `git commit -m x && git push origin main`, `cd . && git push origin main`, `git -C . push origin main` → rc=0 (grep `^\s*git\s+push` sobre el crudo, sin lib, sin fail-closed sin jq). `block-hard-reset`: `git -C repo reset --hard` → rc=0. `pre-release-sweep`: `gh pr create -B main` → rc=0 |
| V8 | Negativos que hoy pasan y deben seguir pasando | `git push origin feature/x`, `-u origin x`, `--follow-tags`, `refs/heads/main:refs/heads/main`, `--delete origin x`, `origin :x`, `git commit -m "push -fu"`, `gh pr view 5 \| grep merge`, `gh pr merge 5 --squash`, `gh pr list --search "admin merge"`, `gh pr create --base dev` |
| V9 | Suite en el branch | `test-hooks.sh`: 415/415 |

### Search-first

Se salta: es fix de hooks existentes sin dependencia nueva. Lo que ya existe y se reutiliza: `guard_sanitize`/`GUARD_ANCHOR` (lib), el fragmento de opciones de árbol de `GIT_COMMIT_RE` (`pre-commit-guard.sh`), `GH_PR_MERGE_RE` (`pre-merge-check.sh`), `_guard_run_with_budget`, `_guard_find_runner_dir`, los helpers `assert_*_cmd`, `_pskip_*`, `assert_bam_*`, `assert_prs_*`, `assert_pre_merge_*` de la suite y el `gh` falso de `pre-release-sweep`.

### Modelo de amenaza (fijo, no se renegocia en review)

Errores honestos del orchestrator/dev: formas que alguien escribe de buena fe (`+main`, `-fu`, `git -C`, `gh -R`, `cd x && gh pr create`, un heredoc de reporte). Fuera de alcance por D-05: todo lo de la sección "Fuera de alcance" abajo. Un reviewer que encuentre una forma disfrazada nueva la agrega a esa lista, no abre un hallazgo bloqueante.

### Archivos afectados

- `hooks/lib/guard-matching.sh` — regex de heredoc (espacio tras `<<`, delimitador con `-`); nuevos: `guard_command_has_nul`, `GUARD_GIT_TREE_OPTS` (fragmento `((-C|--git-dir|--work-tree)(=\S*|\s+\S*)?\s+)*`, hoy inline en `GIT_COMMIT_RE`), `GUARD_GH_PR_MERGE_RE` (hoy inline en `pre-merge-check.sh`); header con inventario verificado de lo que NO sanea.
- `hooks/block-force-push.sh` — `+<ref>`, cluster `-…f…`, `git -C <ruta> push`.
- `hooks/block-hard-reset.sh` — `git -C <ruta> reset --hard`; NUL.
- `hooks/block-admin-merge.sh` — `gh -R o/r pr merge --admin`, `gh pr -R o/r merge --admin`; NUL.
- `hooks/pre-merge-check.sh` — NUL (bloqueo) y comentario; usa `GUARD_GH_PR_MERGE_RE`; header de wrappers `gh()`; mensaje `GH_REPO`/`GH_HOST`.
- `hooks/pre-push-guard.sh` — sourcea la lib (fail-closed), jq fail-closed, detección saneada+anclada, branch desde `.cwd`, redirecciones bloquean; NUL.
- `hooks/pre-release-sweep.sh` — sourcea la lib, fail-closed sin jq/gh, detección saneada+anclada, `-B main`; NUL.
- `hooks/pre-commit-guard.sh` — #86 (runners por archivo cambiado), budget compartido, usa `GUARD_GIT_TREE_OPTS`, cita al DESIGN renombrado.
- `tests/adversarial/test-hooks.sh` — todos los casos de abajo.
- `README.md` (tabla de hooks: `pre-commit-guard`, `block-force-push`, `block-hard-reset`, `block-admin-merge`, `pre-merge-check`, `pre-push-guard`, `pre-release-sweep`; sección "Fuera de alcance"), `global/CLAUDE.md` (una línea en "Hooks": `--help`/`-h` y que el `if` es best-effort; respetar el tope ≤130 líneas/≤10 KB del test).
- `hooks/hooks.json` — **sin cambios** (V2).

### Contratos por hallazgo

Cada fila: forma que pasa a bloquear · casos negativos que deben seguir pasando · test. Los tests de "sigue pasando" se escriben en la MISMA tarea que el bloqueo (retro PR-79). Antes de tocar cualquier regex, la suite completa es el corpus de regresión (retro PR-87): se corre al cerrar cada tarea.

#### A. `guard-matching.sh` — heredoc (#77 §2)

Cambio: `s/<<-?[\x27"]?(\w+)…/` → `<<-?[ \t]*[\x27"]?([A-Za-z0-9_-]+)[\x27"]?[^\n]*\n(?:(?!^[ \t]*\1[ \t]*$)[^\n]*\n)*?[ \t]*\1(?:\n|$)`. Solo cambia la apertura; el cuerpo y el terminador quedan idénticos (propiedades 1 y 2 del comentario de la lib: `[^\n]` y no-greedy; el test de ReDoS y el de dos heredocs con el mismo delimitador siguen verdes).

| ID | Comando (input del hook) | Hook | Esperado |
|----|--------------------------|------|----------|
| A1 | `cat > r.md << 'EOF'⏎- corrí `gh pr merge 5`⏎EOF` | pre-merge-check | pasa, 0 llamadas a gh (`assert_pre_merge_continue_no_calls`) — **rojo hoy** |
| A2 | `cat > r.md << 'EOF'⏎- `git commit -m "x"` falló⏎EOF` en repo con runner y tests en rojo | pre-commit-guard | pasa sin correr el runner (`_pskip_assert_marker … no`) — hoy pasa por casualidad del anchor; el test fija el contrato |
| A3 | `cat > r.md << EOF⏎- el dev corrió gh pr merge 5 --admin⏎EOF` (delimitador sin comillas, espacio, mención sin comillas) | block-admin-merge | pasa — **rojo hoy** (el cuerpo no se borra y `--admin` queda a la vista). A3b: la misma mención entre comillas dobles ya pasa hoy; se fija como negativo |
| A4 | `cat > r.md <<'END-1'⏎`gh pr merge 5`⏎END-1` | pre-merge-check | pasa — **rojo hoy** |
| A5 | heredoc `<<'EOF'` con cuerpo `it's` + `gh pr merge 5` real después del terminador | pre-merge-check | bloquea (multilínea) — negativo, hoy ya bloquea |
| A6 | `gh pr merge 5 \⏎ --admin` | block-admin-merge | bloquea — negativo existente (continuación de línea) |
| A7 | Los 4 casos existentes de heredoc (`HEREDOC_MENTION_*`, líneas ~2710-2736, 342, 585, 1134, 1252) | — | siguen verdes sin tocarlos |

Limitación que queda documentada en el header de la lib (no se arregla): una línea del cuerpo que termina en `\` justo antes del terminador (`s/\\\n\s*/ /` corre antes y se traga el `EOF`); heredoc cuyo delimitador lleva caracteres fuera de `[A-Za-z0-9_-]`.

#### B. NUL en el comando (#77 §3)

Cambio: `guard_command_has_nul "$INPUT"` en la lib (jq -e sobre el JSON, V4). Cada guard lo llama justo después de `INPUT=$(cat)` y bloquea con `BLOCKED: <hook>: el comando trae un byte NUL`. Los 7 guards (los dos que hoy no sourcean la lib pasan a hacerlo, ver E y F). En `pre-merge-check.sh` se reemplaza el párrafo "El caso que sí importa es un NUL…" por la referencia al helper.

| ID | Comando | Esperado |
|----|---------|----------|
| B1 | `jq -n '{tool_input:{command:"gh pr merge --help\u0000 5 --admin"}}'` → block-admin-merge, pre-merge-check | bloquea (hoy: admin bloquea por `--admin`; pre-merge pasa como `--help` con 0 consultas → **rojo hoy** para pre-merge-check) |
| B2 | `"git status\u0000"` → block-force-push, block-hard-reset, pre-commit-guard, pre-push-guard, pre-release-sweep | bloquea (rojo hoy en todos) |
| B3 | Los mismos comandos sin NUL | siguen pasando (existentes) |

#### C. `block-force-push` (#77 comentario 2)

Regex nuevos sobre el saneado, todos con `${GUARD_ANCHOR}git\s+${GUARD_GIT_TREE_OPTS}push\b`:
- flag larga/corta como hoy: `\s.*(-f|--force)\b` (sin cambio de semántica; `--force-with-lease`/`--force-if-includes` siguen bloqueando como hoy, test 369);
- cluster corto: `\s-[a-zA-Z]*f[a-zA-Z]*(\s|$)`;
- refspec forzado: `\s\+[^\s:]+` (un token que empieza con `+`).
El segundo camino (flag entre comillas sobre el crudo) queda igual, solo con el anchor nuevo.

| ID | Comando | Esperado |
|----|---------|----------|
| C1 | `git push origin +main` · `git push origin +feature/x` · `git push origin +HEAD:main` | bloquea (rojo hoy) |
| C2 | `git push -fu origin x` · `git push -uf origin x` | bloquea (rojo hoy) |
| C3 | `git -C repo push --force` · `git -C repo push -f` · `git -C repo push origin +main` · `cd a && git -C repo push -fu` | bloquea (rojo hoy) |
| C4 | negativos V8 + `git push origin main --follow-tags` + `git commit -m "+main -fu"` + `git push origin 'feat/+x'` (token quoted) + `git push -u origin feature/x` | pasan |
| C5 | existentes 297-388 | verdes |

#### D. `block-hard-reset` y `block-admin-merge`

- hard-reset: `${GUARD_ANCHOR}git\s+${GUARD_GIT_TREE_OPTS}reset\s+--hard`.
- admin-merge: `${GUARD_ANCHOR}${GUARD_GH_PR_MERGE_RE}\b.*--admin` con `GUARD_GH_PR_MERGE_RE='gh\s+(\S+\s+){0,2}pr\s+(\S+\s+){0,2}merge'` (el mismo texto que hoy usa `pre-merge-check.sh` sin anclar; se mueve a la lib y ese hook lo importa — misma cadena, cero cambio de comportamiento ahí).

| ID | Comando | Hook | Esperado |
|----|---------|------|----------|
| D1 | `git -C repo reset --hard` · `git -C repo reset --hard HEAD~1` · `cd a && git -C b reset --hard` | hard-reset | bloquea (rojo hoy) |
| D2 | `git commit -m "reset --hard"` · `git reset --soft HEAD~1` · `git -C repo reset --soft` | hard-reset | pasan |
| D3 | `gh -R o/r pr merge 5 --admin` · `gh pr -R o/r merge 5 --admin` · `gh --repo o/r pr merge 5 --admin` · `git fetch && gh -R o/r pr merge 5 --admin` | admin-merge | bloquea (rojo hoy) |
| D4 | `gh pr view 5 \| grep merge` · `gh pr merge 5 --squash` · `gh pr list --search "admin merge"` · `gh pr view 5 --repo o/r --json title` · mención quoted existente (471) | admin-merge | pasan |
| D5 | `pre-merge-check`: toda su sección (2676-3300+) | — | verde sin tocar tests |

#### E. `pre-push-guard` (D-07, V7)

Contrato nuevo (allowlist, misma doctrina que ARCHITECTURE 2026-09-26):
1. Fail-closed sin jq y sin lib (como los otros guards).
2. Detección: `${GUARD_ANCHOR}git\s+${GUARD_GIT_TREE_OPTS}push\b` sobre el saneado (una mención quoted no cuenta).
3. Branch: `git -C "$BASE_DIR" branch --show-current` con `BASE_DIR` = `.cwd` del input (fallback `pwd -P`), igual que `pre-commit-guard`.
4. Si el saneado tiene `cd`/`pushd` en posición de comando, `-C`, `--git-dir`/`--work-tree` o `GIT_DIR=`/`GIT_WORK_TREE=` → bloquea: "pre-push-guard no resuelve redirecciones; hacé el cd en una llamada previa (el hook sigue el cwd de la sesión)". No se resuelve la ruta: el push lo hace el orchestrator desde el cwd de la sesión, no hay forma honesta que lo necesite.
5. Excepción del merge commit intacta (línea `^Merge`).

| ID | Sandbox (`sandbox_create_pushrepo`, en `main`) | Comando | Esperado |
|----|-----------------------------------------------|---------|----------|
| E1 | main | `git commit -m x && git push origin main` · `npm test && git push` · `git push origin main;` | bloquea (rojo hoy) |
| E2 | main | `git commit -m "git push origin main"` · `gh pr create --body "git push origin main"` | pasa (hoy pasa porque el crudo no empieza con `git push`; el test fija el contrato para la detección anclada nueva) |
| E3 | main | `cd . && git push origin main` · `git -C . push origin main` · `GIT_DIR=x git push` | bloquea con el mensaje de redirección (rojo hoy) |
| E4 | feature/test, `HOOK_JSON_CWD=$SANDBOX_REPO` | `git push origin feature/test` | pasa |
| E5 | main, `.cwd` apuntando a un segundo sandbox en `feature/x` | `git push origin feature/x` | pasa: el branch se lee del `.cwd`, no del cwd del proceso (marcador: el test corre el hook con `run_cwd` = repo en main y `HOOK_JSON_CWD` = repo en feature) |
| E6 | PATH sin jq | `git push origin main` | bloquea (rojo hoy) |
| E7 | existentes 267-288 | — | verdes (E4 usa el mismo fixture) |

#### F. `pre-release-sweep` (#77 comentario 1 + V7)

1. Sourcea la lib (fail-closed si falta). Sin jq o sin gh → `BLOCKED: pre-release-sweep no operativo: falta jq o gh`. (Con `if: Bash(gh *)` el costo es un bloqueo de `gh` sin `gh` instalado, que fallaría igual.)
2. Detección sobre el saneado: `${GUARD_ANCHOR}gh\s+pr\s+create\b.*(--base[ =]main|-B\s+main)\b`.

| ID | Comando (fixture `sandbox_create_prs`, modo `critical`) | Esperado |
|----|----------------------------------------------------------|----------|
| F1 | `cd x && gh pr create --base main --title x` (x = `$PRS_REPO` relativo o `.`; el hook sigue corriendo `git diff` en su cwd, no resuelve el cd — documentarlo en el header) | bloquea por `app.js` (rojo hoy) |
| F2 | `gh pr create -B main --title x` · `gh pr create --title x --base=main` | bloquea (rojo hoy para `-B`) |
| F3 | `gh pr create --base dev` · `gh pr create --base main-2` · `git commit -m "gh pr create --base main"` · `gh pr create --base dev --body "--base main"` | pasan |
| F4 | PATH sin jq · PATH sin gh | bloquea (rojo hoy: hoy `exit 0`) |
| F5 | existentes 2603-2607 | verdes |

#### G. `pre-commit-guard` — #86

**Decisión:** correr los runners de los subdirectorios afectados por los archivos con cambios; NO bloquear cuando no se encuentra ninguno. Justificación: "bloquear si hay cambios de código y no hay runner" rompería todo repo sin runner (este mismo repo no tiene `package.json` ni `pyproject.toml`; `test-hooks.sh` no es un runner detectable) y exige definir "código" a ojo. Correr por archivo tocado es una extensión del resolver que ya existe (`_guard_find_runner_dir`) y cae del lado de correr de más.

Contrato:
1. Se mantiene TODO lo actual cuando `_guard_find_runner_dir SESSION_DIR TARGET_DIR` encuentra un marcador (`package.json`/`pyproject.toml`/`setup.py`/`pytest.ini`) — incluido `workspace-scope.sh`.
2. Si no encuentra ninguno: por cada línea de `git status --porcelain --no-renames --untracked-files=all` (ya se corre en `TARGET_DIR`), dir = directorio del archivo; se sube desde `TARGET_DIR/dir` hasta `TARGET_DIR` (exclusive, ya se sabe que no tiene marcador) con el mismo `_guard_find_runner_dir`; se junta el set único (`sort -u`).
3. Set vacío → `exit 0` como hoy (repo sin runner). Set no vacío → para cada dir, en orden, se corre la detección+suite de siempre (bloque "Detectar el test runner" extraído a `_guard_run_suite_in <dir>`, sin cambios internos; `workspace-scope` sigue aplicando dentro de cada dir si ese `package.json` declara workspaces). Cualquier fallo bloquea con el nombre del dir en el mensaje.
4. Budget compartido: `_guard_run_with_budget` descuenta de un `GUARD_BUDGET_LEFT` global inicializado una vez con `_guard_resolve_test_budget`; una segunda suite recibe lo que queda. Sin esto dos suites de 540 s superan los 600 s del harness, que descarta la salida y deja pasar el commit (fail-open).
5. Path con espacios en `git status` (C-quoted) → se trata como "sin dir resoluble" y se ignora para el set (nunca se ejecuta nada derivado de él); se anota en el header como en `workspace-scope.sh`.

Tabla de layouts (todos con `HOOK_JSON_CWD` y marcador `pwd -P` escrito por un runner falso — `npm` real con script `test` que escribe `pwd -P > <marker>` y sale 1, y un `pytest` falso en PATH que escribe su `pwd -P` y sale 0/1 según `FAKE_PYTEST_RC`):

| ID | Layout | Cambios | Sesión / comando | Esperado |
|----|--------|---------|------------------|----------|
| G1 | `frontend/package.json` + `backend/pyproject.toml`, sin marcador en raíz | `backend/b.py` | raíz, `git commit -am x` | corre solo pytest, marcador = `<repo>/backend`; frontend no corre (rojo hoy: exit 0 sin nada) |
| G2 | idem | `backend/b.py` + `frontend/a.js` | raíz | corren ambos; con frontend en rojo bloquea nombrando `frontend` |
| G3 | idem | `docs/README.md` | raíz | pasa sin correr nada (set vacío) |
| G4 | idem | `docs/README.md` + `frontend/a.js` | raíz | corre solo frontend |
| G5 | `git worktree add` del layout G1 | `frontend/a.js` en el worktree | raíz del worktree | marcador = `<worktree>/frontend`, nunca el árbol principal (rojo hoy) |
| G6 | `packages/a/package.json`, cambio en `packages/a/src/x.js` | — | raíz | marcador = `<repo>/packages/a` |
| G7 | G1 | `frontend/a.js` | raíz, `cd frontend && git commit -am x` | intacto (existente: corre en frontend por SESSION_DIR) |
| G8 | raíz con `package.json` + `workspaces` | — | raíz | intacto (existentes de workspace-scope) |
| G9 | repo sin runner en ningún lado | — | raíz | pasa (existente 547) |
| G10 | G1 con `PRECOMMIT_TEST_BUDGET=3`, ambos runners falsos duermen 2 s | ambos | raíz | bloquea por budget (total 4 s > 3 s) con el mensaje de `superó 3s` — rojo sin el budget compartido |
| G11 | G1 solo `.planning/` sucio | — | raíz | salta suites (existente 939) |

### Decisión sobre `hooks.json` `if` (V2)

Sin cambios. `env git …` y `/usr/bin/git …` no disparan el hook y tampoco los matchearía el script: no son errores honestos del flujo (nadie escribe `env git commit` por accidente). Van a "Fuera de alcance". Quitar el `if` costaría 7 spawns por cada llamada Bash sin cerrar nada que el script cierre.

### Fuera de alcance (texto para el header de `guard-matching.sh` y la sección nueva del README)

> **Fuera de alcance de los guards (documentado, no parcheado).** Los guards de `hooks/` protegen errores honestos del orchestrator y los devs: formas que alguien escribe de buena fe. No son un parser de shell ni un control de evasión. Verificado contra los hooks reales (2026-09-27), estas formas pasan sin bloquear y quedan así por decisión (D-05):
> - comillas partidas o escapadas que rompen el emparejamiento del saneo: `echo \'; gh pr merge 5; echo \'`, `$'it\'s' && gh pr merge 5`;
> - heredoc con delimitador comillado a medias (`<<E"OF"`), delimitador con caracteres fuera de `[A-Za-z0-9_-]`, o una línea del cuerpo que termina en `\` justo antes del terminador;
> - la flag o el subcomando en una variable (`F=--force; git push $F`), `eval`, `bash -c '…'`/`sh -c`, alias y funciones de git/gh definidas en el mismo comando o en uno anterior (`w() { gh "$@"; }; w pr merge 5` pasa — corrige lo que decía el header de `pre-merge-check.sh`);
> - la palabra del binario alterada o disfrazada: `"gh"`, `g\h`, `env git …`, `/usr/bin/git …`, `command git …` (el `if` de `hooks.json` tampoco dispara para las tres últimas: compara cada subcomando por prefijo y solo descarta asignaciones `VAR=x` al frente; ver la tabla "Bash if matching" de la doc de hooks).
> Si una de estas formas te bloquea o se te cuela, no es un bug a arreglar aquí: la salida es escribir el comando en su forma directa.

`README.md`: fila de cada hook actualizada con las formas nuevas y una subsección "Fuera de alcance" con ese texto. `global/CLAUDE.md` (una línea, dentro del tope): "`gh pr merge --help`/`-h` exactos pasan; el filtro `if` de los hooks es best-effort y las formas disfrazadas quedan fuera de alcance por diseño (README, sección Hooks)".

Docs puntuales de #77 §3 (van en el Lote 5):
- Header de `pre-merge-check.sh` (~L123-124): quitar "un wrapper o una función `gh()` … TODOS bloquean"; inventario: `command gh`, `env gh`, `FOO=1 gh`, `\gh`, ruta absoluta → bloquean (siguen verificados); `w() { gh "$@"; }; w pr merge 5` → pasa.
- Mensaje `GH_REPO`/`GH_HOST` (L420): sin `${MERGE_FORM_HELP}` al final (contradice "no uses --repo"); test que afirma que el stderr de ese bloqueo no contiene "usa --repo".
- La cita a `hooks/pre-merge-check.sh` en `global/CLAUDE.md` ya no existe (verificado: commit 920a413 la quitó); no hay tarea.

### Plan de implementación

**Estrategia de PR:** single-PR (D-06). Branch `fix/guards-honest-errors`, base `dev`.
**Agente:** `backend-dev` en todos los lotes. **Secuenciales** (todos tocan `test-hooks.sh` y los lotes 2-4 dependen de la lib del Lote 1). TDD sobre `tests/adversarial/test-hooks.sh`: cada tarea = test rojo → fix → suite completa verde → commit. Regla de regresión (retro PR-87): al cambiar un regex, la suite completa es el corpus; un test existente que cambie de veredicto se discute, no se edita.

**Por qué 6 lotes (> 3):** son 7 hooks + la lib compartida, cada uno con sus positivos y negativos; cortar por hook mantiene cada commit trazable a un hallazgo y evita el lote de 490 k tokens de PR-76 (H2). El Lote 6 es la reserva que pide D-07 para la ronda de fixes del review.

#### Lote 1 — lib compartida: heredoc y NUL (backend-dev)
**Depende de:** ninguno (antes: el `git mv` del DESIGN de #73 por el orchestrator)
- [ ] T1: `guard_sanitize` reconoce `<< 'EOF'` con espacio tras `<<` (A1, A2, A3/A3b rojos → verdes; A5, A6, A7 siguen igual).
- [ ] T2: delimitador con `-` (A4); test de ReDoS y de dos heredocs con el mismo delimitador siguen verdes.
- [ ] T3: `guard_command_has_nul` en la lib + bloqueo en los 5 guards que hoy la sourcean (B1, B2 para esos 5; B3). Reescribir el párrafo del NUL en `pre-merge-check.sh`.
- [ ] T4: mover a la lib `GUARD_GIT_TREE_OPTS` (desde `GIT_COMMIT_RE`) y `GUARD_GH_PR_MERGE_RE` (desde `pre-merge-check.sh`), importándolos donde estaban: cero cambio de veredicto (suite completa verde, 415 + los nuevos).
- [ ] T5: header de `guard-matching.sh`: sección "Fuera de alcance" con el texto de arriba (V6 + limitaciones de A).

#### Lote 2 — guards de git: force-push, hard-reset, admin-merge (backend-dev)
**Depende de:** Lote 1
- [ ] T1: `block-force-push`: refspec `+<ref>` (C1; negativos C4).
- [ ] T2: `block-force-push`: cluster corto con `f` (C2; negativos C4, C5).
- [ ] T3: `block-force-push` y `block-hard-reset`: `git -C <ruta>` vía `GUARD_GIT_TREE_OPTS` (C3, D1; negativos D2).
- [ ] T4: `block-admin-merge`: `gh -R o/r pr merge --admin` y `gh pr -R o/r merge --admin` vía `GUARD_GH_PR_MERGE_RE` anclado (D3; negativos D4; D5 intacto).
- [ ] T5: filas de README de los tres hooks con las formas nuevas.

#### Lote 3 — pre-push-guard y pre-release-sweep (backend-dev)
**Depende de:** Lote 1
- [ ] T1: `pre-push-guard`: fail-closed sin jq/lib y detección saneada+anclada (E1, E2, E6, E7).
- [ ] T2: `pre-push-guard`: branch desde `.cwd` y bloqueo de redirecciones con mensaje (E3, E4, E5) + NUL (B2).
- [ ] T3: `pre-release-sweep`: lib + detección saneada+anclada + `-B main` (F1, F2, F3, F5).
- [ ] T4: `pre-release-sweep`: fail-closed sin jq/gh (F4) + NUL (B2).
- [ ] T5: headers y filas de README de ambos hooks (incluida la limitación de F1: `cd` no se resuelve, el diff se calcula en el cwd de la sesión).

#### Lote 4 — pre-commit-guard: monorepo sin runner en la raíz, #86 (backend-dev)
**Depende de:** Lote 1 (`GUARD_GIT_TREE_OPTS`)
- [ ] T1: extraer `_guard_run_suite_in <dir>` (refactor sin cambio de veredicto: suite verde) y correr runners derivados de los archivos cambiados cuando no hay marcador entre SESSION_DIR y TARGET_DIR (G1 rojo → verde; G3, G9 pasan).
- [ ] T2: varios dirs → todos corren, cualquier fallo bloquea nombrando el dir (G2, G4).
- [ ] T3: worktree y anidado (G5, G6); intactos G7, G8, G11.
- [ ] T4: budget compartido entre corridas (G10).
- [ ] T5: header del hook (contrato 1-5 de G, salvedad de paths con espacios) y fila de README.

#### Lote 5 — docs de #77 §3 y cierre (backend-dev)
**Depende de:** Lotes 2-4
- [ ] T1: header de `pre-merge-check.sh`: inventario de wrappers verificado (`w() {…}` pasa) — verificación ejecutada, no deducida.
- [ ] T2: mensaje `GH_REPO`/`GH_HOST` sin la recomendación de `--repo`; test sobre el stderr.
- [ ] T3: README: sección "Fuera de alcance"; `global/CLAUDE.md`: línea de `--help`/`-h` + `if` best-effort (test de tope verde).
- [ ] T4: `pre-commit-guard.sh`: cita a `.planning/DESIGN-pre-commit-target-tree.md`; `claude plugin validate --strict .` y `test-plugin-manifest.sh` verdes.
- [ ] T5: correr las tres suites completas + revertir cada fix de regex (hunk mínimo) confirmando rojo→verde, y anotar en el reporte qué test cubre cada forma de V5/V7.

#### Lote 6 — reserva para la ronda de fixes del review (backend-dev)
**Depende de:** Fase 2.6 (security-reviewer + qa-backend)
Sin tareas planificadas; hasta 5 tareas con los hallazgos de la ronda. Cada fix lleva su caso negativo. Hallazgos que sean formas disfrazadas van a la sección "Fuera de alcance" (un commit de docs), no a un fix.

### Riesgos
- **Cambiar la apertura del heredoc afecta a los 5 guards** → el Lote 1 va primero y solo, y la suite completa (415) es el corpus; A5-A7 fijan que lo que bloqueaba sigue bloqueando.
- **Reorden `\`-newline vs heredoc** no se hace (H5): quedaría como falso positivo posible, documentado; reordenar tocaría la propiedad "un merge partido con `\` se une" y no hay caso honesto que lo pida.
- **`pre-push-guard` con redirecciones bloqueando** puede sorprender a un flujo que hoy hace `cd repo && git push` en una sola llamada → el mensaje da la salida (cd en una llamada previa); el orchestrator pushea desde el cwd.
- **#86 corre más suites que antes** (antes: ninguna) → un monorepo con suites lentas puede chocar con el budget; G10 garantiza que choque bloqueando, no dejando pasar. `PRECOMMIT_TEST_BUDGET` sigue siendo la válvula.
- **`pre-release-sweep` fail-closed sin gh** bloquea todo `gh …` en una máquina sin gh → el comando fallaría igual; mensaje claro.
- **Prueba en vivo del `if` NO VERIFICADA** → la decisión de no tocar `hooks.json` descansa en la doc y en que el script tampoco cubriría esas formas; si el usuario quiere la prueba, requiere una sesión autenticada en una carpeta con trust.
- **Tope de `global/CLAUDE.md`** (≤130 líneas/≤10 KB) → una sola línea nueva; el test lo vigila.
