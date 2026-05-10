# Claude Code Methodology

Sistema de agentes especializados, hooks de automatización y workflows para desarrollo fullstack con Claude Code.

## Qué incluye

### Agentes (8)
| Agente | Modelo | Rol |
|--------|--------|-----|
| **orchestrator** | opus | Coordina todo el flujo: brainstorming → diseño → implementación → review → merge |
| **architect** | opus | Diseña soluciones, define contratos/schemas, descompone en tareas atómicas |
| **backend-dev** | sonnet | Implementa backend con TDD, gitflow, verificación pre-commit |
| **frontend-dev** | sonnet | Implementa frontend (capa delgada, cero lógica de negocio) |
| **db-specialist** | sonnet | Diseño de esquemas, migraciones, optimización de queries |
| **security-reviewer** | opus | Auditoría OWASP Top 10, secrets, dependencias (read-only) |
| **qa-frontend** | sonnet | UX, accesibilidad, componentes, estado UI, tests frontend, coverage ≥ 80% |
| **qa-backend** | sonnet | Contratos de API, lógica de negocio, datos, tests backend, coverage ≥ 80% |

### Hooks (10)
| Hook | Evento | Qué hace |
|------|--------|----------|
| **pre-commit-guard** | PreToolUse (Bash) | Corre tests antes de cada commit. Detecta pnpm/yarn/npm/pytest |
| **pre-push-guard** | PreToolUse (Bash) | Bloquea push directo a main |
| **block-admin-merge** | PreToolUse (Bash) | Bloquea `gh pr merge --admin` que bypasea branch protections |
| **block-force-push** | PreToolUse (Bash) | Bloquea `git push --force` / `-f` |
| **block-hard-reset** | PreToolUse (Bash) | Bloquea `git reset --hard` |
| **pre-merge-check** | PreToolUse (Bash) | Bloquea `gh pr merge` si hay comentarios, reviews o checks pendientes |
| **post-pr-create** | PostToolUse (Bash) | Instruye al orquestador para disparar security-reviewer + qa-frontend/qa-backend (según capas del diff) al crear un PR |
| **session-start-context** | SessionStart | Muestra branch, último commit, estado de .planning/ |
| **context-monitor** | PostToolUse (Bash) | Avisa cuando el contexto se está agotando (35% warning, 25% critical) |
| **docker-refresh** | PostToolUse (Bash) | Detecta si servicios Docker necesitan restart/rebuild después de push o PR. Respeta hot reload |

### Skills (1)
| Skill | Qué hace |
|-------|----------|
| **/new-project** | Scaffold de proyecto con gitflow, GitHub Actions CI/CD, CLAUDE.md |

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
│   └── docker-refresh.sh
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
