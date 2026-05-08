# Orchestrator Runbook

Detalles operativos del agente `orchestrator`: formatos de archivos persistentes, comandos específicos, criterios de clasificación, reportes. El agente lo lee bajo demanda, no en cada invocación.

El comportamiento del orchestrator (qué fases ejecutar, cuándo invocar a qué agente, reglas duras) vive en `.claude/agents/orchestrator.md`. Este documento es el complemento práctico.

## Estructura de `.planning/`

```
.planning/
├── STATE.md          # Estado actual: fase, progreso, decisiones, blockers
├── BRIEF.md          # Brief del brainstorming (lo que recibe el architect)
├── DESIGN.md         # Diseño del architect
├── ARCHITECTURE.md   # Decisiones recurrentes del architect (persistente entre features)
├── HANDOFF.md        # Solo existe si hay trabajo pausado
├── LEARNINGS.md      # Retrospectivas post-merge (acumulativo)
└── reviews/
    └── PR-{N}.md     # Reportes de review por PR
```

## Formato: `BRIEF.md`

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

## Formato: `STATE.md`

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

## Formato: `HANDOFF.md`

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

## Formato: `LEARNINGS.md` (acumulativo)

**Prepend** una entrada por cada merge exitoso (más reciente arriba):

```markdown
### [YYYY-MM-DD] PR #N — Título del PR

**Métricas:**
- Review rounds: N
- Hallazgos security: N (critical: N, high: N, medium: N, low: N)
- Hallazgos qa-frontend: N (stubs: N, coverage: N, edge cases: N, otros: N)
- Hallazgos qa-backend: N (stubs: N, coverage: N, edge cases: N, otros: N)
- Errores de build/CI: N
- Self-reflection atrapó: N (cosas que detectó antes del review, o "nada")
- Lotes ejecutados: N / Tareas: M
- Devs involucrados: [db-specialist? backend-dev? frontend-dev?]

**Qué salió bien:**
- [descripción]

**Qué causó re-work:**
- [descripción — y si era prevenible]

**Patrón potencial:** [sí/no — si sí, cuál y cuántas veces se ha visto]
```

**Regla de 3**: si un mismo patrón aparece en 3+ entradas, sugerir al usuario:

- Agregar regla en `rules/` (si es idiomático/calidad)
- Modificar prompt de un agente (si es de proceso)
- Crear hook nuevo (si es bloqueable automáticamente)

## Clasificación del diff por capa (para QA en Fase 3)

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

## Comandos: monitoreo de CI

```bash
# Esperar a que terminen los checks (modo watch, falla rápido)
gh pr checks <number> --watch --fail-fast

# Si algún check falló, obtener run ID y logs
gh run list --branch <branch> --limit 1 --json databaseId,conclusion
gh run view <run-id> --log-failed
```

## Comandos: verificación pre-merge (OBLIGATORIO antes de cada merge)

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

Solo si las 3 pasan:

```bash
gh pr merge <number> --merge --delete-branch
```

## Hotfix → integrar a dev después del merge

Después de mergear un hotfix a main:

```bash
git checkout dev && git pull origin dev
git merge origin/main --no-ff
git push origin dev
```

## Formato: reporte de review

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

## Detalle: Fase 0.5 (design system con `ui-ux`)

Cuando la tarea tiene componente visual:

1. **Invocá `ui-ux`** con context isolation. Pasale SOLO:
   - El brief del brainstorming (`.planning/BRIEF.md` o pasaje relevante)
   - Nombre del proyecto
   - Path al `design-system/` del proyecto si ya existe (para extender en lugar de reescribir)
   - **NO le pases historial de conversación ni diseños técnicos previos**

2. **`ui-ux` genera o extiende:**
   - `design-system/<NombreProyecto>/MASTER.md` (estilo UI, paleta, tipografía, espaciado, componentes core, anti-patterns, checklist)
   - `design-system/<NombreProyecto>/pages/<page>.md` para páginas críticas (landing, onboarding, dashboard, checkout)

3. Si `ui-ux` te pide tono/audiencia/industria/referencias que faltan en el brief, preguntale al usuario y reenviá la respuesta al agente

4. Recibí el reporte del `ui-ux` y copiá el bloque "Para incluir en el brief al architect" a la sección `### Design System` del `BRIEF.md` antes de invocar al architect

**Cuándo NO invocar `ui-ux`:**

- La tarea no tiene componente visual (solo backend, DB, CLI, internal API)
- El cambio respeta el design system existente sin nuevos componentes ni páginas críticas
- El usuario ya proporcionó un design system completo o guía visual específica

## Detalle: Fase 2.5 (E2E)

Antes de invocar `e2e-runner`:

```bash
docker compose up -d
docker compose ps
```

Verificá que todos los servicios estén `healthy`. Si alguno falla, escalá al dev correspondiente antes de lanzar E2E.

Después:

1. **Invocá `e2e-runner`** con:
   - Flujos de usuario descritos en `DESIGN.md`
   - Branch donde está el código
   - URL base del frontend en Docker (ej: `http://localhost:3000`)
2. El `e2e-runner` crea tests de Playwright para los flujos críticos y los ejecuta
3. Si los tests fallan, asigná el fix al dev correspondiente (front, back o db según dónde falle el flow)
4. El `e2e-runner` re-ejecuta hasta que pasen
5. **Máximo 3 ciclos de fix-rerun.** Si después de 3 sigue fallando, escalá al usuario

**Cuándo NO ejecutar E2E:**

- La feature no tiene componente visual
- Cambio pequeño cubierto por unit/integration tests
- Usuario explícitamente lo pide

## Detalle: orden de lotes cuando hay db-specialist

Cuando una feature involucra trabajo de DB complejo, el orden esperado en el plan del architect es:

1. **db-specialist primero** (siempre): schema, migraciones, queries, tests de DB
2. **backend-dev después**: consume el schema en endpoints
3. **frontend-dev al final** (o en paralelo con backend si trabajan archivos disjuntos)

Esto porque backend-dev necesita el schema disponible para importar tipos. Si el architect entrega un plan que tiene backend-dev antes del db-specialist en una feature con DB compleja, **devolverlo al architect** — es probable que esté mal particionado.

Excepción: si los lotes son genuinamente independientes (db-specialist trabaja en una tabla X que backend-dev no toca, y backend-dev trabaja sobre tablas existentes que no cambian), pueden ir en paralelo.

## Detalle: handoff a dev (template del prompt)

Aplica para `db-specialist`, `backend-dev`, `frontend-dev`. El handoff es el mismo formato:

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
- rules/<lenguaje>.md
- rules/docker.md (si aplica)

Si no es el primer lote: leé `git log` y `.planning/STATE.md` antes de empezar.

Si last_batch=false: NO push, NO PR. Reportá completado.
Si last_batch=true: después de la última tarea, push + crear PR.
```

## Errores comunes y cómo manejarlos

| Situación | Acción |
|-----------|--------|
| Architect entrega plan con lote >5 | Devolver con mensaje específico (ver agent prompt). Max 3 retries, después escalar |
| Architect entrega plan con backend-dev antes que db-specialist en feature con DB compleja | Devolver al architect: "el orden es incorrecto, db-specialist va primero porque backend-dev consume el schema" |
| Dev (cualquiera) reporta `BUDGET LIMIT` | Leer `HANDOFF.md`, reinvocar al mismo dev con tareas restantes, anotar en `LEARNINGS.md` |
| Dev reporta error de build/CI | `build-resolver` con error completo + branch + archivos. Max 3 fixes automáticos |
| Reviewer reporta bloqueante | Asignar fix al dev del lote correspondiente en mismo branch. Re-lanzar solo el reviewer que reportó. Repetir hasta aprobación |
| `gh pr merge` falla | Verificar las 3 condiciones de pre-merge. Reportar cuál bloquea |
| Healthcheck Docker falla en Fase 2.5 | Escalar al dev del servicio fallando antes de continuar con E2E |
| Hotfix mergeado pero falló integración a dev | Conflicto manual. Escalar al usuario con detalles del conflicto |
| Migración del db-specialist falla en CI | Asignar fix al db-specialist (no a backend-dev) — es su scope |
| Backend-dev intenta crear migración compleja (no simple) | Devolver: "esto califica como complejo según criterios del orchestrator. Escalar al architect para que reasigne al db-specialist" |
