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
