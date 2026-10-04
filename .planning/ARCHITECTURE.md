# Architecture

Decisiones arquitectónicas recurrentes del proyecto. El `architect` lee este archivo al inicio de cada diseño para mantener consistencia, y lo actualiza al final con decisiones nuevas.

A diferencia de `DESIGN.md` (que vive solo durante una feature), este archivo persiste y acumula decisiones de **alcance recurrente**: stack, patrones, librerías canónicas, convenciones.

## Qué va aquí

- Arquitectura elegida y justificación (Monolito | Modular | Clean | Hexagonal | Microservicios)
- Patrones adoptados (repository, service layer, ports/adapters, etc.)
- Stack confirmado: librerías canónicas para validación, ORM, HTTP client, logging, cache, queue, testing
- Convenciones de nombres y estructura de directorios
- Boundaries entre módulos / bounded contexts

## Qué NO va aquí

- Detalles de la feature actual (eso vive en `DESIGN.md`)
- Decisiones específicas a un PR
- Notas de implementación

## Formato de entrada

```markdown
### [YYYY-MM-DD] Título de la decisión

**Contexto:** qué situación llevó a esta decisión.

**Decisión:** qué se eligió.

**Justificación:** por qué (alternativas evaluadas, tradeoffs).

**Implicación:** qué cambia para futuros diseños / qué patrones se siguen.
```

---

## Decisiones

(Las entradas se agregan aquí, la más reciente arriba)

### [2026-10-03] Guards que ejecutan una herramienta del proyecto: la del proyecto antes que la global; declarada pero ausente → bloquear

**Contexto:** `pre-commit-guard` corría `pytest` del PATH o nada (fail-open) en proyectos uv / `.venv` cuyo pytest no está en el PATH del hook (vector: `uv.lock` + `.venv/bin/pytest`, `uv` en `/opt/homebrew/bin`). D-01/D-02 del brief `pre-commit-guard-uv-pytest`. La ronda 1 de review (QA B1, security MEDIUM) encontró que la primera implementación seguía cayendo al `pytest` global cuando el proyecto declaraba entorno propio sin runner (`uv.lock` sin `uv` en PATH; `.venv/` sin pytest) y que `[tool.uv]` sin `uv.lock` invocaba `uv run --frozen`, que sin lock falla siempre (rc 1) y crea `.venv/` como efecto colateral (verificado con uv 0.12.22). D-04/D-05/D-06.

**Decisión:** por cada directorio con marcador, el runner se resuelve en orden cerrado: (1) uv solo si hay `uv.lock` **y** `uv` en el PATH del hook (`uv run --frozen pytest`, nunca reescribe el lock); una tabla `[tool.uv…]` sin lock no es trigger; (2) el venv local del mismo directorio (`.venv/bin/pytest`, `.venv/Scripts/pytest.exe`), archivo regular y ejecutable; (3) si el proyecto declara entorno propio (`uv.lock`, `[tool.uv…]`, `.venv` como carpeta o symlink, incluso roto) y no se resolvió, bloquea con la razón específica de ese entorno (uv fuera del PATH / `uv sync` pendiente / venv sin pytest) y **nunca** cae al binario global; (4) el binario del PATH solo para proyectos sin entorno declarado; (5) nada → bloqueo genérico con las vías. Un `package.json` sin script `test` usable (ausente, placeholder de `npm init` o `scripts.test` que no es string) no tapa un marcador Python del mismo directorio; uno que no es un objeto JSON (no parsea, vacío, `null`, array) bloquea con su razón si no hay marcador Python (el hook no puede saber qué suite correr; antes pasaba en silencio) y cede a la rama Python si lo hay. La búsqueda de lockfile/venv no sube del directorio del marcador (un directorio = un proyecto = un runner, mismo invariante que el lockfile junto a `package.json`). En el loop multi-directorio la razón viaja por directorio (arrays paralelos: bash 3.2 de macOS no tiene asociativos), "sin runner" (marcador Python sin runner o `package.json` ilegible) es un código de retorno dedicado (`127`) y el rc del runner se normaliza a 0/1 (verificado: un venv con intérprete roto devuelve 126/127 en bash y colisionaría). Las dependencias de binarios del preámbulo (`jq`, `grep`) se declaran fail-closed en `guard_init` de la lib, para todos los guards a la vez.

**Justificación:** un pytest global en un proyecto con venv corre con el intérprete equivocado (verde falso o rojo espurio); "no pude verificar" no es "verde" (`rules/bash.md`, fail-closed). Caer al binario global cuando el proyecto declara su entorno es exactamente ese error disfrazado de verde. El trigger de uv es el lockfile y no la tabla de configuración porque es lo que `--frozen` exige; invocar la herramienta sabiendo que va a fallar produce un bloqueo con la razón equivocada ("Tests failed"). Subir hasta el toplevel atribuiría el `.venv` de otro paquete del monorepo al directorio equivocado. Alternativas descartadas: escape hatch por env (usuario), `uv run --locked` / sin flags (usuario), búsqueda hasta `TARGET_DIR` (más loop, mismo fail-closed, atribución errónea posible), declarar `grep` solo en este hook (los seis guards y la lib lo usan: el agujero era común).

**Implicación:** un guard que invoque una herramienta del proyecto sigue este orden y nunca pasa en silencio cuando el marcador existe y la herramienta no. Agregar un gestor (poetry/pdm/hatch) entra con cuatro piezas: su trigger (lockfile, no tabla de config), su caso "declarado pero sin herramienta" con mensaje propio, su caso "declarado sin lock" y su negativo de regex. Un ADR que afirma un comportamiento fail-closed lleva en el mismo PR el test que lo demuestra (QA B1 de esta feature: el documento afirmaba lo que el código no hacía). Los tests de esa resolución corren con PATH curado (symlinks solo a lo que el hook necesita, sin el binario real), afirman la precondición en todo caso cuya expectativa es un bloqueo, y un fake registra argv y `pwd -P`, no solo presencia.

### [2026-09-27] Simplificación: `.planning/` fuera de git, `guard_init`, forma única de commit, escáner read-only

**Contexto:** la auditoría del 2026-09-27 encontró ceremonia que existía solo porque `.planning/` viajaba en git (sellado anticipado, commits de registro/vinculación/retro, check 4 de pre-merge, salto de suites solo-`.planning/`), tres hooks y una lib con más líneas que protección demostrada (`pre-release-sweep`, `session-end-check`, `workspace-scope`), agentes divididos por tipo de problema (`refactor`/`latent-bugs-sweep`/`product-reviewer`) y catálogos de manual en los prompts. Decisiones del usuario D-01…D-06 en `BRIEF.md`.

**Decisión:** (1) `.planning/` se gitignorea en todo proyecto; el estado sobrevive en el working tree y en los snapshots de `PreCompact`; `state.json` se escribe local en cada transición, incluido `phases.merge` después del merge; el registro de review es un archivo local por feature (`.planning/reviews/<slug>.md`). Sin retros ni `learnings/`: una lección accionable se convierte al momento en regla o issue. (2) El preámbulo de los guards `PreToolUse` es `guard_init <nombre>` en `hooks/lib/guard-matching.sh` (jq fail-closed, stdin, NUL, saneo) más `guard_block` y `guard_session_dir`; la existencia de la lib la verifica cada guard antes de sourcear. (3) Un guard que depende del directorio acepta una lista cerrada de formas y bloquea el resto nombrándolas; para `pre-commit-guard` son dos: `.cwd` de la sesión y `cd /ruta/absoluta && git commit`. El runner sin marcador en la raíz se busca solo en subdirectorios de primer nivel de los paths con cambios, con el presupuesto dividido entre directorios. (4) `block-force-push` permite `--force-with-lease` fuera de `main`/`master`/`dev` (branch de `.cwd` y tokens del `push`); `--force` sigue bloqueado; flag entre comillas y redirección antes de la flag pasan al inventario "Fuera de alcance". (5) Un agente que escanea (`code-sweep`, modos `bugs`/`smells`) es read-only; lo que encuentra lo ejecutan los devs como lotes. Los bloques repetidos de reviewers y devs viven en `rulebooks/reviewer-common.md` y `rulebooks/dev-common.md`; los prompts guardan solo su delta. Sin agentes opcionales por tipo de proyecto (supersede la entrada del 2026-09-26 sobre `Tipo: producto con usuarios`): las preguntas de producto son parte del brainstorming.

**Justificación:** cada pieza eliminada se justificaba por el versionado del estado o por un modelo de amenaza que D-05 del PR #77 ya había acotado a errores honestos; un escáner que escribe código era la única excepción a "los devs implementan". La forma única de commit sigue el criterio que ya adoptaron `pre-push-guard` y `pre-merge-check` (allowlist de forma, no blocklist de construcciones).

**Implicación:** un guard nuevo empieza con el preámbulo canónico de 6 líneas y `guard_init`; una forma de comando nueva se agrega a la allowlist con su caso positivo, su bloqueo y sus negativos, nunca como parseo. Nada del flujo puede volver a depender de que `.planning/` esté commiteado. Un hallazgo sobre una forma que quedó en "Fuera de alcance" se cierra agregándola al inventario. Antes de proponer un agente nuevo o un rulebook nuevo: si el texto es común a dos prompts, va a `*-common.md`.

### [2026-09-27] Guards de texto: fragmentos de detección compartidos, `if` best-effort y formas disfrazadas fuera de alcance

**Contexto:** cada guard tenía su propio regex para "es una invocación de git/gh" y cada uno cubría un subconjunto distinto de las formas honestas (`git -C`, `gh -R`, cluster `-fu`, refspec `+ref`, `cd x && gh pr create`); dos guards no sourceaban la lib y fallaban abiertos sin jq. Verificado (doc oficial de hooks, tabla "Bash if matching"): el `if` de `hooks.json` compara cada subcomando por prefijo, solo descarta asignaciones `VAR=x` al frente, y corre el hook si no puede resolver el comando; `env git …` y `/usr/bin/git …` no lo disparan, y los scripts tampoco los matchean.

**Decisión:** los fragmentos de detección viven en `hooks/lib/guard-matching.sh` (`GUARD_ANCHOR`, `GUARD_GIT_TREE_OPTS`, `GUARD_GH_PR_MERGE_RE`, `guard_command_has_nul`) y todo guard que intercepta comandos Bash la sourcea fail-closed y es fail-closed sin jq. `hooks.json` conserva el `if` con el nombre pelado del binario. Las formas disfrazadas (comillas partidas, variables, `eval`, `bash -c`, alias/funciones, binario por ruta o vía `env`/`command`) quedan fuera de alcance por decisión del usuario (D-05) y se listan en el README y en el header de la lib como inventario verificado, no como garantía.

**Justificación:** el modelo de amenaza es el error honesto; una forma que solo aparece como evasión deliberada no justifica interpretar shell (retro PR-76). Un fragmento compartido evita que dos guards diverjan sobre la misma sintaxis y que un fix en uno deje al otro atrás.

**Implicación:** un hallazgo de review sobre una forma disfrazada se cierra agregándola al inventario, no con un fix. Un fix a un regex de detección lleva en la misma tarea sus casos negativos y se valida contra la suite completa como corpus (retros PR-79, PR-87). Cuando un guard cambia el directorio donde actúa, la tabla de tests trae monorepo, worktree y subdirectorio. Toda verificación sobre el harness que no se pudo ejecutar se escribe como NO VERIFICADA con la razón.

### [2026-09-26] Guards que dependen del directorio: `cwd` del input + allowlist de redirecciones

**Contexto:** `pre-commit-guard.sh` corría `git status` y el runner en el cwd del proceso del hook, y `pre-merge-check.sh` resolvía el repo con `gh repo view` ahí mismo, sin saber si ese directorio era el del comando interceptado (#73, #77 §4). Verificado con CLI 2.1.283 en modo de permisos default: el JSON de `PreToolUse` trae `cwd`, que refleja el `cd` persistido de llamadas Bash anteriores (incluido un directorio agregado con `--add-dir`), y el proceso del hook corre exactamente ahí; `CLAUDE_PROJECT_DIR` no sigue al `cd`. El `if: "Bash(git *)"` de `hooks.json` dispara también con `FOO=1 git …`, `cd X && git …` y `git -C X …`.

**Decisión:** un hook que necesita saber en qué directorio actúa el comando lee `.cwd` del input (con fallback al cwd del proceso si el campo no viene) y trata una discrepancia con el proceso como fail-closed. Para redirecciones dentro del texto del comando, allowlist cerrada de formas literales sobre el texto crudo (`cd <ruta> &&` al inicio y una sola vez, `git -C <ruta>` con una sola ruta) con charset `[A-Za-z0-9_./-]` (más prefijo `~/`); todo lo demás (`pushd`, subshells, variables, comillas, `--git-dir`/`--work-tree`, `GIT_DIR`/`GIT_WORK_TREE`) bloquea con un mensaje que nombra las formas aceptadas y el escape: hacer el `cd` en una llamada previa para que llegue por `.cwd`.

**Justificación:** interpretar shell arbitrario es una carrera perdida (retro PR-76); una allowlist literal es verificable y cada forma lleva su caso positivo, su caso de bloqueo y sus negativos (retro PR-79). El escape por `.cwd` cubre cualquier forma que no esté en la lista sin parsear nada.

**Implicación:** un guard nuevo que dependa del directorio no usa `$PWD` a secas ni `CLAUDE_PROJECT_DIR`; parte de `.cwd`. Si acepta rutas del texto del comando, las valida contra ese charset antes de usarlas y nunca las pasa por `eval`. Los tests afirman en qué árbol actuó el hook (marcador con `pwd -P`), no solo el exit code.

### [2026-09-26] Agentes opcionales se activan por una línea declarativa en el `CLAUDE.md` del proyecto

*(Superseded 2026-09-27: `product-reviewer` se quitó — sus preguntas de producto [¿vale la pena?, resultado esperado, criterios de aceptación medibles] pasaron al brainstorming de la sesión principal. Sin ese agente, la mecánica de activación condicional por `Tipo:` deja de tener un consumidor — ver la entrada de esa fecha, punto 5.)*

**Contexto:** `product-reviewer` solo tiene sentido en productos con usuarios reales, no en repos de tooling o metodología. Preguntar en cada brainstorming si corre agrega fricción; inferirlo del código es adivinar.

**Decisión:** un agente o fase opcional que depende del tipo de proyecto se activa por una línea exacta, sin formato, en el `CLAUDE.md` del proyecto (raíz o `.claude/CLAUDE.md`): `Tipo: producto con usuarios`. `/new-project` la pregunta y la escribe; el orchestrator la lee del contexto (o con `Grep`, patrón `^(- )?Tipo: producto con usuarios$`). Sin la línea, la fase no corre y el orchestrator no pregunta.

**Justificación:** el `CLAUDE.md` del proyecto ya está en contexto en toda sesión, así que la detección no cuesta tools ni turnos; una línea literal es greppable y testeable; el falso negativo (no correr) es la dirección segura. Alternativas descartadas: preguntar en cada feature (fricción), variable de entorno (invisible en el repo), detección heurística por stack (adivina).

**Implicación:** futuras fases o agentes condicionales al tipo de proyecto reutilizan la misma clave `Tipo:` con un valor nuevo o existente, no una línea propia. La forma exacta se documenta en el README y en la skill que la escribe; los tests aseguran que ambas coincidan. El agente que se activa así sigue la regla de frontera de contexto (entrada anterior): `product-reviewer` la cumple por contexto limpio.

### [2026-09-26] Hooks bloqueantes: un solo mecanismo, stderr + `exit 2`

**Contexto:** cuatro guards de `PreToolUse` bloqueaban con `{"decision":"block"}` a nivel raíz (deprecado para ese evento) y dos con `exit 2`; la suite tenía dos familias de asserts. La doc prescribe `exit 2` para hooks de policy: bloquea aunque otro JSON diga `allow` y se evalúa antes de las allow rules.

**Decisión:** todo hook que bloquea escribe el motivo en stderr y termina con `exit 2`; permitir es `exit 0` sin stdout. Ningún hook mezcla JSON de decisión con exit codes. Los hooks de contexto (`SessionStart`, observabilidad) siguen imprimiendo texto plano con `exit 0`.

**Justificación:** un mecanismo, una familia de asserts (`assert_blocked_cmd`/`assert_allowed_cmd`), sin depender de `jq` para serializar el motivo. Alternativa descartada: `hookSpecificOutput.permissionDecision: "deny"` (válida, pero segunda vía sin ventaja sobre lo que ya usaban `pre-commit-guard` y `pre-push-guard`).

**Implicación:** un guard nuevo se escribe y se testea por exit code; si además necesita un timeout largo, implementa su propio watchdog fail-closed (un hook que alcanza el `timeout` del harness en `PreToolUse` deja pasar el comando).

### [2026-09-26] `if` en hooks PreToolUse: optimización con superconjunto del guard

**Contexto:** los siete guards `matcher: "Bash"` spawneaban en todo comando Bash. La doc ofrece `if` con sintaxis de permission rules; verificado (CLI 2.1.274) que matchea subcomandos de compuestos (`cd x && git …`) y prefijos (`git -C …`), y que funciona dentro del `hooks.json` de un plugin.

**Decisión:** cada guard lleva `if` con el nombre del binario que ancla su regex (`Bash(git *)`, `Bash(gh *)`), nunca algo más estrecho que lo que el script matchea. El script sigue validando el comando completo.

**Implicación:** `if` reduce latencia, no decide; un `if` más específico que el anclaje del script abre un hueco (el hook ni corre) y se rechaza en review.

### [2026-09-26] Progressive disclosure del orchestrator en tres niveles

**Contexto:** `global/CLAUDE.md` (21 KB, 6.4k tokens medidos) se carga en todos los subagentes; el manual del orchestrator era la mayor parte y su regla "no escribes código" chocaba con el rol de los devs. Verificado: el `SessionStart` no llega a los subagentes; el `CLAUDE.md` sí.

**Decisión:** nivel 1 `global/CLAUDE.md` (siempre; ≤ 10 KB y ≤ 130 líneas, con test de regresión): idioma, rol corto de la sesión principal, workflow, invariantes de merge, gitflow, hooks, verificación pre-commit, reglas operativas comunes. Nivel 2 `skills/orchestrator/SKILL.md` (< 500 líneas, invocable por el modelo, cargada al iniciar trabajo que termina en PR): fases, equipo, lotes, tracker, pause/resume. Nivel 3 `rulebooks/orchestrator-runbook.md`: formatos y comandos exactos, bajo demanda. Cada nivel remite al siguiente por nombre de sección; nada se copia hacia arriba.

**Implicación:** una regla nueva entra en el nivel más bajo que la necesita; si sube al núcleo tiene que caber en el tope y aplicar a todos los subagentes. Medir tokens con `claude -p --output-format json` en dos repos temporales (con y sin el archivo) cuando se toque el núcleo.

### [2026-09-26] Especialidades como rulebooks, agentes solo por frontera de contexto

**Contexto:** 13 agentes divididos por tipo de problema; el log de `SubagentStop` muestra 2 invocaciones de `build-resolver` y 2 de `db-specialist` frente a ~80 de `backend-dev`. Guía oficial: dividir por límites de contexto, no por tipo de problema.

**Decisión:** un agente aparte se justifica cuando necesita un contexto que el invocador no tiene o no debe cargar (fresco, aislado, o de otro tamaño): reviewers, `docs` (diff completo con contexto fresco), `ui-ux` (produce archivos grandes que el architect solo consume resumidos). El conocimiento de una especialidad sin esa frontera vive en `rulebooks/<tema>.md` y lo carga el dev cuando el lote lo pide (`build-errors.md`, `db-migrations.md`).

**Implicación:** antes de proponer un agente nuevo, nombrar la frontera de contexto que lo justifica; si no hay, es un rulebook. El lint de frontmatter verifica que toda referencia a un agente corresponda a un archivo en `agents/`.

### [2026-09-26] Frontmatter de agentes y skills: lint propio, no el validador del plugin

**Contexto:** `claude plugin validate --strict agents` pasa con `memory: true` (inválido) y `permissionMode` (ignorado en plugins). Con `marketplace.json` presente, `validate .` valida solo el marketplace; la validación del plugin es `--strict .claude-plugin/plugin.json`, que advierte por un `CLAUDE.md` en la raíz.

**Decisión:** el `CLAUDE.md` del repo vive en `.claude/CLAUDE.md` (carga igual como instrucciones del proyecto; verificado). La validación documentada corre ambas formas. `tests/adversarial/test-frontmatter.sh` es la fuente de verdad de campos permitidos/prohibidos y valores válidos en `agents/*.md` y `skills/*/SKILL.md`, incluida la forma `Agent(methodology:<agente>)` (el nombre pelado no matchea a un agente de plugin; verificado). `maxTurns` no se configura: el budget se controla con el cap de 5 tareas y commit por tarea.

**Implicación:** un campo nuevo de frontmatter se agrega primero al lint; una skill con efectos secundarios lleva `disable-model-invocation: true`, una que el orchestrator debe poder cargar solo no lo lleva.

### [2026-08-14] Review dual pre-push (Fase 2.6): el PR nace revisado

**Contexto:** el review dual corría después de crear el PR; cada ronda de fixes post-PR era un push extra = un run extra de GitHub Actions (minutos contados en repos privados). Los reviewers son subagentes locales (Read/Grep/Bash sobre el working tree) — nunca necesitaron el branch pusheado.

**Decisión:** el review dual (security + qa-*) corre por default en la **Fase 2.6**, nueva entre docs (2.5) y push + PR (2.7), sobre el **diff local** (`git diff <base>...HEAD`); las rondas de fixes pre-PR no pushean nada. Sin renumerar fases existentes: 2.6 entra en el hueco y Fase 3 conserva número redefinida como post-PR (re-reviews condicionales, E2E Modo B, pre-merge, merge). Registro pre-PR en `.planning/reviews/pre-pr-<feature-slug>.md`, reconciliado a `PR-<N>.md` con `git mv` + commit + push inmediato al crear el PR. `post-pr-create.sh` queda como checkpoint de respaldo: distingue "PR del flujo ya revisado" (state.json con `phases.review=done` y `branch` actual) de "PR fuera del flujo" (instruye lanzar el review), fallando siempre hacia el review.

**Justificación:** los fixes viajan en el push inicial → un solo run de CI por PR en el caso normal. El invariante "review dual bloqueante antes de merge" no cambia — solo se adelanta el momento. Evidencia del costo cero del caso remoto: el scaffold de `new-project` genera `ci.yml` con triggers `push: dev` + `pull_request: main/dev` y `security.yml` solo `pull_request: main` + cron, así que pushear `feature/*` sin PR no dispara workflows. La reconciliación inmediata cuesta neto un run gracias a `concurrency cancel-in-progress` (pr-workflow 5.5, obligatoria). Alternativas descartadas: dos convenciones permanentes de naming (fragmenta la historia de review de un PR entre dos archivos), predecir el número de PR vía API (racy), y diferir el rename a un push posterior (puede no existir; commit local se pierde al borrar el branch).

**Implicación:** los reviewers reciben la **fuente del diff parametrizada** por el orchestrator (local: base+branch; PR: número) — todo agente reviewer futuro se escribe así, sin asumir `gh pr diff`. Reviewers remotos son excepción con condición verificable: push del branch sin PR solo si ningún workflow dispara `on: push` sobre `feature/*`/`hotfix/*` (grep de triggers antes del push). La regla "un push por ronda" aplica solo a rondas post-PR. `phases.review` de `state.json` transiciona a `done` antes que `pr`/`ci` (sin bump de schema).

### [2026-08-14] Distribución: plugin de Claude Code + install.sh residual (híbrido)

**Contexto:** la metodología se distribuía con `install.sh` por symlinks de directorios a `~/.claude/`, con settings.json compartido (mezclaba prefs personales con registro de hooks) y sin resolver la carga global vs por proyecto de CLAUDE.md. Los plugins de Claude Code empaquetan skills+agents+hooks pero NO distribuyen CLAUDE.md, `rules/` ni `rulebooks/` (verificado contra CLI 2.1.232).

**Decisión:** el repo es **plugin y marketplace a la vez** (`.claude-plugin/plugin.json` + `marketplace.json`; hooks registrados en `hooks/hooks.json` vía `${CLAUDE_PLUGIN_ROOT}`). Lo que el plugin no cubre lo instala un `install.sh` residual: `global/CLAUDE.md` (curado, global-safe) → symlink a `~/.claude/CLAUDE.md`; `rules/`, `rulebooks/` y `statusline.sh` por symlink como antes. `settings.json` deja de distribuirse. El autor desarrolla con symlink `~/.claude/skills/methodology` → repo (plugin en vivo vía skills-dir); terceros instalan vía marketplace con versionado semver + `claude plugin tag`.

**Justificación:** el layout del repo ya coincidía con las convenciones del plugin (cero reestructuración); el mecanismo nativo elimina la clase de bug "hook documentado pero no instalado" (paridad hooks.json testeada) y da versionado/updates a terceros. Curar un CLAUDE.md global en vez de symlinkear el del repo evita duplicar ~200 líneas en sesiones dentro del repo y filtrar secciones repo-específicas a todos los proyectos. Alternativas descartadas: subdir `plugin/` (reestructura paths sin beneficio), symlink del CLAUDE.md entero (duplicación + drift), depreciar install.sh del todo (imposible: rules/rulebooks/CLAUDE.md quedan fuera del plugin).

**Implicación:** `global/CLAUDE.md` es canónico para la metodología operativa; el CLAUDE.md del repo solo lleva el delta repo-específico — nunca duplicar contenido entre ambos. Todo hook nuevo se registra en `hooks/hooks.json` (no en settings.json) y el test de paridad lo exige. Skills nuevas se auto-empaquetan (namespace `/methodology:<skill>`). Release = bump de versión + `claude plugin tag` + push.

### [2026-08-14] Slug de artefactos de hooks: `<basename>-<hash8>` (SHA-256 del toplevel)

**Contexto:** la convención anterior (`tr '/' '-'` sobre el path del toplevel) no es inyectiva: `/a/b-c` y `/a-b/c` colisionan y los repos se pisan snapshots/markers bajo `~/.claude/methodology/` (security review PR #49).

**Decisión:** slug = `basename` del toplevel saneado con allowlist `A-Za-z0-9_-` (vacío → `repo`) + `-` + primeros 8 hex del SHA-256 del path completo. Implementado en la lib compartida `hooks/lib/slug.sh` (`repo_slug()`), con cadena de fallback de herramienta de hash portable macOS/Linux: `shasum -a 256` → `sha256sum` → `md5 -q` → `md5sum`. Los artefactos con convención vieja (prefijo `-`) **se abandonan**: no se migran ni se leen ambos formatos.

**Justificación:** el hash del path completo elimina colisiones; el basename mantiene legibilidad humana. La consistencia del hash importa por máquina a lo largo del tiempo (los artefactos viven en `$HOME`), no entre máquinas, así que el fallback de herramienta es seguro. Abandonar los artefactos viejos: son efímeros y acotados (snapshots con retención 5, markers consume-once), migrar markers es ambiguo (no guardan el path del repo) y leer ambos formatos mantendría vivo el bug.

**Implicación:** todo hook futuro que necesite un directorio/archivo por repo bajo `~/.claude/methodology/` deriva el slug con `repo_slug()` de la lib — nunca inline. Modo degradado obligatorio: sin lib o sin herramienta de hash, los hooks de observabilidad hacen no-op `exit 0` (nunca bloquean) y los lectores saltan solo la sección afectada.

### [2026-08-14] Tests de hooks: sandbox obligatorio, nunca el repo real

**Contexto:** los tests de guards de `tests/adversarial/test-hooks.sh` hacían `git stash` + `git checkout main` sobre el repo real para testear `pre-push-guard`; en el PR #49 un checkout fallido dentro de Docker dejó el repo host en `main` con el trabajo en stash. Los tests de hooks de observabilidad ya usaban sandbox (repo git temporal + HOME override).

**Decisión:** **ningún test de la suite puede mutar el repo real.** Todo test que necesite estado git específico usa un sandbox (`mktemp` + `git init`, con branch/commits/remote fake bare según lo que el hook inspeccione) y HOME override si el hook escribe en `$HOME`. La suite incluye un guard de no-contaminación: branch y `git status --porcelain` del repo real se capturan al inicio y se comparan al final; cualquier diferencia es FAIL.

**Justificación:** la suite corre decenas de veces por feature (verificación por tarea de los devs, re-runs de QA, contenedores Docker) — cada corrida contra el repo real es una oportunidad de pérdida de estado. El sandbox además vuelve incondicionales tests que antes se saltaban en silencio si el stash fallaba.

**Implicación:** tests nuevos de hooks siguen el patrón sandbox desde el diseño (los helpers `sandbox_create*` son la infraestructura canónica); si un hook nuevo inspecciona estado git no cubierto por los helpers, se extiende el helper, nunca se recurre al repo real. El guard de no-contaminación atrapa regresiones de esta regla automáticamente.

### [2026-08-13] Artefactos operativos de hooks fuera del worktree, bajo `~/.claude/methodology/`

**Contexto:** los hooks de observabilidad nuevos (PreCompact, SubagentStop, SessionEnd) generan artefactos que mutan constantemente (logs de invocaciones, snapshots, markers entre sesiones). Guardarlos en `.planning/` ensuciaría `git status` en cada evento, se colaría en los commits per-tarea de los devs y metería ruido en cada PR; gitignorearlos desde un hook global sería invasivo en repos del usuario.

**Decisión:** todo artefacto operativo generado por hooks vive bajo la raíz única `~/.claude/methodology/` (`logs/`, `snapshots/<slug>/`, `session-end/`), fuera del worktree. Slug de repo = path del toplevel con `/` → `-` (misma convención que los directorios de proyectos de Claude Code). *(Superseded 2026-08-14: la convención de slug cambió a `<basename>-<hash8>` — ver entrada de esa fecha.)* Todo output acotado: retención de 5 snapshots por repo, rotación del log a 1 MB, markers que se sobrescriben.

**Justificación:** cero ruido git, sobrevive al cleanup de `.planning/`, agregable entre proyectos, y una sola raíz que documentar y limpiar. Alternativa descartada: archivos dentro de `.planning/` (ruido en diffs y riesgo de colarse en commits).

**Implicación:** futuros hooks de observabilidad escriben ahí, usan `$HOME` (nunca `~` literal — los tests hacen override de `HOME` para sandboxear), son siempre `exit 0` (observabilidad ≠ guard), y definen su política de retención/rotación desde el diseño. Lo que debe viajar en el PR (estado de la feature) sigue en `.planning/`.

### [2026-08-13] Estado mutable en JSON (`state.json`), prosa en markdown

**Contexto:** hallazgo de Anthropic (nov-2025): los modelos corrompen/sobrescriben menos JSON que markdown al mutar estado. El checklist de fases/lotes con pass-fail de `STATE.md` es exactamente ese caso.

**Decisión:** el estado enumerable y mutable (fase del pipeline, lotes con status/progreso, branch/PR) vive en `.planning/state.json` (archivo separado, no bloque fenced) con schema versionado (`"schema": 1`), enum cerrado de status y claves fijas. La prosa (decisiones, blockers descritos, BRIEF/DESIGN/LEARNINGS) sigue en markdown.

**Justificación:** un archivo JSON puro minimiza la superficie de mutación y es parseable por hooks (`session-start-context.sh` lo renderiza) sin extraerlo de un .md. Un bloque embebido en markdown mantiene el riesgo de que el modelo reescriba la prosa circundante o rompa el fence.

**Implicación:** todo estado futuro que los agentes muten con frecuencia se diseña como JSON con schema explícito y enum cerrado; markdown queda para contenido que se lee y razona, no que se muta. Formato canónico en `rulebooks/orchestrator-runbook.md`.

### [2026-08-13] Memoria del sistema de agentes: archivos en repo, no backend externo (Notion descartado)

**Contexto:** se evaluó mover la memoria/estado del sistema (`.planning/`, auto-memory) a Notion AI u otro backend externo, ante la duda de si la metodología de archivos markdown quedó obsoleta. Investigación completa en `AUDIT-memory-agents-2026-08.md`.

**Decisión:** la memoria del agente permanece en archivos versionados en el repo. No se adopta Notion ni ningún backend externo de estado.

**Justificación:** el MCP de Notion carga ~26k tokens de definiciones de tools por sesión y ~18k por escritura de un documento; un backend externo rompe el versionado atómico estado-código (divergencia silenciosa); y su valor diferencial real (visibilidad para no-técnicos, edición multi-persona concurrente) no existe con un solo usuario. Archivos-en-repo es además el patrón que Anthropic implementa en su propio memory tool y documenta como best practice; no hay equipos documentados en producción usando Notion como memoria de agentes de código.

**Implicación:** no reabrir el debate sin que cambie el contexto. Triggers de reevaluación: (a) aparece un stakeholder no-técnico que necesita visibilidad del estado, o (b) se suma un colaborador no-dev. En ese caso el paso correcto es GitHub Issues (vía `gh`) o Linear MCP para el backlog humano — el estado del agente sigue en el repo igual.
