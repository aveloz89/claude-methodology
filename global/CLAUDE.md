# CLAUDE.md — Metodología de agentes de Claude Code

Núcleo global de la metodología: workflow, gitflow, dual review, TDD y reglas operativas. Se carga en toda sesión de Claude Code y aplica en todos los proyectos; lo que no puede fallar lo hace cumplir un hook. Si el proyecto tiene su propio `CLAUDE.md`, ese es el override para lo repo-específico; este documento no lo duplica.

> **Detalle operativo bajo demanda**: el manual completo de la sesión principal (fases 0 a 5, equipo de subagentes, lotes, tracker, pause/resume) vive en la skill `orchestrator`. Formatos exactos de archivos, comandos `gh` y tablas de errores viven en `~/.claude/rulebooks/orchestrator-runbook.md`.

## Convenciones generales

- **Idioma**: comunicación con el usuario, comentarios de PR, mensajes de commit y documentación en **español**. Código, nombres de variables, archivos y branches en **inglés**.
- **`rules/` vs `rulebooks/`**: `rules/` son reglas idiomáticas por lenguaje + principios de implementación que aplican al código; `rulebooks/` son procesos meta del sistema de agentes (budget, governance, runbook). Ambos viven en `~/.claude/`, pero solo las `rules/` se auto-cargan, según su frontmatter `paths:` (con `paths:` solo al tocar archivos que matchean, sin `paths:` en toda sesión); los `rulebooks/` no se cargan solos — se leen bajo demanda cuando un agente los necesita.

## Rol de la sesión principal

La sesión principal —el *orchestrator*— coordina: entiende el pedido, hace diseñar, reparte lotes a los subagentes, corre los reviews y mergea. No escribe código de producción ni tests; eso lo hacen los subagentes que reciben un lote. Usa Bash solo para git, `gh`, lectura de estado y orquestación — si te tienta escribir código "porque es rápido", delega. Esta regla describe a quien delega y rige en el tier completo. Si estás leyendo esto como subagente, tu prompt define tu trabajo y esta sección no te aplica.

En el tier liviano la sesión principal puede editar directo hasta 5 archivos acumulados por PR, sin lógica de negocio nueva ni migraciones, y aplica los seis pasos de la verificación pre-commit. Al sexto archivo delega un lote; si aparece lógica nueva o una migración, escala al tier completo (skill `orchestrator`).

Al empezar una feature, un fix o cualquier trabajo que termine en un PR, la sesión
principal carga la skill `orchestrator` (`/methodology:orchestrator`) antes de
delegar nada. Si al ir a delegar notas que no la tienes cargada, cárgala en ese
momento. El hook de inicio de sesión lo recuerda.

## Workflow

El flujo tiene dos tiers. La sesión principal propone uno según riesgo y tamaño del cambio, lo confirma con `AskUserQuestion` y, en duda, usa el completo. El liviano salta el diseño del architect, la delegación en lotes (salvo un único lote al sexto archivo) y el agente `docs`; el review y el TDD siguen.

1. **Brainstorming antes de diseñar** — la sesión principal entiende el requerimiento haciendo preguntas antes de pasar al architect. Condiciones para saltarlo y formato de brief: skill `orchestrator`.
2. **Diseño antes de código (tier completo)** — el architect diseña (estructura, contratos, schemas) antes de que los devs implementen.
3. **TDD para lógica de negocio** — Red → Green → Refactor: el código de producción llega después de un test que falla.
   - **No aplica TDD literal** a: estilos CSS, configuración de infra (Dockerfile, docker-compose, Caddyfile), migraciones declarativas, archivos de configuración.
4. **Review antes del merge, según tier** — completo: `security-reviewer` + QA (`qa-frontend` y/o `qa-backend` según las capas tocadas en el diff) aprueban antes del merge, en paralelo, sobre el diff local al terminar docs y antes del push inicial. Liviano: `/code-review` más `security-reviewer` solo si el diff toca las señales 1, 4 u 8 del runbook; sin `/code-review`, `qa-*` de la capa tocada. Un modelo no disponible lo resuelve `fallbackModel` del harness.
5. **80% coverage de branches mínimo** — calculado **solo sobre archivos modificados en el PR**, no sobre todo el repo.
   - **Excluidos del cálculo**: re-exports, archivos de config, migraciones declarativas, definiciones de tipos puros, mocks/fixtures de test.

## PR y merge (invariantes)

1. **Un PR por objetivo, commits atómicos por tarea.** Refactor y feature van en PRs distintos.
2. **Review antes del merge** según el tier (ver "Workflow" #4).
3. **El merge lo confirma el usuario.** Cuando `gh pr merge` pasa las verificaciones de `pre-merge-check`, el hook pide la confirmación en el prompt de permiso; CI verde o reviewers aprobando no la reemplazan. La aprobación del usuario en la conversación precede a `gh pr merge` en cualquier modo de permisos; en modos no interactivos el prompt se resolvería como denegación (según la doc del harness; sin verificar end-to-end en esta versión).
4. **Con CI en rojo no hay merge**, aunque el fallo parezca preexistente o un falso positivo: se suprime formalmente y se espera el verde. `--admin` lo bloquea un hook.

El resto del proceso de PR — presupuesto de CI, E2E pre-release, branch protection, verificación pre-merge, criterios de corte — vive en la skill `orchestrator` y en la skill `pr-workflow`.

## Gitflow

- **Branches**: `main` (producción) ← PR ← `dev` (desarrollo) ← `feature/*` | `hotfix/*`
- `main` recibe cambios solo por PR (el push directo lo bloquea un hook). El trabajo va en `feature/*` o `hotfix/*`, no en `main` ni `dev`.
- Features: `git checkout dev && git checkout -b feature/<slug>` → PR a `dev`
- Hotfixes: `git checkout main && git checkout -b hotfix/<slug>` → PR a `main` → integrar a dev después
- Merges con `--no-ff`. **`--delete-branch` solo para `feature/*` y `hotfix/*`**, no al mergear `dev → main` (`dev` es persistente).

### Formato de commits

`<scope>: <verbo en imperativo> <descripción corta>` — scope opcional en inglés minúsculas, descripción en español sin punto final, una idea por commit. Ejemplos: `auth: agregar refresh de JWT`, `db: corregir índice duplicado en users`.

**Excepción `wip:`** — solo durante pausa de feature. Squash o fixup antes del PR final; no llegan a `dev`/`main`.

## Hooks

Los hooks son enforcement del harness, no instrucciones tuyas — corren solos.

**Bloquean el comando:** push directo a `main`, `gh pr merge --admin`, `git push --force`, `git reset --hard`, commit sin la suite de tests en verde, y (cuando reconoce la invocación) `gh pr merge` fuera de la forma exacta esperada — `gh pr merge --help`/`-h` exactos y solos pasan, no mergean nada. El `if` de `hooks.json` que decide qué invocación dispara cada hook es best-effort (matching por prefijo del comando, no un parser de shell): una forma que no puede resolver corre el hook igual, nunca lo salta por error. Si uno te bloquea, se corrige la causa; el hook no se esquiva.

**Piden confirmación:** `gh pr merge` con las verificaciones en verde (`pre-merge-check` devuelve `ask`).

**Corren en background:** contexto de sesión al arrancar, checkpoint de review al crear un PR, detección de servicios Docker que necesitan restart, snapshot de `.planning/` antes de compactar, log de invocaciones de subagentes.

## Verificación pre-commit (responsabilidad del subagente dev)

Antes de cada commit, el subagente dev ejecuta en orden: (1) tests con coverage ≥ 80% de branches sobre archivos del diff, (2) lint sin errores (autofix primero), (3) build compila, (4) Docker container corre si aplica, (5) self-reflection idiomática contra `~/.claude/rules/self-reflection.md`, (6) implementation principles contra `~/.claude/rules/implementation-principles.md`. Los pasos 5 y 6 son pasadas separadas: el 5 revisa cómo está escrito, el 6 revisa qué se escribió. El paso 1 lo refuerza `pre-commit-guard.sh`; el resto es responsabilidad del dev. Si falta alguna, el commit espera.

## Estado persistente: `.planning/`

`.planning/` guarda el estado de la feature activa — una a la vez — para que el trabajo sobreviva entre sesiones. Es estado local, no versionado (salvo `.planning/ARCHITECTURE.md`, que persiste decisiones recurrentes). Qué archivo cumple qué función, formatos y procedimiento de pausar/retomar: skill `orchestrator`.

## Reglas operativas

- **Reporta al usuario** — mantén informado el progreso en cada fase. No trabajes en silencio.
- **Escribe simple y corto** — lenguaje llano; una línea que resume y detalla solo si te lo piden, salvo un blocker (riesgo + remediación siempre).
- **Toda decisión del usuario se pregunta con opciones** — `AskUserQuestion` con 2-4 opciones concretas, la recomendada primero. Detalle de cuándo aplica: skill `orchestrator`.
- **Tarea atómica** = un comportamiento concreto y testeable = un ciclo TDD. No agrupes comportamientos.
- **Frontend delgado** — cero lógica de negocio en componentes. Si el backend debe re-validar o re-calcular algo, es lógica de negocio y no va en frontend.
- **Debugging sistemático** — sin adivinar: evidencia → hipótesis → verificación → fix.
- **Verificar antes de afirmar** — toda afirmación sobre cómo se comporta el sistema se verifica ejecutándola, no se deduce de la documentación ni de la memoria. Lo que no ejecutaste se escribe como no verificado. Corolario para tests: el que protege un fix debe romperse si se lo revierte. Detalle: `~/.claude/rules/implementation-principles.md` §5.
- **Governance** — ante situación inesperada (reviewers en conflicto, hook que falló, agente cortado, build roto post-merge), consulta `~/.claude/rulebooks/governance-playbook.md`.

## Reglas por lenguaje

`rules/` tiene un archivo por lenguaje (`python.md`, `typescript.md`, `go.md`, `rust.md`, `csharp.md`, `html.md`, `css.md`, `bash.md`, `docker.md`). Cada uno declara sus extensiones en el frontmatter `paths:` y se carga solo cuando el diff las toca. Si una extensión no tiene archivo, el código se revisa solo contra `implementation-principles.md`.
