# Claude Methodology

Sistema de agentes especializados, hooks y workflows para desarrollo fullstack con Claude Code.

## Workflow obligatorio

1. **Brainstorming antes de diseñar** — El orchestrator entiende el requerimiento haciendo preguntas antes de pasar al architect. Solo se salta para bug fixes y tareas técnicas acotadas
2. **Diseño antes de código** — El architect diseña la solución (estructura, contratos, schemas) antes de que los devs implementen
3. **TDD obligatorio** — Red → Green → Refactor. Nunca código de producción sin un test que falle primero
4. **Dual review obligatorio** — security-reviewer + QA (qa-frontend y/o qa-backend según capas del diff) deben aprobar antes de merge
5. **80% test coverage mínimo** — PRs con menos de 80% no se mergean

## Gitflow

- **Branches**: `main` (producción) ← PR ← `dev` (desarrollo) ← `feature/*` | `hotfix/*`
- **Nunca push directo a main** — siempre por PR
- **Nunca trabajar en main o dev directamente** — crear feature branch
- Features: `git checkout dev && git checkout -b feature/descripcion-corta`
- Hotfixes: `git checkout main && git checkout -b hotfix/descripcion-corta`
- PRs de features van a `dev`, hotfixes a `main`
- Merges siempre con `--no-ff`
- Commits atómicos con mensajes descriptivos en imperativo

## Comandos bloqueados por hooks

| Comando | Hook | Razón |
|---------|------|-------|
| Push directo a main | `pre-push-guard.sh` | Debe hacerse por PR |
| `gh pr merge --admin` | `block-admin-merge.sh` | Bypasea branch protections |
| `git push --force` / `-f` | `block-force-push.sh` | Sobrescribe historia remota |
| `git reset --hard` | `block-hard-reset.sh` | Pérdida irreversible de cambios |
| `gh pr merge` con comentarios/checks pendientes | `pre-merge-check.sh` | Verifica comentarios, reviews y CI antes de merge |

## Hooks automáticos

| Hook | Evento | Qué hace |
|------|--------|----------|
| `pre-commit-guard.sh` | PreToolUse (Bash) | Corre tests antes de cada commit (detecta pnpm/yarn/npm/pytest) |
| `post-pr-create.sh` | PostToolUse (Bash) | Dispara review automático de QA + security al crear PR |
| `session-start-context.sh` | SessionStart | Muestra branch, último commit, estado de `.planning/` |
| `context-monitor.sh` | PostToolUse (Bash) | Avisa cuando el contexto se agota (35% warning, 25% critical) |
| `docker-refresh.sh` | PostToolUse (Bash) | Detecta si servicios Docker necesitan restart/rebuild después de push o PR |

## Verificación pre-commit (obligatoria para devs)

Antes de cada commit, los devs deben verificar:
1. Tests pasan con coverage ≥ 80%
2. Lint pasa sin errores (autofix primero, manual después)
3. Build compila sin errores
4. Docker container corre (si aplica)
5. Self-reflection contra `rules/self-reflection.md` (revisar código contra rules idiomáticas del lenguaje)

No se hace commit si falta alguna de estas verificaciones.

## Agentes

| Agente | Modelo | Rol |
|--------|--------|-----|
| `orchestrator` | opus | Coordina el flujo completo. No implementa — delega |
| `architect` | opus | Diseña soluciones, define contratos/schemas como código |
| `backend-dev` | sonnet | Implementa backend con TDD y gitflow |
| `frontend-dev` | sonnet | Implementa frontend (capa delgada, cero lógica de negocio) |
| `db-specialist` | sonnet | Esquemas, migraciones, optimización de queries |
| `security-reviewer` | opus | Auditoría OWASP Top 10, secrets, dependencias (read-only) |
| `qa-frontend` | sonnet | UX, accesibilidad, componentes, estado UI, tests frontend, coverage ≥ 80% |
| `qa-backend` | sonnet | Contratos de API, lógica de negocio, datos, tests backend, coverage ≥ 80% |
| `e2e-runner` | sonnet | Tests E2E con Playwright (cero mocks, sistema real) |
| `build-resolver` | sonnet | Diagnostica y resuelve errores de build/compilación |
| `refactor` | sonnet | Detecta code smells, refactoriza sin cambiar comportamiento |
| `docs` | sonnet | Genera/actualiza documentación a partir del diff del PR |

## Flujo completo

```
Brainstorming → Brief → Architect diseña → Devs implementan (TDD + Self-Reflection)
  → PR creado → CI checks → Docs genera/actualiza documentación
  → Security + QA (qa-frontend y/o qa-backend según capas del diff) review en paralelo
  → Correcciones en mismo PR → Re-review → Todos aprueban → Merge → Learn
```

## Estado persistente (.planning/)

El estado del trabajo se persiste en `.planning/` para sobrevivir cambios de sesión:
- `STATE.md` — fase actual, progreso, decisiones, blockers
- `BRIEF.md` — brief del brainstorming
- `DESIGN.md` — diseño del architect
- `HANDOFF.md` — solo si hay trabajo pausado (instrucciones para retomar)
- `LEARNINGS.md` — retrospectivas post-merge (métricas, aprendizajes, patrones recurrentes)

## Principios clave

- **No stubs/TODOs** en código mergeado — código placeholder es bloqueante
- **Frontend delgado** — cero lógica de negocio en componentes, solo renderizado y llamadas a API
- **Context isolation** — cada subagente recibe solo lo que necesita, no todo el historial
- **Tareas atómicas** — una tarea = un comportamiento concreto = un ciclo TDD
- **Fixes en mismo PR** — correcciones van en el mismo branch/PR, no en uno nuevo
- **Debugging sistemático** — nunca adivinar, seguir: evidencia → hipótesis → verificación → fix
- **Governance playbook** — ante fallos o situaciones inesperadas, seguir los decision trees en `rules/governance-playbook.md`

## Adversarial Testing

Tests que validan la metodología misma — que los hooks bloquean lo que deben, que QA detecta code smells, que security detecta vulnerabilidades:
- `tests/adversarial/test-hooks.sh` — tests automatizados de hooks
- `tests/adversarial/test-qa-detection.md` — fixtures de código malo para validar QA
- `tests/adversarial/test-security-detection.md` — fixtures de vulnerabilidades para validar security

Ejecutar después de modificar agentes, hooks o rules. Ver `tests/adversarial/README.md`.

## Validación Periódica de Agentes

Proceso para verificar que los agentes no han degradado en calidad:
- `tests/validation/agent-validation.md` — prompts canónicos y expected behaviors por agente
- `tests/validation/VALIDATION-LOG.md` — log de resultados
- `rules/validation-schedule.md` — frecuencia y proceso

Ejecutar mensualmente o antes de cada release. Ver `rules/validation-schedule.md`.

## Stack

Los agentes detectan el stack del proyecto automáticamente. Ver `rules/` para reglas idiomáticas por lenguaje:

| Archivo | Lenguaje / Tecnología | Extensiones |
|---------|----------------------|-------------|
| `rules/python.md` | Python | `.py` |
| `rules/typescript.md` | TypeScript / JavaScript | `.ts`, `.tsx`, `.js`, `.jsx` |
| `rules/go.md` | Go | `.go` |
| `rules/rust.md` | Rust | `.rs` |
| `rules/csharp.md` | C# | `.cs` |
| `rules/html.md` | HTML | `.html`, `.htm`, `.jsx`, `.tsx`, `.vue`, `.svelte` |
| `rules/css.md` | CSS | `.css`, `.scss`, `.sass`, `.less` |
