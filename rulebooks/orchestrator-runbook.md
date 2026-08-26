# Orchestrator Runbook

Detalle operativo del flujo de orchestration. **Lectura bajo demanda**: el comportamiento esencial vive en `CLAUDE.md` raíz y se carga siempre; este documento se consulta cuando necesitas un formato exacto, un comando específico o resolver una situación puntual.

---

## Contenido

1. [Detalle de cada fase del flujo](#detalle-de-cada-fase-del-flujo)
2. [Criterios completos: db-specialist vs backend-dev](#criterios-completos-db-specialist-vs-backend-dev)
3. [Context isolation: qué recibe cada agente](#context-isolation-qué-recibe-cada-agente)
4. [Template del prompt de handoff a devs](#template-del-prompt-de-handoff-a-devs)
5. [Formatos de archivos en `.planning/`](#formatos-de-archivos-en-planning)
6. [Clasificación del diff por capa (frontend / backend)](#clasificación-del-diff-por-capa)
7. [Comandos `gh` específicos](#comandos-gh-específicos)
8. [Formato de reporte de review](#formato-de-reporte-de-review)
9. [Pre-release E2E (Modo B del e2e-runner)](#pre-release-e2e-modo-b-del-e2e-runner)
10. [Anti-drift: DoD de cambios de proceso](#anti-drift-dod-de-cambios-de-proceso)
11. [Errores comunes y cómo manejarlos](#errores-comunes-y-cómo-manejarlos)
12. [Flujo: revisar PR existente sin pasar por el flow completo](#flujo-revisar-pr-existente-sin-pasar-por-el-flow-completo)

---

## Detalle de cada fase del flujo

### Fase 0: Brainstorming

Antes de diseñar o implementar nada, entiende qué quiere el usuario. **Nunca asumas — pregunta.**

**Proceso:**

1. Escucha la idea inicial
2. Haz preguntas en bloques de 2-4 (no 10 de golpe). Categorías a cubrir según complejidad:
   - **Alcance**: ¿qué incluye, qué NO? ¿MVP o completo?
   - **Usuarios**: ¿quién usa, qué roles/permisos?
   - **Datos**: ¿qué entidades, qué relaciones?
   - **Flujo**: ¿qué hace el usuario paso a paso?
   - **Edge cases**: ¿qué pasa si X? ¿qué límites?
   - **Integraciones**: ¿APIs externas, dependencias?
   - **Prioridad**: si hay mucho, ¿qué primero?
3. **Itera en rondas**. Después de cada respuesta, evalúa huecos y haz nueva ronda. NO saltes a diseño después de una sola ronda
4. Cuando creas tener claridad, presenta el resumen y pregunta con `AskUserQuestion` (regla operativa de `CLAUDE.md`): dos opciones — avanzar al diseño, u otra ronda de preguntas sobre lo que siga abierto. Marca la recomendada. En prosa no: la decisión enterrada en un párrafo se pierde
5. **Solo avanza al diseño con confirmación explícita del usuario.** Si agrega contexto, otra ronda
6. Con confirmación, escribe `.planning/BRIEF.md` (formato más abajo) y avanza

**Cuándo saltar brainstorming:**

- Bug fix con pasos de reproducción claros
- Tarea técnica acotada y concreta ("actualiza dependencia X", "cambia puerto 3000 a 8080")

**NUNCA saltes brainstorming para features o cambios funcionales**, aunque el requerimiento parezca detallado. Mínimo una ronda de preguntas.

### Fase 0.5: Design system (si hay UI)

Si la tarea involucra trabajo visual, invoca `ui-ux` ANTES del architect.

**Cómo invocar `ui-ux`:**

1. Pásale SOLO:
   - El brief del brainstorming (`.planning/BRIEF.md` o pasaje relevante)
   - Nombre del proyecto
   - Path al `design-system/` del proyecto si ya existe (para extender en lugar de reescribir)
   - **NO le pases historial de conversación ni diseños técnicos previos**

2. **`ui-ux` genera o extiende:**
   - `design-system/<NombreProyecto>/MASTER.md` (estilo UI, paleta, tipografía, espaciado, componentes core, anti-patterns, checklist)
   - `design-system/<NombreProyecto>/pages/<page>.md` para páginas críticas (landing, onboarding, dashboard, checkout)

3. Si `ui-ux` te pide tono/audiencia/industria/referencias que faltan en el brief, pregúntale al usuario y reenvía la respuesta al agente

4. Recibe el reporte del `ui-ux` y copia el bloque "Para incluir en el brief al architect" a la sección `### Design System` del `BRIEF.md` antes de invocar al architect

**Cuándo NO invocar `ui-ux`:**

- La tarea no tiene componente visual (solo backend, DB, CLI, internal API)
- El cambio respeta el design system existente sin nuevos componentes ni páginas críticas

### Fase 1: Diseño

1. Invoca al `architect` pasándole `.planning/BRIEF.md` (no la conversación raw). Si hubo design system, ya está dentro del brief
2. Si el diseño identifica DB compleja (ver criterios completos abajo), invoca al `db-specialist` para diseñar/validar el esquema antes de cerrar el plan
3. El architect entrega `.planning/DESIGN.md` con plan de lotes y estrategia de PR. Si hay DB compleja, el plan debe incluir un lote asignado a `db-specialist`
4. **Validación del plan** (antes de implementar):
   - Cada lote tiene **≤5 tareas**. Si excede, devolver al architect: *"El Lote X tiene N tareas. Excede el cap de 5. Repártelo en lotes más chicos."*
   - **Máximo 3 reintentos de validación.** Si después de 3 intentos el architect no entrega plan válido, escala al usuario con el plan actual y los problemas detectados
   - Estrategia de PR declarada (single-PR o multi-PR con justificación)
5. Solo cuando el plan es válido, procedes a Fase 2

### Fase 2: Implementación

El architect ya entregó el plan con lotes y estrategia de PR. **Tu trabajo es seguirlo literalmente, no re-particionar.**

#### Setup del branch (lo haces tú, una sola vez)

```bash
git checkout dev && git pull origin dev
git checkout -b feature/<feature-slug>
```

Los devs **no crean branches nuevos** en este flujo — trabajan sobre el branch que ya creaste.

#### Modo single-PR (default)

Todos los lotes corren sobre el mismo branch; un único PR al final.

1. **Invoca los lotes en orden** (respetando dependencias del plan):
   - Por cada lote, invoca al dev correspondiente con context isolation y flag **`last_batch=false`**
   - El dev hace commit por tarea y termina sin push ni PR
   - Esperas el reporte del dev antes de pasar al siguiente lote
2. **El último lote** se invoca con flag **`last_batch=true`**: el dev cierra la implementación con la verificación final completa y termina **sin push ni PR** — después vienen docs (Fase 2.5), review dual local (Fase 2.6) y push + PR (Fase 2.7, los haces tú)
3. **Orden esperado cuando hay db-specialist**:
   - `db-specialist` primero (siempre): schema, migraciones, queries, tests de DB
   - `backend-dev` después (necesita el schema)
   - `frontend-dev` al final (necesita los endpoints)
   - Si back y front son independientes (archivos disjuntos), pueden paralelizar

   Esto porque backend-dev necesita el schema disponible para importar tipos. Si el architect entrega un plan que tiene backend-dev antes del db-specialist en una feature con DB compleja, **devuélveselo al architect** — es probable que esté mal particionado.

   Excepción: si los lotes son genuinamente independientes (db-specialist trabaja en una tabla X que backend-dev no toca, y backend-dev trabaja sobre tablas existentes que no cambian), pueden ir en paralelo.

#### Modo multi-PR (solo si architect lo justificó)

Cada grupo de lotes (con su propio `**PR:**` declarado) corre sobre branch propio + PR. Para cada grupo:

1. Crear branch desde dev
2. Invocar lotes del grupo (último con `last_batch=true`)
3. Fase 2.5 (docs) → Fase 2.6 (review local) → Fase 2.7 (push + PR) → Fase 2.8 (CI) → Fase 3 (post-PR) → Fase 4 (retro) → Fase 5 (merge)
4. Pasar al siguiente grupo

#### Si un dev reporta `BUDGET LIMIT — ver HANDOFF.md`

El plan del architect debió evitar esto. Si pasa:

1. Lee `.planning/HANDOFF.md`
2. Reinvoca al mismo dev con SOLO las tareas restantes
3. Documenta el corte en `.planning/LEARNINGS.md` para que el architect ajuste sus particiones futuras

#### Si un dev reporta error de build/compilación que no puede resolver

Invoca `build-resolver` con: error completo, branch, archivos afectados. Resuelve en el mismo branch y reporta qué hizo.

### Fase 2.5: Documentación (pre-push)

Cuando el último lote reporta completado, invoca `docs` con: branch, base branch y la instrucción de leer el diff local (`git diff <base>...HEAD`). El `docs` genera/actualiza docs y **commitea al branch SIN pushear** — su commit viaja en el push inicial (presupuesto de CI: evita un run de Actions solo por docs).

Si reporta "sin cambios necesarios", avanza directo a Fase 2.6.

### Fase 2.6: Review dual local (pre-push)

El review dual ocurre **ANTES del push inicial**: `security-reviewer` + `qa-*` revisan el diff local y las rondas de fixes suceden sin pushear nada. El PR nace revisado y el caso normal cuesta un solo run de CI. `<base>` = branch base del PR futuro (normalmente `dev`).

1. **Clasifica el diff local por capa**: `git diff --name-only <base>...HEAD` + sección "Clasificación del diff por capa" más abajo
2. **Presupuesta el review proporcional al diff**: `git diff --shortstat <base>...HEAD` para additions+deletions; misma tabla y mandato de cierre que la skill `review-pr` (paso 3) — el presupuesto proporcional aplica igual en pre-PR
3. **Lanza en paralelo** (single message, multiple Agent calls):
   - `security-reviewer` — siempre
   - `qa-frontend` — solo si el diff tiene frontend
   - `qa-backend` — solo si el diff tiene backend (incluye revisar migraciones y queries del db-specialist)

   Paquete de contexto (context isolation): base + branch + instrucción de leer `git diff <base>...HEAD` + lista de archivos + `BRIEF.md` + `DESIGN.md` + presupuesto + formato de salida. **Sin número de PR — no existe todavía.** Si el diff **introduce una regla nueva**, decilo en el paquete: el reviewer tiene que aplicarla al propio diff (ver `agents/qa-backend.md`). Puede identificarla leyendo el diff, pero nombrarla le ahorra ese paso.
4. **Consolida y registra**: reporte con el "Formato de reporte de review" (más abajo), guardado en `.planning/reviews/pre-pr-<feature-slug>.md` con header de trazabilidad (branch, base, SHA de HEAD revisado, fecha, veredicto). Commit al branch: `planning: registrar review dual pre-push`
5. **Mientras haya un reviewer corriendo, el árbol no se mueve.** Cuando lanzás varios en paralelo —pueden ser tres en un diff full-stack— esperá a que vuelvan **todos** antes de aplicar nada: si aplicás los hallazgos del primero, los demás quedan leyendo un árbol que cambió bajo sus pies. Si uno se cuelga o excede su presupuesto, no esperes indefinido: cortalo y relanzalo después de aplicar, o aplicá solo en archivos que ese reviewer no esté mirando — pero decidilo explícitamente, no por olvido. Ya pasó (ver `.planning/LEARNINGS.md`, entradas de los PRs #65 y #66, y la de este mismo PR). Las veces que pasó lo detectó el reviewer y avisó, en vez de reportar un rojo falso — pero eso es disciplina suya, no una red del proceso. Vale igual para un dev trabajando en paralelo: si un lote y un review tocan los mismos archivos, no van juntos.
6. **Si hay bloqueantes**: fixes por el dev correspondiente en el mismo branch, **sin push** (si el bloqueante es de schema/migración/query optimizada, va al `db-specialist`). Re-lanza **solo** los reviewers que marcaron issues, acotados al delta local (`git diff <sha-ya-revisado>...HEAD`). Append de la re-ronda al registro. Sugerencias baratas: aplicadas antes del push (política en la skill `pr-workflow`, regla 2)
7. **Veredictos limpios**: actualiza `.planning/state.json` (`phases.review` a `done` y `review_sha` al SHA de HEAD al momento de los veredictos limpios) y avanza a Fase 2.7. Fixes, sugerencias aplicadas y registro viajan en el push inicial: **el PR nace revisado**

### Fase 2.7: Push + PR

Lo haces tú (es orquestación git, no código). El push, la creación del PR y la **reconciliación del registro de review** son una sola secuencia inmediata (segundos entre `create` y el segundo push):

```bash
git push -u origin <branch>
gh pr create --base dev --title "<título>" --body "<resumen de lotes + decisiones>"   # body incluye veredictos del review pre-push
git mv .planning/reviews/pre-pr-<feature-slug>.md .planning/reviews/PR-<N>.md
# actualizar .planning/state.json: pr = N
git commit -m "planning: vincular review pre-push al PR #<N>"
git push
```

Costo de la secuencia: con la `concurrency` + `cancel-in-progress: true` de la skill `pr-workflow` (regla 5.5, obligatoria en todos los repos), el run del evento `opened` se cancela a los segundos y solo completa el del `synchronize` — neto: **un run completo de CI**, igual que el ideal. En repos sin Actions, gratis. Si un repo no cumple 5.5, arreglar el workflow es prerequisito de esta secuencia.

El body del PR lo armas desde `.planning/` (BRIEF/DESIGN), los reportes de los devs y el registro del review pre-push: qué se implementó, decisiones ambiguas resueltas durante los lotes, veredictos del review dual (Fase 2.6), y sección `## Self-reflection — pendientes` si algún dev la reportó.

### Fase 2.8: Monitoreo de CI

Después de que se crea el PR:

```bash
gh pr checks <number> --watch --fail-fast
```

- Si todos pasan → Fase 3
- Si falla algún check:
  - Lee logs: `gh run view <run-id> --log-failed`
  - Asigna el fix:
    - Build/compilación/dependencias → `build-resolver`
    - Tests o lint → dev que creó el PR
    - Tests de DB que fallan por schema/migración → `db-specialist`
  - El agente corrige en el **mismo branch del PR**. **Antes de pushear, debe reproducir el check fallido localmente y verlo pasar** (presupuesto de CI: un run fallido cuesta lo mismo que uno verde)
  - Si el fix cambia código ya revisado en Fase 2.6, anótalo: al quedar CI verde dispara el re-review acotado de la Fase 3
  - Vuelve a monitorear
- **Máximo 3 intentos de fix automático.** Cuenta cada ciclo "diagnóstico → fix → push → CI": si el fix introduce un error nuevo no presente antes (regresión), ese intento **no cuenta** y reinicias el diagnóstico. Si el mismo error persiste tras 3 ciclos genuinos, escalas al usuario con contexto completo

**Cuándo NO monitorear CI**: el proyecto no tiene GitHub Actions, o el usuario lo pide explícitamente.

### Fase 3: Post-PR (re-reviews condicionales, E2E)

El review dual ya ocurrió en Fase 2.6, antes del push: **el PR nació revisado**. Esta fase cubre solo lo que requiere el PR abierto:

1. **Re-review condicional**: SOLO si la Fase 2.8 obligó fixes que cambian código ya revisado. Acotado al delta del fix, re-lanzando **solo los reviewers de la capa afectada**. Los fixes que salgan de esta ronda siguen la regla de un push por ronda (skill `pr-workflow`, regla 5.2). Append de la ronda al registro `.planning/reviews/PR-<N>.md`. Si CI pasó a la primera (caso normal), esta sub-fase es no-op
2. **Si el PR es a `main` (release)**: invoca `e2e-runner` en Modo B antes de la verificación pre-merge (ver sección "Pre-release E2E" más abajo)
3. Cuando no queda nada pendiente (re-reviews limpios si los hubo, `e2e-runner` si era PR a main), avanza a la **Fase 4**: la retro se escribe y se commitea en este mismo branch, antes del merge

**PRs fuera del flujo** (sin review pre-push — el checkpoint del hook `post-pr-create` lo señala): skill `review-pr` (ver también "Flujo: revisar PR existente" más abajo).

### Fase 4: Learn (retro, antes del merge)

La retro cierra el PR y **viaja en su propio branch**, como último commit antes del merge — nunca en un PR aparte (skill `pr-workflow`, regla 5.7). En modo multi-PR cada grupo hace su Fase 4: una entrada de LEARNINGS por PR mergeado. En este punto ya se conocen todas las métricas del template: rondas de review, hallazgos por reviewer, errores de CI, lotes, devs. Lo único que falta es el merge, que ocurre a continuación.

1. Recolecta métricas: rounds de review, hallazgos por reviewer, errores de build, si self-reflection atrapó algo antes
2. Identifica aprendizajes: qué salió bien, qué causó re-work
3. Prepend a `.planning/LEARNINGS.md` — más reciente arriba (formato más abajo)
4. **Sella el estado en el mismo commit**: `.planning/state.json` con `phases.merge` en `done`, y `.planning/STATE.md` si hay una decisión o aprendizaje que registrar. No queda nada que escribir después del merge
5. Commitea y pushea al branch del PR:

```bash
git commit -m "planning: registrar retro del PR #<N> y cerrar el estado"
git push
```

6. Espera CI verde sobre el HEAD nuevo — branch protection valida el último SHA, no el que ya estaba verde
7. **Regla de 3**: si un patrón aparece en 3+ entradas de LEARNINGS, súbelo al usuario — las opciones y el criterio están en la sección `LEARNINGS.md` más abajo

**Por qué el estado se sella acá y no después del merge:** escribirlo post-merge obliga a commitear sobre `dev`, que en cualquier repo con branch protection es un push directo a un branch protegido — el bypass que la metodología prohíbe en todos los demás lugares. Sellarlo en el commit de retro elimina esa escritura del flujo. El costo es que `phases.merge` se marca `done` segundos antes de que el merge ocurra: si el merge no llega a pasar, el estado queda adelantado. **Esa ventana no se detectaba sola**: `session-end-check.sh` compara mtimes y nunca mira `phases`, y `session-start-context.sh` reportaba `Fase activa: ninguna` — enmascaraba el desfase en vez de señalarlo. Por eso el mismo cambio agrega el aviso al arranque cuando el estado está sellado y seguimos parados en el branch del feature. Es un desfase de segundos, con aviso, contra un bypass sistemático.

**El commit de retro toca SOLO `.planning/`** — es la norma, no una expectativa. Con el delta acotado ahí, no dispara re-review; si incluye cualquier otra cosa, vuelve a la Fase 2.6 antes de mergear.

Es el único punto del flujo donde el contenido de un push post-review no lo mira ningún hook: `post-pr-create.sh` valida el delta contra `review_sha` al crearse el PR (Fase 2.7) y no vuelve a mirar el branch. Por eso el check 4 de la verificación pre-merge incluye el mismo test de contenido (ver "Comandos `gh` específicos").

**Costo de CI**: este push cuesta un run completo mientras el workflow del repo corra las suites para cualquier diff. Un filtro de "diff sin código → sin suites", con el job agregador reportando verde para no dejar a branch protection esperando, lo baja a segundos: es la contraparte natural de esta regla.

**Cuándo saltar Learn**:

- **Hotfix urgente**: no bloquees el merge con la retro. Si igual quieres registrarla, va en el **branch del hotfix, antes del merge a `main`**, igual que en el flujo de feature — nunca sobre `dev` después de la integración, que es un push directo a un branch protegido (ver el procedimiento de integración más abajo). El sellado del estado sigue las mismas reglas: en el branch, antes del merge
- **Tareas triviales** (typos, bumps de dependencias): sin retro

**Si se salta Learn, el sellado del estado NO se salta.** Va igual en un commit propio de `.planning/` antes del merge — lo que se omite es la entrada de LEARNINGS, no el cierre. Sin eso, `phases.merge` quedaría en `pending` sobre algo ya mergeado, que es el espejo del problema que este orden resuelve.

### Fase 5: Merge

1. Ejecuta la **verificación pre-merge** (4 checks en sección "Comandos `gh` específicos")
2. Solo si las verificaciones pasan **y el usuario aprobó el merge explícitamente** (invariante 3 de `CLAUDE.md`: no se infiere de CI verde), mergea con el comando apropiado según el tipo de branch:
   - `feature/*` o `hotfix/*` → `gh pr merge <number> --merge --delete-branch`
   - `dev → main` (release) → `gh pr merge <number> --merge` **sin `--delete-branch`** (`dev` es persistente, ver Gitflow en `CLAUDE.md`)
3. Si era hotfix (PR a main), después del merge integra a dev (procedimiento más abajo)

**No hay paso de cierre de estado**: `state.json` y `STATE.md` ya quedaron sellados en el commit de retro (Fase 4, paso 4). En el flujo de feature no queda escritura en `.planning/` después del merge, y por lo tanto no se commitea sobre `dev`. La integración de un hotfix a `dev` es la excepción, y tiene su propio procedimiento más abajo.

---

## Criterios completos: db-specialist vs backend-dev

`db-specialist` recibe lotes de implementación cuando el trabajo de DB es **complejo**. Para trabajo simple, lo hace `backend-dev`. La línea divisoria:

**Va al `db-specialist` (complejo):**

- Migraciones que requieren **backfill de datos** (script de transformación)
- Cambio de tipo de columna con datos existentes (`varchar → text`, `int → bigint`, JSON → columnas tipadas)
- Particionamiento o sharding
- Migración de datos entre tablas (split/merge)
- Estrategia zero-downtime (expand-contract)
- Optimización de queries lentas (EXPLAIN, índices compuestos, materialización)
- Constraints nuevos sobre datos existentes (`NOT NULL` en columna con NULLs)
- Migraciones que afecten >1M de filas en producción
- Schema con relaciones complejas, herencia, polimorfismo, requisitos de performance específicos

**Lo hace `backend-dev` (simple):**

- Crear/borrar tabla nueva (sin datos previos a preservar)
- Agregar columna nullable o con default (sin backfill)
- Agregar/quitar índice
- Renombrar columna sin uso en producción o detrás de feature flag
- Agregar/modificar foreign key
- Cambios en seeds/fixtures de desarrollo

**Regla rápida:** si la migración necesita un script que toque datos, o requiere análisis de performance, va al specialist.

**Cuando entra db-specialist en una feature**: recibe su propio lote en el plan del architect, trabaja sobre el **mismo branch** que los demás devs, commitea con flag `last_batch=true|false` igual que cualquier dev. Su lote incluye: schema (vía Drizzle/Pydantic/equivalente del proyecto), migraciones, queries optimizadas, tests de DB. Backend-dev consume el schema resultante en sus endpoints.

---

## Context isolation: qué recibe cada agente

Cada subagente recibe un paquete de contexto, **no el historial completo**:

- `architect` recibe: `BRIEF.md` completo + tarea ("diseña la solución para esto").
- `backend-dev` / `frontend-dev` reciben: sección de `DESIGN.md` correspondiente al lote + lista de tareas TDD del lote + `rules/<lenguaje>.md` aplicable.
- `security-reviewer` / `qa-*` reciben: **la fuente del diff, que la parametriza el orchestrator** — diff local (`git diff <base>...HEAD`) en Fase 2.6 (default del flujo, no existe PR todavía); diff del PR (`gh pr diff <N>`) solo en re-reviews post-PR y PRs fuera del flujo — + `DESIGN.md` + `BRIEF.md` (necesitan saber qué se quería para juzgar si el código lo cumple).
- `db-specialist` recibe: `DESIGN.md` (sección de datos) + schema actual.

**Quien construye el paquete eres tú**, no el agente que va a recibirlo.

**Por cada invocación de dev**, el handoff debe incluir:

- **Solo las tareas de su lote** (no el plan completo)
- **Path al schema/contratos** que ya escribió el architect (o el db-specialist si aplica)
- **Sección de DESIGN.md** correspondiente al lote (no DESIGN completo)
- **Branch en el que trabajar** (sin `git checkout` desde cero)
- **Flag `last_batch=true|false`** explícito
- **Si no es el primer lote**: instrucción de leer `git log`, `.planning/STATE.md` y `.planning/state.json` para entender qué hay
- `rules/<lenguaje>.md` aplicable

**NO incluyas:**

- Historial de conversación previo
- Tareas de otros lotes
- DESIGN.md completo si solo necesita una parte
- Contexto de reviews anteriores (salvo que sea un fix post-review)

---

## Template del prompt de handoff a devs

Aplica para `db-specialist`, `backend-dev`, `frontend-dev`. El formato es el mismo:

```
Branch: <feature-branch>
Lote: <N> de <M>
Last batch: <true|false>

Tareas a implementar:
1. <tarea 1>
2. <tarea 2>
...
(máximo 5)

Schemas/contratos a usar (ya escritos por architect o db-specialist):
- <path/al/schema.ts>
- <path/al/types.ts>

Sección de DESIGN.md correspondiente:
<inline o path>

Rules aplicables:
- ~/.claude/rules/<lenguaje>.md
- ~/.claude/rules/docker.md (si aplica)

Si no es el primer lote: lee `git log`, `.planning/STATE.md` y `.planning/state.json` antes de empezar.

Si last_batch=false: NO push, NO PR. Reporta completado.
Si last_batch=true: verificación final completa del branch y reporta listo.
NO push ni PR en ningún caso — el orchestrator corre docs y hace push + PR.
```

---

## Tracker de tareas de sesión (TaskCreate/TaskUpdate)

Visibilidad en vivo del pipeline de la fase para el usuario. Se crea SIEMPRE al cerrar el diseño con el architect (sin que el usuario lo pida) y se mantiene actualizado durante toda la fase. No sustituye a `.planning/STATE.md` ni a `.planning/state.json`: el tracker vive solo en la sesión; STATE.md (decisiones, blockers) y state.json (fase, lotes, progreso) siguen siendo el estado persistente entre sesiones.

### Estructura estándar del listado

Al recibir el plan de lotes del architect, crea:

1. **Una tarea por lote** — subject: `Lote N: <resumen corto del contenido>`. Si el plan es multi-PR, indica a qué PR pertenece en la descripción.
2. **Una tarea de review por PR del plan**: `Review dual local (security + qa-*)` — bloqueada por (`addBlockedBy`) los lotes que contiene el PR.
3. **Una tarea por PR del plan**: `Abrir PR <n> + CI` — bloqueada por la tarea de review dual local.
4. **Una tarea de E2E** por cada PR que toque UI: `E2E visual en navegador` — bloqueada por la tarea del PR. Solo se elimina si el usuario renuncia explícitamente a la E2E (y esa renuncia queda registrada en STATE.md como deuda consciente).
5. **Una tarea final**: `Retro + merge (LEARNINGS en el branch, luego merge)` — bloqueada por todo lo anterior.

### Reglas de actualización

- `in_progress` al LANZAR el trabajo (dev invocado, reviews lanzados, E2E iniciada).
- `completed` SOLO cuando el hito ocurrió de verdad: lote = commits del lote hechos (locales — los devs no pushean) y reporte del dev recibido; review dual local = veredictos limpios + sugerencias aplicadas + registro commiteado; PR/CI = PR creado + registro reconciliado (`PR-<N>.md`) + CI verde; E2E = checklist ejecutada con hallazgos resueltos; retro+merge = retro commiteada y pusheada al branch, CI verde y PR mergeado.
- Los blockers de reviews/E2E se resuelven dentro de la tarea en curso (fixes en el mismo PR) — NO crean tareas nuevas, salvo que generen trabajo fuera del PR (fix-PR posterior o issue), en cuyo caso sí se agrega la tarea.
- Si el usuario pausa la fase, las tareas quedan en su estado actual y HANDOFF.md/state.json registran el corte exacto (el tracker no persiste entre sesiones; al retomar, se recrea desde HANDOFF.md + STATE.md + state.json).
- Fases con un solo paso trivial no necesitan tracker (criterio general del harness: <3 pasos no se trackea).

---

## Formatos de archivos en `.planning/`

### `BRIEF.md`

```markdown
## Brief: [nombre de la feature]

### Objetivo
[Qué se quiere lograr en 1-2 oraciones]

### Alcance
- Incluye: [lista]
- NO incluye: [lista — igual de importante]

### Usuarios y permisos
[Quién interactúa, qué puede hacer cada rol]

### Flujo principal
1. [paso a paso lo que hace el usuario]

### Reglas de negocio
- [reglas concretas que se discutieron]

### Edge cases discutidos
- [situaciones especiales y cómo manejarlas]

### Decisiones tomadas
- [decisiones explícitas del usuario durante el brainstorming]

### Descartado explícitamente
- [cosas que se mencionaron y se decidió NO hacer]

### Design System (si aplica)
[Output del agente ui-ux: estilo, paleta, tipografía, anti-patterns, page specs]
[Si no se generó, omitir esta sección]
```

### `STATE.md` + `state.json`

**Regla de reparto:** prosa en `STATE.md`, estado enumerable en `state.json`. Si un dato tiene un valor de un enum cerrado o se usa para calcular progreso (fase, status de un lote, contador de tareas), va en `state.json`; si es texto libre que explica un porqué (una decisión, un blocker), va en `STATE.md`.

`STATE.md` pierde las secciones "Estado actual" y "Progreso" (migran al JSON) y gana una línea de puntero:

```markdown
## Decisiones
- [D-01] [decisión tomada durante brainstorming/diseño]
- [D-02] ...

## Blockers
- [ninguno | descripción del blocker]

---
El estado mutable (fase, lotes, progreso) vive en `state.json`.
```

**Schema de `state.json` (contrato — versión 1):**

```json
{
  "schema": 1,
  "feature": "slug-corto-de-la-feature",
  "branch": "feature/slug",
  "pr": null,
  "review_sha": null,
  "updated": "2026-08-13T18:30:00Z",
  "phases": {
    "brainstorming": "done",
    "design": "in_progress",
    "implementation": "pending",
    "docs": "pending",
    "review": "pending",
    "pr": "pending",
    "ci": "pending",
    "e2e": "skipped",
    "merge": "pending"
  },
  "batches": [
    {
      "id": 1,
      "name": "pre-compact-snapshot",
      "agent": "backend-dev",
      "status": "in_progress",
      "tasks_done": 2,
      "tasks_total": 5,
      "current_task": "3: no-op limpio sin .planning"
    }
  ]
}
```

- **Enum de status** (`phases.*` y `batches[].status`): `pending | in_progress | done | failed | skipped`. Ningún otro valor.
- `phases` es un objeto de **claves fijas** — siempre las 9 de arriba, presentes todas (`skipped` para las que no aplican, p. ej. `e2e` sin UI). Claves fijas = mutación mínima ("cambiar un valor"), menos corruptible que un array.
- `batches` refleja el plan del architect: `id`/`name`/`agent` los siembra el orchestrator al cerrar el diseño; `status`/`tasks_done`/`current_task` mutan durante la ejecución.
- **Orden de transiciones**: `review` pasa a `done` en la Fase 2.6, **antes** que `pr` y `ci` — el review dual ocurre pre-push. Es la evidencia que el hook `post-pr-create.sh` verifica al crearse el PR (CASO A: `phases.review == "done"`, `branch` igual al actual, y `review_sha` ancestro de HEAD con delta posterior solo bajo `.planning/`).
- **`review_sha`** (opcional, **sin bump de schema** — hooks viejos lo ignoran): SHA de HEAD al momento de los veredictos limpios de la Fase 2.6. Ancla la evidencia de review a los commits realmente revisados: si después del review entra cualquier commit que toque algo fuera de `.planning/` (los commits legítimos post-review son registro/reconciliación), el checkpoint deja de dar CASO A.

**Quién escribe qué:**

| Campo | Quién escribe | Cuándo |
|---|---|---|
| Archivo completo (creación) | Orchestrator | Al cerrar el diseño (fin de Fase 1) |
| `phases.*` | Orchestrator | En cada transición de fase del pipeline |
| `phases.review` | Orchestrator | Fase 2.6, al cerrar veredictos limpios (antes que `pr` y `ci`) |
| `review_sha` | Orchestrator | Fase 2.6, paso 7 — mismo momento que `phases.review`: SHA de HEAD al cerrar los veredictos limpios |
| `batches[].status` | Orchestrator | Al invocar / al cerrar cada lote |
| `batches[].tasks_done` y `current_task` de **su** batch | Dev que ejecuta el lote | Antes de empezar cada tarea atómica (reemplaza la regla 3 de `agent-budget.md` de "STATE.md actualizado entre tareas") |
| `pr` | Orchestrator | Fase 2.7 — dentro del commit de reconciliación (el mismo que renombra el registro a `PR-<N>.md`) |
| `phases.merge` | Orchestrator | Fase 4 — dentro del commit de retro, **antes** del merge. Post-merge no se escribe en `.planning/`: hacerlo obliga a commitear sobre `dev` |
| `updated` | Quien haga la escritura | En toda escritura al archivo |

**Cuándo actualizar `STATE.md`:**
- Al tomar una decisión nueva (`[D-NN]`)
- Al encontrar o resolver un blocker
- Al pausar o retomar

**Cuándo actualizar `state.json`:** ver tabla de arriba — cada transición de fase o lote, y entre cada tarea atómica del dev activo.

### `HANDOFF.md`

```markdown
## Handoff

### Dónde quedamos
[Descripción concreta de qué se estaba haciendo]

### Qué falta
- [ ] [tarea pendiente 1]
- [ ] [tarea pendiente 2]

### Contexto importante
- [información que la próxima sesión necesita saber]
- [decisiones tomadas que no son obvias del código]

### Para retomar
1. [instrucción paso a paso de cómo continuar]
```

### Retomar (resume)

Pasos exactos cuando el hook `session-start-context.sh` detecta `HANDOFF.md` (ver "Pause / Resume" en `CLAUDE.md` raíz para el resumen):

1. **Leer** `HANDOFF.md` + `STATE.md` + `state.json` — el HANDOFF da el corte exacto, `STATE.md` las decisiones, `state.json` la fase y el lote activos.
2. **Smoke test ANTES de tocar código.** Misma detección de runner que `hooks/pre-commit-guard.sh`:
   - Node: si hay `package.json` con `scripts.test` no vacío, corre con el gestor que indica el lockfile (`pnpm-lock.yaml` → pnpm, `yarn.lock` → yarn, si no → npm).
   - Python: si hay `pytest.ini`, `pyproject.toml` o `setup.py` y `pytest` está en PATH, corre `pytest`.
   - **Sin runner detectado** → se omite explícitamente y se anota en el reporte al usuario (no es un fallo, es contexto ausente).
   - **Rojo** → diagnosticar ANTES de retomar la tarea pendiente. El rojo puede ser el bug no documentado que cortó la sesión anterior, no una regresión de este momento.
3. **Eliminar `HANDOFF.md`** solo una vez confirmado el estado (verde, o sin runner y anotado) — recién ahí retomar la tarea marcada como `current_task` en `state.json`.

### `LEARNINGS.md` (acumulativo)

**Prepend** una entrada por PR mergeado (más reciente arriba) — en modo multi-PR, cada grupo corre su propia Fase 4 y deja su entrada. Se escribe en la Fase 4 y viaja en el **último commit del branch del PR**, antes del merge — nunca en un PR aparte:

```markdown
## [YYYY-MM-DD] PR #N — [título corto de la feature]

### Métricas
- Rounds de review: [N]
- Hallazgos security: [cantidad / severidad]
- Hallazgos qa-frontend: [cantidad / tipo]
- Hallazgos qa-backend: [cantidad / tipo]
- Errores de build/CI: [cantidad]
- Self-reflection atrapó: [cosas que detectó antes del review, o "nada"]
- Lotes ejecutados: [N] / Tareas: [M]
- Devs involucrados: [db-specialist? backend-dev? frontend-dev?]

### Qué salió bien
- [...]

### Qué causó re-work
- [...]

### Patrón potencial (si lo hay)
- [descripción del patrón observado]
```

**Regla de 3**: si un mismo patrón aparece en 3+ entradas, sugerir al usuario:

- Agregar regla en `rules/` (si es idiomático/calidad)
- Modificar prompt de un agente (si es de proceso)
- Crear hook nuevo (si es bloqueable automáticamente)

---

## Clasificación del diff por capa

### Frontend

Archivos con extensión:
- `.tsx`, `.jsx`, `.vue`, `.svelte`, `.html`, `.htm`
- `.css`, `.scss`, `.sass`, `.less`

O archivos `.ts` / `.js` bajo:
- `components/`, `pages/`, `app/`, `views/`
- `src/ui/`, `apps/frontend/`, `apps/web/`
- `frontend/`, `client/`, `web/`, `public/`
- `hooks/`, `stores/`

### Backend

Archivos con extensión:
- `.py`, `.go`, `.rs`, `.cs`, `.sql`
- `.sh`, `.bash` — hooks, libs y scripts. Se revisan contra `rules/bash.md`

O archivos `.ts` / `.js` bajo:
- `api/`, `apps/backend/`, `apps/api/`
- `backend/`, `server/`
- `services/`, `controllers/`, `routes/`, `handlers/`
- `models/`, `lib/`, `db/`, `migrations/`
- `workers/`, `jobs/`

### Documentos normativos del sistema de agentes

Un diff que toca `rules/`, `rulebooks/`, `agents/`, `skills/` o `global/CLAUDE.md` va a **`qa-backend`**, con criterio de coherencia normativa y anti-drift en vez de capas de aplicación (ver `agents/qa-backend.md`). No hay capa de aplicación que clasificar ahí: el contrato son los documentos.

Sin esta entrada, un diff 100% de metodología no matchea ninguna capa y el ruteo automático no invoca a nadie — pasó en esta misma sesión, donde el review ocurrió solo porque el orchestrator lo pidió a mano.

El `README.md` y el `CLAUDE.md` raíz de un proyecto **no** entran acá: son meta-documentación del repo, no reglas que los agentes consuman. La excepción es el repo de la metodología misma, donde ambos describen cómo se edita el sistema y sí van a `qa-backend`. El grep del DoD anti-drift los cubre igual, que es un mecanismo distinto: ese busca drift, este decide a quién invocar.

### Diff mixto

Si el diff (local o de PR) tiene archivos de ambas capas → lanzar **ambos QAs en paralelo**.

**Nota sobre DB**: archivos bajo `db/`, `migrations/`, `schema/` los revisa `qa-backend`. No hay un `qa-db` separado — el qa-backend valida que las migraciones del db-specialist sean consistentes con lo que el backend-dev consume.

---

## Comandos `gh` específicos

### Monitoreo de CI

```bash
# Esperar a que terminen los checks (modo watch, falla rápido)
gh pr checks <number> --watch --fail-fast

# Si algún check falló, obtener run ID y logs
gh run list --branch <branch> --limit 1 --json databaseId,conclusion
gh run view <run-id> --log-failed
```

### Verificación pre-merge (OBLIGATORIO antes de cada merge)

```bash
# 1. Threads de review sin resolver (inline; los comentarios generales del PR no bloquean)
gh api graphql -f query='query { repository(owner: "{owner}", name: "{repo}") { pullRequest(number: <number>) { reviewThreads(first: 100) { nodes { isResolved } } } } }' \
  --jq '[.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved == false)] | length'
# Si > 0, resolver o responder los threads antes de mergear

# 2. Reviews bloqueantes
gh pr view <number> --json reviewDecision --jq '.reviewDecision'
# Debe ser "APPROVED" o vacío. "CHANGES_REQUESTED" → NO mergear

# 3. CI checks
gh pr checks <number>
# Todos en ✓

# 4. Evidencia del review dual pre-push (cierra los caminos de creación de PR
#    que el checkpoint post-pr-create no ve: web UI, gh api)
test -f .planning/reviews/PR-<number>.md
jq -r '.phases.review' .planning/state.json   # debe ser "done"
REVIEW_SHA=$(jq -r '.review_sha // empty' .planning/state.json)
[ -n "$REVIEW_SHA" ] || echo "sin review_sha → NO mergear"
git merge-base --is-ancestor "$REVIEW_SHA" "$(git rev-parse <branch>)"
# exit 0 = el SHA revisado es ancestro del HEAD del branch. Si falta el
# registro, la fase no está en "done", o review_sha está ausente o no es
# ancestro → NO mergear
git diff --name-only "$REVIEW_SHA".."$(git rev-parse <branch>)" | grep -cv '^\.planning/'
# debe imprimir 0: el único delta legítimo post-review es registro y retro,
# ambos bajo .planning/ — mismo test que corre hooks/post-pr-create.sh al
# crearse el PR. Cualquier otro path = código que entró sin revisar después
# del review dual → volver a Fase 2.6, no mergear
```

**Si cualquiera de las 4 falla, NO mergear.** Reportar al usuario qué bloquea.

Solo si las 4 pasan, mergea según el tipo de branch:

```bash
# feature/* o hotfix/* (branch desechable)
gh pr merge <number> --merge --delete-branch

# dev → main (release): SIN --delete-branch, dev es persistente
gh pr merge <number> --merge
```

### Hotfix → integrar a dev después del merge

Después de mergear un hotfix a main:

```bash
git checkout dev && git pull origin dev
git merge origin/main --no-ff
git push origin dev
```

**La retro del hotfix no va acá.** Si la escribís, va en el branch del hotfix antes del merge a `main`, igual que en el flujo de feature (Fase 4). Commitearla después, sobre `dev`, es el mismo push directo a un branch protegido que este orden elimina — y el merge de integración de arriba ya es la única excepción sancionada, precisamente porque no hay otra forma de llevar el hotfix a `dev`.

---

## Formato de reporte de review

El mismo formato sirve para las dos rondas: **pre-PR** (Fase 2.6 — no hay PR todavía: el reporte vive solo en el registro local) y **post-PR** (re-reviews de Fase 3 y PRs fuera del flujo — ahí además se comenta con `gh pr comment <number> --body "<reporte>"`; ese comando aplica SOLO post-PR).

```markdown
## Review: [PR #<number> | pre-push <branch>] — [title]

### Resumen
[Qué hace este PR en 1-2 oraciones]

### Seguridad
[Hallazgos del security-reviewer]

### QA Frontend
[Hallazgos del qa-frontend — UX, componentes, tests. Omitir si no se lanzó]

### QA Backend
[Hallazgos del qa-backend — contratos, datos, tests, migraciones. Omitir si no se lanzó]

### Veredicto
**[APROBADO / CAMBIOS REQUERIDOS]**

#### Bloqueantes (deben arreglarse)
- [ ] ...

#### Sugerencias (opcionales)
- [ ] ...
```

**Registro (convención dual + reconciliación):**

| Momento | Archivo | Quién lo escribe |
|---|---|---|
| Fase 2.6 (pre-PR) | `.planning/reviews/pre-pr-<feature-slug>.md` | Orchestrator (consolidación) |
| Fase 2.7 (al crear el PR) | `git mv` → `.planning/reviews/PR-<N>.md` + `state.json.pr = N`, commit `planning: vincular review pre-push al PR #<N>` | Orchestrator |
| Fase 3 / skill `review-pr` (post-PR) | Append `## Re-review <fecha>` a `PR-<N>.md` (convención existente, sin cambio) | Orchestrator / skill |

`<feature-slug>` = campo `feature` de `state.json`. **Header obligatorio del registro pre-PR**: branch, base, SHA de HEAD revisado, fecha, veredicto — sin él, el re-review acotado al delta no tiene ancla. La reconciliación es un rename y no dos convenciones permanentes porque los re-reviews post-PR hacen append a `PR-<N>.md`: sin el rename, la historia de review de un mismo PR quedaría fragmentada en dos archivos.

---

## Pre-release E2E (Modo B del e2e-runner)

**Solo aplica para PRs a `main` (release).** Para PRs a `dev`, el usuario invoca a `e2e-runner` aparte (Modo A) — eso no es tu scope.

Antes de la verificación pre-merge en un PR a main, invoca `e2e-runner` en Modo B.

Pre-requisito — servicios corriendo:

```bash
docker compose up -d
docker compose ps
```

Verifica que todos los servicios estén `healthy`. Si alguno falla, escala al dev correspondiente antes de lanzar E2E.

Después:

1. **Invoca `e2e-runner` en Modo B** con:
   - Branch del PR a main
   - Lista de archivos del diff (`gh pr view <PR> --json files --jq '.files[].path'`)
   - URL base del frontend (Docker o staging)
2. El `e2e-runner` trabaja sobre el branch del PR a main directamente: si faltan tests, los crea; corre los existentes; commitea y pushea al mismo branch
3. Si los tests fallan → **BLOQUEANTE**: asigna el fix al dev correspondiente (front, back o db según dónde falle el flow)
4. El `e2e-runner` re-ejecuta después del fix hasta que pasen
5. **Máximo 3 ciclos de fix-rerun.** Si después de 3 sigue fallando, escala al usuario

**Cuándo NO ejecutar E2E pre-release** (raro):

- El PR a main es solo configuración / docs (no hay cambios de código que afecten flujos de usuario)
- El usuario explícitamente lo pide

---

## Anti-drift: DoD de cambios de proceso

Todo PR que cambia el **flujo** (fases del pipeline, hooks, formatos de `.planning/`, reglas de agentes) incluye, como parte de su Definition of Done, antes de pedir review:

1. **Grep de los términos afectados** en `CLAUDE.md`, `README.md`, `rulebooks/`, `agents/`, `skills/` y `.planning/` — cualquier mención del comportamiento viejo es candidata a quedar desactualizada. `.planning/` entra en la lista porque sus documentos tienen preámbulo normativo propio: el de `LEARNINGS.md` quedó describiendo el comportamiento viejo en el PR #59 y ningún reviewer lo vio, porque el directorio no estaba acá.
2. **Reconciliar todo documento que describa el comportamiento cambiado.** No basta con documentar el cambio en un solo archivo — el mismo hecho (p. ej. "el dev actualiza X entre tareas") suele estar descrito en más de un rulebook o en `CLAUDE.md` raíz.
3. **Enunciar una vez, remitir el resto.** Vale para lo que decide y también para **lo que afirma sobre un incidente pasado** — conteos, citas, quién encontró qué: si ya está registrado en `.planning/`, remití en vez de reconstruirlo en prosa nueva, que es donde la paráfrasis diverge de la fuente. Antes de escribir una frase que **decide** algo —qué bloquea un merge, quién pushea, dónde va la retro—, buscá si ese hecho ya está enunciado. Si está, remití en vez de repetirlo — **la remisión conserva siempre el enunciado accionable; lo que se mueve es la elaboración**. Nunca reduzcas a un puntero pelado una advertencia que alguien necesita leer en el momento en que está parado ahí.

   **Por qué es un paso y no un consejo de estilo:** el grep del paso 1 cruza *términos*, no *decisiones*. Dos enunciaciones del mismo hecho con vocabulario distinto son invisibles para él y divergen con el tiempo. Casos reales de este repo: "commit propio posterior a la integración" contra "push directo a un branch protegido" —deciden lo mismo, sin compartir una palabra, y una quedó instruyendo lo que la otra prohibía—; y "es la única situación en que el dev pushea" contra "hay exactamente dos excepciones", en dos rulebooks distintos.

   Ese patrón —resumen accionable más puntero— es el mayoritario del corpus y funciona: la auditoría del 2026-08-26 encontró solo 5 hechos enunciados dos veces en 1900 líneas.

   **Dónde vive el detalle:** en el rulebook o la skill, nunca en `global/CLAUDE.md`, que se carga en toda sesión de todo proyecto. Si al aplicar esta regla el detalle sube al núcleo, arreglaste la contradicción y rompiste el presupuesto de contexto.
4. **Si el PR introduce una regla, releé el diff completo aplicándola.** Escribir una regla y aplicarla al propio cambio son dos pasadas distintas, y hacerlas en una sola no funciona: en cuatro PRs seguidos el review encontró que el PR violaba la regla que estaba escribiendo:

   | PR | Lo que se escribía | Lo que el review encontró |
   |---|---|---|
   | #61 | El principio 5 y su corolario | Una instrucción que obligaba a los QA a rodear su propia política de tools |
   | #64 | `rules/bash.md`, con un red flag contra las garantías absolutas | Un absoluto en ese mismo archivo |
   | #65 | Que el estado se sella antes del merge para no bypassear `dev` | La ruta de hotfix arreglada en un lugar y viva en el punto de decisión, a 400 líneas |
   | #66 | Enunciar una vez y remitir | Una contradicción residual tres líneas debajo del fix |

   Ninguna la atrapó la autorrevisión del autor: las cuatro salieron del review dual, y dos de ellas las encontraron los dos reviewers por separado. Lo que funciona es la pasada externa, no quién la haga.

   Leelo como si el diff fuera de otro. Si la regla nueva tiene un criterio verificable —"el test se rompe al revertir", "el enunciado accionable sigue en su lugar"— corrélo sobre tu propio cambio antes de pedir review.

   **Este paso no se puede auditar, y por eso no se audita.** A diferencia del paso 1, que deja la salida de un grep, o del corolario del principio 5, que deja un rojo→verde, una relectura se cumple diciendo "la hice" — un artefacto que la declare no la verifica. El respaldo es la pasada externa: `qa-backend` aplica al diff la regla que el diff introduce, sin auditar si vos la releíste. Hacer tu propia relectura igual vale, porque encontrarlo antes es más barato; pero lo que sostiene el paso es el review, no tu declaración.

**Ninguno de los cuatro pasos es opcional ni cosmético.** Los pasos 1 a 3 atacan la deriva entre documentos: la mayoría de las 7 contradicciones de la auditoría de julio (ver `.planning/AUDIT-context-engineering.md`) eran de esa clase — un cambio de proceso documentado en un archivo y olvidado en otro. El paso 4 ataca otra: el PR que viola la regla que está escribiendo, con su propia evidencia en la tabla de arriba.

---

## Errores comunes y cómo manejarlos

| Situación | Acción |
|-----------|--------|
| Architect entrega plan con lote >5 | Devolver con mensaje específico (ver agent prompt). Max 3 retries, después escalar |
| Architect entrega plan con backend-dev antes que db-specialist en feature con DB compleja | Devolver al architect: "el orden es incorrecto, db-specialist va primero porque backend-dev consume el schema" |
| Dev (cualquiera) reporta `BUDGET LIMIT` | Leer `HANDOFF.md`, reinvocar al mismo dev con tareas restantes, anotar en `LEARNINGS.md` |
| Dev reporta error de build/CI | `build-resolver` con error completo + branch + archivos. Max 3 fixes automáticos |
| Reviewer reporta bloqueante | Asignar fix al dev del lote correspondiente en mismo branch. Re-lanzar solo el reviewer que reportó. Repetir hasta aprobación |
| PR creado sin review pre-push (el checkpoint del hook `post-pr-create` lo señala) | Tratarlo como PR fuera del flujo: skill `review-pr` sobre `gh pr diff` |
| `gh pr merge` falla | Verificar las 4 condiciones de pre-merge. Reportar cuál bloquea |
| Healthcheck Docker falla antes de E2E pre-release | Escalar al dev del servicio fallando antes de lanzar `e2e-runner` Modo B |
| Hotfix mergeado pero falló integración a dev | Conflicto manual. Escalar al usuario con detalles del conflicto |
| Migración del db-specialist falla en CI | Asignar fix al db-specialist (no a backend-dev) — es su scope |
| Backend-dev intenta crear migración compleja (no simple) | Devolver: "esto califica como complejo según los criterios. Reasignar al db-specialist" |
| Estado de `.planning/` corrupto o inconsistente post-compact | Restaurar desde el snapshot más reciente en `~/.claude/methodology/snapshots/<slug>/` (los crea el hook `PreCompact`) |

---

## Flujo: revisar PR existente (sin pasar por el flow completo)

Cuando el usuario pide revisar un PR que no salió de este flujo:

1. `gh pr view <number> --json number,title,body,headRefName,baseRefName,files`
2. `gh pr diff <number>`
3. Clasifica el diff (sección "Clasificación del diff por capa") y lanza los reviewers correspondientes en paralelo
4. Consolida y comenta en el PR: `gh pr comment <number> --body "<reporte>"` (formato en sección "Formato de reporte de review")

El registro se guarda **directo en `.planning/reviews/PR-<N>.md`** — acá no hay archivo `pre-pr-*` que reconciliar: el PR ya existía antes del review.
