# Security Review (pre-push) — hook-skip-planning-only

- **Branch:** `feature/hook-skip-planning-only`
- **Base:** `dev`
- **SHA revisado (HEAD):** `b108ad8`
- **Fecha:** 2026-09-12
- **Reviewer:** `security-reviewer` (Fase 2.6, diff local `git diff dev...HEAD`)
- **Veredicto:** **CAMBIOS REQUERIDOS** (1 HIGH bloqueante)

## Resumen

- CRITICAL: 0
- HIGH: 1
- MEDIUM: 1
- LOW: 3
- Legacy: 0 bloqueantes (el HIGH tiene raíz legacy — #212 — pero este diff le sube el blast radius; ver el hallazgo)

El diff no toca auth, red, entrada de usuario ni dependencias: no hay superficie OWASP clásica. Sin secretos, sin archivos sensibles, sin cambios de `package.json`/Docker/CI. La superficie real es **una condición de bypass de un gate de calidad** (`pre-commit-guard.sh`), y ahí se concentra la revisión.

El parseo en sí está bien construido: sin `eval`, sin interpolar el path en ningún comando, comparaciones por `case` con glob anclado al inicio. Ejecuté 24 escenarios adversariales contra el hook real (repos temporales con runner npm instrumentado) y **todos los ataques de forma del path fallan del lado seguro**. El problema no está en cómo se parsea la lista, sino en **de qué árbol se lee**.

---

## Hallazgos

### [HIGH] El salto se decide sobre el árbol del `cwd`, no sobre el repo donde va a ocurrir el commit

- **Archivo:** `hooks/pre-commit-guard.sh:76` (la llamada a `git status`), consumida en `:102-105`
- **Descripción:** `_guard_planning_only_change` corre `git status` en el cwd del proceso del hook. El comando interceptado puede commitear en **otro** árbol de trabajo: `cd <worktree> && git commit`, `git -C <otro> commit`, `git --git-dir=... --work-tree=... commit`. En esos casos el hook decide "solo `.planning/`" leyendo un árbol que no es el que se está commiteando, sale 0 y **no corre ninguna suite** sobre un commit de código.
- **Verificado** (no deducido), con `git worktree` real del mismo repo:
  - árbol principal: ` M .planning/x.md` — worktree: ` M src/a.js`
  - comando interceptado: `cd $WT && git commit -am x`, cwd del hook = árbol principal
  - resultado: **exit 0, runner NO corrió**. Idéntico con `git -C $OTRO commit -am x` y con `--git-dir/--work-tree`.
- **Riesgo:** el gate queda completamente anulado, en silencio, en un flujo que la metodología usa de rutina — y que **este mismo PR institucionaliza** en su segunda mitad (`rulebooks/orchestrator-runbook.md:359`, `agents/qa-*.md`: devs y reviewers corriendo desde worktrees). La precondición no es exótica: "el árbol principal sucio solo bajo `.planning/`" es el estado normal del orchestrator a mitad de feature (STATE.md, state.json, `reviews/`). Rompe además el invariante que el propio `BRIEF.md` declara como red de seguridad ("la lista se calcula con la sobreestimación segura de `git status`"): leída sobre otro árbol, la lista no sobreestima el commit, simplemente no lo describe.
- **Raíz legacy, delta de este PR:** la ceguera a worktrees es #212 y el BRIEF la deja fuera de alcance ("que el hook corra las suites del worktree en vez de las del árbol principal"). Eso sigue fuera de alcance. Lo que cambia acá es el **grado**: antes ese escenario corría las suites del árbol equivocado (gate mal apuntado, pero gate); ahora no corre nada (sin gate). Es el caso de "el PR aumenta el blast radius de una vulnerabilidad legacy" → bloqueante.
- **Remediación (dentro de alcance, conservadora, ~3 líneas):** antes de tomar el salto, exigir que el commit interceptado opere sobre el árbol del cwd. Sobre `$SANITIZED_COMMAND`, si aparece `cd `, `git -C`, `--git-dir` o `--work-tree`, **no saltar** y caer al camino normal (status quo exacto para esos comandos, sin tocar #212). Es la misma filosofía que ya rige la función: ante la duda, corre de más. Va con su caso en `tests/adversarial/test-hooks.sh` (el helper `assert_blocked_cmd` ya toma `run_cwd`, así que el escenario se arma sin infraestructura nueva).

### [MEDIUM — sugerencia urgente] Los 6 casos nuevos no fijan las invariantes que hacen segura la condición

- **Archivo:** `tests/adversarial/test-hooks.sh:460-570`
- **Descripción:** los casos (a)–(f) cubren el camino feliz, la mezcla con un archivo fuera, untracked fuera, y el rename `.planning/` → afuera. Verifiqué a mano que el comportamiento **hoy es correcto** en los casos que faltan, pero ninguno queda pineado; cualquier "simplificación" futura del glob (`.planning*`, un `grep -q '^\.planning'`) pasa la suite verde:
  - **Hermanos del prefijo**: `.planning-evil.js`, `.planningx.js`, `.planning-evil/x.js`, `src/.planning/x.js` → hoy corren suites (correcto). Es el primer ataque que se le ocurre a cualquiera contra un match por prefijo y no hay test.
  - **`.planning` como archivo regular** (sin barra) → hoy corre suites (correcto).
  - **Lista vacía** (`git commit --allow-empty`, `--amend` con árbol limpio) → hoy corre suites (correcto). Es un requisito **explícito del BRIEF** ("Conservador: lista vacía ... → camino normal") y no tiene test: el caso (f) tiene el árbol sucio bajo `.planning/`, no limpio.
  - **Fail-closed de `git`**: con `git` devolviendo 1 y con 128 (repo corrupto) → hoy corre suites (correcto), sin test.
  - **Rename afuera → `.planning/`** (código entrando) → hoy corre suites (correcto); solo está pineada la dirección inversa, y el comentario del hook promete "ambos lados".
- **Remediación:** agregar los 5 casos de arriba. Son baratos con el helper `_pskip_*` ya escrito; el de fail-closed necesita un shim de `git` en PATH (`printf '#!/bin/sh\nexit 1\n'`), que es el mismo patrón que ya usa la suite para el shim de `jq`.

### [LOW] `git add -f` de un archivo gitignoreado dentro del mismo comando salta el gate

- **Archivo:** `hooks/pre-commit-guard.sh:51-61` (el bloque de salvedades delegadas)
- **Descripción:** verificado — con `.planning/` sucio y el comando `git add -f ignored-code.js && git commit -m x`, el hook sale 0 y no corre suites; el archivo ignorado no aparece en `git status` hasta que se lo stagea, y el `add -f` todavía no corrió (es PreToolUse). El comentario delega las salvedades a `workspace-scope.sh`, que documenta el agujero de `.gitignore` — pero ahí la consecuencia era "corre menos workspaces" y acá es "no corre nada".
- **Remediación:** una línea propia en el comentario del bloque nuevo diciendo que la salvedad de `.gitignore` acá degrada a salto completo. Arreglarlo en código (mirar también `git ls-files --others --ignored`) sería sobreingeniería para un caso que exige un `add -f` deliberado.

### [LOW] El comentario afirma "el MISMO comando" y tres párrafos después lo desmiente

- **Archivo:** `hooks/pre-commit-guard.sh:52` vs `:63-67`
- **Descripción:** ":52" dice que se usa "el MISMO comando y las mismas salvedades que `_workspace_scope_match`"; ":63-67" explica que no, que acá se omite `--no-renames` a propósito. Quien lea de arriba hacia abajo se lleva una afirmación falsa antes de llegar a la corrección. Aplico acá el criterio del propio repo (`verificar antes de afirmar`, y la pasada de "si el diff introduce una regla, aplicala al diff").
- **Remediación:** reescribir ":52" como "el mismo comando salvo `--no-renames` (ver abajo)".

### [LOW] `global/CLAUDE.md:160` enuncia la condición en términos del commit, no del árbol

- **Archivo:** `global/CLAUDE.md:160`
- **Descripción:** "tests antes de cada commit (se omiten si el commit toca solo `.planning/`)". La condición real es "si el árbol de trabajo del cwd solo tiene cambios locales bajo `.planning/`". La diferencia es exactamente la que explota el hallazgo HIGH, y el enunciado actual le da al lector una garantía que el hook no da.
- **Remediación:** "(se omiten cuando el árbol solo tiene cambios en `.planning/`)". Si se aplica la remediación del HIGH, este enunciado queda además respaldado.

---

## Veredicto

**CAMBIOS REQUERIDOS**

### Bloqueantes

- [ ] **[HIGH]** `hooks/pre-commit-guard.sh:76/102` — no tomar el salto cuando el comando interceptado redirige git a otro árbol (`cd `, `git -C`, `--git-dir`, `--work-tree`); test adversarial que lo pine.

### Sugerencias

- [ ] **[MEDIUM]** `tests/adversarial/test-hooks.sh:460` — pinear los 5 casos faltantes (hermanos del prefijo, `.planning` archivo, lista vacía, fail-closed de `git`, rename afuera→`.planning/`).
- [ ] **[LOW]** `hooks/pre-commit-guard.sh:51-61` — documentar que la salvedad de `.gitignore` degrada a salto completo.
- [ ] **[LOW]** `hooks/pre-commit-guard.sh:52` — corregir "el MISMO comando".
- [ ] **[LOW]** `global/CLAUDE.md:160` — enunciar la condición sobre el árbol, no sobre el commit.
- [ ] **[LOW, informativo]** Un archivo de `.planning/` con **espacio** en el nombre desactiva el salto en silencio (git lo entrecomilla en `--porcelain` y deja de matchear). Es el lado seguro (corre de más), pero conviene que el equipo lo sepa antes de reportarlo como bug.

---

## Verificado y limpio (no son hallazgos)

Ejecutado contra el hook real, en repos temporales, con runner npm instrumentado para distinguir "no corrió" de "corrió y falló":

| Escenario | Resultado |
|---|---|
| `.planning-evil.js`, `.planningx.js`, `.planning-evil/x.js`, `src/.planning/x.js` | corre suites — el glob `.planning/*` está anclado al inicio, no hay escape por prefijo |
| `.planning` como archivo regular (sin barra) | corre suites |
| Path con espacio / tab / `->` en el nombre | git lo entrecomilla en `--porcelain` (verificado también con `core.quotePath=false`: el entrecomillado por espacio no depende de esa config); el string arranca con `"` y no matchea → corre suites |
| Archivo `.planning/a -> b.md` (intento de inyectar la forma de rename) | corre suites: el lado derecho `b.md` no cae bajo `.planning/` |
| Rename `.planning/` → afuera / afuera → `.planning/` | corre suites en ambas direcciones |
| Rename dentro de `.planning/` | salta (correcto) |
| `git commit --allow-empty` / `--amend` con árbol limpio | lista vacía → camino normal (requisito del BRIEF, cumplido) |
| `git status` falla (exit 1), repo corrupto (exit 128), cwd fuera de un repo | camino normal — **fail-closed correcto** |
| `git commit <pathspec fuera de .planning/>` con el árbol sucio solo en `.planning/` | salta, pero el pathspec no tiene nada que commitear: todo lo que puede entrar por pathspec tiene diff vs HEAD y por eso aparece en `git status`. La sobreestimación se conserva (salvo el caso gitignore del LOW) |
| Symlink bajo `.planning/` apuntando afuera (a archivo y a directorio) | salta, pero **no cuela código**: git almacena el enlace, no lo sigue; los archivos del destino siguen apareciendo con su propio path en `git status`. Sin bypass |
| Paths relativos | `--porcelain` los emite relativos a la raíz del repo, no al cwd (verificado desde un subdirectorio): no hay escape anidando un `.planning/` |
| Inyección de shell / prototype pollution / reflected input | N/A — el path nunca se interpola en un comando ni se ejecuta; solo `case` con globs y `${line:3}` |
| Secretos y archivos sensibles en el diff | limpio (`.pem/.key/.p12/.pfx/.env` ausentes; sin patrones de credenciales) |
| Dependencias / Docker / CI | sin cambios en el diff → audit N/A |
| `tests/adversarial/test-hooks.sh` completo | **231/231 PASS**, incluida la aserción de que la suite no modificó el repo real |
| Prosa de `agents/qa-*.md`, `rulebooks/orchestrator-runbook.md`, `global/CLAUDE.md` | no relaja ningún gate: agrega una exigencia (base de test propia por worktree) y documenta el salto. Único reparo, el LOW de `:160` |

## NO CUBIERTO

- **No verifiqué contra el harness real** que el cwd del proceso del hook sea siempre el cwd de la sesión: reproduje el escenario del HIGH pasando el cwd explícitamente, que es el mismo modelo que usan los helpers de la suite (`assert_allowed_cmd` recibe `run_cwd`) y lo que describe #212 en el BRIEF. Si el harness pusiera el cwd en el directorio del worktree, el HIGH cambiaría de forma pero no desaparece (se invierte: el árbol leído sería el del worktree y el commit podría ser el del principal).
- **No revisé** si el salto debería cubrir también otros directorios de puro estado (`.planning/` fue una decisión de producto, D-02 del BRIEF).
- **No medí** el costo del loop nuevo en repos con muchos untracked: sale al primer path fuera de `.planning/`, así que es más barato que `_workspace_scope_match`, que ya está medido en su propio comentario.
- **No revisé** `.planning/state.json`, `BRIEF*.md` ni el rename de `DESIGN.md` más allá de confirmar que no traen secretos: son estado de planning, sin implicación de seguridad.

---

## Re-review 2026-09-12 (ronda 2)

- **SHA ronda 2 (HEAD):** `2825e81` (delta `b108ad8...HEAD`: `c0bb1d4` fix del HIGH, `af06933` casos pineados, `2825e81` docs)
- **SHA ronda 1:** `b108ad8`
- **Fecha:** 2026-09-12
- **Veredicto:** **APROBADO** (0 bloqueantes; 2 LOW nuevos, ninguno bloquea)

Alcance: solo el delta. No repetí el checklist OWASP ni los 24 escenarios de ronda 1.

### 1. HIGH — CERRADO (reproducido de nuevo por mí, no leído del diff)

Rearmé el escenario de ronda 1 desde cero (repo temporal, `git worktree` real, runner npm instrumentado que escribe un marcador y falla, cwd del hook = árbol principal):

- árbol principal: ` M .planning/x.md` — worktree: ` M src/a.js`
- comando: `cd $WT && git commit -am x`

| hook | `cd $WT && git commit` | `git -C $WT commit` | `--git-dir/--work-tree` |
|---|---|---|---|
| `dev` (antes del PR) | exit 2, **runner corrió** | exit 0, runner NO | exit 0, runner NO |
| `b108ad8` (ronda 1) | exit 0, **runner NO** ← el HIGH | exit 0, runner NO | exit 0, runner NO |
| `2825e81` (ronda 2) | exit 2, **runner corrió** | exit 0, runner NO | exit 0, runner NO |

El camino normal queda restaurado **exactamente** como en `dev`. El control también pasa: commit local con el árbol sucio solo bajo `.planning/` sigue saltando (`Solo cambios en .planning/: sin suites.`).

**Anclaje del `cd` — verificado, sin falsos positivos y del lado seguro cuando los hay:**

- Desactivan el salto (correcto): `(cd $WT && git commit)` subshell, `cd "$WT" && …` (path entrecomillado), `cd $WT`+newline+`git commit`, `{ cd $WT; git commit; }`, `cd<TAB>$WT`.
- NO desactivan el salto (correcto, no son invocaciones): `cd` dentro de `'…'`, dentro de `"…"`, dentro de heredoc, `acd foo`, `abcd && …`, `cd-tool …`.
- Modo degradado sin `perl` (sin saneo): `git commit -m "hacer cd algo"` tampoco falsea — el anclaje a posición de comando aguanta solo. Y si llegara a falsear (ej. `"(cd x)"`), corre suites de más: lado seguro.

**Residual LOW (ver hallazgos nuevos):** `pushd <dir> && git commit` y `cd;` pelado siguen tomando el salto.

### 2. MEDIUM — CERRADO (probado por mutación, no por lectura)

Los 5 casos existen y **el hueco declarado en ronda 1 quedó cubierto con poder de matar**. Cloné el branch en un scratchpad (no toqué el repo real), muté el hook y corrí la suite completa por mutación:

| Mutación | Resultado |
|---|---|
| `.planning/*)` → `.planning*)` (prefijo relajado) | **muerta** — 6 asserts (`.planning-evil.js`, `.planningx.js`, `.planning-evil/x.js`) |
| `.planning/*)` → `*.planning/*)` (sin anclar) | **muerta** — 2 asserts (`src/.planning/x.js`) |
| `[ -z "$files" ] && return 1` → `return 0` | **muerta** — 2 asserts (lista vacía / `--allow-empty`) |
| quitar el lado **derecho** del rename | **muerta** — 2 asserts (`.planning/` → afuera) |
| quitar el lado **izquierdo** del rename | **muerta** — 2 asserts (afuera → `.planning/`) |
| quitar el guard `cd`/`-C`/`--git-dir`/`--work-tree` (revertir el fix) | **muerta** — 6 asserts (g, j×2) |
| quitar `\|\| return 1` de `git status` | **SOBREVIVE** → LOW-1 abajo |

### 3. LOW — 3/3 CERRADOS

- `hooks/pre-commit-guard.sh:76-85` — la salvedad de `.gitignore` + `git add -f` está documentada con su consecuencia propia ("acá degrada a saltar las suites por completo"), no delegada.
- `hooks/pre-commit-guard.sh:52-54` — "el MISMO comando" → "el mismo comando … salvo `--no-renames`". **Verificado factualmente:** `workspace-scope.sh:262` usa `git status --porcelain --no-renames --untracked-files=all` y el hook `git status --porcelain --untracked-files=all`; `--no-renames` es la única diferencia. La afirmación ahora es cierta.
- `global/CLAUDE.md:160` y `README.md:29` — ambos enuncian la condición **sobre el árbol** y agregan la no-redirección ("y el comando no redirige git a otro árbol"). Barrí el repo: no queda ninguna otra superficie que describa el salto (las menciones de `skills/pr-workflow` y del runbook son sobre CI, no sobre el hook).

### 4. Nota del dev sobre `git -C` / `--git-dir` / `--work-tree` — CONFIRMADA

La tabla del punto 1 la sostiene con ejecución, no con lectura: esas tres formas dan **exit 0 sin correr nada** en `dev`, en `b108ad8` y en `2825e81`. El hook sale en el filtro `${GUARD_ANCHOR}git\s+commit` de la línea 40 (necesita `commit` pegado a `git`), así que nunca llegan a `_guard_planning_only_change`. **Este PR no lo empeora ni lo mejora** — es #212/#73 legacy, fuera de alcance. Quedó documentado en el comentario de `(g)-(i)` y pineado por los tests `(h)` e `(i)` como status quo. Añado un dato verificado en la misma familia: `GIT_WORK_TREE=… GIT_DIR=… git commit` se comporta idéntico (exit 0, nada, antes y después) por el mismo motivo.

La rama `-C`/`--git-dir`/`--work-tree` del chequeo nuevo solo se ejercita de verdad en comando compuesto — que es exactamente lo que hacen los dos asserts `(j)`. Correcto.

### 5. Suite adversarial — VERDE

`bash tests/adversarial/test-hooks.sh` → **Total: 257 | Pass: 257 | Fail: 0** (30s), incluido el assert de que la suite no modificó el repo real.

---

## Hallazgos nuevos (ninguno bloqueante)

### [LOW] El test de fail-closed no mata la mutación que debería

- **Archivo:** `tests/adversarial/test-hooks.sh` (caso `"git status" falla … → corre suites (fail-closed)`)
- **Descripción:** el `git` falso sale 1 **sin imprimir nada**, así que el camino normal lo produce `[ -z "$files" ] && return 1`, no el `|| return 1` del exit status. Quitar `|| return 1` deja la suite en **257/257 verde**. Y es un cambio de comportamiento real: verificado con un `git` falso que imprime ` M .planning/x.md` **y** sale 1 (repo corrupto con salida parcial) — con `|| return 1` corre suites (exit 2), sin él **salta** (exit 0, runner no corrió).
- **Riesgo:** el invariante "git falla → camino normal" está pineado a medias; un refactor que elimine el chequeo de exit status pasa verde.
- **Remediación (una línea):** que el `git` falso imprima una línea bajo `.planning/` antes de `exit 1`. Ahí sí las dos guardas quedan distinguidas.

### [LOW] `pushd` y `cd` pelado siguen tomando el salto (residual del HIGH)

- **Archivo:** `hooks/pre-commit-guard.sh:136`
- **Descripción:** verificado contra `dev` y contra HEAD, mismo escenario de worktree:
  - `pushd $WT && git commit -am x` → `dev`: exit 2, runner corrió · HEAD: **exit 0, runner NO**
  - `cd; git commit -am x` (`cd` pelado → `$HOME`) → `dev`: exit 2, runner corrió · HEAD: **exit 0, runner NO** (el regex exige `cd\s`)
- **Riesgo:** misma clase que el HIGH, formas mucho más angostas. `pushd` no aparece **ni una vez** en todo el repo y el idioma que instruyen el runbook y los `agents/qa-*` es `git worktree` + `cd`; `cd` pelado solo hace daño si `$HOME` es un repo git. Por eso es LOW y no bloquea: la forma que la metodología realmente emite quedó cubierta.
- **Remediación (una palabra, si se quiere residual cero):** `(cd|pushd)\s` en la alternancia. `cd` pelado requeriría además contemplar `cd$`/`cd;`.

---

## Veredicto

**APROBADO**

### Bloqueantes

- Ninguno. El HIGH de ronda 1 está cerrado con reproducción propia; el MEDIUM está cerrado con poder de matar demostrado por mutación; los 3 LOW están cerrados.

### Sugerencias (no bloquean el push)

- [ ] **[LOW]** `tests/adversarial/test-hooks.sh` — que el `git` falso del caso fail-closed imprima una línea `.planning/` antes de `exit 1`.
- [ ] **[LOW]** `hooks/pre-commit-guard.sh:136` — `(cd|pushd)\s` si se quiere cerrar el residual.
- [ ] **[LOW, arrastrado de ronda 1, informativo]** un archivo de `.planning/` con espacio en el nombre desactiva el salto en silencio (lado seguro).

## NO CUBIERTO

- **No re-verifiqué** lo ya cerrado en ronda 1 (los 24 escenarios de forma del path, secretos, symlinks, pathspec, `core.quotePath`): el delta no toca `_guard_planning_only_change` salvo el comentario.
- **No corrí `npm audit`**: el delta no toca dependencias.
- **Sigue sin verificar contra el harness real** que el cwd del proceso del hook sea el cwd de la sesión (mismo límite que ronda 1). Todo lo de arriba pasa el cwd explícito, igual que los helpers de la suite.
- **#212 sigue abierto y sin cubrir por diseño**: con `cd <worktree> && git commit` el hook ahora corre suites, pero las del **árbol principal**, no las del worktree. Gate mal apuntado, no ausente — que era el acuerdo de alcance.
- **No medí** el costo del `grep` nuevo: es un `grep` sobre un string ya en memoria, previo a cualquier `git`.
