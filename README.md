# Claude Code Methodology

Sistema de agentes especializados, hooks de automatización y workflows para desarrollo fullstack con Claude Code.

## Qué incluye

El **orchestrator** no es un subagente: es el Claude de la sesión principal, definido en `global/CLAUDE.md` (instalado como `~/.claude/CLAUDE.md`). Coordina el flujo (brainstorming → diseño → implementación → review → merge) y delega en estos 13 agentes:

### Agentes (13)
| Agente | Modelo | Rol |
|--------|--------|-----|
| **architect** | fable | Diseña soluciones, define contratos/schemas, descompone en tareas atómicas |
| **ui-ux** | opus | Genera el design system y valida flujos antes de que el frontend implemente |
| **backend-dev** | sonnet | Implementa backend con TDD, gitflow, verificación pre-commit |
| **frontend-dev** | sonnet | Implementa frontend (capa delgada, cero lógica de negocio) |
| **db-specialist** | sonnet | Esquemas complejos, migraciones con backfill, optimización de queries |
| **security-reviewer** | opus | Auditoría OWASP Top 10, secrets, dependencias (read-only) |
| **qa-frontend** | sonnet | UX, accesibilidad, componentes, estado UI, tests frontend, coverage ≥ 80% |
| **qa-backend** | sonnet | Contratos de API, lógica de negocio, datos, tests backend, coverage ≥ 80% |
| **e2e-runner** | sonnet | Tests E2E con Playwright. Bloqueante en pre-release a `main` |
| **build-resolver** | sonnet | Diagnostica y resuelve errores de build, compilación y dependencias |
| **refactor** | sonnet | Refactoriza sin cambiar comportamiento. Consume issues de deuda técnica |
| **latent-bugs-sweep** | sonnet | Escanea el repo buscando bugs latentes (read-only). Crea issues |
| **docs** | sonnet | Genera/actualiza documentación a partir del diff, antes del push |

### Hooks (14)
| Hook | Evento | Qué hace |
|------|--------|----------|
| **pre-commit-guard** | PreToolUse (Bash) | Corre tests antes de cada commit. Detecta pnpm/yarn/npm/pytest |
| **pre-push-guard** | PreToolUse (Bash) | Bloquea push directo a main |
| **block-admin-merge** | PreToolUse (Bash) | Bloquea `gh pr merge --admin` que bypasea branch protections |
| **block-force-push** | PreToolUse (Bash) | Bloquea `git push --force` / `-f` |
| **block-hard-reset** | PreToolUse (Bash) | Bloquea `git reset --hard` |
| **pre-merge-check** | PreToolUse (Bash) | Bloquea `gh pr merge` sin número de PR explícito, con threads de review sin resolver o reviews/checks pendientes (fail-closed si no puede verificar) |
| **pre-release-sweep** | PreToolUse (Bash) | Dispara `latent-bugs-sweep` antes de un `gh pr create --base main` |
| **post-pr-create** | PostToolUse (Bash) | Instruye al orquestador para disparar security-reviewer + qa-frontend/qa-backend (según capas del diff) al crear un PR |
| **session-start-context** | SessionStart | Muestra branch, último commit, estado de .planning/, marker de SessionEnd y resumen de state.json |
| **context-monitor** | PostToolUse (Bash) | Avisa cuando el contexto se está agotando (35% warning, 25% critical) |
| **docker-refresh** | PostToolUse (Bash) | Detecta si servicios Docker necesitan restart/rebuild después de push o PR. Respeta hot reload |
| **pre-compact-snapshot** | PreCompact | Guarda un snapshot de `.planning/` antes de compactar el contexto, para restaurar si el compact deja el estado inconsistente |
| **subagent-stop-log** | SubagentStop | Appendea una línea JSONL por invocación de subagente, para medir el budget de `agent-budget.md` |
| **session-end-check** | SessionEnd | Detecta STATE.md desactualizado (commits o archivos dirty posteriores) y deja un marker que avisa en la próxima sesión |

Los tres hooks de observabilidad (`pre-compact-snapshot`, `subagent-stop-log`, `session-end-check`) escriben sus artefactos bajo `~/.claude/methodology/` (`snapshots/`, `logs/`, `session-end/`, uno por repo vía slug) con retención acotada (5 snapshots más recientes por repo, log rotado a `.old` al superar 1 MB, marker de sesión sobrescrito en cada cierre); el directorio entero se puede borrar sin riesgo — se regenera solo en la siguiente invocación de cada hook.

### Skills (4)
| Skill | Qué hace |
|-------|----------|
| **/new-project** | Scaffold de proyecto con gitflow, GitHub Actions CI/CD, CLAUDE.md |
| **/refactor-scan** | Escanea el codebase buscando code smells y genera un reporte priorizado |
| **/pr-workflow** | Presupuesto de CI, E2E pre-release, branch protection y verificación pre-merge — se invoca en Fase 2.7 o al trabajar sobre un PR existente |
| **/review-pr** | Re-dispara manualmente el review dual (security + QA según capas tocadas) sobre un PR existente, sin pasar por el flujo completo del orchestrator |

## Workflow

```
Idea → Brainstorming (orchestrator pregunta) → Brief
  → Architect diseña + escribe schemas/contratos
  → Devs implementan con TDD (Red → Green → Refactor)
  → PR creado → Security + QA (qa-frontend y/o qa-backend según capas) review en paralelo
  → Si hay issues → Dev corrige en mismo PR → Re-review
  → Todos aprueban → Merge
```

## Reglas enforced

- **80% test coverage** mínimo para mergear
- **Dual review** obligatorio (security + QA frontend/backend según capas del diff)
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

1. Bump de `version` en `.claude-plugin/plugin.json`.
2. `claude plugin tag` — valida consistencia `plugin.json` ↔ `marketplace.json` y crea el tag git `methodology--v<version>`.
3. Push del tag.

Terceros actualizan con `claude plugin marketplace update` + `claude plugin update methodology@claude-methodology` — el cache del plugin queda fijo en la versión instalada hasta ese punto.

### Limpieza opcional de artefactos con slug viejo

Los hooks de observabilidad `pre-compact-snapshot` y `session-end-check` escriben bajo `~/.claude/methodology/{snapshots,session-end}/<slug>/`, con `<slug>` = `basename-hash8` del path del repo (ver `hooks/lib/slug.sh`). Instalaciones de antes de este cambio de convención pueden tener artefactos huérfanos bajo el slug viejo (`tr '/' '-'` del path completo) — son inertes y se pueden borrar sin riesgo. `~/.claude/methodology/` completo también se puede borrar sin riesgo: se regenera solo en la siguiente invocación de cada hook.

## Estructura

```
claude-methodology/
├── .claude-plugin/
│   ├── marketplace.json
│   └── plugin.json
├── agents/
│   ├── architect.md
│   ├── backend-dev.md
│   ├── build-resolver.md
│   ├── db-specialist.md
│   ├── docs.md
│   ├── e2e-runner.md
│   ├── frontend-dev.md
│   ├── latent-bugs-sweep.md
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
│   │   └── slug.sh
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
│   ├── dev-common.md
│   ├── governance-playbook.md
│   ├── orchestrator-runbook.md
│   └── validation-schedule.md
├── skills/
│   ├── new-project/
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

Los agentes detectan el stack del proyecto leyendo CLAUDE.md. Funcionan con:
- **Node.js** (pnpm/yarn/npm) + TypeScript/JavaScript
- **Python** (pip/poetry) + pytest
- **Cualquier framework** — el CLAUDE.md del proyecto define convenciones

El architect escribe schemas en la herramienta del proyecto (Zod, Pydantic, Go structs, etc.).
