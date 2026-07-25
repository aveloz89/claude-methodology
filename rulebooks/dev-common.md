# Dev Common

Procedimientos idénticos para todos los agentes que escriben código (`backend-dev`, `frontend-dev`, `db-specialist`, `refactor`, `e2e-runner`, `build-resolver`, `docs`). Vivían copiados en cada prompt; ahora viven acá una sola vez.

Cada agente los referencia desde su sección "Reglas heredadas" y agrega solo su delta específico, si tiene.

## Gitflow

Antes de empezar:

1. Verifica el branch actual con `git branch --show-current`
2. **Nunca trabajes en `main` o `dev` directamente**
3. **El orchestrator ya creó el branch** — tú NO creas branch nuevo. Trabajas sobre el `feature/*` o `hotfix/*` que ya existe
4. Si no hay branch (raro, indicaría falla del orchestrator), reporta el error en lugar de crear uno

Formato de commit y reglas de gitflow generales: `CLAUDE.md` raíz.

**Excepción — `refactor` y `e2e-runner` en Modo A** (invocación directa del usuario): ahí sí creas tu propio branch, porque no hay orchestrator que lo haya hecho. Ver el prompt de cada agente.

## Push: quién y cuándo

**No pusheas ni abres PR.** Al cerrar el último lote, el orchestrator invoca `docs` sobre el diff local y recién ahí hace push + PR — un solo push inicial que ya incluye la documentación (presupuesto de CI).

Hay exactamente **dos excepciones**:

1. **Fix de un check de CI fallido** — reproduces el check localmente, lo ves pasar, y pusheas directo al branch del PR.
2. **Budget agotado** — ver abajo.

En rondas de review nunca pusheas: el orchestrator consolida todos los fixes de la ronda en un solo push.

## Correcciones post-review

Cuando el orchestrator o un reviewer te pide corregir algo en un PR existente:

1. **Trabaja en el MISMO branch del PR** — NO crees un branch nuevo
2. `git checkout <branch-del-pr>`
3. Aplica las correcciones solicitadas (siguiendo TDD si tocan lógica)
4. Verificación pre-commit completa (tests + coverage + lint + build)
5. Commit al mismo branch **SIN push** — el orchestrator consolida la ronda. **Excepción:** si te invocaron por un check de CI fallido, reproduce el check localmente, confírmalo verde, y ahí sí pusheas directo
6. Reporta que las correcciones están listas para re-review

## Budget agotado a mitad de lote

Si te das cuenta de que no vas a alcanzar a terminar el lote dentro del budget:

1. Commit local de lo que ya tienes (con prefijo `wip:` si la tarea está incompleta)
2. Actualiza `.planning/HANDOFF.md` con instrucciones para retomar
3. **Push del branch** — excepción explícita a la regla de no pushear: sin push, el HANDOFF y los commits parciales no sobreviven a la invocación
4. Reporta:

```
BUDGET LIMIT — N de M tareas completadas
HANDOFF actualizado en .planning/HANDOFF.md
Branch: <nombre>
```

Procedimiento completo y prevención: `rulebooks/agent-budget.md`.

Algunos agentes agregan información al HANDOFF por su dominio (el `db-specialist` debe registrar el estado exacto de la DB de test; el `refactor` no commitea refactors a medio terminar). Eso está en su prompt.

## Debugging

Nunca por prueba y error: **evidencia → hipótesis → experimento que la confirme o descarte → fix mínimo**. Antes de arreglar un bug, escribe el test que lo reproduce. Después de arreglarlo, pregúntate si el mismo patrón existe en otro lado.

Si un cambio tuyo rompe algo, revierte a estado limpio y vuelve a aplicarlo en el pedazo más chico posible hasta aislar qué lo rompe.
