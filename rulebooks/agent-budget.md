# Agent Budget

Cada invocación de un agente tiene un techo finito de tokens/iteraciones (`maxTurns`). Cuando se acerca al límite, el agente se corta — y si lo hace en un mal momento, deja código sin commitear, sin reporte, y sin trazabilidad.

Este rulebook codifica las reglas que orchestrator y devs aplican para que el trabajo sobreviva al corte.

## Diagnóstico del fallo

Síntomas típicos:
- El dev escribió todo el código pero nada quedó commiteado (todo perdido)
- El último mensaje del agente parece cortado a mitad de oración (no es el reporte estructurado que se pidió)
- Las tareas críticas que estaban al final del prompt nunca se ejecutaron

Causa raíz: la invocación no podía caber el trabajo completo, pero nadie redujo el alcance antes de delegar.

## Reglas

### 1. El architect define los lotes, el orchestrator los sigue

**Hard cap: máximo 5 tareas atómicas por lote.** Un *lote* es una invocación de un dev. El cap aplica al budget de un agente, **no al tamaño del PR ni de la feature**.

**Lote ≠ PR.** Un PR puede contener varios lotes ejecutados secuencialmente sobre el mismo branch (modo single-PR, default). Sub-PRs separados solo cuando el architect lo justifique (modo multi-PR — slices independientes y shippeables solos).

**Quién hace qué:**
- **Architect:** entrega un Plan de implementación con lotes explícitos (≤5 tareas cada uno) y declara la estrategia de PR (single-PR default, multi-PR solo con justificación). Si el trabajo total excede el cap de un solo lote, lo parte en múltiples lotes secuenciales siguiendo seams naturales. Lo crítico va en el primer lote. Ver `agents/architect.md` sección "Plan de implementación".
- **Orchestrator:** valida que cada lote ≤5 tareas y que la estrategia de PR está declarada. Si un lote excede el cap, devuelve el plan al architect — **no improvisa la partición**. Sigue el plan literalmente: en single-PR, invoca devs lote por lote sobre el mismo branch y crea un único PR al final; en multi-PR, un branch + PR por grupo.

**Ejemplos:**
- Feature con 28 tareas backend secuencialmente dependientes → architect entrega 6 lotes de ≤5 tareas en estrategia **single-PR**. El orchestrator invoca al backend-dev 6 veces sobre el mismo branch (commits per-tarea acumulándose), review local + push + PR + CI **una sola vez**.
- Feature con 2 servicios independientes (cada uno ~10 tareas backend, sin overlap de archivos, shippeables solos) → architect podría justificar **multi-PR** (2 PRs paralelos), pero también es válido un único PR con 4 lotes. El default sigue siendo single-PR salvo justificación.
- 5 tareas + 2 "extras" agregados después por el usuario → no son extras, vuelven al architect como input para un nuevo lote (o ajuste del plan).

**Anti-patrones:**
- Architect entrega un plan plano de 28 tareas sin partir en lotes → el orchestrator debe rechazarlo
- Orchestrator improvisa lotes cuando el plan excede el cap → rompe coherencia lógica
- Orchestrator parte en sub-PRs por defecto en vez de single-PR → multiplica innecesariamente el costo de CI/review
- Dumpear todas las tareas en un único prompt al dev → corte garantizado a mitad

### 2. Commit por tarea, no commit al final

Cada ciclo TDD termina en commit local. La secuencia es:

```
RED → GREEN → REFACTOR → COMMIT → siguiente tarea
```

**Razón:** si la invocación se corta a mitad, los commits anteriores ya están en el branch local. Cero pérdida del trabajo previo.

**Anti-patrón:** "implementa las 5 tareas y al final commitea todo." Si se corta en la tarea 4, las tareas 1-3 también se pierden porque nunca se commitearon.

Lint, build y self-review ocurren al cierre de la invocación, después de todos los commits per-tarea. Si self-review encuentra violaciones, se corrigen en commits adicionales.

**El dev no pushea ni abre PR.** Al terminar el último lote, el orchestrator invoca `docs` sobre el diff local, corre el review dual local y recién ahí hace push + PR. Ver `rulebooks/orchestrator-runbook.md`, Fases 2.5–2.7.

### 3. state.json actualizado entre tareas

El dev actualiza `.planning/state.json` (`tasks_done` y `current_task` de **su** batch) *antes* de empezar cada tarea. Si la invocación se corta a mitad, la próxima sabe exactamente dónde quedó. `STATE.md` queda para prosa (decisiones, blockers) — no lo toca el dev entre tareas. Detalle del schema y del reparto en `rulebooks/orchestrator-runbook.md`, sección "STATE.md + state.json".

### 4. Definition of done con fallback de budget

Cada invocación tiene un DoD explícito:

> **Done = todos los commits per-tarea hechos (locales, sin push) + reporte estructurado entregado.**
>
> **Si sientes que se acaba el budget antes de terminar:**
> 1. Parar de implementar nuevas tareas
> 2. Si hay código a medio escribir, commitearlo con prefijo `wip:`
> 3. Escribir `.planning/HANDOFF.md` con: tarea en curso, qué falta, decisiones tomadas
> 4. **Push del branch** — es la única situación en que el dev pushea. Sin push, el HANDOFF y los commits parciales viven solo en el working tree local y una invocación nueva no los ve
> 5. Reportar al orchestrator: `BUDGET LIMIT — N de M tareas completadas, ver HANDOFF.md`

El paso 4 es la excepción explícita a "el dev no pushea": el costo de un run de CI extra es menor que el de perder el trabajo del lote.

El fallback es frágil (requiere que el agente monitoree su propio progreso) pero garantiza salida ordenada en vez de corte abrupto.

## Cómo se valida

- **Orchestrator:** antes de invocar a un dev, cuenta tareas y parte si excede el cap. Si recibe `BUDGET LIMIT`, retoma el trabajo en una nueva invocación leyendo HANDOFF.md
- **Devs:** commit por tarea, no al final; aplicar el fallback si el budget se acaba
- **QA agents:** un PR con un único commit gigante cubriendo múltiples tareas atómicas es señal del anti-patrón de commit-al-final — márquenlo
- **Cómo medir invocaciones reales** (lotes ejecutados, devs involucrados): ver "Cómo se mide" abajo — el log de `SubagentStop` es la fuente de datos para la retro de Fase 4.

## Cómo se mide

Cada invocación de un subagente que termina dispara el hook `hooks/subagent-stop-log.sh` (evento `SubagentStop`), que appendea una línea JSONL a un log global — no scoped a un repo ni a una feature, así que sirve para medir el budget en cualquier proyecto donde se use la metodología.

- **Ubicación:** `~/.claude/methodology/logs/subagent-invocations.jsonl` (rota a `subagent-invocations.jsonl.old` al superar ~1MB, pisando el `.old` anterior — techo duro de ~2MB totales).
- **Schema por línea:**

```json
{"ts":"2026-08-13T18:30:00Z","agent":"backend-dev","session":"abc-123","repo":"/Users/alas/Proyectos/miapp","branch":"feature/x","transcript":"/path/al/transcript.jsonl"}
```

| Campo | Contenido | Puede ser `null` |
|---|---|---|
| `ts` | Timestamp UTC ISO-8601 del cierre del subagente | no |
| `agent` | Tipo de agente invocado (`backend-dev`, `qa-backend`, etc.) | no — fallback `"unknown"` |
| `session` | ID de sesión del harness | sí |
| `repo` | Toplevel del repo git donde corrió el subagente | sí (si no había repo git) |
| `branch` | Branch activo al momento de la invocación | sí |
| `transcript` | Path al transcript del subagente (útil para post-mortem de cortes `BUDGET LIMIT`) | sí |

- **Query de ejemplo** (invocaciones por agente en el repo actual, para llenar las métricas de `LEARNINGS.md` en la retro de Fase 4):

```bash
jq -s '[.[] | select(.repo == "'"$(git rev-parse --show-toplevel)"'")] | group_by(.agent) | map({agent: .[0].agent, invocaciones: length})' ~/.claude/methodology/logs/subagent-invocations.jsonl
```

## Relación con otros rulebooks

- **`rules/implementation-principles.md`** → trata del *qué* implementar (scope mínimo, sin abstracciones especulativas)
- **`agent-budget.md` (este)** → trata del *cómo invocar* (cuántas tareas por agente, cuándo commitear)
- **`dev-common.md`** → el procedimiento concreto que ejecuta el dev cuando se le acaba el budget, junto con gitflow y correcciones post-review
- **`governance-playbook.md` #9** → trata de qué hacer cuando el contexto del *usuario* (no del agente) se agota
