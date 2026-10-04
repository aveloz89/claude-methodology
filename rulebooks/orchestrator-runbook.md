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

**Cómo invocar `ui-ux`:** pásale solo el brief (`.planning/BRIEF.md` o el pasaje relevante), nombre del proyecto y el path a `design-system/` si ya existe — nunca historial ni diseños técnicos previos. Genera/extiende `design-system/<proyecto>/MASTER.md` (estilo, paleta, tipografía, componentes, anti-patterns) y `pages/<page>.md` para páginas críticas. Si te pide tono/audiencia/referencias que faltan en el brief, pregúntale al usuario y reenvía la respuesta. Copia el bloque "Para incluir en el brief al architect" a `### Design System` del `BRIEF.md` antes de invocar al architect.

**Cuándo NO invocar `ui-ux`:** la tarea no tiene componente visual, o el cambio respeta el design system existente sin componentes ni páginas críticas nuevas.

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

Setup del branch (una sola vez): `git checkout dev && git pull origin dev && git checkout -b feature/<feature-slug>`. Los devs **no crean branches nuevos** — trabajan sobre el que ya creaste.

**Modo single-PR (default):** todos los lotes corren sobre el mismo branch. Invocas cada lote en orden con `last_batch=false`; el dev commitea por tarea y termina sin push ni PR; esperas su reporte antes de pasar al siguiente. El último lote lleva `last_batch=true` (verificación final completa, sin push ni PR) — después vienen docs (2.5), review dual local (2.6) y push + PR (2.7). **Con lote `db-complejo`**: primero ese lote (schema, migraciones, queries, tests de DB, con `rulebooks/db-migrations.md`), después el resto de `backend-dev`, `frontend-dev` al final. Back/front paralelizan si son archivos disjuntos. Un plan con lote consumidor antes del `db-complejo` se devuelve al architect.

**Modo multi-PR** (solo si el architect lo justificó): cada grupo de lotes corre sobre branch + PR propio — branch desde dev, lotes del grupo (último `last_batch=true`), Fase 2.5 → 2.6 → 2.7 → 2.8 → 3 → 5, y al siguiente grupo.

**Si un dev reporta `BUDGET LIMIT`**: lee `.planning/HANDOFF.md`, reinvócalo con solo las tareas restantes, y abre un issue si el patrón se repite.

**Si un dev reporta error de build/CI que no resuelve**: reinvócalo con `rulebooks/build-errors.md`, en el mismo branch.

### Fase 2.5: Documentación (pre-push)

Cuando el último lote reporta completado, corre `git diff --stat <base>...HEAD`. Si el diff solo toca tests, `.planning/` o código interno, salta `docs` y lo registra en el body del PR — excepto cambios en hooks, permisos, auth o controles de seguridad, que siempre invocan `docs`. En cualquier otro caso, invoca `docs` con branch, base y la instrucción de leer el diff local. `docs` genera/actualiza y **commitea sin pushear** — viaja en el push inicial (evita un run de CI solo por documentación). Si reporta "sin cambios necesarios", avanza directo a Fase 2.6.

### Fase 2.6: Review dual local (pre-push)

El review dual ocurre **ANTES del push inicial**: `security-reviewer` + `qa-*` revisan el diff local y las rondas de fixes suceden sin pushear nada. El PR nace revisado y el caso normal cuesta un solo run de CI. `<base>` = branch base del PR futuro (normalmente `dev`).

1. Clasifica el diff local por capa (`git diff --name-only <base>...HEAD` + "Clasificación del diff por capa") y presupuesta el review proporcional (`git diff --shortstat`, misma tabla que la skill `review-pr` paso 3)
2. Lanza en paralelo: `security-reviewer` siempre, `qa-frontend`/`qa-backend` según la capa (single message, multiple Agent calls). Paquete de contexto: base + branch + diff + lista de archivos + `BRIEF.md` + `DESIGN.md` + presupuesto + formato de salida — sin número de PR, no existe todavía. Si el diff introduce una regla nueva, dilo (el reviewer la aplica al propio diff). Si corre suites desde un worktree, que use su propia base de test
3. **Consolida y registra**: el orchestrator es el único escritor del registro — ningún reviewer lo toca (tienen `Write`/`Edit` prohibidos). Consolidas los reportes **después de que vuelvan todos**, con el "Formato de reporte de review", guardado local (sin commit) en `.planning/reviews/<feature-slug>.md`
4. **Mientras haya un reviewer corriendo, el árbol no se mueve.** Espera a que vuelvan todos antes de aplicar nada. Vale igual para un dev en paralelo: si un lote y un review tocan los mismos archivos, no van juntos
5. **Si hay bloqueantes**: fixes por el dev correspondiente, sin push (schema/migración va a `backend-dev` con `rulebooks/db-migrations.md`). Re-lanza solo los reviewers que marcaron issues, acotados al delta local. Sugerencias baratas: aplicadas antes del push (skill `pr-workflow`, §2)
6. **Veredictos limpios**: `phases.review = done` y `review_sha` al SHA de HEAD, avanza a Fase 2.7. Fixes, sugerencias y registro viajan en el push inicial: **el PR nace revisado**

### Fase 2.7: Push + PR

Lo haces tú:

```bash
git push -u origin <branch>
gh pr create --base dev --title "<título>" --body "<resumen de lotes + decisiones>"   # body incluye veredictos del review pre-push
```

Actualiza `.planning/state.json` con `pr = N` (local, sin commit). El body del PR sale de `.planning/` (BRIEF/DESIGN), los reportes de los devs y el registro del review pre-push: qué se implementó, decisiones ambiguas, veredictos, y `## Self-reflection — pendientes` si algún dev la reportó.

### Fase 2.8: Monitoreo de CI

```bash
gh pr view <number> --json mergeable,mergeStateStatus
gh pr checks <number> --watch --fail-fast
```

**El chequeo de `mergeable` va primero y no es opcional.** GitHub no crea ninguna corrida en un PR con conflictos, así que un `--watch` esperaría algo que nunca llega — se lee igual que "CI encolado". `CONFLICTING`/`DIRTY` → resolver el conflicto (nunca `--force`). `UNKNOWN` → reintentar, no es verde.

Si falla algún check: lee logs (`gh run view <run-id> --log-failed`), asigna el fix (build/lint → dev del PR; DB → `backend-dev` con `rulebooks/db-migrations.md`), corrige en el mismo branch y **reproduce el check fallido localmente antes de pushear**. Si el fix cambia código ya revisado, anótalo para el re-review de Fase 3. **Máximo 3 intentos**: si un fix introduce una regresión nueva, ese intento no cuenta; si el mismo error persiste tras 3 ciclos genuinos, escalas al usuario.

**Cuándo NO monitorear CI**: sin GitHub Actions, o el usuario lo pide.

### Fase 3: Post-PR (re-reviews condicionales, E2E)

El review dual ya ocurrió en Fase 2.6: **el PR nació revisado**. Esta fase cubre solo lo que requiere el PR abierto:

1. **Re-review condicional**: solo si la Fase 2.8 obligó fixes sobre código ya revisado. Acotado al delta, re-lanzando solo los reviewers de la capa afectada (skill `pr-workflow`, §2). Append al registro local. Si CI pasó a la primera, no-op
2. **Si el PR es a `main`**: invoca `e2e-runner` Modo B antes de la verificación pre-merge (ver "Pre-release E2E"); opcionalmente `code-sweep` modo `bugs` sobre el diff
3. Sin nada pendiente, avanza a **Fase 5**

**PRs fuera del flujo** (sin review pre-push, señalado por `post-pr-create`): skill `review-pr`.

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

**Es `db-complejo`:** backfill de datos, cambio de tipo de columna con datos existentes, particionamiento/sharding, migración de datos entre tablas, expand-contract zero-downtime, optimización de queries lentas (EXPLAIN, índices compuestos), constraints nuevos sobre datos existentes (`NOT NULL` con NULLs), migraciones que afecten >1M de filas, schema con relaciones complejas o requisitos de performance específicos.

**No es `db-complejo`** (lote simple): tabla nueva sin datos previos, columna nullable o con default, índice nuevo, renombrar columna sin uso en producción, foreign key, seeds/fixtures de desarrollo.

**Regla rápida:** si la migración necesita un script que toque datos, o requiere análisis de performance, es `db-complejo`.

**Cuando la feature tiene un lote `db-complejo`**: recibe su propio lote en el plan del architect, va primero, trabaja sobre el **mismo branch** que los demás lotes, commitea con flag `last_batch=true|false` igual que cualquier lote. Incluye: schema (vía Drizzle/Pydantic/equivalente del proyecto), migraciones, queries optimizadas, tests de DB. Los lotes siguientes (de `backend-dev` o `frontend-dev`) consumen el schema resultante en sus endpoints, sin modificarlo.

---

## Template del prompt de handoff a devs

Cada subagente recibe un paquete de contexto armado por ti, **no el historial completo ni tareas de otros lotes**: `architect` recibe `BRIEF.md` completo; `backend-dev`/`frontend-dev` reciben solo las tareas y la sección de `DESIGN.md` de su lote + path al schema/contratos + branch + `last_batch` + `rules/<lenguaje>.md` (y en `db-complejo`, además schema actual + `rulebooks/db-migrations.md`); si no es el primer lote, instrucción de leer `git log`/`STATE.md`/`state.json`; `security-reviewer`/`qa-*` reciben la fuente del diff (local o `gh pr diff`, según la fase) + `DESIGN.md` + `BRIEF.md`.

Aplica para `backend-dev`, `frontend-dev`. El formato del prompt:

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

Si trabajas o corres suites desde un worktree: exporta tu propia base de test (`TEST_DATABASE_URL` o el equivalente del proyecto, ej. `<base>_<lote>`) para no pisar la corrida del árbol principal ni bloquear el hook de pre-commit de otro agente.

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
- `phases` tiene **claves fijas** — siempre las 9 de arriba, `skipped` para las que no aplican (p. ej. `e2e` sin UI).
- `batches` refleja el plan del architect: `id`/`name`/`agent` los siembra el orchestrator; `status`/`tasks_done`/`current_task` mutan durante la ejecución.
- **Orden de transiciones**: `review` pasa a `done` antes que `pr`/`ci` — el review dual ocurre pre-push. `review_sha` ancla el checkpoint de `post-pr-create.sh`.

**Quién escribe qué:** archivo completo y `phases.*` los escribe el orchestrator en cada transición de fase (`phases.review`/`review_sha` en Fase 2.6, al cerrar veredictos limpios; `pr` en Fase 2.7; `phases.merge` en Fase 5, post-merge) — todo local, sin commit (`.planning/` no se versiona). `batches[].tasks_done`/`current_task` de su batch los escribe el dev que ejecuta el lote, antes de cada tarea atómica. `updated` lo toca quien haga la escritura.

**`STATE.md`** se actualiza al tomar una decisión (`[D-NN]`), al encontrar/resolver un blocker, o al pausar/retomar.

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

Cuando `session-start-context.sh` detecta `HANDOFF.md` (ver "Pause / Resume" en la skill `orchestrator`): lee `HANDOFF.md` + `STATE.md` + `state.json` (corte, decisiones, fase/lote activos); corre el smoke test del proyecto ANTES de tocar código (misma detección de runner que `hooks/pre-commit-guard.sh` — Node por lockfile; Python: uv (solo con `uv.lock`) → `.venv` → `pytest` del PATH, salvo que el proyecto declare entorno propio sin runner (`uv.lock` sin `uv`, `[tool.uv]` sin lock, `.venv` sin pytest); sin runner, anótalo y sigue — pero el hook sí bloqueará el commit de un directorio con marcador Python sin runner (con la razón específica si declara entorno propio) o con un `package.json` ilegible y sin marcador Python, así que resuélvelo antes de retomar; rojo, diagnostica antes de retomar); recién con el estado confirmado, elimina `HANDOFF.md` y retoma la tarea de `current_task`.

---

## Clasificación del diff por capa

**Frontend**: extensiones `.tsx`, `.jsx`, `.vue`, `.svelte`, `.html`, `.htm`, `.css`, `.scss`, `.sass`, `.less`; o `.ts`/`.js` bajo `components/`, `pages/`, `app/`, `views/`, `src/ui/`, `apps/frontend/`, `apps/web/`, `frontend/`, `client/`, `web/`, `public/`, `hooks/`, `stores/`.

**Backend**: extensiones `.py`, `.go`, `.rs`, `.cs`, `.sql`, `.sh`/`.bash` (contra `rules/bash.md`); o `.ts`/`.js` bajo `api/`, `apps/backend/`, `apps/api/`, `backend/`, `server/`, `services/`, `controllers/`, `routes/`, `handlers/`, `models/`, `lib/`, `db/`, `migrations/`, `workers/`, `jobs/`.

**Documentos normativos del sistema de agentes**: un diff que toca `rules/`, `rulebooks/`, `agents/`, `skills/` (incluida `skills/orchestrator/SKILL.md`) o `global/CLAUDE.md` va a **`qa-backend`**, con criterio de coherencia normativa en vez de capas de aplicación. Sin esta entrada, un diff 100% de metodología no matchea ninguna capa. `README.md` y el `CLAUDE.md` raíz de un proyecto no entran acá (son meta-documentación) — excepto en este mismo repo, donde ambos describen cómo se edita el sistema y sí van a `qa-backend`.

**Diff mixto**: archivos de ambas capas → lanzar ambos QAs en paralelo. Archivos bajo `db/`, `migrations/`, `schema/` los revisa `qa-backend` (no hay `qa-db` separado).

---

## Comandos `gh` específicos

### Monitoreo de CI

```bash
# mergeable SIEMPRE primero: un PR en conflicto no genera corridas, y el
# watch de abajo esperaría indefinidamente algo que nunca va a existir
gh pr view <number> --json mergeable,mergeStateStatus
# CONFLICTING/DIRTY → resolver antes de esperar checks. UNKNOWN → reintentar, no es verde

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
# Si > 0, resolver o responder antes de mergear

# 2. Reviews bloqueantes
gh pr view <number> --json reviewDecision --jq '.reviewDecision'
# "APPROVED" o vacío. "CHANGES_REQUESTED" → NO mergear

# 3. CI checks — mergeable primero, mismo motivo que arriba
gh pr view <number> --json mergeable,mergeStateStatus
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

**Solo aplica para PRs a `main` (release).** Para PRs a `dev`, el usuario invoca a `e2e-runner` aparte (Modo A) — no es tu scope.

Antes de la verificación pre-merge: `docker compose up -d && docker compose ps`, verifica `healthy` en todos los servicios (si alguno falla, escala al dev antes de lanzar E2E). Invoca `e2e-runner` Modo B con branch del PR, lista de archivos del diff (`gh pr view <PR> --json files --jq '.files[].path'`) y URL base del frontend. El agente trabaja directo sobre el branch: crea tests si faltan, corre los existentes, commitea y pushea. Si fallan → **BLOQUEANTE**, asigna el fix al dev correspondiente y el `e2e-runner` re-ejecuta. **Máximo 3 ciclos**; si sigue fallando, escala al usuario.

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
