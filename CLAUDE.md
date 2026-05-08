# CLAUDE.md — claude-methodology

Documento raíz del repo. **Todo subagente debe leer este archivo antes de actuar.**
Las reglas aquí son obligatorias salvo que un sub-`CLAUDE.md` más específico las override.

## Convenciones generales

- **Idioma**: comunicación con el usuario, comentarios de PR, mensajes de commit y documentación en **español**. Código, nombres de variables, archivos y branches en **inglés**.
- **Override**: solo un `CLAUDE.md` más cercano al archivo en cuestión puede modificar una regla de este documento.
- **`rules/` vs `rulebooks/`**:
  - `rules/` → reglas idiomáticas por lenguaje (`python.md`, `typescript.md`, etc.) + principios de implementación que aplican al código.
  - `rulebooks/` → procesos meta del sistema de agentes (budget, governance, validación). Aplican al *cómo trabajan los agentes*, no al código en sí.

## Workflow obligatorio

1. **Brainstorming antes de diseñar** — El orchestrator entiende el requerimiento haciendo preguntas antes de pasar al architect. Solo se salta para bug fixes y tareas técnicas acotadas.
2. **Diseño antes de código** — El architect diseña la solución (estructura, contratos, schemas) antes de que los devs implementen.
3. **TDD obligatorio para lógica de negocio** — Red → Green → Refactor. Nunca código de producción sin un test que falle primero.
   - **No aplica TDD literal** a: estilos CSS, configuración de infra (Dockerfile, docker-compose, Caddyfile), migraciones declarativas, archivos de configuración. En estos casos basta con verificación manual + smoke test.
4. **Dual review obligatorio (bloqueante)** — `security-reviewer` + QA (`qa-frontend` y/o `qa-backend` según las capas tocadas en el diff) deben aprobar antes de merge. Sin ambas aprobaciones el PR no se mergea.
5. **80% coverage de branches mínimo** — Calculado **solo sobre archivos modificados en el PR**, no sobre todo el repo.
   - **Excluidos del cálculo**: re-exports (`index.ts` que solo re-exporta), archivos de config, migraciones declarativas, mocks/fixtures de test, y archivos que **solo contienen** declaraciones `type`, `interface` o `declare` — sin runtime code.
   - **NO se excluyen** (aunque "parezcan" archivos de tipos): `enum` / `const enum` (generan objeto JS), type guards (`function isX(...): x is X`), funciones de validación o narrowing, constantes calculadas. Tienen runtime y pueden tener bugs.

## Handoff entre agentes (context isolation)

Cada subagente recibe un paquete de contexto, no el historial completo de la sesión:

- **Documento(s) completo(s) relevantes** + **descripción específica de la tarea**.
- Documentos típicos según el agente:
  - `architect` recibe: `BRIEF.md` completo + tarea ("diseña la solución para esto").
  - `backend-dev` / `frontend-dev` reciben: sección de `DESIGN.md` correspondiente al lote + lista de tareas TDD del lote + `rules/<lenguaje>.md` aplicable.
  - `security-reviewer` / `qa-*` reciben: diff completo del PR + `DESIGN.md` + `BRIEF.md` (necesitan saber qué se quería para juzgar si el código lo cumple).
  - `db-specialist` recibe: `DESIGN.md` (sección de datos) + schema actual.
- **Quien construye el paquete es el orchestrator**, no el agente que va a recibirlo. Los devs no se autoinvocan.
- **Lo que NUNCA se pasa**: el historial completo de la conversación con el usuario, mensajes de otros agentes, ni outputs de fases ya cerradas que no sean relevantes para la tarea actual.

Si un agente necesita información que no recibió, debe **pedirla explícitamente al orchestrator** en lugar de adivinar o pedirla al usuario.

## Gitflow

- **Branches**: `main` (producción) ← PR ← `dev` (desarrollo) ← `feature/*` | `hotfix/*`
- **Nunca push directo a main** — siempre por PR.
- **Nunca trabajar en main o dev directamente** — crear feature branch.
- Features: `git checkout dev && git checkout -b feature/descripcion-corta`
- Hotfixes: `git checkout main && git checkout -b hotfix/descripcion-corta`
- PRs de features van a `dev`, hotfixes a `main`.
- Merges siempre con `--no-ff`.

### Formato de commits

**Imperativo + scope opcional**, en español:

```
<scope>: <verbo en imperativo> <descripción corta>
```

Ejemplos:
- `auth: agregar refresh de JWT`
- `agregar validación de email en signup` (sin scope cuando no aplica)
- `db: corregir índice duplicado en users`
- `ui: ajustar contraste de botón primario`

Reglas:
- Verbo en **imperativo presente** ("agregar", "corregir", "eliminar"), no pasado ni gerundio.
- Scope opcional, en **inglés** y minúsculas (coincide con módulos/carpetas del repo).
- Descripción en **español**, primera letra minúscula, sin punto final.
- Una idea por commit. Si necesitas "y" en el mensaje, probablemente son dos commits.

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

## Verificación pre-commit (responsabilidad del dev)

Antes de cada commit, el dev verifica (en este orden):

1. Tests pasan con coverage ≥ 80% de branches sobre archivos del diff.
2. Lint pasa sin errores (autofix primero, manual después).
3. Build compila sin errores.
4. Docker container corre, si aplica.
5. **Self-reflection idiomática** contra `rules/self-reflection.md` — ejecutar el proceso ahí definido, que carga `rules/<lenguaje>.md` aplicable según el diff y revisa solo las líneas modificadas. Las reglas concretas viven en cada `rules/<lenguaje>.md`, no aquí.
6. **Implementation principles** contra `rules/implementation-principles.md` — revisar el diff contra YAGNI, scope mínimo, cambios quirúrgicos, sin abstracciones especulativas ni refactor colateral.

Los pasos 5 y 6 son ejercicios distintos: el 5 revisa **cómo** está escrito el código, el 6 revisa **qué** se escribió. Hacerlos en pasadas separadas evita que el juicio de scope se diluya en la revisión idiomática.

El paso 1 está reforzado por `pre-commit-guard.sh`, pero los demás son responsabilidad del dev. **No se hace commit si falta alguna.**

## Agentes

| Agente | Modelo | Rol |
|--------|--------|-----|
| `orchestrator` | opus | Coordina el flujo completo. No implementa — delega y construye paquetes de contexto |
| `architect` | opus | Diseña soluciones, define contratos/schemas como código |
| `ui-ux` | opus | Genera design system (estilo, paleta, tipografía, anti-patterns) y valida flujos antes de implementar |
| `backend-dev` | sonnet | Implementa backend con TDD y gitflow |
| `frontend-dev` | sonnet | Implementa frontend (capa delgada, cero lógica de negocio) |
| `db-specialist` | sonnet | Esquemas, migraciones, optimización de queries |
| `security-reviewer` | opus | Auditoría OWASP Top 10, secrets, dependencias (read-only). **Bloqueante en PR.** |
| `qa-frontend` | sonnet | UX, accesibilidad, componentes, estado UI, tests frontend, coverage ≥ 80%. **Bloqueante en PR si el diff toca frontend.** |
| `qa-backend` | sonnet | Contratos de API, lógica de negocio, datos, tests backend, coverage ≥ 80%. **Bloqueante en PR si el diff toca backend.** |
| `e2e-runner` | sonnet | Tests E2E con Playwright (cero mocks, sistema real). Corre **solo en PRs a `main`** (no en cada PR a `dev`) y nightly |
| `build-resolver` | sonnet | Diagnostica y resuelve errores de build/compilación |
| `refactor` | sonnet | Detecta code smells, refactoriza sin cambiar comportamiento |
| `docs` | sonnet | Genera/actualiza documentación a partir del diff del PR |

### Política de degradación de modelo

Si `opus` está rate-limited o devuelve error de capacidad:
- `orchestrator` y `architect` → **esperar y reintentar** (no degradar a sonnet, su valor está en el razonamiento profundo).
- `security-reviewer` → degradar a sonnet **solo si el PR no toca auth, crypto, manejo de secrets o pagos**. En esos casos esperar.
- `ui-ux` → degradar a sonnet aceptable.

## Flujo completo

```
Brainstorming → Brief → [UI/UX genera design system si hay UI] → Architect diseña
  → Devs implementan (TDD + Self-Review: implementation-principles + idiomática)
  → PR creado → CI checks → Docs genera/actualiza documentación
  → Security + QA (qa-frontend y/o qa-backend según capas del diff) review en paralelo
  → Correcciones en mismo PR → Re-review → Todos aprueban → Merge → Learn
```

## Estado persistente (`.planning/`)

El estado del trabajo se persiste en `.planning/` para sobrevivir cambios de sesión:

- `STATE.md` — fase actual, progreso, decisiones, blockers
- `BRIEF.md` — brief del brainstorming
- `DESIGN.md` — diseño del architect (vida = una feature)
- `ARCHITECTURE.md` — decisiones arquitectónicas recurrentes (stack, patrones, librerías canónicas). Persiste y acumula a través de features
- `HANDOFF.md` — solo si hay trabajo pausado (instrucciones para retomar)
- `LEARNINGS.md` — retrospectivas post-merge (métricas, aprendizajes, patrones recurrentes)

## Principios clave

- **No stubs/TODOs** en código mergeado — código placeholder es bloqueante (ver `rules/implementation-principles.md`, principio 4).
- **Logs y observabilidad son scope siempre** — logger estructurado en boundaries y paths de error no cuenta como especulativo. `console.log` / `print()` residual de debug sí está prohibido (lo bloquea `rules/self-reflection.md`).
- **Frontend delgado** — cero lógica de negocio en componentes. El frontend orquesta render, estado **de UI** (tabs activos, modales abiertos, formularios en edición) y llamadas a API. Toda regla de negocio vive en backend. `qa-frontend` revisa lo primero, no lo segundo.
- **Context isolation** — cada subagente recibe solo lo que necesita (ver sección Handoff). No el historial completo.
- **Tareas atómicas** — una tarea = un comportamiento concreto = un ciclo TDD.
- **Agent budget** — el architect entrega un plan particionado en *lotes* (≤5 tareas cada uno = una invocación de dev) y declara estrategia de PR (single-PR default, multi-PR solo si los grupos son independientes y shippeables solos). El orchestrator valida y sigue el plan; los devs commitean por cada ciclo TDD. Sin esto el agente se corta a mitad o se multiplica innecesariamente el costo de CI/review. Ver `rulebooks/agent-budget.md`.
- **Fixes en mismo PR** — correcciones van en el mismo branch/PR, no en uno nuevo.
- **Debugging sistemático** — nunca adivinar, seguir: evidencia → hipótesis → verificación → fix.
- **YAGNI estricto** — implementar solo lo que el brief pide; sin abstracciones especulativas ni error handling defensivo (ver `rules/implementation-principles.md`).
- **Cambios quirúrgicos** — el diff debe ser mínimo y trazable al brief; refactor colateral va en PR aparte.
- **Asumir explícito** — si el brief es ambiguo, preguntar antes de implementar; no adivinar.
- **Governance playbook** — ante fallos o situaciones inesperadas, seguir los decision trees en `rulebooks/governance-playbook.md`.

## Salud del sistema de agentes (recomendado, no bloqueante)

Estas dos prácticas verifican que **los agentes mismos** no se hayan degradado. No bloquean PRs ni releases, pero se recomienda correrlas mensualmente y antes de cualquier cambio significativo en `agents/`, `hooks/` o `rules/`.

### Adversarial Testing

Tests que validan que QA y security **detecten** lo que deben detectar, usando fixtures de código intencionalmente malo:

- `tests/adversarial/test-hooks.sh` — tests automatizados de hooks
- `tests/adversarial/test-qa-detection.md` — fixtures de code smells para QA
- `tests/adversarial/test-security-detection.md` — fixtures de vulnerabilidades para security

Si un agente deja de detectar algo que antes sí detectaba, hay regresión. Ver `tests/adversarial/README.md`.

### Validación Periódica de Agentes

Prompts canónicos con expected behaviors documentados, para verificar que cada agente sigue produciendo output de la calidad esperada:

- `tests/validation/agent-validation.md` — prompts y expected behaviors por agente
- `tests/validation/VALIDATION-LOG.md` — log de resultados
- `rulebooks/validation-schedule.md` — frecuencia y proceso

Cuándo ejecutar: mensualmente, o antes de cada release significativo, o después de modificar prompts de agentes.

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
| `rules/docker.md` | Docker (Dockerfile + compose) | `Dockerfile`, `Dockerfile.*`, `docker-compose*.yml`, `compose*.yml`, `.dockerignore` |
