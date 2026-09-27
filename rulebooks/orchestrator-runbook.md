# Orchestrator Runbook

Detalle operativo del flujo de orchestration. **Lectura bajo demanda**: las invariantes viven en `CLAUDE.md` raíz y se cargan siempre; el manual de la sesión principal (fases, equipo de subagentes, lotes) vive en la skill `orchestrator`; este documento se consulta cuando necesitas un formato exacto, un comando específico o resolver una situación puntual.

---

## Contenido

1. [Detalle de cada fase del flujo](#detalle-de-cada-fase-del-flujo)
2. [Cuándo un lote es DB complejo](#cuándo-un-lote-es-db-complejo)
3. [Template del prompt de handoff a devs](#template-del-prompt-de-handoff-a-devs)
4. [Formatos de archivos en `.planning/`](#formatos-de-archivos-en-planning)
5. [Clasificación del diff por capa (frontend / backend)](#clasificación-del-diff-por-capa)
6. [Comandos `gh` específicos](#comandos-gh-específicos)
7. [Formato de reporte de review](#formato-de-reporte-de-review)
8. [Pre-release E2E (Modo B del e2e-runner)](#pre-release-e2e-modo-b-del-e2e-runner)
9. [Errores comunes y cómo manejarlos](#errores-comunes-y-cómo-manejarlos)

---

## Detalle de cada fase del flujo

El proceso de brainstorming (Fase 0) vive en la skill `orchestrator`, sección 3. Acá empieza el detalle desde el diseño.

### Fase 0.5: Design system (si hay UI)

Invoca `ui-ux` solo si no existe `design-system/<proyecto>/MASTER.md`, o si el brief introduce una página crítica o un patrón visual nuevo. Si `MASTER.md` ya existe y la UI del brief es chica, no lo invocas: el `architect` referencia `MASTER.md` en el brief y el `frontend-dev` lee `MASTER.md` y aplica sus constraints directamente, sin pasar por `ui-ux`.

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
2. El architect entrega `.planning/DESIGN.md` con plan de lotes y estrategia de PR. Si identifica DB compleja (ver criterios completos abajo), marca ese lote de `backend-dev` como `db-complejo` y lo ubica primero
3. **Validación del plan** (antes de implementar):
   - Cada lote tiene **≤5 tareas**. Si excede, devolver al architect: *"El Lote X tiene N tareas. Excede el cap de 5. Repártelo en lotes más chicos."*
   - **Máximo 3 reintentos de validación.** Si después de 3 intentos el architect no entrega plan válido, escala al usuario con el plan actual y los problemas detectados
   - Estrategia de PR declarada (single-PR o multi-PR con justificación)
4. Solo cuando el plan es válido, procedes a Fase 2

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
3. **Orden esperado cuando hay un lote `db-complejo`**:
   - El lote `db-complejo` primero (siempre): schema, migraciones, queries, tests de DB. Lo hace `backend-dev`, con `rulebooks/db-migrations.md`
   - El resto de `backend-dev` después (necesita el schema)
   - `frontend-dev` al final (necesita los endpoints)
   - Si el resto de back y front son independientes (archivos disjuntos), pueden paralelizar

   Esto porque los lotes siguientes necesitan el schema disponible para importar tipos. Si el architect entrega un plan que tiene un lote consumidor antes del `db-complejo` en una feature con DB compleja, **devuélveselo al architect** — es probable que esté mal particionado.

   Excepción: si los lotes son genuinamente independientes (el lote `db-complejo` trabaja en una tabla X que el otro lote no toca, y ese otro lote trabaja sobre tablas existentes que no cambian), pueden ir en paralelo.

#### Modo multi-PR (solo si architect lo justificó)

Cada grupo de lotes (con su propio `**PR:**` declarado) corre sobre branch propio + PR. Para cada grupo:

1. Crear branch desde dev
2. Invocar lotes del grupo (último con `last_batch=true`)
3. Fase 2.5 (docs) → Fase 2.6 (review local) → Fase 2.7 (push + PR) → Fase 2.8 (CI) → Fase 3 (post-PR) → Fase 5 (merge)
4. Pasar al siguiente grupo

#### Si un dev reporta `BUDGET LIMIT — ver HANDOFF.md`

El plan del architect debió evitar esto. Si pasa:

1. Lee `.planning/HANDOFF.md`
2. Reinvoca al mismo dev con SOLO las tareas restantes
3. Abre un issue si el patrón se repite, para que el architect ajuste sus particiones futuras

#### Si un dev reporta error de build/compilación que no puede resolver

Reinvoca al mismo dev (el que produjo el error) con la instrucción de leer `rulebooks/build-errors.md`. Resuelve en el mismo branch y reporta qué hizo. Si el usuario pide ayuda directa con un build roto fuera de un lote en curso, delega en `backend-dev` o `frontend-dev` según el stack, con el mismo rulebook.

### Fase 2.5: Documentación (pre-push)

Cuando el último lote reporta completado, corre `git diff --stat <base>...HEAD`. Si el diff solo toca tests, `.planning/` o código interno — sin cambios en README, API, CLI ni config —, salta `docs` y lo registra en el body del PR. Excepción: cambios en hooks, permisos, auth o controles de seguridad siempre invocan `docs`, aunque el resto del diff clasifique como código interno. En cualquier otro caso, invoca `docs` con: branch, base branch y la instrucción de leer el diff local (`git diff <base>...HEAD`). El `docs` genera/actualiza docs y **commitea al branch SIN pushear** — su commit viaja en el push inicial (presupuesto de CI: evita un run de Actions solo por docs).

Si reporta "sin cambios necesarios", avanza directo a Fase 2.6.

### Fase 2.6: Review dual local (pre-push)

El review dual ocurre **ANTES del push inicial**: `security-reviewer` + `qa-*` revisan el diff local y las rondas de fixes suceden sin pushear nada. El PR nace revisado y el caso normal cuesta un solo run de CI. `<base>` = branch base del PR futuro (normalmente `dev`).

1. **Clasifica el diff local por capa**: `git diff --name-only <base>...HEAD` + sección "Clasificación del diff por capa" más abajo
2. **Presupuesta el review proporcional al diff**: `git diff --shortstat <base>...HEAD` para additions+deletions; misma tabla y mandato de cierre que la skill `review-pr` (paso 3) — el presupuesto proporcional aplica igual en pre-PR
3. **Lanza en paralelo** (single message, multiple Agent calls):
   - `security-reviewer` — siempre
   - `qa-frontend` — solo si el diff tiene frontend
   - `qa-backend` — solo si el diff tiene backend (incluye revisar migraciones y queries del lote `db-complejo`)

   Paquete de contexto: base + branch + instrucción de leer `git diff <base>...HEAD` + lista de archivos + `BRIEF.md` + `DESIGN.md` + presupuesto + formato de salida. **Sin número de PR — no existe todavía.** Si el diff **introduce una regla nueva**, decilo en el paquete: el reviewer tiene que aplicarla al propio diff (ver `agents/qa-backend.md`). Puede identificarla leyendo el diff, pero nombrarla le ahorra ese paso. Si el reviewer corre suites desde un worktree: que exporte su propia base de test (`TEST_DATABASE_URL` o el equivalente del proyecto, ej. `<base>_<reviewer>`) para no pisar la corrida del árbol principal ni bloquear el hook de pre-commit de otro agente.
4. **Consolida y registra**: el orchestrator es el único escritor del registro — ningún reviewer lo toca (tienen `Write`/`Edit` prohibidos y devuelven el reporte como respuesta). Consolidás, uno por sección, los reportes que te devuelven los reviewers en paralelo **después de que vuelvan todos**, con el "Formato de reporte de review" (más abajo), guardado local (sin commit — `.planning/` no se versiona) en `.planning/reviews/<feature-slug>.md`, con header de trazabilidad (branch, base, SHA de HEAD revisado, fecha, veredicto).
5. **Mientras haya un reviewer corriendo, el árbol no se mueve.** Esperá a que vuelvan **todos** antes de aplicar nada: si aplicás los hallazgos del primero, los demás quedan leyendo un árbol que cambió bajo sus pies. Si uno se cuelga o excede su presupuesto, cortalo y relanzalo después de aplicar, o aplicá solo en archivos que ese reviewer no esté mirando — pero decidilo explícitamente. Vale igual para un dev trabajando en paralelo: si un lote y un review tocan los mismos archivos, no van juntos.
6. **Si hay bloqueantes**: fixes por el dev correspondiente en el mismo branch, **sin push** (si el bloqueante es de schema/migración/query optimizada, va a `backend-dev` con `rulebooks/db-migrations.md`). Re-lanza **solo** los reviewers que marcaron issues, acotados al delta local (`git diff <sha-ya-revisado>...HEAD`). Append de la re-ronda al registro. Sugerencias baratas: aplicadas antes del push (política en la skill `pr-workflow`, regla 2)
7. **Veredictos limpios**: actualiza `.planning/state.json` (`phases.review` a `done` y `review_sha` al SHA de HEAD al momento de los veredictos limpios) y avanza a Fase 2.7. Fixes, sugerencias aplicadas y registro viajan en el push inicial: **el PR nace revisado**

### Fase 2.7: Push + PR

Lo haces tú (es orquestación git, no código):

```bash
git push -u origin <branch>
gh pr create --base dev --title "<título>" --body "<resumen de lotes + decisiones>"   # body incluye veredictos del review pre-push
```

Actualiza `.planning/state.json` con `pr = N` (local, sin commit — `.planning/` no se versiona).

El body del PR lo armas desde `.planning/` (BRIEF/DESIGN), los reportes de los devs y el registro del review pre-push (`.planning/reviews/<feature-slug>.md`): qué se implementó, decisiones ambiguas resueltas durante los lotes, veredictos del review dual (Fase 2.6), y sección `## Self-reflection — pendientes` si algún dev la reportó.

### Fase 2.8: Monitoreo de CI

Después de que se crea el PR, y **antes** de ponerte a esperar checks:

```bash
gh pr view <number> --json mergeable,mergeStateStatus
gh pr checks <number> --watch --fail-fast
```

**El chequeo de `mergeable` va primero y no es opcional.** GitHub **no crea ninguna corrida** en un PR con conflictos —no puede calcular el merge commit—, así que `gh pr checks` responde "no checks reported" indefinidamente y un `--watch` se queda esperando algo que nunca va a llegar. El síntoma se lee igual que "CI encolado", que es lo que lo vuelve caro: se confunde un bloqueo permanente con una demora. Si sale `CONFLICTING`/`DIRTY`, resuelve el conflicto (mergeá la base al branch, nunca `--force`) y recién entonces esperá checks. Si sale `UNKNOWN`, GitHub todavía está calculando el merge: reintentá — `UNKNOWN` no es verde.

- Si todos pasan → Fase 3
- Si falla algún check:
  - Lee logs: `gh run view <run-id> --log-failed`
  - Asigna el fix:
    - Build/compilación/dependencias → dev que creó el PR, con `rulebooks/build-errors.md`
    - Tests o lint → dev que creó el PR
    - Tests de DB que fallan por schema/migración → `backend-dev`, con `rulebooks/db-migrations.md`
  - El agente corrige en el **mismo branch del PR**. **Antes de pushear, debe reproducir el check fallido localmente y verlo pasar** (presupuesto de CI: un run fallido cuesta lo mismo que uno verde)
  - Si el fix cambia código ya revisado en Fase 2.6, anótalo: al quedar CI verde dispara el re-review acotado de la Fase 3
  - Vuelve a monitorear
- **Máximo 3 intentos de fix automático.** Cuenta cada ciclo "diagnóstico → fix → push → CI": si el fix introduce un error nuevo no presente antes (regresión), ese intento **no cuenta** y reinicias el diagnóstico. Si el mismo error persiste tras 3 ciclos genuinos, escalas al usuario con contexto completo

**Cuándo NO monitorear CI**: el proyecto no tiene GitHub Actions, o el usuario lo pide explícitamente.

### Fase 3: Post-PR (re-reviews condicionales, E2E)

El review dual ya ocurrió en Fase 2.6, antes del push: **el PR nació revisado**. Esta fase cubre solo lo que requiere el PR abierto:

1. **Re-review condicional**: SOLO si la Fase 2.8 obligó fixes que cambian código ya revisado. Acotado al delta del fix, re-lanzando **solo los reviewers de la capa afectada**. Los fixes que salgan de esta ronda siguen la regla de un push por ronda (skill `pr-workflow`, regla 5.2). Append de la ronda al registro local (`.planning/reviews/<feature-slug>.md`). Si CI pasó a la primera (caso normal), esta sub-fase es no-op
2. **Si el PR es a `main` (release)**: invoca `e2e-runner` en Modo B antes de la verificación pre-merge (ver sección "Pre-release E2E" más abajo); opcionalmente invoca `code-sweep` en modo `bugs` sobre los archivos del diff
3. Cuando no queda nada pendiente (re-reviews limpios si los hubo, `e2e-runner` si era PR a main), avanza a **Fase 5**

**PRs fuera del flujo** (sin review pre-push — el checkpoint del hook `post-pr-create` lo señala): skill `review-pr`.

### Fase 5: Merge

1. Ejecuta la **verificación pre-merge** (3 checks en sección "Comandos `gh` específicos")
2. Solo si las verificaciones pasan **y el usuario aprobó el merge explícitamente** (invariante 3 de `CLAUDE.md`: no se infiere de CI verde), mergea con el comando apropiado según el tipo de branch:
   - `feature/*` o `hotfix/*` → `gh pr merge <number> --merge --delete-branch`
   - `dev → main` (release) → `gh pr merge <number> --merge` **sin `--delete-branch`** (`dev` es persistente, ver Gitflow en `CLAUDE.md`)
3. Si era hotfix (PR a main), después del merge integra a dev (procedimiento más abajo)
4. Después del merge: `.planning/state.json` con `phases.merge` en `done` (local — `.planning/` no se versiona, no hay commit que hacer)

---

## Cuándo un lote es DB complejo

`backend-dev` recibe todos los lotes de DB — no hay agente aparte. El `architect` marca un lote como `db-complejo` cuando el trabajo califica; el resto lo trata como cualquier lote de `backend-dev`. La línea divisoria (detalle completo en `rulebooks/db-migrations.md`):

**Es `db-complejo`:**

- Migraciones que requieren **backfill de datos** (script de transformación)
- Cambio de tipo de columna con datos existentes (`varchar → text`, `int → bigint`, JSON → columnas tipadas)
- Particionamiento o sharding
- Migración de datos entre tablas (split/merge)
- Estrategia zero-downtime (expand-contract)
- Optimización de queries lentas (EXPLAIN, índices compuestos, materialización)
- Constraints nuevos sobre datos existentes (`NOT NULL` en columna con NULLs)
- Migraciones que afecten >1M de filas en producción
- Schema con relaciones complejas, herencia, polimorfismo, requisitos de performance específicos

**No es `db-complejo` (lote simple de `backend-dev`):**

- Crear/borrar tabla nueva (sin datos previos a preservar)
- Agregar columna nullable o con default (sin backfill)
- Agregar/quitar índice
- Renombrar columna sin uso en producción o detrás de feature flag
- Agregar/modificar foreign key
- Cambios en seeds/fixtures de desarrollo

**Regla rápida:** si la migración necesita un script que toque datos, o requiere análisis de performance, es `db-complejo`.

**Cuando la feature tiene un lote `db-complejo`**: recibe su propio lote en el plan del architect, va primero, trabaja sobre el **mismo branch** que los demás lotes, commitea con flag `last_batch=true|false` igual que cualquier lote. Incluye: schema (vía Drizzle/Pydantic/equivalente del proyecto), migraciones, queries optimizadas, tests de DB. Los lotes siguientes (de `backend-dev` o `frontend-dev`) consumen el schema resultante en sus endpoints, sin modificarlo.

---

## Template del prompt de handoff a devs

Cada subagente recibe un paquete de contexto armado por vos, **no el historial completo**: `architect` recibe `BRIEF.md` completo; `backend-dev`/`frontend-dev` reciben la sección de `DESIGN.md` de su lote + tareas + `rules/<lenguaje>.md` (y en `db-complejo`, además schema actual + `rulebooks/db-migrations.md`); `security-reviewer`/`qa-*` reciben la fuente del diff (local o `gh pr diff`, según la fase) + `DESIGN.md` + `BRIEF.md`.

**Por cada invocación de dev**, el handoff debe incluir:

- **Solo las tareas de su lote** (no el plan completo)
- **Path al schema/contratos** que ya escribió el architect (o un lote `db-complejo` anterior, si aplica)
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

Aplica para `backend-dev`, `frontend-dev`. El formato del prompt es el mismo:

```
Branch: <feature-branch>
Lote: <N> de <M>
Last batch: <true|false>

Tareas a implementar:
1. <tarea 1>
2. <tarea 2>
...
(máximo 5)

Schemas/contratos a usar (ya escritos por architect o por un lote `db-complejo` anterior):
- <path/al/schema.ts>
- <path/al/types.ts>

Sección de DESIGN.md correspondiente:
<inline o path>

Rules aplicables:
- ~/.claude/rules/<lenguaje>.md
- ~/.claude/rules/docker.md (si aplica)

Si no es el primer lote: lee `git log`, `.planning/STATE.md` y `.planning/state.json` antes de empezar.

Si trabajás o corrés suites desde un worktree: exportá tu propia base de test (`TEST_DATABASE_URL` o el equivalente del proyecto, ej. `<base>_<lote>`) para no pisar la corrida del árbol principal ni bloquear el hook de pre-commit de otro agente.

Si last_batch=false: NO push, NO PR. Reporta completado.
Si last_batch=true: verificación final completa del branch y reporta listo.
NO push ni PR en ningún caso — el orchestrator corre docs y hace push + PR.
```

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

### Resultado esperado
- **Para el usuario:** [una frase]
- **Señal de éxito:** [métrica o evento observable, dónde se mide, plazo]

### Criterios de aceptación
1. [criterio verificable con sí/no] — origen: brief §<sección> | nuevo

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
- **Orden de transiciones**: `review` pasa a `done` antes que `pr`/`ci` — el review dual ocurre pre-push. `review_sha` ancla el checkpoint de `post-pr-create.sh`.
- **`review_sha`** (opcional, **sin bump de schema** — hooks viejos lo ignoran): SHA de HEAD al momento de los veredictos limpios de la Fase 2.6.

**Quién escribe qué:**

| Campo | Quién escribe | Cuándo |
|---|---|---|
| Archivo completo (creación) | Orchestrator | Al cerrar el diseño (fin de Fase 1) |
| `phases.*` | Orchestrator | En cada transición de fase del pipeline |
| `phases.review` | Orchestrator | Fase 2.6, al cerrar veredictos limpios (antes que `pr` y `ci`) |
| `review_sha` | Orchestrator | Fase 2.6, paso 7 — mismo momento que `phases.review`: SHA de HEAD al cerrar los veredictos limpios |
| `batches[].status` | Orchestrator | Al invocar / al cerrar cada lote |
| `batches[].tasks_done` y `current_task` de **su** batch | Dev que ejecuta el lote | Antes de empezar cada tarea atómica (reemplaza la regla 3 de `agent-budget.md` de "STATE.md actualizado entre tareas") |
| `pr` | Orchestrator | Fase 2.7, local (sin commit — `.planning/` no se versiona) |
| `phases.merge` | Orchestrator | Fase 5, post-merge, local (sin commit) |
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

Pasos exactos cuando el hook `session-start-context.sh` detecta `HANDOFF.md` (ver "Pause / Resume" en la skill `orchestrator` para el resumen):

1. **Leer** `HANDOFF.md` + `STATE.md` + `state.json` — el HANDOFF da el corte exacto, `STATE.md` las decisiones, `state.json` la fase y el lote activos.
2. **Smoke test ANTES de tocar código.** Misma detección de runner que `hooks/pre-commit-guard.sh`:
   - Node: si hay `package.json` con `scripts.test` no vacío, corre con el gestor que indica el lockfile (`pnpm-lock.yaml` → pnpm, `yarn.lock` → yarn, si no → npm).
   - Python: si hay `pytest.ini`, `pyproject.toml` o `setup.py` y `pytest` está en PATH, corre `pytest`.
   - **Sin runner detectado** → se omite explícitamente y se anota en el reporte al usuario (no es un fallo, es contexto ausente).
   - **Rojo** → diagnosticar ANTES de retomar la tarea pendiente. El rojo puede ser el bug no documentado que cortó la sesión anterior, no una regresión de este momento.
3. **Eliminar `HANDOFF.md`** solo una vez confirmado el estado (verde, o sin runner y anotado) — recién ahí retomar la tarea marcada como `current_task` en `state.json`.

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

Un diff que toca `rules/`, `rulebooks/`, `agents/`, `skills/` (incluida `skills/orchestrator/SKILL.md`) o `global/CLAUDE.md` va a **`qa-backend`**, con criterio de coherencia normativa y anti-drift en vez de capas de aplicación (ver `agents/qa-backend.md`). No hay capa de aplicación que clasificar ahí: el contrato son los documentos.

Sin esta entrada, un diff 100% de metodología no matchea ninguna capa y el ruteo automático no invoca a nadie.

El `README.md` y el `CLAUDE.md` raíz de un proyecto **no** entran acá: son meta-documentación del repo, no reglas que los agentes consuman. La excepción es el repo de la metodología misma, donde ambos describen cómo se edita el sistema y sí van a `qa-backend`.

### Diff mixto

Si el diff (local o de PR) tiene archivos de ambas capas → lanzar **ambos QAs en paralelo**.

**Nota sobre DB**: archivos bajo `db/`, `migrations/`, `schema/` los revisa `qa-backend`. No hay un `qa-db` separado — el qa-backend valida que las migraciones del lote `db-complejo` sean consistentes con lo que el resto de `backend-dev` consume.

---

## Comandos `gh` específicos

### Monitoreo de CI

```bash
# SIEMPRE primero: un PR en conflicto no genera corridas, así que el watch
# de abajo esperaría indefinidamente algo que nunca va a existir, con el
# mismo aspecto que "CI encolado" (ver Fase 2.8)
gh pr view <number> --json mergeable,mergeStateStatus
# CONFLICTING/DIRTY → resolver el conflicto antes de esperar checks
# UNKNOWN → GitHub sigue calculando: reintentar, no es verde

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

# 3. CI checks — `mergeable` PRIMERO: un PR en conflicto no genera corridas,
#    así que `gh pr checks` diría "no checks reported" para siempre y el
#    check se leería como "todavía no corrió" en vez de "está bloqueado"
gh pr view <number> --json mergeable,mergeStateStatus
# MERGEABLE + CLEAN/BLOCKED. Si es CONFLICTING/DIRTY → resolver el conflicto,
# no mergear. Si es UNKNOWN, GitHub aún está calculando: reintentar, nunca
# interpretarlo como verde
gh pr checks <number>
# Todos en ✓
```

**Si cualquiera de las 3 falla, NO mergear.** Reportar al usuario qué bloquea.

Solo si las 3 pasan, mergea según el tipo de branch:

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
[Criterios de aceptación del brief: cubiertos N de M (lista los no cubiertos). Solo si BRIEF.md los trae; no bloquea por sí solo.]

### QA Backend
[Hallazgos del qa-backend — contratos, datos, tests, migraciones. Omitir si no se lanzó]
[Criterios de aceptación del brief: cubiertos N de M (lista los no cubiertos). Solo si BRIEF.md los trae; no bloquea por sí solo.]

### Veredicto
**[APROBADO / CAMBIOS REQUERIDOS]**

#### Bloqueantes (deben arreglarse)
- [ ] ...

#### Sugerencias (opcionales)
- [ ] ...
```

El registro vive en `.planning/reviews/<feature-slug>.md` (local, sin commit — `.planning/` no se versiona), un archivo por feature con append por ronda (pre-PR, post-PR, PRs fuera del flujo). `<feature-slug>` = campo `feature` de `state.json`. **Header obligatorio en la primera ronda**: branch, base, SHA de HEAD revisado, fecha, veredicto — sin él, el re-review acotado al delta no tiene ancla.

**El orchestrator es el único escritor del registro**, aunque los reviewers corran en paralelo: `security-reviewer`, `qa-backend` y `qa-frontend` tienen `Write`/`Edit` prohibidos, devuelven su reporte como respuesta y el orchestrator consolida después de que vuelven todos.

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

## Errores comunes y cómo manejarlos

| Situación | Acción |
|-----------|--------|
| Architect entrega plan con lote >5 | Devolver con mensaje específico (ver agent prompt). Max 3 retries, después escalar |
| Architect entrega plan con un lote consumidor antes que el lote `db-complejo` | Devolver al architect: "el orden es incorrecto, el lote `db-complejo` va primero porque los lotes siguientes consumen su schema" |
| Dev (cualquiera) reporta `BUDGET LIMIT` | Leer `HANDOFF.md`, reinvocar al mismo dev con tareas restantes |
| Dev reporta error de build/CI | Reinvocar al mismo dev con `rulebooks/build-errors.md`. Max 3 fixes automáticos |
| Reviewer reporta bloqueante | Asignar fix al dev del lote correspondiente en mismo branch. Re-lanzar solo el reviewer que reportó. Repetir hasta aprobación |
| PR creado sin review pre-push (el checkpoint del hook `post-pr-create` lo señala) | Tratarlo como PR fuera del flujo: skill `review-pr` sobre `gh pr diff` |
| `gh pr merge` falla | Verificar las 3 condiciones de pre-merge. Reportar cuál bloquea |
| Healthcheck Docker falla antes de E2E pre-release | Escalar al dev del servicio fallando antes de lanzar `e2e-runner` Modo B |
| Hotfix mergeado pero falló integración a dev | Conflicto manual. Escalar al usuario con detalles del conflicto |
| Migración del lote `db-complejo` falla en CI | Asignar fix a `backend-dev` (mismo dev, `rulebooks/db-migrations.md`) |
| Backend-dev encuentra migración compleja en un lote no marcado `db-complejo` | Devolver al architect: "esto califica como complejo según `rulebooks/db-migrations.md`. Reordenar el plan con un lote `db-complejo` propio" |
| Estado de `.planning/` corrupto o inconsistente post-compact | Restaurar desde el snapshot más reciente en `~/.claude/methodology/snapshots/<slug>/` (los crea el hook `PreCompact`) |
