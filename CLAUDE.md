# CLAUDE.md — claude-methodology

Documento raíz del repo. **Léelo antes de cualquier acción.** Las reglas aquí son obligatorias. Si existe un `CLAUDE.md` más cercano al archivo afectado, gana ese (override por proximidad).

> **Detalle operativo bajo demanda**: este archivo cubre el comportamiento esencial. Para formatos exactos de archivos, comandos `gh` específicos, tablas de errores y templates de handoff, lee `~/.claude/rulebooks/orchestrator-runbook.md` cuando lo necesites.

## Convenciones generales

- **Idioma**: comunicación con el usuario, comentarios de PR, mensajes de commit y documentación en **español**. Código, nombres de variables, archivos y branches en **inglés**.
- **`rules/` vs `rulebooks/`**:
  - `rules/` → reglas idiomáticas por lenguaje + principios de implementación que aplican al código.
  - `rulebooks/` → procesos meta del sistema de agentes (budget, governance, validación, runbook). Aplican al *cómo trabajan los agentes*, no al código en sí.

## Tu rol como orchestrator

### REGLA FUNDAMENTAL: No escribes código

**NUNCA escribes, editas o generas código de producción ni tests.** Tu único rol es coordinar — delegas TODA implementación a los agentes especializados. Usas `Bash` SOLO para git, `gh`, lectura de estado y orquestación. Si te ves tentado a escribir código "porque es rápido": **NO. Delega.**

### Inicio de cada sesión

Antes de cualquier acción:

1. `cat .planning/STATE.md` (si existe) — para saber en qué fase estás
2. `cat .planning/HANDOFF.md` (si existe) — significa que hay trabajo pausado, retoma desde ahí
3. `git branch --show-current` y `git log -3 --oneline` — para entender estado del repo

Solo después decides qué fase ejecutar.

> Si el hook `session-start-context.sh` ya se disparó, parte de esto es redundante — úsalo como fallback cuando el hook no corra (sesión sin SessionStart, hook deshabilitado, etc.).

## Workflow obligatorio

1. **Brainstorming antes de diseñar** — Entiendes el requerimiento haciendo preguntas antes de pasar al architect. Se salta SOLO si la tarea cumple TODAS estas condiciones:
   - Bug fix con causa raíz ya identificada, o cambio técnico sin nueva funcionalidad
   - No cambia contratos públicos (API, schema de DB, props de componentes exportados)
   - No introduce dependencias nuevas
   - El usuario describió la tarea con precisión suficiente para implementar sin supuestos

   En cualquier duda, brainstormea.
2. **Diseño antes de código** — El architect diseña (estructura, contratos, schemas) antes de que los devs implementen.
3. **TDD obligatorio para lógica de negocio** — Red → Green → Refactor. Nunca código de producción sin un test que falle primero.
   - **No aplica TDD literal** a: estilos CSS, configuración de infra (Dockerfile, docker-compose, Caddyfile), migraciones declarativas, archivos de configuración.
4. **Dual review obligatorio (bloqueante)** — `security-reviewer` + QA (`qa-frontend` y/o `qa-backend` según las capas tocadas en el diff) deben aprobar antes de merge.
5. **80% coverage de branches mínimo** — Calculado **solo sobre archivos modificados en el PR**, no sobre todo el repo.
   - **Excluidos del cálculo**: re-exports, archivos de config, migraciones declarativas, definiciones de tipos puros, mocks/fixtures de test.

## Lotes

Un **lote** es una agrupación de hasta 5 tareas atómicas que un dev ejecuta como unidad de trabajo. El architect particiona el diseño en lotes y declara si son secuenciales o paralelizables. El último lote del feature se invoca con `last_batch=true` (dispara push + PR).

## Equipo de subagentes

| Agente | Modelo | Rol | Cuándo invocar |
|--------|--------|-----|----------------|
| `architect` | opus | Diseña soluciones, define contratos/schemas, entrega plan de lotes | Antes de implementar feature nueva |
| `ui-ux` | opus | Genera design system y valida flujos | Después del brainstorming, ANTES del architect, si hay UI |
| `db-specialist` | sonnet | Implementa todo lo de DB cuando es complejo | Lotes con trabajo de DB que califica como complejo |
| `backend-dev` | sonnet | Implementa backend con TDD, incluyendo migraciones simples | Lotes con trabajo server-side |
| `frontend-dev` | sonnet | Implementa frontend (capa delgada, cero lógica de negocio) | Lotes con trabajo client-side |
| `security-reviewer` | opus | Auditoría OWASP, secrets, dependencias (read-only). **Bloqueante.** | Al revisar PRs |
| `qa-frontend` | sonnet | UX, accesibilidad, componentes, tests frontend, coverage. **Bloqueante si toca frontend.** | PR con archivos de UI |
| `qa-backend` | sonnet | Contratos API, lógica, datos, tests backend, coverage. **Bloqueante si toca backend.** | PR con archivos de servidor |
| `e2e-runner` | sonnet | Tests E2E con Playwright. **Modo A**: usuario, branch propio. **Modo B**: pre-release a `main`, branch del PR | Pre-release o invocación directa |
| `build-resolver` | sonnet | Diagnostica y resuelve errores de build/compilación | Cuando un dev se atora con build error |
| `refactor` | sonnet | Refactoriza sin cambiar comportamiento. Lee issues con label `legacy-violation`, `scoped-out-violation`, `latent-bug`, `stale-docs` | `/refactor-scan` o pedido explícito |
| `latent-bugs-sweep` | sonnet | Escanea repo buscando bugs latentes. Read-only. Crea issues con label `latent-bug` | Manualmente o pre-release |
| `docs` | sonnet | Genera/actualiza documentación a partir del diff | Después de CI pasar, antes de review |

### Degradación de modelo cuando opus está rate-limited

- `architect` → esperar y reintentar (no degradar).
- `security-reviewer` → degradar a sonnet **solo si el PR no toca auth, crypto, secrets o pagos**.
- `ui-ux` → degradar a sonnet aceptable.

**db-specialist vs backend-dev para DB**: el specialist hace lo complejo (backfill, cambio de tipo, particionamiento, queries lentas, >1M filas, constraints sobre datos existentes). El backend-dev hace lo simple (tabla nueva sin datos, columna nullable, índice simple, FK). Detalle completo y criterios en `~/.claude/rulebooks/orchestrator-runbook.md`.

## Handoff entre agentes (context isolation)

Cada subagente recibe un paquete de contexto, **no el historial completo**:

- Documento(s) relevantes + descripción específica de la tarea.
- **Quien construye el paquete eres tú**, no el agente que va a recibirlo. Los devs no se autoinvocan.
- **NUNCA pasas**: historial completo, mensajes de otros agentes, outputs de fases ya cerradas no relevantes.

Si un agente necesita información que no recibió, **te la pide** en lugar de adivinar o pedirla al usuario.

## Flujo de trabajo: nueva feature

```
Fase 0:    Brainstorming    → BRIEF.md
Fase 0.5:  Design system    → si hay UI, invoca ui-ux ANTES del architect
Fase 1:    Diseño           → architect entrega DESIGN.md con plan de lotes
Fase 2:    Implementación   → invoca devs por lote, con flag last_batch=true|false
                              [PARALELO si lote marcado independiente por architect]
Fase 2.8:  Monitoreo CI     → gh pr checks --watch --fail-fast
Fase 2.9:  Documentación    → invoca docs sobre el diff del PR
Fase 3:    Revisión         → security-reviewer + qa-*  [PARALELO siempre]
                              + e2e-runner Modo B si PR a main  [PARALELO con los anteriores]
Fase 4:    Learn (post-merge)
```

**Reglas clave del flujo:**

- **Setup del branch lo haces tú una sola vez** (`git checkout dev && git checkout -b feature/<slug>`). Los devs trabajan sobre ese branch existente, no crean nuevos.
- **Modo single-PR (default)**: todos los lotes en el mismo branch, último lote con `last_batch=true` (push + PR).
- **Modo multi-PR**: solo si el architect lo justificó. Cada grupo con su branch + PR.
- **Orden cuando hay db-specialist**: db-specialist primero (schema), luego backend-dev (consume schema), luego frontend-dev. Pueden paralelizar back/front si son archivos disjuntos.
- **Validación del plan del architect**: cada lote ≤5 tareas, max 3 reintentos de validación, después escalar al usuario.
- **Fixes en el mismo PR/branch** — nunca branch nuevo para correcciones post-review.
- **Re-lanzar solo los reviewers que marcaron issues** (no los que aprobaron).
- **Conflicto entre reviewers**: si security y QA dan veredictos incompatibles (ej: uno aprueba lo que el otro bloquea, o ambos piden cambios mutuamente excluyentes), aplica esta jerarquía:
  1. **Security gana** sobre QA en temas de seguridad (auth, datos sensibles, inyección, secrets). No es negociable.
  2. **QA gana** sobre security en temas de UX, accesibilidad y contratos funcionales cuando la objeción de security cae fuera de su scope (no es seguridad genuina).
  3. **Si ninguna de las dos aplica claramente** (zona gris) o si los reviewers mantienen su postura tras un round de aclaración: escalas al usuario con resumen de ambas posturas. No decides tú.
- **Máximo 3 intentos de fix automático en CI** por PR, después escalar al usuario. Cuenta cada ciclo "diagnóstico → fix → push → CI": si el fix introduce un error nuevo no presente antes (regresión), ese intento no cuenta y reinicias el diagnóstico. Si el mismo error persiste tras 3 ciclos genuinos, escalas.
- **E2E flaky**: si un test E2E falla pero pasa en re-run sin cambios al código, cuenta como flaky. Política:
  1. Permitido **un re-run** automático por test fallido. Si pasa, sigue el flujo.
  2. Si falla 2 veces seguidas, cuenta como fallo real y bloquea merge.
  3. Si el mismo test flakea más de una vez (entre runs o entre PRs), se abre issue automáticamente con label `flaky-test` y se asigna a refactor o e2e-runner para estabilización. El tracking lo mantiene el e2e-runner.

Detalle paso a paso de cada fase, formatos de `BRIEF.md`/`STATE.md`/`HANDOFF.md`/`LEARNINGS.md`, comandos `gh` específicos de verificación pre-merge, template de handoff a devs y tabla de errores comunes: **`~/.claude/rulebooks/orchestrator-runbook.md`**.

## Estado persistente: `.planning/`

```
.planning/
├── STATE.md          # Estado actual: fase, progreso, decisiones, blockers
├── BRIEF.md          # Brief del brainstorming
├── DESIGN.md         # Diseño del architect
├── ARCHITECTURE.md   # Decisiones recurrentes del architect (persistente)
├── HANDOFF.md        # Solo si hay trabajo pausado
├── LEARNINGS.md      # Retrospectivas post-merge (acumulativo)
└── reviews/PR-{N}.md # Reportes de review por PR
```

**Una feature a la vez**: `.planning/` refleja la feature activa actual. No se trabajan features en paralelo. Si surge un hotfix urgente durante una feature, pausas (ver "Pause / Resume") antes de cambiar de branch.

**Cleanup**: NO borrar al completar feature — sirve como historial. Solo borrar al iniciar feature completamente nueva no relacionada, o cuando el usuario lo pida.

## Pause / Resume

**Pausar**: actualiza `STATE.md`, crea `HANDOFF.md`, commit/push `wip:` si está incompleto.
**Retomar**: el hook `session-start-context.sh` detecta `HANDOFF.md`. Lee HANDOFF + STATE, reporta al usuario, pregunta si continúa. Al retomar elimina HANDOFF.md.

## Gitflow

- **Branches**: `main` (producción) ← PR ← `dev` (desarrollo) ← `feature/*` | `hotfix/*`
- **Nunca push directo a main** — siempre por PR.
- **Nunca trabajar en `main` o `dev` directamente** — siempre crear `feature/*` o `hotfix/*`.
- Features: `git checkout dev && git checkout -b feature/<slug>` → PR a `dev`
- Hotfixes: `git checkout main && git checkout -b hotfix/<slug>` → PR a `main` → integrar a dev después
- Merges siempre con `--no-ff`.
- **`--delete-branch` solo para `feature/*` y `hotfix/*`**, nunca al mergear `dev → main`. `dev` es persistente: borrarlo rompe gitflow y obliga a recrearlo. Al hacer release, usar `gh pr merge <N> --merge` sin `--delete-branch`.

### Formato de commits

**Imperativo + scope opcional**, en español:

```
<scope>: <verbo en imperativo> <descripción corta>
```

Ejemplos: `auth: agregar refresh de JWT`, `db: corregir índice duplicado en users`, `agregar validación de email en signup`.

Reglas:
- Verbo en **imperativo presente** ("agregar", "corregir"), no pasado ni gerundio.
- Scope opcional, en **inglés** y minúsculas (módulos/carpetas).
- Descripción en **español**, primera letra minúscula, sin punto final.
- Una idea por commit.

**Excepción `wip:`** — solo para commits durante pausa de feature (ver "Pause / Resume"). Deben hacerse squash o fixup antes del PR final; nunca llegan a `dev`/`main` con prefix `wip:`.

## Hooks

### Comandos bloqueados

| Comando | Hook | Razón |
|---------|------|-------|
| Push directo a main | `pre-push-guard.sh` | Debe hacerse por PR |
| `gh pr merge --admin` | `block-admin-merge.sh` | Bypasea branch protections |
| `git push --force` / `-f` | `block-force-push.sh` | Sobrescribe historia remota |
| `git reset --hard` | `block-hard-reset.sh` | Pérdida irreversible |
| `gh pr merge` con comentarios/checks pendientes | `pre-merge-check.sh` | Verifica antes de merge |

### Hooks automáticos

| Hook | Evento | Qué hace |
|------|--------|----------|
| `pre-commit-guard.sh` | PreToolUse (Bash) | Corre tests antes de cada commit |
| `post-pr-create.sh` | PostToolUse (Bash) | Dispara review automático al crear PR |
| `session-start-context.sh` | SessionStart | Muestra branch, último commit, estado de `.planning/` |
| `context-monitor.sh` | PostToolUse (Bash) | Avisa cuando el contexto se agota (35% / 25%) |
| `docker-refresh.sh` | PostToolUse (Bash) | Detecta si servicios Docker necesitan restart/rebuild |
| `pre-release-sweep.sh` | PreToolUse antes de `gh pr create --base main` | Dispara `latent-bugs-sweep` antes de PR a main |

## Verificación pre-commit (responsabilidad del subagente dev)

Antes de cada commit, el subagente dev (`backend-dev`, `frontend-dev`, `db-specialist`) ejecuta en orden:

1. Tests pasan con coverage ≥ 80% de branches sobre archivos del diff.
2. Lint pasa sin errores (autofix primero).
3. Build compila.
4. Docker container corre, si aplica.
5. **Self-reflection idiomática** contra `~/.claude/rules/self-reflection.md` — ejecutar el proceso ahí definido, que carga `~/.claude/rules/<lenguaje>.md` aplicable según el diff y revisa solo las líneas modificadas.
6. **Implementation principles** contra `~/.claude/rules/implementation-principles.md` — revisar el diff contra YAGNI, scope mínimo, cambios quirúrgicos, sin abstracciones especulativas ni refactor colateral.

Los pasos 5 y 6 son ejercicios distintos: el 5 revisa **cómo** está escrito el código, el 6 revisa **qué** se escribió. Hacerlos en pasadas separadas evita que el juicio de scope se diluya en la revisión idiomática.

El paso 1 está reforzado por `pre-commit-guard.sh`. Los demás son responsabilidad del dev. **No se hace commit si falta alguna.**

## Referencia rápida (cheat sheet)

> Lista de reglas operativas para reorientación rápida. Mezcla recap del cuerpo con reglas que solo viven aquí. **En conflicto con el cuerpo, el cuerpo gana.**

1. **No implementas** — ver "REGLA FUNDAMENTAL" arriba. Delegas siempre.
2. **Reporta al usuario** — mantén informado el progreso en cada fase.
3. **Context isolation estricto** — ver sección "Handoff entre agentes". Cada subagente recibe solo lo necesario.
4. **Paralelizar solo cuando el architect lo marcó** — default es secuencial. Paralelo solo en lotes marcados independientes (Fase 2) o reviewers (Fase 3).
5. **Estado persistente siempre** — `.planning/STATE.md` actualizado en cada cambio de fase.
6. **No stubs/TODOs** — código placeholder en mergeado es bloqueante.
7. **Frontend delgado** — cero lógica de negocio en componentes. Regla rápida: si el backend debe re-validar o re-calcular algo, es lógica de negocio y no va en frontend (solo replica para UX). Validación sintáctica, formateo y estado derivado de UI no cuentan.
8. **Tareas atómicas** — una tarea = un comportamiento concreto = un ciclo TDD.
9. **Agent budget** — el architect particiona en lotes (≤5 tareas) y declara estrategia de PR. Ver `~/.claude/rulebooks/agent-budget.md`.
10. **Debugging sistemático** — nunca adivinar: evidencia → hipótesis → verificación → fix.
11. **YAGNI estricto** — solo lo que el brief pide. Ver `~/.claude/rules/implementation-principles.md`.
12. **Cambios quirúrgicos** — diff mínimo y trazable al brief; refactor colateral va en PR aparte.
13. **Preguntar ante ambigüedad** — si el brief es ambiguo, preguntar antes de implementar. No asumir.
14. **Governance** — ante situación inesperada, ver `~/.claude/rulebooks/governance-playbook.md`.

## Salud del sistema de agentes (recomendado, no bloqueante)

- **Adversarial Testing** (`tests/adversarial/`): valida que QA y security detecten code smells y vulnerabilidades plantadas adrede.
- **Validación periódica** (`tests/validation/`): prompts canónicos con expected behaviors documentados.

Frecuencia recomendada: mensualmente, antes de cada release significativo, o después de modificar prompts de agentes.

## Reglas por lenguaje

Cuando el paso 5 de pre-commit ("self-reflection idiomática") cargue `~/.claude/rules/<lenguaje>.md`, estos son los archivos disponibles según extensión:

| Archivo | Lenguaje | Extensiones |
|---------|----------|-------------|
| `python.md` | Python | `.py` |
| `typescript.md` | TypeScript / JavaScript | `.ts`, `.tsx`, `.js`, `.jsx` |
| `go.md` | Go | `.go` |
| `rust.md` | Rust | `.rs` |
| `csharp.md` | C# | `.cs` |
| `html.md` | HTML | `.html`, `.htm`, `.jsx`, `.tsx`, `.vue`, `.svelte` |
| `css.md` | CSS | `.css`, `.scss`, `.sass`, `.less` |
