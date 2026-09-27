# Dev Common

Procedimientos idénticos para todos los agentes que escriben código (`backend-dev`, `frontend-dev`, `e2e-runner`, `docs`). Vivían copiados en cada prompt; ahora viven acá una sola vez.

Cada agente los referencia desde su sección "Reglas heredadas" y agrega solo su delta específico, si tiene.

## Handoff: qué recibes y qué entregas

**Recibes del orchestrator** (no te autoinvoques, no leas lo que no te toca):

- Sección de `.planning/DESIGN.md` correspondiente a tu lote (no el DESIGN completo, solo lo tuyo)
- Lista de tareas atómicas del lote (≤5 tareas)
- Path al schema/contratos definidos por el architect (o por un lote `db-complejo` anterior, si la feature tuvo uno) — los importas, no los inventas
- `~/.claude/rules/<lenguaje>.md` aplicable y `~/.claude/rules/docker.md` si el lote toca infraestructura
- Flag explícito: **`last_batch=true|false`** — define si cierras la implementación del feature (verificación final completa) o si vienen más lotes

**Si te falta información**, pregunta al orchestrator. **Nunca adivines, nunca preguntes al usuario directamente.**

**Entregas:**

- Si `last_batch=true` → verificación final completa + commits locales + reporte "listo para docs + review dual + push + PR" (el orchestrator los hace)
- Si `last_batch=false` → commits locales + reporte de tareas completadas + `.planning/state.json` actualizado (`tasks_done`/`current_task` de tu batch)

## Reglas heredadas (no reimplementar acá)

Estos documentos son fuente de verdad. Aplícalos sin redactarlos de nuevo:

- **`~/.claude/rules/implementation-principles.md`** — YAGNI, cambios quirúrgicos, asumir explícito, no stubs/TODOs, verificar antes de afirmar. La regla de "validación solo en boundaries" y "no error handling defensivo" sale de ahí.
- **`~/.claude/rules/self-reflection.md`** — proceso de auto-revisión idiomática contra `~/.claude/rules/<lenguaje>.md` antes de cada commit.
- **`~/.claude/rules/<lenguaje>.md`** — reglas idiomáticas concretas (longitud de funciones, nesting, patrones del lenguaje, type hints, etc.). NO duplicar acá.
- **`~/.claude/rules/docker.md`** — hot reload por lenguaje, USER nonroot, multi-stage, pinear versiones, no hardcodear secrets.
- **`CLAUDE.md` raíz** — gitflow, formato de commits (`scope: descripción en imperativo y español`), workflow general.
- **`~/.claude/rulebooks/agent-budget.md`** — qué hacer si te quedas sin budget a mitad del lote.

## Gitflow

Antes de empezar:

1. Verifica el branch actual con `git branch --show-current`
2. **Nunca trabajes en `main` o `dev` directamente**
3. **El orchestrator ya creó el branch** — tú NO creas branch nuevo. Trabajas sobre el `feature/*` o `hotfix/*` que ya existe
4. Si no hay branch (raro, indicaría falla del orchestrator), reporta el error en lugar de crear uno

Formato de commit y reglas de gitflow generales: `CLAUDE.md` raíz.

**Excepción — `e2e-runner` en Modo A** (invocación directa del usuario): ahí sí creas tu propio branch, porque no hay orchestrator que lo haya hecho. Ver el prompt del agente.

## Push: quién y cuándo

**No pusheas ni abres PR.** Al cerrar el último lote, el orchestrator invoca `docs` sobre el diff local y el review dual local (Fase 2.6), y recién ahí hace push + PR — un solo push inicial que ya incluye la documentación y los fixes del review (presupuesto de CI).

Hay exactamente **dos excepciones**:

1. **Fix de un check de CI fallido** — reproduces el check localmente, lo ves pasar, y pusheas directo al branch del PR.
2. **Budget agotado** — ver abajo.

En rondas de review nunca pusheas — ni en las pre-push (Fase 2.6: los fixes viajan en el push inicial) ni en las post-PR (el orchestrator consolida la ronda en un solo push).

## Correcciones post-review

Las correcciones de review pueden llegar en dos momentos: **pre-push** (Fase 2.6 — el review dual corre sobre el diff local y no hay nada pusheado todavía) o **post-PR** (re-reviews sobre un PR existente). El procedimiento es el mismo en ambos:

1. **Trabaja en el MISMO branch** (el del feature o el del PR) — NO crees un branch nuevo
2. `git checkout <branch>`
3. Aplica las correcciones solicitadas (siguiendo TDD si tocan lógica)
4. Verificación pre-commit completa (tests + coverage + lint + build)
5. Commit al mismo branch **SIN push** — el orchestrator decide cuándo pushear (pre-push: los fixes viajan en el push inicial; post-PR: consolida la ronda en un solo push). **Excepción:** si te invocaron por un check de CI fallido, reproduce el check localmente, confírmalo verde, y ahí sí pusheas directo
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

Algunos agentes agregan información al HANDOFF por su dominio (el `backend-dev` debe registrar el estado exacto de la DB de test en un lote `db-complejo`). Eso está en su prompt.

## Guardas que aplican a todo lote

Dos guardas valen en cualquier lote, no solo cuando el build está roto: dependencia nueva, major o downgrade → escala al architect o al usuario antes de aplicarlo; no silenciar checks con `ignore`, `disable` o `strict: false` — arregla lo que el check señala. Detalle completo (tabla de dependencias, causa raíz, escalaciones) en `rulebooks/build-errors.md`.

## Build roto

Si tu build/compilación falla, lee `rulebooks/build-errors.md` — clasificación del error, causa raíz, criterio de dependencias, escalaciones y el corte de tres intentos viven ahí. Lo resuelves tú mismo, en tu propio contexto y branch; no hay agente aparte al que delegar. Si el usuario te pide ayuda directa con un build roto fuera del flujo de un lote, aplica el mismo rulebook.

## Debugging

Nunca por prueba y error: **evidencia → hipótesis → experimento que la confirme o descarte → fix mínimo**. Antes de arreglar un bug, escribe el test que lo reproduce. Después de arreglarlo, pregúntate si el mismo patrón existe en otro lado.

Si un cambio tuyo rompe algo, revierte a estado limpio y vuelve a aplicarlo en el pedazo más chico posible hasta aislar qué lo rompe.

## Flujo de trabajo

### 1. Setup inicial

- Lee la sección de `DESIGN.md` que te pasó el orchestrator
- Lee `.planning/STATE.md` (decisiones, blockers) y `.planning/state.json` (`tasks_done`/`current_task` de tu batch) para saber si hay trabajo previo en curso (puede que esta no sea la primera invocación de este lote)
- Si no es el primer lote del PR, lee `git log --oneline` para entender qué hay
- Verifica que estás en el branch correcto
- Lee los **schemas/contratos** del path que te pasó el orchestrator
- Lee el código existente relacionado con Grep/Glob

### 2. Ciclo TDD por cada tarea atómica

Repetir por cada una de las ≤5 tareas del lote:

- **RED:** escribe un test que describa el comportamiento esperado. Ejecútalo. **Debe fallar.** Si pasa sin código nuevo, el test no prueba nada — reescríbelo.
- **GREEN:** escribe el código MÍNIMO para que el test pase. No más. Ejecútalo y verifica que pasa.
- **REFACTOR:** limpia el código sin cambiar comportamiento. Tests deben seguir pasando.
- **COMMIT:** commit local atómico con mensaje descriptivo (formato definido en CLAUDE.md raíz). Antes de empezar la siguiente tarea, actualiza `.planning/state.json` (`tasks_done`/`current_task` de tu batch).

### 3. Verificación pre-commit (por cada commit)

Antes de cada `git commit`: tests con coverage ≥ 80% de branches sobre archivos del diff, lint sin errores (autofix primero, manual después — nunca commitear con errores de lint), build compila (nunca commitear código que no compile). Si falta alguno, NO hagas commit. Arregla y repite.

### 4. Self-review antes del commit

Aplica `~/.claude/rules/self-reflection.md` siguiendo su proceso completo (clasificar violaciones in-scope triviales / in-scope controvertidas / legacy → arreglar las triviales, crear issues para el resto). Si corregiste violaciones triviales, menciónalo brevemente en el commit message.

### 5. Docker (si el proyecto usa docker-compose)

Rebuild y deploy para preview:

```bash
docker compose up -d --build <servicio>
docker compose ps <servicio>
docker compose logs --tail=20 <servicio>
```

Si el contenedor falla, revisa logs, arregla y repite antes de continuar. Con hot reload verifica que los cambios se reflejaron en logs; sin hot reload, `docker compose restart <servicio>`; si cambiaste dependencias o el Dockerfile, rebuild obligatorio. Sin Docker (proyecto corre localmente sin compose), asegúrate de que el dev server esté en watch mode.

Las reglas de cómo escribir Dockerfiles viven en `~/.claude/rules/docker.md`. Aplícalas sin redactarlas acá; el alcance exacto de qué archivo de infraestructura toca cada dev está en su prompt.

### 6. Verificación final del lote

Antes de cerrar el lote, muestra evidencia concreta: tests (X pasando, 0 fallando), coverage (≥ 80%), build (compilación exitosa), lint (sin errores), Docker (contenedor corriendo, si aplica). Si falta alguna (excepto Docker cuando no hay compose), el lote NO está listo.

### 7. Cierre de lote (según `last_batch`)

Push y PR: ver "Push: quién y cuándo" arriba.

**Si `last_batch=true`** (último lote del PR), verificación final completa del branch (todos los lotes integrados) y reporta:

```
IMPLEMENTACIÓN COMPLETA — <Y> commits locales en branch <nombre>.
LISTO PARA DOCS + PUSH + PR (los hace el orchestrator).
```

**Si `last_batch=false`** (modo single-PR con más lotes pendientes), reporta:

```
LOTE N COMPLETADO — <X> tareas commiteadas localmente en branch <nombre>.
Listo para el siguiente lote.
```

En ambos casos incluye evidencia de verificación (tests, coverage, build, lint).

## Desviaciones del diseño

Implementa EXACTAMENTE lo que el architect diseñó (o lo que quedó definido en un lote `db-complejo` anterior, en el caso del schema). Los contratos y la estructura son vinculantes. Hay **3 situaciones donde puedes desviarte**:

1. **Flaw de seguridad** — Si implementar tal cual crearía una vulnerabilidad, **PARA y reporta al orchestrator antes de arreglar**. No arregles silenciosamente.
2. **Funcionalidad crítica faltante** — Si el diseño olvidó algo obvio y necesario, agrégalo y documéntalo en el commit message.
3. **Inconsistencia con código existente** — Si el diseño propone un patrón diferente al que ya existe en el codebase, sigue el patrón existente y documenta la desviación.

Para cualquier otra desviación: **NO la hagas.** Reporta al orchestrator y espera instrucciones.

Para "no stubs/TODOs", ver principio #4 en `~/.claude/rules/implementation-principles.md`. Si no puedes completar algo, repórtalo como blocker.
