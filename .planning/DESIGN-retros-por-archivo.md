# Diseño: Review dual pre-push (Fase 2.6) — el PR nace revisado

## Resumen

Se inserta una fase nueva, **Fase 2.6: Review dual local**, entre docs (2.5) y push + PR (2.7): security-reviewer + qa-* revisan el **diff local** (`git diff <base>...HEAD`) y las rondas de fixes ocurren sin pushear nada; el PR nace revisado y el caso normal cuesta **un solo run de CI**. La Fase 3 queda redefinida como fase post-PR (re-reviews condicionales, E2E Modo B, verificación pre-merge, merge) y `post-pr-create.sh` pasa de "instruir el review" a **checkpoint de respaldo** para PRs fuera del flujo (D-02).

**Decisión de numeración (anti-drift por diseño):** NO se renumera ninguna fase existente. `2.6` entra en el hueco que ya existía entre 2.5 y 2.7; `2.7`, `2.8`, `3` y `4` conservan su número (Fase 3 conserva número pero cambia contenido). Esto preserva válidas todas las referencias existentes a "Fase 2.7" y "Fase 2.8" en docs, skills y agentes — la clase de drift más barata de evitar es la que no se genera.

## Search-first

No aplica búsqueda de librerías: es un cambio de proceso sobre documentos y un hook bash existentes (categoría "fix/refactor de código existente" — se salta search-first según mi propio prompt). La investigación hecha fue de **evidencia interna**:

1. **Triggers del scaffold de CI** (`skills/new-project/SKILL.md`, paso 4): `ci.yml` → *"Trigger en push a dev y PRs a main/dev"*; `security.yml` → *"Trigger en PRs a main + schedule semanal (cron) sobre dev. NUNCA en push/PRs a dev"*. Conclusión: **pushear un branch `feature/*` sin crear PR no dispara ningún workflow** en repos scaffoldeados por la metodología. Base de la resolución del conflicto remoto (abajo).
2. **Modelo de ejecución de los reviewers** (`agents/security-reviewer.md`, `agents/qa-*.md`): son subagentes con tools `Read, Grep, Glob, Bash` sobre el **filesystem local** — nada en la metodología los corre en entornos remotos por defecto. El caso remoto es excepción, no default.
3. **Inventario anti-drift** (grep sobre CLAUDE.md ambos, README, rulebooks/, agents/, skills/, hooks/, tests/): mapa completo en "Archivos afectados".
4. **Historia del registro de reviews**: `.planning/reviews/PR-{N}.md` está trackeado en git y se commitea en momentos post-review (ej. commit `a053cba` "planning: retro del PR #54"). El naming pre-PR (abajo) respeta esa convención y la reconcilia al crear el PR.
5. **Tests del hook**: `post-pr-create.sh` **no tiene tests hoy** en `tests/adversarial/test-hooks.sh` — el lote 1 los estrena con TDD, usando la infraestructura sandbox existente (`sandbox_create`, `assert_exit0`, decisión ARCHITECTURE 2026-08-14 "sandbox obligatorio").
6. **Este repo no tiene `.github/workflows/`** — para el PR de dogfooding (D-04), CI es N/A ("Cuándo NO monitorear CI") y el costo de la reconciliación es cero.

## Flujo nuevo completo

```
Fase 0:    Brainstorming    → BRIEF.md                                   [sin cambio]
Fase 0.5:  Design system    → si hay UI, ui-ux antes del architect       [sin cambio]
Fase 1:    Diseño           → architect entrega DESIGN.md                [sin cambio]
Fase 2:    Implementación   → devs por lote, last_batch=true|false       [sin cambio]
Fase 2.5:  Documentación    → docs sobre diff local, sin push            [sin cambio]
Fase 2.6:  Review dual LOCAL → security + qa-* sobre git diff <base>...HEAD   [NUEVA]
                               rondas de fixes locales SIN push hasta veredictos
                               limpios + sugerencias baratas aplicadas
                               registro: .planning/reviews/pre-pr-<slug>.md
Fase 2.7:  Push + PR        → push + gh pr create + RECONCILIACIÓN del   [ampliada]
                               registro (pre-pr-<slug>.md → PR-<N>.md)
Fase 2.8:  Monitoreo CI     → gh pr checks --watch --fail-fast           [sin cambio]
Fase 3:    Post-PR          → re-reviews SOLO si CI obligó fixes que     [redefinida]
                               cambian código ya revisado
                               + e2e-runner Modo B si PR a main
                               + verificación pre-merge + merge
Fase 4:    Learn (post-merge)                                            [sin cambio]
```

El invariante de CLAUDE.md global no cambia (D-01): review dual **bloqueante antes de merge**. Lo que cambia es el momento: por default ocurre en 2.6, antes del push inicial. La regla "un push por ronda" (pr-workflow 5.2) sobrevive **solo para rondas post-PR** (D-05): las rondas pre-PR no pushean nada.

### Fase 2.6 — especificación (va al runbook como sección nueva)

1. **Clasificar el diff local por capa**: `git diff --name-only <base>...HEAD` + sección "Clasificación del diff por capa" del runbook. `<base>` = branch base del PR futuro (normalmente `dev`).
2. **Presupuestar el review proporcional al diff**: `git diff --shortstat <base>...HEAD` para additions+deletions; misma tabla y mandato de cierre que la skill `review-pr` paso 3 (el presupuesto proporcional aplica igual en pre-PR — fuera de alcance cambiarlo).
3. **Lanzar en paralelo** (single message, multiple Agent calls): `security-reviewer` siempre; `qa-frontend`/`qa-backend` según capas. Paquete de contexto (context isolation): base + branch + instrucción de leer `git diff <base>...HEAD` + lista de archivos + `BRIEF.md` + `DESIGN.md` + presupuesto + formato de salida. **Sin número de PR — no existe todavía.**
4. **Consolidar y registrar**: reporte con el "Formato de reporte de review" del runbook, guardado en `.planning/reviews/pre-pr-<feature-slug>.md` con header de trazabilidad (branch, base, SHA de HEAD revisado, fecha, veredicto). Commit al branch: `planning: registrar review dual pre-push`.
5. **Blockers** → fixes por el dev correspondiente en el mismo branch, **sin push**. Re-lanzar **solo** los reviewers que marcaron issues, acotados al delta local (`git diff <sha-ya-revisado>...HEAD`). Append de la re-ronda al registro. Sugerencias baratas: aplicadas antes del push (misma regla que hoy).
6. **Veredictos limpios** → Fase 2.7. Fixes, sugerencias aplicadas y registro viajan en el push inicial: **el PR nace revisado**.

### Fase 2.7 — ampliación (reconciliación del registro)

```bash
git push -u origin <branch>
gh pr create --base dev --title "..." --body "..."   # body incluye veredictos del review pre-push
git mv .planning/reviews/pre-pr-<slug>.md .planning/reviews/PR-<N>.md
# actualizar .planning/state.json: pr = N
git commit -m "planning: vincular review pre-push al PR #<N>"
git push
```

Los cinco comandos se ejecutan como **una sola secuencia inmediata** (segundos entre `create` y el segundo push). Costo: con la `concurrency` + `cancel-in-progress` del scaffold (pr-workflow 5.5, **obligatoria en todos los repos**), el run del evento `opened` se cancela a los segundos y solo completa el del `synchronize` → **neto: un run completo de CI**, igual que el ideal. En repos sin Actions (como este), gratis. Si un repo no cumple 5.5, arreglar el workflow es prerequisito — la regla ya existe, no se crea una nueva.

Por qué reconciliar con rename y no con dos convenciones permanentes: los re-reviews post-PR (Fase 3 y skill `review-pr`) hacen **append** a `PR-<N>.md` — sin el rename, la historia de review de un mismo PR quedaría fragmentada en dos archivos.

### Fase 3 — redefinición (post-PR)

1. **Re-review condicional**: SOLO si la Fase 2.8 obligó fixes que cambian código ya revisado. Acotado al delta del fix, re-lanzando solo los reviewers de la capa afectada. Append al registro `PR-<N>.md`. Si CI pasó a la primera (caso normal), esta sub-fase es no-op.
2. **E2E Modo B si el PR es a `main`** (D-03, sin cambio).
3. **Verificación pre-merge** (3 comandos `gh`) + merge según tipo de branch + integración de hotfix + updates de `state.json`/`STATE.md` — todo idéntico a los pasos 6–10 de la Fase 3 actual.
4. PRs fuera del flujo → skill `review-pr` (sin cambio).

## Resolución del conflicto reviewers-remotos vs pre-push

**Evidencia** (Search-first #1 y #2): los reviewers de la metodología son subagentes locales con acceso directo al working tree — no necesitan el branch pusheado. Y el scaffold de `new-project` genera `ci.yml` con triggers `push: dev` + `pull_request: main/dev`, y `security.yml` con `pull_request: main` + cron: **un push de `feature/*` sin PR dispara cero workflows**.

**Regla escrita (ambos casos):**

- **Default — reviewers locales**: el review de Fase 2.6 corre con subagentes locales sobre `git diff <base>...HEAD`. No hay push antes del review. Este es el único modo que el flujo usa automáticamente.
- **Excepción — reviewer remoto** (entorno cloud/aislado que necesita clonar): permitido pushear el branch **sin crear PR** antes del review, con esta **condición verificable**: ningún workflow del repo dispara con `on: push` sobre branches que matcheen `feature/*`/`hotfix/*` (verificar con grep de los triggers en `.github/workflows/*.yml` antes del push). Bajo el scaffold de la metodología la condición se cumple siempre. Flujo remoto: push del branch (0 runs) → review remoto → fixes locales → push de fixes (0 runs) → `gh pr create` (primer y único run). Si la condición NO se cumple: corregir el trigger (filtro de branches) o caer al modo local — nunca pagar runs por review.

## Contratos

### 1. Naming y reconciliación del registro de reviews

| Momento | Archivo | Quién lo escribe |
|---|---|---|
| Fase 2.6 (pre-PR) | `.planning/reviews/pre-pr-<feature-slug>.md` | Orchestrator (consolidación) |
| Fase 2.7 (al crear el PR) | `git mv` → `.planning/reviews/PR-<N>.md` + `state.json.pr = N`, commit `planning: vincular review pre-push al PR #<N>` | Orchestrator |
| Fase 3 / `review-pr` (post-PR) | Append `## Re-review <fecha>` a `PR-<N>.md` (convención existente, sin cambio) | Orchestrator / skill |

`<feature-slug>` = campo `feature` de `state.json`. Header obligatorio del registro pre-PR: branch, base, SHA de HEAD revisado, fecha, veredicto — sin él, el re-review acotado al delta no tiene ancla.

### 2. Hook `post-pr-create.sh` (v2 — checkpoint de respaldo, D-02)

Sigue siendo PostToolUse/Bash, mismo registro en `hooks.json` (comando, matcher, timeout 15 — sin cambios), **siempre `exit 0`** (checkpoint, no guard). Parsing del input sin cambios (`tool_input.command`, `stdout`). Lógica de decisión nueva:

```
gh pr create detectado + URL extraída:
  TOPLEVEL = git rev-parse --show-toplevel
  STATE    = $TOPLEVEL/.planning/state.json
  CASO A — "PR del flujo, ya revisado":
    STATE existe ∧ jq legible ∧ .phases.review == "done" ∧ .branch == branch actual
    → imprime:
        PR creado: <URL>
        Review dual pre-push verificado (state.json: phases.review=done, branch <branch>).
        CHECKPOINT: confirma la reconciliación — .planning/reviews/PR-<N>.md debe existir
        (renombrado desde pre-pr-<slug>.md). Si falta, ejecútala ahora (Fase 2.7).
        No relances reviewers: el PR nació revisado. Re-review solo si CI obliga fixes
        sobre código ya revisado (Fase 3).
  CASO B — "sin evidencia de review pre-push" (todo lo demás: sin .planning/state.json,
    JSON ilegible, review != done, o branch distinto):
    → imprime una línea de diagnóstico ("No hay evidencia de review dual pre-push para
      este branch — se trata como PR fuera del flujo") + el bloque ACCIÓN REQUERIDA
      actual (lanzar security-reviewer + qa-* sobre gh pr diff, con la referencia al
      runbook para clasificación por capa).
gh pr create sin URL en stdout → WARNING actual (verificar a mano + lanzar review).
Comando que no es gh pr create → exit 0 silencioso (passthrough, sin cambio).
jq ausente → no-op exit 0 (degradación estándar de hooks de observabilidad,
  decisión ARCHITECTURE 2026-08-14).
```

La distinción flujo/fuera-del-flujo se **falla hacia el review**: cualquier ambigüedad produce CASO B. El costo del falso negativo es un review redundante; el del falso positivo sería un PR sin review — por eso CASO A exige las dos señales (fase Y branch).

### 3. Paquete de contexto de reviewers (parametrización de la fuente del diff)

`agents/security-reviewer.md`, `agents/qa-backend.md`, `agents/qa-frontend.md` — mismo cambio en tres lugares de cada uno:

- **Handoff "Recibes del orchestrator"**: reemplazar "Número de PR y branch / Diff del PR (o instrucción de leerlo con `gh pr diff <number>`)" por: «**Fuente del diff, indicada por el orchestrator**: *local* (base + branch — lo lees con `git diff <base>...HEAD`; es el default del flujo, el review ocurre antes del push y **no hay número de PR**) o *PR existente* (número — lo lees con `gh pr diff <N>`)».
- **Flujo de trabajo, paso 1**: "Obtén el diff con la fuente indicada: `git diff <base>...HEAD` (pre-push, default) o `gh pr diff <PR>` (PR existente)". En security-reviewer, paso 2 (lista de archivos): `git diff --name-only <base>...HEAD` o `gh pr view <PR> --json files`.
- **Re-review, paso 1**: "lee solo el delta desde el SHA ya revisado (misma fuente de diff que la ronda anterior)".

El veredicto vinculante no cambia de fuerza, solo de fraseo donde dice "el PR no se mergea": en el caso pre-push, "el branch no se pushea hasta corregir".

### 4. `state.json` — sin bump de schema

Claves y enum idénticos (schema 1). Cambia solo el **orden documentado de transiciones**: `review` pasa a `done` en Fase 2.6, **antes** que `pr` y `ci`. Tabla "Quién escribe qué": fila `phases.review` → "Orchestrator, Fase 2.6 (al cerrar veredictos limpios)". El campo `pr` se escribe en 2.7 dentro del commit de reconciliación (mismo commit que el rename).

## Archivos afectados — MAPA ANTI-DRIFT COMPLETO

Resultado del grep DoD (`pr diff|crear el PR|post-pr|Fase 2\.|Fase 3|reviews/PR-|review dual`) sobre CLAUDE.md (ambos), README, rulebooks/, agents/, skills/, hooks/, tests/. Cada entrada indica sección exacta y qué cambia. **Este mapa es la partición de los lotes 2 y 3.**

### Cambios de código (Lote 1)

- `hooks/post-pr-create.sh` — reescritura de la lógica de decisión (contrato #2). Parsing y registro intactos.
- `tests/adversarial/test-hooks.sh` — sección nueva `--- post-pr-create.sh ---` con TDD (no existe cobertura hoy). Patrón sandbox obligatorio.
- `hooks/hooks.json` — **sin cambio** (mismo evento/matcher/timeout); la paridad de `test-plugin-manifest.sh` no se toca.

### Documentos núcleo del proceso (Lote 2)

- `rulebooks/orchestrator-runbook.md`:
  - L110 (modo single-PR, punto 2): "después vienen docs (Fase 2.5)" → "docs (2.5), review dual local (2.6) y push + PR (2.7)".
  - L127 (modo multi-PR, punto 3): insertar "Fase 2.6 (review local)" en la cadena.
  - L146 (Fase 2.5): "avanza directo a Fase 2.7" → "a Fase 2.6".
  - **Sección nueva "Fase 2.6: Review dual local"** entre Fase 2.5 y Fase 2.7 (especificación de arriba) + entrada en el índice.
  - Fase 2.7 (L148–157): agregar la secuencia de reconciliación + nota de costo + body del PR con veredictos.
  - Fase 2.8 (L159+): nota "si el fix de CI cambia código ya revisado → re-review acotado en Fase 3".
  - **Fase 3 (L180–201): redefinición completa** (los pasos 1–5 actuales migran a 2.6; quedan re-review condicional, E2E, pre-merge, merge, state).
  - Context isolation (L252): "security-reviewer / qa-* reciben: diff completo del PR" → "la fuente de diff que indique el orchestrator — local (`git diff <base>...HEAD`, Fase 2.6) o PR (`gh pr diff <N>`, post-PR) — + DESIGN.md + BRIEF.md".
  - Tracker (L311–331): "Review dual local" como tarea separada bloqueada por los lotes; "Abrir PR + CI" bloqueada por el review; criterios de completed actualizados (review = veredictos limpios + sugerencias aplicadas + registro commiteado; PR+CI = PR creado + registro reconciliado + CI verde). **Fix de paso**: el criterio "lote = commits pusheados" es incorrecto incluso hoy (los devs no pushean) → "commits del lote hechos (locales) y reporte del dev recibido".
  - state.json (L389–443): contrato #4 (tabla de transiciones; sin bump).
  - Formato de reporte de review (L600–629): aclarar que `gh pr comment` aplica solo post-PR; L629 "Guardar copia en `.planning/reviews/PR-<number>.md`" → convención dual + reconciliación (contrato #1).
  - Errores comunes (L677+): fila nueva "PR creado sin review pre-push (checkpoint del hook lo señala) → tratarlo como PR fuera del flujo: skill `review-pr`".
  - Flujo "revisar PR existente" (L695+): sin cambio de fondo; nota de que guarda directo en `PR-<N>.md`.
- `skills/pr-workflow/SKILL.md`:
  - Frontmatter `description` (L3): "Invocar al llegar a Fase 2.7" → "Invocar al llegar a Fase 2.6 (review dual local, antes del push + PR) o al revisar/mergear un PR existente".
  - **Regla 2 reescrita** (L38–57): título "Review dual local antes del push (Fase 2.6)"; se lanza al terminar docs, sobre el diff local; fixes locales sin push; sugerencias baratas aplicadas antes del push; el PR nace revisado; post-PR solo re-reviews condicionales. Conserva: paralelismo automático sin confirmación, fixes en mismo branch, re-lanzar solo a quien marcó issues, política de sugerencias, referencia al checklist del security-reviewer. Incorpora la **regla del caso remoto** (resolución del conflicto, con su condición de triggers).
  - Sección E2E (L59–77): sin cambio (D-03).
  - Regla 5.2 (L112–114): reescribir alcance — "las rondas pre-PR (Fase 2.6) no pushean nada; un-push-por-ronda aplica a rondas post-PR: fixes de CI y re-reviews sobre PR existente" (D-05).
  - Regla 5.3 (L116–120): "En rondas de review (Fase 3) nunca" → "En rondas de review post-PR nunca".
  - Regla 5.1 (L106–110): sin cambio de fondo; añadir que tras docs viene el review local (2.6) antes del push.
- `rulebooks/dev-common.md`:
  - L22: "el orchestrator invoca `docs` sobre el diff local y recién ahí hace push + PR" → insertar "y el review dual local (Fase 2.6)" antes del push.
  - L29–40 ("Correcciones post-review"): generalizar — las correcciones de review pueden llegar **pre-push** (Fase 2.6, no hay nada pusheado) o **post-PR**; en ambas: commit al mismo branch sin push, el orchestrator decide cuándo pushear. La excepción de CI (L26, L39) queda igual.
- `rulebooks/agent-budget.md`:
  - L29: "push + PR + CI + review una sola vez" → "review local + push + PR + CI una sola vez".
  - L53: añadir el review local a la cadena "docs → … → push + PR"; la referencia "Fases 2.5–2.7" sigue válida.

### Documentos periféricos (Lote 3)

- `global/CLAUDE.md` (canónico de la metodología; el CLAUDE.md del repo NO describe el flujo — verificado, cero hits):
  - L34 (Workflow obligatorio #4): añadir el momento — "se lanzan… sobre el diff local al terminar docs (Fase 2.6), antes del push inicial; bloqueante antes de merge" (invariante intacto, D-01).
  - L40 (Lotes): "el push + PR lo hace el orchestrator después de docs — Fases 2.5–2.7" → "después de docs y del review dual local — Fases 2.5–2.7".
  - L51–53 (tabla de agentes): security-reviewer/qa-* "Al revisar PRs" / "PR con archivos de…" → "En Fase 2.6 (diff local) y re-reviews post-PR" / "Diff con archivos de…".
  - L87–92 (diagrama de fases): insertar la línea de Fase 2.6 y redefinir la línea de Fase 3 (post-PR: re-reviews condicionales + E2E Modo B). Es el diagrama espejo del de este diseño.
  - L98 (modo single-PR): insertar review dual local entre docs y push + PR.
  - L103 (tracker): "una tarea por etapa del pipeline (PR+reviews+CI, …)" → "(review dual local, PR+CI, …)".
  - L114 (`.planning/`): `reviews/PR-{N}.md` → `reviews/` (pre-PR: `pre-pr-<slug>.md`; al crear el PR se reconcilia a `PR-{N}.md` — ver runbook).
  - L127 (PR y merge, intro): "que invocas al llegar a Fase 2.7" → "al llegar a Fase 2.6".
  - L130 (invariante 2): texto intacto + "(el momento default: Fase 2.6, pre-push)".
  - L156 (hooks background): "review automático al crear un PR" → "checkpoint de review al crear un PR (verifica que el review dual pre-push ocurrió; solo instruye lanzarlo para PRs fuera del flujo)".
- `README.md`:
  - L36 (tabla de hooks, post-pr-create): descripción nueva de checkpoint de respaldo.
  - L51 (tabla de skills, /pr-workflow): "se invoca en Fase 2.7" → "en Fase 2.6".
  - L60–61 (diagrama del flujo): "→ PR creado → Security + QA review en paralelo → …" → "→ Review dual local (pre-push) → fixes locales → Push + PR (nace revisado) → CI → merge".
  - L68 (bullet dual review): añadir "pre-push".
- `agents/security-reviewer.md` — contrato #3 (L14 fraseo del veredicto, L20–21 handoff, L288–289 flujo, L302+ re-review).
- `agents/qa-backend.md` — contrato #3 (L19–20, L267, L286).
- `agents/qa-frontend.md` — contrato #3 (L19–20, L196, L215).
- `agents/docs.md` L14 — precisión opcional: "(Fase 2.5…, ANTES del review dual local y del push + PR)". Barato, evita ambigüedad.
- `rulebooks/governance-playbook.md` §1–§3 — gates de bloqueo reescritos agnósticos al momento ("no se pushea (pre-push, el default) / no se mergea (post-PR)"). Clasificado inicialmente como sin-cambio; el drift se detectó y cerró en b96bf05.

### Verificados SIN cambio (falsos positivos del grep — documentado para no re-investigar)

- `agents/build-resolver.md` L219 "Fase 3: Aplicar el fix mínimo" — fases **internas** del agente, no del pipeline. L17 referencia "Fase 2.8", que conserva número. Sin cambio.
- `skills/review-pr/SKILL.md` — post-PR por definición, fuera de alcance por BRIEF; su convención de append a `PR-<N>.md` es exactamente lo que la reconciliación preserva. Sin cambio.
- `hooks/hooks.json`, `settings.json`, `tests/adversarial/test-plugin-manifest.sh` — registro del hook intacto.
- E2E Modo B / `agents/e2e-runner.md` — sin cambio (D-03).
- `tests/validation/`, `docs/books/` — cero referencias al orden del flujo.
- Presupuesto de review proporcional (memoria `review-budget-proportional.md`) — aplica igual en pre-PR (fuera de alcance por BRIEF); la Fase 2.6 lo referencia con `git diff --shortstat`.

## Plan de implementación

**Estrategia de PR:** single-PR (default). Un branch `feature/pre-pr-dual-review` desde `dev`, 3 lotes secuenciales, un commit por tarea.

**Dogfooding (D-04): ESTE MISMO PR estrena el orden nuevo.** Al cerrar el Lote 3 (`last_batch=true`) y la Fase 2.5, el orchestrator ejecuta la Fase 2.6 tal como la define este diseño: review dual sobre `git diff dev...HEAD` con reviewers locales, registro en `.planning/reviews/pre-pr-pre-pr-dual-review.md`, fixes locales, y recién entonces push + `gh pr create` + reconciliación a `PR-<N>.md`. Este repo no tiene Actions: Fase 2.8 es N/A y la reconciliación cuesta cero.

#### Lote 1 — hook checkpoint con TDD (backend-dev)
**Depende de:** ninguno

- [ ] Tarea 1: test (rojo) + implementación: con `state.json` legible, `phases.review=="done"` y `branch` igual al actual, `post-pr-create.sh` imprime el checkpoint de "PR del flujo ya revisado" (contrato #2, CASO A) y NO imprime "ACCIÓN REQUERIDA"; exit 0.
- [ ] Tarea 2: test (rojo) + implementación: sin `.planning/state.json` en el toplevel, imprime la línea de diagnóstico "sin evidencia de review pre-push" + el bloque ACCIÓN REQUERIDA de PR fuera del flujo (CASO B); exit 0.
- [ ] Tarea 3: test (rojo) + implementación: `phases.review != "done"` o `branch` distinto del actual → CASO B (fail hacia el review).
- [ ] Tarea 4: test (rojo) + implementación: `state.json` malformado (JSON inválido) → CASO B; sin `jq` en PATH → no-op exit 0 (degradación estándar).
- [ ] Tarea 5: tests de caracterización de lo que se conserva: passthrough de comandos que no son `gh pr create` (sin output) y WARNING cuando no hay URL en stdout; suite adversarial completa verde sin contaminar el repo real (guard de no-contaminación).

Todos los tests con sandbox (`sandbox_create` + branch explícito + `state.json` sembrado en el sandbox), nunca contra el repo real (decisión ARCHITECTURE 2026-08-14).

#### Lote 2 — documentos núcleo del proceso (backend-dev)
**Depende de:** ninguno (secuencial tras Lote 1 por trabajar el mismo branch)

- [ ] Tarea 1: `orchestrator-runbook.md` — sección nueva "Fase 2.6", ampliación de 2.7 (reconciliación), nota en 2.8, redefinición de Fase 3, ajustes de L110/L127/L146 e índice.
- [ ] Tarea 2: `orchestrator-runbook.md` — context isolation (fuente de diff parametrizada), tracker (tarea "Review dual local" separada + criterios corregidos), contrato de transiciones de `state.json`.
- [ ] Tarea 3: `orchestrator-runbook.md` — formato de reporte (pre-PR vs post-PR), convención del registro con reconciliación (contrato #1), fila nueva en errores comunes, nota en "revisar PR existente".
- [ ] Tarea 4: `skills/pr-workflow/SKILL.md` — description del frontmatter + regla 2 reescrita (incluye la regla del caso remoto con su condición de triggers) + ajustes 5.1/5.2/5.3.
- [ ] Tarea 5: `rulebooks/dev-common.md` (L22, L29–40 generalizadas) + `rulebooks/agent-budget.md` (L29, L53).

#### Lote 3 — periferia y cierre anti-drift (backend-dev)
**Depende de:** Lote 2 (la periferia referencia las secciones nuevas del runbook)

- [ ] Tarea 1: `global/CLAUDE.md` — diagrama de fases, workflow #4, lotes, tabla de agentes, reglas del flujo, `.planning/`, invariante 2, sección hooks (mapa Lote 3, primer bloque). Verificar que sigue global-safe y sin crecer materialmente.
- [ ] Tarea 2: `README.md` — tabla de hooks, tabla de skills, diagrama del flujo, bullet de dual review.
- [ ] Tarea 3: `agents/security-reviewer.md` — parametrización de la fuente del diff (contrato #3).
- [ ] Tarea 4: `agents/qa-backend.md` + `agents/qa-frontend.md` — parametrización de la fuente del diff (contrato #3) + `agents/docs.md` L14 (precisión).
- [ ] Tarea 5: cierre anti-drift: re-correr el grep DoD completo (`pr diff|crear el PR|post-pr|Fase 2\.|Fase 3|reviews/PR-|review dual`) sobre CLAUDE.md ambos, README, rulebooks/, agents/, skills/, hooks/, tests/ y confirmar que todo hit restante está en la lista "verificados sin cambio" de este diseño; `claude plugin validate --strict .` verde (se tocaron agentes).

### Nota TDD

TDD literal aplica **solo al Lote 1** (lógica del hook): cada comportamiento nuevo entra con su test en rojo en `test-hooks.sh` antes de tocar `post-pr-create.sh` (rojo → verde → refactor, un commit por tarea). Los Lotes 2 y 3 son documentación de proceso — categoría exenta de TDD literal según CLAUDE.md ("archivos de configuración"/docs); su verificación es el grep DoD de la tarea 5 del Lote 3 + la suite adversarial completa verde (restricción del BRIEF).

## Riesgos

- **Drift residual en algún documento no mapeado** → mitigación: el mapa de este diseño se construyó con el grep DoD ampliado (incluye `reviews/PR-` y `review dual`), y la tarea 5 del Lote 3 lo re-corre como cierre; la sección "verificados sin cambio" evita tanto omisiones como cambios innecesarios.
- **Acoplamiento del hook al schema de `state.json`** → el hook lee solo `phases.review` y `branch` (schema 1); cualquier evolución del schema debe preservarlos o actualizar el hook. Mitigación: fail-hacia-review (CASO B) ante cualquier cosa ilegible — el peor caso es un review redundante, nunca un PR sin review.
- **Reconciliación en repos con Actions sin `cancel-in-progress`** → costaría un segundo run completo. Mitigación: 5.5 ya es obligatoria en todos los repos; la secuencia de 2.7 es inmediata (segundos) para que la cancelación del run `opened` sea casi gratis.
- **Push pre-review en el caso remoto con triggers mal configurados** → gastaría runs. Mitigación: la condición de triggers es verificable por grep y está escrita como prerequisito; bajo el scaffold se cumple por construcción.
- **Estado previo del worktree para el dogfooding**: la sesión está sobre `feature/harden-pre-merge-check` con `settings.json` modificado. El orchestrator debe cerrar/guardar ese trabajo y partir de `dev` limpio antes del setup del branch de esta feature.
- **`global/CLAUDE.md` debe seguir global-safe** → los cambios son reemplazos de líneas existentes, sin secciones nuevas; el QA del Lote 3 lo verifica.
