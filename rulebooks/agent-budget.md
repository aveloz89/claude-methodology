# Agent Budget

Cada invocación de un agente tiene un techo finito: la ventana de contexto y el corte de la invocación cuando se agota. El control real de alcance es el cap de 5 tareas por lote (regla 1); ningún agente define `maxTurns` porque cortaría a mitad de un ciclo TDD sin reporte ni trazabilidad.

## Reglas

### 1. El architect define los lotes, el orchestrator los sigue

**Hard cap: máximo 5 tareas atómicas por lote** (una invocación de un dev). El cap aplica al budget de un agente, **no al tamaño del PR ni de la feature** — un PR puede contener varios lotes secuenciales sobre el mismo branch (single-PR, default). El architect entrega el plan ya partido en lotes ≤5 tareas, con lo crítico primero; si un lote excede el cap, el orchestrator devuelve el plan — **no improvisa la partición**.

### 2. Commit por tarea, no commit al final

```
RED → GREEN → REFACTOR → COMMIT → siguiente tarea
```

Si la invocación se corta a mitad, los commits anteriores ya están en el branch local; cero pérdida del trabajo previo. Lint, build y self-review ocurren al cierre de la invocación, después de todos los commits per-tarea. El dev no pushea ni abre PR — el orchestrator invoca `docs`, corre el review dual local y recién ahí hace push + PR (`rulebooks/orchestrator-runbook.md`, Fases 2.5–2.7).

### 3. `state.json` actualizado entre tareas

El dev actualiza `.planning/state.json` (`tasks_done` y `current_task` de **su** batch) *antes* de empezar cada tarea, para que una invocación cortada sepa dónde retomar. `STATE.md` queda para prosa (decisiones, blockers) — no lo toca el dev entre tareas.

### 4. Definition of done con fallback de budget

> **Done = todos los commits per-tarea hechos (locales, sin push) + reporte estructurado entregado.**
>
> **Si sientes que se acaba el budget antes de terminar:**
> 1. Parar de implementar nuevas tareas
> 2. Si hay código a medio escribir, commitearlo con prefijo `wip:`
> 3. Escribir `.planning/HANDOFF.md` con: tarea en curso, qué falta, decisiones tomadas
> 4. **Push del branch** — la única excepción a "el dev no pushea" que no es un fix de CI (inventario completo en `dev-common.md`): sin push, el HANDOFF y los commits parciales viven solo en el working tree local
> 5. Reportar: `BUDGET LIMIT — N de M tareas completadas, ver HANDOFF.md`

El fallback es frágil (requiere que el agente monitoree su propio progreso) pero garantiza salida ordenada en vez de corte abrupto.

## Relación con otros rulebooks

- **`rules/implementation-principles.md`** → trata del *qué* implementar (scope mínimo, sin abstracciones especulativas)
- **`agent-budget.md` (este)** → trata del *cómo invocar* (cuántas tareas por agente, cuándo commitear)
- **`dev-common.md`** → el procedimiento concreto que ejecuta el dev cuando se le acaba el budget, junto con gitflow y correcciones post-review
- **`governance-playbook.md` #10** → qué hacer cuando el corte ya ocurrió y no se aplicó el fallback
