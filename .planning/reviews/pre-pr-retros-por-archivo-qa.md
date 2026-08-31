# QA Backend Review — fix/retros-por-archivo (PR #70)

**Repo:** claude-methodology · **Branch:** `fix/retros-por-archivo` · **Base:** `dev` · **SHA revisado:** `54d3a89` · **Fuente:** `git diff dev...HEAD`

**Scope:** cambio de proceso, sin capa de aplicación. Criterio aplicado: coherencia normativa y anti-drift sobre `agents/refactor.md`, `global/CLAUDE.md`, `rulebooks/agent-budget.md`, `rulebooks/governance-playbook.md`, `rulebooks/orchestrator-runbook.md`, `skills/pr-workflow/SKILL.md`. No hay tests/CI aplicables (confirmado con grep: `hooks/` no aparece en `git diff dev...HEAD --stat`).

## Metodología de verificación

Todo lo marcado VERIFICADO se ejecutó en este entorno (greps sobre el corpus, lectura de archivos, `gh` contra PRs reales de `easy-quotes` — el mismo repo cuyo incidente motiva este PR, con acceso de solo lectura). Lo marcado INFERIDO es conocimiento general no reproducido acá, señalado como tal.

## DoD anti-drift (paso 1 del runbook, ejecutado sobre el propio diff)

Grep de `LEARNINGS`, `learnings`, `entrada`, `prepend`, `retro`, `acumulativo`, `regla de 3` sobre `global/`, `README.md`, `rulebooks/`, `agents/`, `skills/`:

- **7 referencias vivas al comportamiento nuevo**, todas consistentes entre sí: `global/CLAUDE.md:94,114,118`, `rulebooks/orchestrator-runbook.md:136,223,533,537` (y las de gobernanza en `governance-playbook.md:100,170`, `agent-budget.md:103`, `agents/refactor.md:27`). Cero residuos describiendo el comportamiento viejo ("una entrada", "prepend a LEARNINGS.md", "por feature").
- **`README.md` no menciona `LEARNINGS`/retro** — nada que reconciliar ahí.
- **Los hooks no fueron tocados** (`git diff --stat -- '*.sh' 'hooks/*'` vacío) y `hooks/post-pr-create.sh` sigue citando `pre-pr-$SLUG_LABEL.md` — coincide exactamente con lo que el propio diff admite ("el runbook todavía manda un único `pre-pr-<feature-slug>.md` para reviews... corregirlo toca `post-pr-create.sh`, así que va aparte"). No hay drift oculto ahí.
- El check 4 de la verificación pre-merge (delta post-review solo bajo `.planning/`) es agnóstico al nombre de archivo dentro de `.planning/` — no se rompe con el cambio de formato de la retro. Verificado leyendo el comando (`git diff --name-only "$REVIEW_SHA"..HEAD | grep -cv '^\.planning/'`).

**Paso 1-3 del DoD: LIMPIO.**

## Coherencia con el modo multi-PR

**No hay contradicción.** El modo multi-PR (`rulebooks/orchestrator-runbook.md`, sección "Modo multi-PR") es un *for-loop* estrictamente secuencial: "Para cada grupo: 1. Crear branch... 3. Fase 2.5 → ... → Fase 5 (merge) 4. Pasar al siguiente grupo." Cada grupo llega hasta el merge **antes** de que exista el branch del siguiente. Bajo esa lectura literal, multi-PR nunca produce dos PRs de la misma feature abiertos a la vez, así que la regla nueva no colisiona con él.

La regla nueva tampoco se presenta como específica de multi-PR: la última frase la ata explícitamente al invariante preexistente "una feature a la vez" de `CLAUDE.md` — correcto, porque el escenario real que la motivó **no fue multi-PR de una sola feature, sino dos features distintas con PR abierto a la vez** (ver evidencia abajo). Un orchestrator que la lea no debería dudar sobre si aplica a multi-PR: no aplica ahí porque ahí no se da la precondición.

## Verificación empírica del incidente real (no narrado, reproducido)

El texto nuevo dice: *"Pasó con los PRs #184 y #186"* (cita en `easy-quotes/.planning/LEARNINGS.md:5`, no en este repo — la metodología no puede citarlo con path porque vive en otro proyecto). Reproduje la secuencia con `gh` contra el repo real:

```
gh pr view 186 --json commits  →  3 commits:
  286bc370  2026-08-31T05:22:04Z
  042980e1  2026-08-31T14:23:59Z   "planning: sellar el estado y la retro del PR #186"
  f4356997  2026-08-31T15:10:37Z   "merge: integrar dev (retro del PR #184) en el branch de precios"

gh pr view 184 --json mergedAt  →  2026-08-31T14:22:49Z  (un minuto antes del commit 042980e1)

gh run list --branch chore/precios-249-799  →  2 runs (05:42:58 y 15:10:44),
  CERO runs para el commit 042980e1
```

Esto confirma con datos reales, no con narración: **el commit que sella la retro y el estado (Fase 4, paso 5) es exactamente el que se pushea sin generar ningún check**, un minuto después de que la otra PR mergeó y dejó el branch en conflicto silencioso. La causa raíz que el PR describe es real y está bien diagnosticada.

## BLOQUEANTE — Fase 4 no aplica su propio remedio en el punto exacto donde ya falló

El diff introduce una regla nueva ("el chequeo de `mergeable` va primero y no es opcional") y, por el DoD paso 4, tengo que releerla aplicada al propio diff. No se sostiene en un lugar:

**Fase 4, paso 6** — texto sin tocar por este diff: *"Espera CI verde sobre el HEAD nuevo — branch protection valida el último SHA, no el que ya estaba verde."* Esta instrucción llega **inmediatamente después** del `git push` que sella retro + `state.json` (paso 5) — es decir, literalmente el mismo paso donde ocurrió el incidente reproducido arriba. No dice qué hacer si no llegan checks, ni referencia el diagnóstico nuevo de Fase 2.8. Un orchestrator que siga la Fase 4 al pie de la letra pushea el commit de sellado y luego espera checks sin chequear `mergeable` — y si otra PR mergeó en el medio (el escenario que el propio párrafo "Si hay dos PRs abiertos a la vez" reconoce como posible dos frases más abajo), vuelve a caer en el mismo bloqueo mudo que este PR dice cerrar. El chequeo de Fase 2.8 corre una sola vez, "después de que se crea el PR" — no se repite acá, que es el punto temporal donde realmente hizo falta en el incidente real.

Contraste dentro del mismo diff: el párrafo "Por qué no es un archivo acumulativo" (línea 537) sí cita `"(ver Fase 2.8)"` al explicar el mismo modo de falla para el archivo de retro. El párrafo "Si hay dos PRs abiertos a la vez" (línea 537, la nueva regla de sellado) y el paso 6 de Fase 4 no llevan esa misma referencia — inconsistencia dentro del propio commit, no entre documentos distintos.

El mismo hueco está en la verificación pre-merge (Fase 5, check 3: `gh pr checks <number>` / "Todos en ✓") — tampoco repite el chequeo de `mergeable`, así que es la segunda oportunidad perdida de blindar el mismo punto.

**Reasignación:** quien haga el fix agrega, en Fase 4 paso 6 (y como defensa adicional en el check 3 de la verificación pre-merge), la misma llamada `gh pr view <number> --json mergeable,mergeStateStatus` que ya está en Fase 2.8, con la misma resolución ("mergeá la base, nunca `--force`"). No requiere diseño nuevo — es repetir/cross-referenciar lo que Fase 2.8 ya resuelve bien.

## Fase 2.8 — accionable y segura, con un hueco menor

- **Segura**: la resolución explícita ("mergeá la base al branch, nunca `--force`") coincide con lo que los hooks ya bloquean (`git push --force`, `git reset --hard`). No sugiere nada peligroso. VERIFICADO: `gh pr view <N> --json mergeable,mergeStateStatus` es un comando válido en `gh 2.88.1` (lo corrí contra PR #70 real: `{"mergeStateStatus":"CLEAN","mergeable":"MERGEABLE"}`).
- **Hueco menor, no bloqueante**: `mergeable` puede volver `UNKNOWN` mientras GitHub todavía lo está calculando (ventana típica de segundos tras crear/actualizar una PR) — INFERIDO de comportamiento general de la API de GitHub, no reproducido acá (reproducirlo exigiría crear una PR real, fuera de mi alcance read-only). El texto solo cubre `CONFLICTING`/`DIRTY` explícitamente; no dice qué hacer con `UNKNOWN` (¿reintentar? ¿proceder?). Dado que el propio flujo ya mete un par de escrituras entre `gh pr create` y este chequeo (Fase 2.7: push + PR + reconciliación), la ventana probablemente ya cerró en la práctica — por eso lo dejo como sugerencia, no bloqueante.

## Autoconsistencia — "un proyecto lo resolvió"

El párrafo de línea 537 admite que el mismo patrón de conflicto ya falló con los reportes de review, y que "un proyecto lo resolvió" con un archivo por escritor concurrente. Verifiqué la cita: es real y describe con precisión el mismo mecanismo — **`easy-quotes/.planning/LEARNINGS.md:212`**, *"Reviewers en paralelo escribiendo al mismo archivo de reporte... La ronda 3 usó un archivo por reviewer... que es la única forma de que 'no sobrescribas' sea una instrucción que un proceso concurrente pueda honrar."* La admisión de que "el runbook todavía manda un único `pre-pr-<feature-slug>.md` para reviews" es clara y no deja al lector dudando qué hacer hoy: confirmé por grep que las 6 referencias vivas a `pre-pr-<feature-slug>.md`/`PR-<N>.md` para reviews (líneas 160, 172, 211, 646, 720, 721, 821) no cambiaron — el comportamiento actual de reviews sigue siendo el de siempre, sin ambigüedad.

**Sugerencia (no bloqueante):** la cita no lleva número de PR ni nombre de proyecto, a diferencia de la convención ya establecida en el mismo archivo tocado por este diff dos líneas más abajo en `skills/pr-workflow/SKILL.md:163` ("Medido: el PR #179 de easy-quotes — 47 líneas..."). Nombrar el proyecto/PR (aunque sea de otro repo, sin path citable) haría la afirmación sobre el incidente pasado verificable de la misma forma que las demás del corpus, en vez de "un proyecto" genérico.

## Nits (no bloqueantes)

- `global/CLAUDE.md:118` — en la misma oración que este diff edita, conviven `learnings/PR-<N>.md` (ángulos, la convención de todo el resto del corpus — 12+ apariciones) y `reviews/... PR-{N}.md` (llaves, sin tocar por este diff). No genera ambigüedad real, pero ya que la oración se estaba editando era la oportunidad de unificar.

## Veredicto

**CAMBIOS NECESARIOS.**

Un bloqueante: Fase 4 (paso 6) y el check 3 de la verificación pre-merge no aplican el chequeo de `mergeable` que Fase 2.8 introduce, exactamente en el punto del flujo donde el incidente real (`PR #186` de easy-quotes, reproducido arriba con `gh run list`) ya lo hizo fallar. El resto del diff — DoD anti-drift, coherencia con multi-PR, formato de retros por archivo, seguridad de la resolución de conflictos — está limpio y bien fundamentado.

### Bloqueantes (deben arreglarse)

- [ ] `rulebooks/orchestrator-runbook.md` — Fase 4, paso 6 ("Espera CI verde sobre el HEAD nuevo") — agregar el mismo chequeo de `mergeable`/`mergeStateStatus` de Fase 2.8 antes de esperar checks, con la misma resolución (merge de la base, nunca `--force`). Es el punto exacto donde el incidente real ocurrió (commit de sellado sin ningún check, verificado con `gh run list` contra `easy-quotes#186`). Reasignar a quien firme el PR de metodología (no aplica dev/db-specialist — es el mismo autor del diff).
- [ ] `rulebooks/orchestrator-runbook.md` — verificación pre-merge, check 3 ("CI checks... Todos en ✓") — mismo hueco, segunda línea de defensa.

### Sugerencias (opcionales)

- [ ] `rulebooks/orchestrator-runbook.md:537` — citar el incidente de "reportes de review pisándose" con proyecto/PR, como ya hace `skills/pr-workflow/SKILL.md:163` con el PR #179.
- [ ] `rulebooks/orchestrator-runbook.md` (Fase 2.8) — aclarar qué hacer si `mergeable` sale `UNKNOWN` (reintentar vs. proceder).
- [ ] `global/CLAUDE.md:118` — unificar `PR-{N}.md` → `PR-<N>.md` ya que la oración se tocó.
