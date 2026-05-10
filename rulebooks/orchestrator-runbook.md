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
10. [Errores comunes y cómo manejarlos](#errores-comunes-y-cómo-manejarlos)
11. [Flujo: revisar PR existente sin pasar por el flow completo](#flujo-revisar-pr-existente-sin-pasar-por-el-flow-completo)

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
4. Cuando creas tener claridad, presenta resumen y pregunta explícitamente: **"¿Estamos listos para pasar al diseño o hay algo más que quieras definir?"**
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
2. **El último lote** se invoca con flag **`last_batch=true`**: el dev hace push y crea el PR
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
3. Cuando se cree el PR → Fase 2.8 → 2.9 → Fase 3 → merge
4. Pasar al siguiente grupo

#### Si un dev reporta `BUDGET LIMIT — ver HANDOFF.md`

El plan del architect debió evitar esto. Si pasa:

1. Lee `.planning/HANDOFF.md`
2. Reinvoca al mismo dev con SOLO las tareas restantes
3. Documenta el corte en `.planning/LEARNINGS.md` para que el architect ajuste sus particiones futuras

#### Si un dev reporta error de build/compilación que no puede resolver

Invoca `build-resolver` con: error completo, branch, archivos afectados. Resuelve en el mismo branch y reporta qué hizo.

### Fase 2.8: Monitoreo de CI

Después de que se crea el PR:

```bash
gh pr checks <number> --watch --fail-fast
```

- Si todos pasan → Fase 2.9
- Si falla algún check:
  - Lee logs: `gh run view <run-id> --log-failed`
  - Asigna el fix:
    - Build/compilación/dependencias → `build-resolver`
    - Tests o lint → dev que creó el PR
    - Tests de DB que fallan por schema/migración → `db-specialist`
  - El agente corrige en el **mismo branch del PR**
  - Vuelve a monitorear
- **Máximo 3 intentos de fix automático.** Después de 3, escala al usuario con contexto completo

**Cuándo NO monitorear CI**: el proyecto no tiene GitHub Actions, o el usuario lo pide explícitamente.

### Fase 2.9: Documentación

Después de CI verde, invoca `docs` con número de PR y branch. El `docs` lee el diff (`gh pr diff <number>`), genera/actualiza docs, commitea al mismo branch.

Si reporta "sin cambios necesarios", avanza directo a Fase 3.

### Fase 3: Revisión

1. Lee el diff completo: `gh pr diff <number>`
2. **Clasifica el diff por capa** (criterios completos en sección "Clasificación del diff por capa" más abajo)
3. **Lanza en paralelo** (context isolation: solo PR number, branch, diff, archivos):
   - `security-reviewer` — siempre
   - `qa-frontend` — solo si el PR tiene frontend
   - `qa-backend` — solo si el PR tiene backend (incluye revisar migraciones y queries del db-specialist)
4. Consolida hallazgos
5. Si hay bloqueantes:
   - Asigna fixes al dev correspondiente (mismo branch del PR). Si el bloqueante es de schema/migración/query optimizada, va al `db-specialist`
   - Re-lanza **solo los reviewers que marcaron issues** (no los que aprobaron)
   - Repite hasta que todos aprueben
6. **Si el PR es a `main` (release)**: invoca `e2e-runner` en Modo B antes de la verificación pre-merge (ver sección "Pre-release E2E" más abajo)
7. Cuando todos aprueben (incluyendo `e2e-runner` si era PR a main), ejecuta la **verificación pre-merge** (3 comandos `gh` en sección "Comandos `gh` específicos")
8. Solo si las verificaciones pasan, mergea con el comando apropiado según el tipo de branch:
   - `feature/*` o `hotfix/*` → `gh pr merge <number> --merge --delete-branch`
   - `dev → main` (release) → `gh pr merge <number> --merge` **sin `--delete-branch`** (`dev` es persistente, ver Gitflow en `CLAUDE.md`)
9. Si era hotfix (PR a main), después del merge integra a dev (procedimiento más abajo)
10. Actualiza `.planning/STATE.md` con resultado

### Fase 4: Learn (post-merge)

Después de cada merge exitoso, retrospectiva breve:

1. Recolecta métricas: rounds de review, hallazgos por reviewer, errores de build, si self-reflection atrapó algo antes
2. Identifica aprendizajes: qué salió bien, qué causó re-work
3. Prepend a `.planning/LEARNINGS.md` — más reciente arriba (formato más abajo)
4. **Regla de 3**: si un patrón aparece en 3+ entradas de LEARNINGS, sugiere al usuario agregar regla en `rules/` o modificar un agente

**Cuándo saltar Learn**: hotfixes urgentes (retro después), tareas triviales (typos, bumps de dependencias).

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
- `security-reviewer` / `qa-*` reciben: diff completo del PR + `DESIGN.md` + `BRIEF.md` (necesitan saber qué se quería para juzgar si el código lo cumple).
- `db-specialist` recibe: `DESIGN.md` (sección de datos) + schema actual.

**Quien construye el paquete eres tú**, no el agente que va a recibirlo.

**Por cada invocación de dev**, el handoff debe incluir:

- **Solo las tareas de su lote** (no el plan completo)
- **Path al schema/contratos** que ya escribió el architect (o el db-specialist si aplica)
- **Sección de DESIGN.md** correspondiente al lote (no DESIGN completo)
- **Branch en el que trabajar** (sin `git checkout` desde cero)
- **Flag `last_batch=true|false`** explícito
- **Si no es el primer lote**: instrucción de leer `git log` y `.planning/STATE.md` para entender qué hay
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

Si no es el primer lote: lee `git log` y `.planning/STATE.md` antes de empezar.

Si last_batch=false: NO push, NO PR. Reporta completado.
Si last_batch=true: después de la última tarea, push + crear PR.
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

### Design System (si aplica)
[Output del agente ui-ux: estilo, paleta, tipografía, anti-patterns, page specs]
[Si no se generó, omitir esta sección]
```

### `STATE.md`

```markdown
## Estado actual

- **Feature:** [nombre]
- **Fase:** [brainstorming | diseño | implementación | review | completado]
- **Branch:** [nombre del branch activo]
- **PR:** [número si existe]
- **Última actualización:** [timestamp]

## Progreso
- [x] Brainstorming completado
- [x] Diseño aprobado
- [ ] DB implementada (si aplica db-specialist)
- [ ] Backend implementado
- [ ] Frontend implementado
- [ ] PR creado
- [ ] CI verde
- [ ] Documentación actualizada
- [ ] Review aprobado
- [ ] Mergeado

## Decisiones
- [D-01] [decisión tomada durante brainstorming/diseño]
- [D-02] ...

## Blockers
- [ninguno | descripción del blocker]
```

**Cuándo actualizar:**
- Al completar cada fase
- Al crear un PR
- Al recibir resultados de review
- Al encontrar un blocker
- Al pausar o retomar

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

### `LEARNINGS.md` (acumulativo)

**Prepend** una entrada por cada merge exitoso (más reciente arriba):

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

O archivos `.ts` / `.js` bajo:
- `api/`, `apps/backend/`, `apps/api/`
- `backend/`, `server/`
- `services/`, `controllers/`, `routes/`, `handlers/`
- `models/`, `lib/`, `db/`, `migrations/`
- `workers/`, `jobs/`

### PR mixto

Si tiene archivos de ambas capas → lanzar **ambos QAs en paralelo**.

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
# 1. Comentarios sin resolver
gh api repos/{owner}/{repo}/pulls/<number>/comments \
  --jq '[.[] | select(.in_reply_to_id == null)] | length'
# Si > 0, revisar si están resueltos

# 2. Reviews bloqueantes
gh pr view <number> --json reviewDecision --jq '.reviewDecision'
# Debe ser "APPROVED" o vacío. "CHANGES_REQUESTED" → NO mergear

# 3. CI checks
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

Para `gh pr comment <number> --body "<reporte>"`:

```markdown
## Review: PR #[number] — [title]

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

Guardar copia en `.planning/reviews/PR-<number>.md`.

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
| Architect entrega plan con backend-dev antes que db-specialist en feature con DB compleja | Devolver al architect: "el orden es incorrecto, db-specialist va primero porque backend-dev consume el schema" |
| Dev (cualquiera) reporta `BUDGET LIMIT` | Leer `HANDOFF.md`, reinvocar al mismo dev con tareas restantes, anotar en `LEARNINGS.md` |
| Dev reporta error de build/CI | `build-resolver` con error completo + branch + archivos. Max 3 fixes automáticos |
| Reviewer reporta bloqueante | Asignar fix al dev del lote correspondiente en mismo branch. Re-lanzar solo el reviewer que reportó. Repetir hasta aprobación |
| `gh pr merge` falla | Verificar las 3 condiciones de pre-merge. Reportar cuál bloquea |
| Healthcheck Docker falla antes de E2E pre-release | Escalar al dev del servicio fallando antes de lanzar `e2e-runner` Modo B |
| Hotfix mergeado pero falló integración a dev | Conflicto manual. Escalar al usuario con detalles del conflicto |
| Migración del db-specialist falla en CI | Asignar fix al db-specialist (no a backend-dev) — es su scope |
| Backend-dev intenta crear migración compleja (no simple) | Devolver: "esto califica como complejo según los criterios. Reasignar al db-specialist" |

---

## Flujo: revisar PR existente (sin pasar por el flow completo)

Cuando el usuario pide revisar un PR que no salió de este flujo:

1. `gh pr view <number> --json number,title,body,headRefName,baseRefName,files`
2. `gh pr diff <number>`
3. Clasifica el diff (sección "Clasificación del diff por capa") y lanza los reviewers correspondientes en paralelo
4. Consolida y comenta en el PR: `gh pr comment <number> --body "<reporte>"` (formato en sección "Formato de reporte de review")
