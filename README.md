# Claude Code Methodology

Sistema de agentes especializados, hooks de automatización y workflows para desarrollo fullstack con Claude Code.

## Qué incluye

El **orchestrator** no es un subagente: es el Claude de la sesión principal, definido en `CLAUDE.md`. Coordina el flujo (brainstorming → diseño → implementación → review → merge) y delega en estos 13 agentes:

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

### Skills (2)
| Skill | Qué hace |
|-------|----------|
| **/new-project** | Scaffold de proyecto con gitflow, GitHub Actions CI/CD, CLAUDE.md |
| **/refactor-scan** | Escanea el codebase buscando code smells y genera un reporte priorizado |

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

```bash
git clone https://github.com/TU_USUARIO/claude-methodology.git
cd claude-methodology
./install.sh --symlink   # Symlinks (cambios en repo se reflejan)
./install.sh --copy      # Copia independiente
```

## Estructura

```
claude-methodology/
├── agents/
│   ├── architect.md
│   ├── backend-dev.md
│   ├── frontend-dev.md
│   ├── db-specialist.md
│   ├── qa-frontend.md
│   ├── qa-backend.md
│   └── security-reviewer.md
├── hooks/
│   ├── pre-commit-guard.sh
│   ├── pre-push-guard.sh
│   ├── block-admin-merge.sh
│   ├── block-force-push.sh
│   ├── block-hard-reset.sh
│   ├── pre-merge-check.sh
│   ├── post-pr-create.sh
│   ├── session-start-context.sh
│   ├── context-monitor.sh
│   ├── docker-refresh.sh
│   ├── pre-compact-snapshot.sh
│   ├── subagent-stop-log.sh
│   └── session-end-check.sh
├── skills/
│   └── new-project/
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
