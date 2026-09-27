# Claude Code Methodology

Sistema de agentes especializados, hooks de automatización y workflows para desarrollo fullstack con Claude Code.

## Qué incluye

El **orchestrator** no es un subagente: es el Claude de la sesión principal. Las invariantes viven en `global/CLAUDE.md` (instalado como `~/.claude/CLAUDE.md`); el manual operativo — fases 0 a 5, equipo de subagentes, lotes — vive en la skill `orchestrator`. Coordina el flujo (brainstorming → diseño → implementación → review → merge) y delega en estos 12 agentes:

### Agentes (12)
| Agente | Modelo | Rol |
|--------|--------|-----|
| **product-reviewer** | opus | Cuestiona si la feature vale la pena y deja resultado esperado y criterios de aceptación medibles (read-only, no bloquea). Solo en proyectos con `Tipo: producto con usuarios` |
| **architect** | fable | Diseña soluciones, define contratos/schemas, descompone en tareas atómicas |
| **ui-ux** | opus | Genera el design system y valida flujos antes de que el frontend implemente |
| **backend-dev** | sonnet | Implementa backend con TDD, gitflow, verificación pre-commit; esquemas complejos, migraciones con backfill y optimización de queries en lotes `db-complejo` |
| **frontend-dev** | sonnet | Implementa frontend (capa delgada, cero lógica de negocio) |
| **security-reviewer** | opus | Auditoría OWASP Top 10, secrets, dependencias (read-only) |
| **qa-frontend** | sonnet | UX, accesibilidad, componentes, estado UI, tests frontend, coverage ≥ 80% |
| **qa-backend** | sonnet | Contratos de API, lógica de negocio, datos, tests backend, coverage ≥ 80% |
| **e2e-runner** | sonnet | Tests E2E con Playwright. Bloqueante en pre-release a `main` |
| **refactor** | sonnet | Refactoriza sin cambiar comportamiento. Consume issues de deuda técnica |
| **latent-bugs-sweep** | sonnet | Escanea el repo buscando bugs latentes (read-only). Crea issues |
| **docs** | sonnet | Genera/actualiza documentación a partir del diff, antes del push |

### Hooks (14)
| Hook | Evento | Qué hace |
|------|--------|----------|
| **pre-commit-guard** | PreToolUse (Bash) | Resuelve el árbol al que va el commit —cwd de la sesión, `cd <ruta> && git commit`, o `git -C <ruta> commit`, allowlist de tres formas— y corre tests ahí. Detecta pnpm/yarn/npm/pytest. En monorepos npm/pnpm acota la corrida a los workspaces tocados (`hooks/lib/workspace-scope.sh`); si no puede resolverlo con confianza, corre todo. Sin marcador de runner (`package.json`/`pyproject.toml`/`setup.py`/`pytest.ini`) en la raíz del árbol resuelto (#86): corre el runner de cada archivo con cambios locales que sí tenga uno arriba suyo (todos, sin cortar en el primer fallo) y no bloquea si ninguno tiene — bloquear rompería cualquier repo sin runner. Se descartan de esa derivación (sin bloquear, solo se ignoran como candidatos): directorios sin trackear enteros o repos git anidados (una línea de `git status` que colapsa a un directorio, o cualquier ancestro con su propio `.git`), y cualquier path con un segmento `node_modules`, `vendor`, `fixtures`, `__fixtures__` o `testdata` — nunca son código del usuario. Se omite cuando lo único con cambios locales en el árbol resuelto es `.planning/`. Cualquier otra redirección (`--git-dir`/`--work-tree`, `GIT_DIR`/`GIT_WORK_TREE`, `pushd`, dos `cd`, ruta con comillas/variables) bloquea sin correr, con las formas aceptadas en el mensaje. Watchdog fail-closed: si la suma de las corridas supera `PRECOMMIT_TEST_BUDGET` segundos (default 540, overridable por env, presupuesto compartido entre corridas), mata el grupo de procesos y bloquea en vez de dejar pasar el commit sin tests |
| **pre-push-guard** | PreToolUse (Bash) | Bloquea push directo a main (branch resuelto del `.cwd` de la sesión, no del cwd del proceso). Detección saneada+anclada: `git commit -m x && git push origin main`, `npm test && git push`. Fail-closed sin jq; cualquier redirección (`cd`, `git -C`, `--git-dir`/`--work-tree`, `GIT_DIR=`/`GIT_WORK_TREE=`) bloquea sin resolverla — hacé el cd en una llamada previa |
| **block-admin-merge** | PreToolUse (Bash) | Bloquea `gh pr merge --admin` que bypasea branch protections; también `gh -R o/r pr merge --admin` y `gh pr -R o/r merge --admin` |
| **block-force-push** | PreToolUse (Bash) | Bloquea `git push --force` / `-f`; también un refspec forzado (`+<ref>`), un cluster corto con `f` (`-fu`, `-uf`) y `git -C <ruta> push` |
| **block-hard-reset** | PreToolUse (Bash) | Bloquea `git reset --hard`, incluido `git -C <ruta> reset --hard` |
| **pre-merge-check** | PreToolUse (Bash) | Cuando reconoce la invocación (detalle de qué formas reconoce en el propio hook), solo acepta `gh pr merge <N> [flags conocidos]` sola en el comando y en una línea; bloquea con threads de review sin resolver, reviews/checks pendientes, sin número de PR explícito, o si no puede verificar (fail-closed). Para un PR de otro repo, usa `--repo`/`-R` explícito, nunca `cd`. Sin `--repo`, si el cwd de la sesión no coincide con el cwd donde corre el hook (o no existe), bloquea sin consultar y pide `--repo owner/repo` |
| **pre-release-sweep** | PreToolUse (Bash) | Dispara `latent-bugs-sweep` antes de un `gh pr create --base main` (también `-B main`/`--base=main`). Detección saneada+anclada: `cd . && gh pr create --base main` bloquea igual. Fail-closed sin jq o sin gh. No resuelve el `cd`: el diff sigue calculándose en el cwd de la sesión, no en la ruta del `cd` del comando |
| **post-pr-create** | PostToolUse (Bash) | Checkpoint de respaldo al crear un PR: verifica en `state.json` que el review dual pre-push ocurrió y recuerda la reconciliación del registro; si no hay evidencia, instruye lanzar el review (PR fuera del flujo) |
| **session-start-context** | SessionStart | Muestra branch, último commit, estado de .planning/, marker de SessionEnd y resumen de state.json |
| **context-monitor** | PostToolUse (Bash) | Avisa cuando el contexto se está agotando (35% warning, 25% critical) |
| **docker-refresh** | PostToolUse (Bash) | Detecta si servicios Docker necesitan restart/rebuild después de push o PR. Respeta hot reload |
| **pre-compact-snapshot** | PreCompact | Guarda un snapshot de `.planning/` antes de compactar el contexto, para restaurar si el compact deja el estado inconsistente |
| **subagent-stop-log** | SubagentStop | Appendea una línea JSONL por invocación de subagente, para medir el budget de `agent-budget.md` |
| **session-end-check** | SessionEnd | Detecta STATE.md desactualizado (commits o archivos dirty posteriores) y deja un marker que avisa en la próxima sesión |

Los tres hooks de observabilidad (`pre-compact-snapshot`, `subagent-stop-log`, `session-end-check`) escriben sus artefactos bajo `~/.claude/methodology/` (`snapshots/`, `logs/`, `session-end/`, uno por repo vía slug) con retención acotada (5 snapshots más recientes por repo, log rotado a `.old` al superar 1 MB, marker de sesión sobrescrito en cada cierre); el directorio entero se puede borrar sin riesgo — se regenera solo en la siguiente invocación de cada hook.

#### Fuera de alcance de los guards (documentado, no parcheado — #77, D-05)

Los guards de `hooks/` protegen errores honestos del orchestrator y los devs: formas que alguien escribe de buena fe. No son un parser de shell ni un control de evasión. Verificado contra los hooks reales (2026-09-27), estas formas pasan sin bloquear y quedan así por decisión:

- comillas partidas o escapadas que rompen el emparejamiento del saneo: `echo \'; gh pr merge 5; echo \'`, `$'it\'s' && gh pr merge 5`;
- heredoc con delimitador comillado a medias (`<<E"OF"`), delimitador con caracteres fuera de `[A-Za-z0-9_-]`, o una línea del cuerpo que termina en `\` justo antes del terminador;
- la flag o el subcomando en una variable (`F=--force; git push $F`), `eval`, `bash -c '…'`/`sh -c`, alias y funciones de git/gh definidas en el mismo comando o en uno anterior (`w() { gh "$@"; }; w pr merge 5` pasa);
- la palabra del binario alterada o disfrazada: `"gh"`, `g\h`, `env git …`, `/usr/bin/git …`, `command git …` (el `if` de `hooks.json` tampoco dispara para las tres últimas: compara cada subcomando por prefijo y solo descarta asignaciones `VAR=x` al frente; ver la tabla "Bash if matching" de la doc de hooks).

Si una de estas formas bloquea o se cuela, no es un bug a arreglar acá: la salida es escribir el comando en su forma directa.

### Skills (5)
| Skill | Qué hace |
|-------|----------|
| **orchestrator** | Manual operativo de la sesión principal: fases 0 a 5, equipo de subagentes, lotes y handoff, tracker de sesión, pause/resume — se carga al iniciar cualquier trabajo que termine en un PR |
| **/new-project** | Scaffold de proyecto con gitflow, GitHub Actions CI/CD, CLAUDE.md |
| **/refactor-scan** | Escanea el codebase buscando code smells y genera un reporte priorizado |
| **/pr-workflow** | Review dual local pre-push, presupuesto de CI, E2E pre-release, branch protection y verificación pre-merge — se invoca en Fase 2.6 o al trabajar sobre un PR existente |
| **/review-pr** | Re-dispara manualmente el review dual (security + QA según capas tocadas) sobre un PR existente, sin pasar por el flujo completo del orchestrator |

## Workflow

```
Idea → Brainstorming (orchestrator pregunta) → Brief
  → Product reviewer (solo productos con usuarios): ¿vale la pena?, resultado esperado, criterios de aceptación
  → Architect diseña + escribe schemas/contratos
  → Devs implementan con TDD (Red → Green → Refactor)
  → Review dual local pre-push → Security + QA (qa-frontend y/o qa-backend según capas) en paralelo
  → Si hay issues → Dev corrige en el mismo branch, sin push → Re-review
  → Veredictos limpios → Push + PR (nace revisado) → CI → Merge
```

## Reglas enforced

- **80% test coverage** mínimo para mergear
- **Dual review** obligatorio, pre-push por default (security + QA frontend/backend según capas del diff)
- **TDD** obligatorio (test antes que código)
- **Build debe compilar** antes de commit
- **No push directo a main**
- **No stubs/TODOs** en código mergeado
- **Frontend delgado** — cero lógica de negocio
- **Estado persistente** en `.planning/` — sobrevive cambios de sesión

## Instalación

Este repo es **plugin y marketplace de Claude Code a la vez**: instala agents/, hooks/ (registrados en `hooks/hooks.json`) y skills/ (namespace `/methodology:<skill>`, ej. `/methodology:pr-workflow`) por el mecanismo nativo de plugins. Los plugins de Claude Code **no** cargan `CLAUDE.md`, `rules/` ni `rulebooks/` — para eso hace falta el `install.sh` residual del repo clonado.

### Terceros

```bash
claude plugin marketplace add aveloz89/claude-methodology
claude plugin install methodology@claude-methodology   # agents, hooks, skills

git clone https://github.com/aveloz89/claude-methodology.git
cd claude-methodology
./install.sh                                            # residual: CLAUDE.md global, rules/, rulebooks/, statusline.sh
```

`install.sh` es idempotente (correrlo N veces deja el mismo estado) y nunca sobreescribe un archivo o directorio real del usuario: si el destino ya existe y no es un symlink hacia este repo, avisa y lo deja intacto.

### Autor (dev-loop)

El autor no instala el plugin propio vía marketplace — duplicaría la carga. `install.sh` crea el symlink `~/.claude/skills/methodology` → raíz del repo, que Claude Code auto-carga en vivo como `methodology@skills-dir`: cualquier cambio en `agents/`, `hooks/` o `skills/` está disponible en la próxima sesión, sin reinstalar ni hacer version bump.

```bash
./install.sh
```

### Transición desde instalaciones por symlink (versiones anteriores)

Antes del plugin, el repo se instalaba symlinkeando `agents/`, `hooks/`, `skills/` y `settings.json` completos a `~/.claude/`. `install.sh` migra esa instalación automáticamente la primera vez que se corre después de actualizar:

- `~/.claude/agents` y `~/.claude/hooks`: si son symlinks a este repo, se eliminan (ahora los provee el plugin). Si son directorios reales, no se tocan — quedan para revisión manual.
- `~/.claude/skills`: si es symlink al repo completo, se reemplaza por un directorio real con el symlink dev-loop `skills/methodology` adentro.
- `~/.claude/settings.json`: si es symlink a este repo, se **materializa** como archivo real (copia del contenido vigente) para desacoplar la config viva del working tree. `settings.json` deja de distribuirse por `install.sh` — el registro de hooks vive en `hooks/hooks.json`.

### Release (para el autor)

1. Validar antes de tocar manifests o agentes: `claude plugin validate --strict .claude-plugin/plugin.json` y `claude plugin validate --strict .` (con `marketplace.json` presente, este segundo valida solo el marketplace).
2. Bump de `version` en `.claude-plugin/plugin.json`.
3. `claude plugin tag` — valida consistencia `plugin.json` ↔ `marketplace.json` y crea el tag git `methodology--v<version>`.
4. Push del tag.

Terceros actualizan con `claude plugin marketplace update` + `claude plugin update methodology@claude-methodology` — el cache del plugin queda fijo en la versión instalada hasta ese punto.

### Limpieza opcional de artefactos con slug viejo

Los hooks de observabilidad `pre-compact-snapshot` y `session-end-check` escriben bajo `~/.claude/methodology/{snapshots,session-end}/<slug>/`, con `<slug>` = `basename-hash8` del path del repo (ver `hooks/lib/slug.sh`). Instalaciones de antes de este cambio de convención pueden tener artefactos huérfanos bajo el slug viejo (`tr '/' '-'` del path completo) — son inertes y se pueden borrar sin riesgo. `~/.claude/methodology/` completo también se puede borrar sin riesgo: se regenera solo en la siguiente invocación de cada hook.

## Estructura

```
claude-methodology/
├── .claude/
│   └── CLAUDE.md
├── .claude-plugin/
│   ├── marketplace.json
│   └── plugin.json
├── agents/
│   ├── architect.md
│   ├── backend-dev.md
│   ├── docs.md
│   ├── e2e-runner.md
│   ├── frontend-dev.md
│   ├── latent-bugs-sweep.md
│   ├── product-reviewer.md
│   ├── qa-backend.md
│   ├── qa-frontend.md
│   ├── refactor.md
│   ├── security-reviewer.md
│   └── ui-ux.md
├── global/
│   └── CLAUDE.md
├── hooks/
│   ├── block-admin-merge.sh
│   ├── block-force-push.sh
│   ├── block-hard-reset.sh
│   ├── context-monitor.sh
│   ├── docker-refresh.sh
│   ├── hooks.json
│   ├── lib/
│   │   ├── guard-matching.sh
│   │   ├── slug.sh
│   │   └── workspace-scope.sh
│   ├── post-pr-create.sh
│   ├── pre-commit-guard.sh
│   ├── pre-compact-snapshot.sh
│   ├── pre-merge-check.sh
│   ├── pre-push-guard.sh
│   ├── pre-release-sweep.sh
│   ├── session-end-check.sh
│   ├── session-start-context.sh
│   └── subagent-stop-log.sh
├── rules/
│   ├── bash.md
│   ├── csharp.md
│   ├── css.md
│   ├── docker.md
│   ├── go.md
│   ├── html.md
│   ├── implementation-principles.md
│   ├── python.md
│   ├── rust.md
│   ├── self-reflection.md
│   └── typescript.md
├── rulebooks/
│   ├── agent-budget.md
│   ├── build-errors.md
│   ├── db-migrations.md
│   ├── dev-common.md
│   ├── governance-playbook.md
│   ├── orchestrator-runbook.md
│   └── validation-schedule.md
├── skills/
│   ├── new-project/
│   │   └── SKILL.md
│   ├── orchestrator/
│   │   └── SKILL.md
│   ├── pr-workflow/
│   │   └── SKILL.md
│   ├── refactor-scan/
│   │   └── SKILL.md
│   └── review-pr/
│       └── SKILL.md
├── settings.json
├── install.sh
└── README.md
```

## Stack-agnóstico

Si el `CLAUDE.md` del proyecto tiene la línea `Tipo: producto con usuarios`, el orchestrator invoca `product-reviewer` después del brainstorming de cada feature nueva. Sin la línea no corre; `/new-project` la escribe al preguntar el tipo de proyecto. En un proyecto ya existente, actívalo agregando esa línea a mano en el `CLAUDE.md` del proyecto.

Los agentes detectan el stack del proyecto leyendo CLAUDE.md. Funcionan con:
- **Node.js** (pnpm/yarn/npm) + TypeScript/JavaScript
- **Python** (pip/poetry) + pytest
- **Cualquier framework** — el CLAUDE.md del proyecto define convenciones

El architect escribe schemas en la herramienta del proyecto (Zod, Pydantic, Go structs, etc.).
