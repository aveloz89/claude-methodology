---
name: pr-workflow
description: Proceso de review, creación y merge de pull requests — review dual local pre-push, presupuesto de CI, verificación E2E pre-release, branch protection y verificación pre-merge. Invocar al llegar a Fase 2.6 (review dual local, antes del push + PR) o al revisar/mergear un PR existente.
user-invocable: true
allowed-tools: Read, Grep, Glob, Bash, Agent(security-reviewer), Agent(qa-frontend), Agent(qa-backend), Agent(e2e-runner), Agent(build-resolver)
argument-hint: "[número de PR, si es sobre uno existente]"
---

# PR Workflow

Proceso para crear, reviewear y mergear pull requests. Aplica a TODOS los proyectos.

Las cuatro reglas invariantes (un PR por objetivo con commits atómicos por tarea, review dual bloqueante, nunca mergear sin aprobación explícita, nunca mergear con CI en rojo) viven en `CLAUDE.md` porque no pueden llegar tarde. Este documento tiene el detalle operativo.

## 1. Un PR por unidad coherente, commits atómicos por tarea

**Decisión del usuario 2026-07-24 (reemplaza a "una fase = un PR"):** varias fases que persiguen el mismo objetivo viajan en **un solo PR**, con **un commit por fase**. La regla anterior multiplicaba los runs de CI sin comprar review de mejor calidad.

> **Enmienda 2026-08-14:** la unidad del commit se precisó de **fase → tarea** — un comportamiento/una idea = un commit; una fase viaja como una serie de commits atómicos. Es la práctica real desde los PRs #49–#56. El espíritu no cambia: nunca un commit gigante.

**Por qué el cambio:** cada PR cuesta como mínimo dos runs completos (el del PR + el del push a `dev` al mergear), más uno por ronda de review. Cinco fases como cinco PRs son ~15 runs; como un PR con cinco commits son ~3. Los minutos de Actions se agotaban en 15 días.

**Por qué no se pierde nada:** lo que hacía valiosos a los PRs chicos era poder revisar y bisectar por unidad — y eso lo da el **commit**, no el PR. Un commit por tarea, con mensaje que explique el porqué, deja el historial igual de navegable y `git bisect` igual de útil.

**Cómo aplicar:**
- Un branch por objetivo, no por fase. Las fases se acumulan ahí como series de commits atómicos.
- **Un commit por tarea, siempre** (un comportamiento/una idea = un commit). Nunca un commit gigante con todo: eso sí destruye la trazabilidad.
- El PR body lista las fases con un párrafo cada una, para que el reviewer navegue commit por commit.

**Cuándo SÍ separar en PRs distintos** (cualquiera de estas basta):

- **Refactor y feature nunca se mezclan.** Sigue siendo intocable: un refactor colateral dentro de un PR de feature hace irrevisable el diff.
- El trabajo es **genuinamente independiente y shippeable solo** — podría ir a `dev` sin lo demás.
- El diff se vuelve irrevisable: **>1000 LoC de naturaleza mixta que el PR body no logra agrupar de forma navegable**; el número de commits atómicos no es señal de corte.
- Una fase **depende del review de la anterior** para decidir su alcance. Si el feedback puede cambiar lo que viene, no lo adelantes.
- El riesgo de revert es asimétrico: una fase que quizás haya que revertir sola no debe arrastrar a las demás.

**Excepción legítima:** un refactor pequeño necesario para implementar la feature correctamente está dentro del scope. Documentarlo en el PR body.

## 2. Review dual local antes del push (Fase 2.6)

Al terminar docs (Fase 2.5), lanzar **security-reviewer + qa** (qa-frontend y/o qa-backend según lo que toque el diff) **sobre el diff local (`git diff <base>...HEAD`), en paralelo automáticamente, sin pedir confirmación al usuario** — ANTES del push y de crear el PR. Las rondas de fixes ocurren sin pushear nada: **el PR nace revisado** y el caso normal cuesta un solo run de CI.

**Cuándo y cómo lanzar:**
- En el mismo turn donde cierro Fase 2.5 (docs commiteado), lanzo los agents en paralelo (single message, multiple Agent calls)
- Los reviewers son subagentes locales: leen el working tree con `git diff <base>...HEAD` — no necesitan el branch pusheado ni número de PR (no existe todavía)
- Reportar findings al usuario después (detalle operativo de la fase — presupuesto, paquete de contexto, registro — en `rulebooks/orchestrator-runbook.md`, Fase 2.6)

**Si hay blockers:**
- Fixearlos en el MISMO branch, **sin push** (no hay nada pusheado que actualizar)
- Re-correr SOLO los reviewers que marcaron issues, acotados al delta local, para validar el fix
- Avanzar a Fase 2.7 (push + PR) solo cuando todo verde

**Sugerencias no bloqueantes: aplicarlas antes del push.**
Cuando un reviewer marca sugerencias (no bloqueantes) que son baratas, sin riesgo y trazables al scope del diff, aplicarlas en el MISMO branch antes del push inicial — no diferirlas ni solo anotarlas. Las que cambien comportamiento, requieran decisión de diseño, o sean scope de otra fase, NO se aplican: se anotan como issue o handoff en `.planning/STATE.md`. Después de aplicar, re-correr solo el reviewer que las marcó (o los tests si es cambio menor). Fixes, sugerencias aplicadas y registro del review viajan en el push inicial.

**Post-PR solo hay re-reviews condicionales** (Fase 3): únicamente si CI obligó fixes que cambian código ya revisado — acotados al delta del fix, re-lanzando solo los reviewers de la capa afectada. Si CI pasó a la primera, no se relanza nada.

**Por qué:** el patrón "aplicar sugerencias en el mismo PR" apareció en 4 PRs consecutivos como decisión manual del usuario. Formalizarlo evita el ida-y-vuelta de pedir permiso para cada mejora obvia. El usuario sigue siendo el checkpoint del **merge** (regla 3), no de cada pulido.

El checklist de infraestructura que el security-reviewer debe correr (rate limiting, shell injection, prototype pollution, reflected input) vive en `agents/security-reviewer.md`, en el prompt del agente que lo ejecuta.

**Caso remoto (excepción):** si un reviewer corre en un entorno cloud/aislado que necesita clonar el repo, está permitido pushear el branch **sin crear PR** antes del review, con esta **condición verificable**: ningún workflow del repo dispara con `on: push` sobre branches que matcheen `feature/*`/`hotfix/*` (verificar con grep de los triggers en `.github/workflows/*.yml` antes del push; bajo el scaffold de `new-project` se cumple siempre). Flujo: push del branch (0 runs) → review remoto → fixes locales → push de fixes (0 runs) → `gh pr create` (primer y único run). Si la condición NO se cumple: corregir el trigger (filtro de branches) o caer al modo local — nunca pagar runs por review. El default del flujo es siempre el modo local.

### Verificación E2E real obligatoria en PRs a main (pre-release)

**Decisión del usuario 2026-07-19:** la verificación E2E completa (suite Playwright + flujos en navegador real) es obligatoria y bloqueante **solo en PRs a `main`** (pre-release). En PRs de feature a `dev` NO se corre E2E por default — basta con security + qa + tests unitarios + build. Razón: el ciclo dev es más ágil sin el gate más caro; la suite E2E se actualiza y corre una sola vez por release, contra el acumulado.

Consecuencia aceptada: la suite `e2e/` puede quedar temporalmente desactualizada respecto a `dev` entre releases; ponerla al día es parte del PR a `main` (lote del e2e-runner, bloqueante ahí). El usuario puede seguir invocando E2E puntual en dev cuando lo pida explícitamente.

Para el PR a main, la regla original aplica íntegra:

Antes de aprobar el merge a main de cambios que tocan UI (componentes, páginas, flujos de usuario), **ejecutar el flujo real en un navegador contra el backend levantado** — no basta con tests unitarios ni con verificación por `curl`.

**Por qué es obligatorio:** los tests de frontend mockean `fetch` y corren en jsdom, que NO renderiza CSS, NO aplica `@media`/`@page`, NO ejecuta las reglas nativas de `<dialog>`/top-layer, y NO negocia `Content-Type` real con el servidor. La "verificación en vivo por `curl`" ejercita la API pero nunca la UI. En una sola fase (catálogos) se escaparon a review 3 bugs que ningún test veía: un modal que no cerraba en desktop (CSS sin scope a `[open]`), archivado completamente roto (`Content-Type: application/json` en POST sin body → Fastify lo rechazaba), y un falso positivo de test que afirmaba renderizar un botón que en el DOM real no estaba.

**Cómo aplicar:**
- **Preferente:** invocar `e2e-runner` sobre el flujo del PR (crea/corre tests Playwright contra los servicios en Docker). Bloqueante si falla.
- **Mínimo:** manejar el flujo en un navegador real (extensión de browser o Playwright manual) contra `docker compose up` — ejercitar happy path + las mutaciones (crear, editar, archivar/deshacer) y confirmar en el DOM real, no solo en screenshot.
- **Distinguir bug de código vs bundle stale:** si algo no se ve/comporta como el código fuente dice, reiniciar el contenedor de frontend (HMR + service worker de PWA pueden servir módulos viejos tras muchos pushes) y re-verificar ANTES de escalar al dev. No mandar a "arreglar" código correcto.
- Restaurar datos de seed (`db:seed`) si la verificación ensució el entorno de dev.

**Qué NO requiere E2E real:** PRs sin superficie de UI (backend puro, migraciones, docs, config). Ahí basta con tests + la verificación en vivo por `curl`/API que ya hacen los devs.

## 3. NUNCA mergear sin aprobación explícita del usuario

Aunque CI esté verde y los reviewers aprueben sin blockers, **no ejecutar `gh pr merge` hasta que el usuario diga "mergea" o equivalente**.

**Por qué:** el usuario quiere ser el checkpoint final. Cada merge es una decisión que afecta la rama destino — debe ser explícita, no inferida del estado de CI/reviews.

**Cómo aplicar:**
- Cuando CI pasa y reviewers aprueban, informar al usuario "PR listo para tu review" + link
- Esperar respuesta explícita antes de mergear
- Si el usuario dice "mergea X y Y", validar uno a la vez. En PRs a `main` cada merge invalida los demás (branch protection estricta); en PRs a `dev` no, porque `dev` no exige branch up-to-date (ver regla 5)

## 4. NUNCA mergear con CI en rojo

Si algún CI workflow falla (lint, test, security scan, codeql, semgrep, dependency-audit), NO mergear — aunque el finding parezca preexistente o un falso positivo.

**Por qué:** un blocker es un blocker. Mergear con CI rojo argumentando "es preexistente" rompe el contrato del status check y normaliza fallos. Si es falso positivo legítimo, agregar la supresión correspondiente y esperar que CI pase.

**Cómo aplicar:**
1. Verificar que TODOS los workflows pasaron antes de `gh pr merge`
2. Si alguno falla, arreglarlo primero — no usar `--admin` para saltarlo
3. Falso positivo → suprimir formalmente + re-correr CI
4. Solo después de todo verde, mergear (con aprobación del usuario per regla 3)

## 5. Presupuesto de CI (repos privados)

**Decisión del usuario 2026-07-19:** los repos son privados y los minutos de GitHub Actions se agotaron en 15 días (3000 min/mes del plan Pro). Cada push a un PR cuesta un run completo de CI, así que el workflow minimiza runs sin sacrificar los gates de calidad. Se descartó el self-hosted runner — la estrategia es optimizar consumo en runners de GitHub.

### 5.1 Docs viaja en el push inicial

El agente `docs` se invoca **después del último lote y ANTES del push + PR** (Fase 2.5 del flujo). Lee el diff local contra la base (`git diff <base>...HEAD`), commitea al branch y NO pushea. Tras su commit viene el review dual local (Fase 2.6, regla 2) y recién entonces el push inicial que abre el PR — con docs, fixes del review y registro incluidos.

**Por qué:** el orden anterior (docs después de CI verde) generaba un push extra → un run completo de CI solo por documentación, en cada PR.

### 5.2 Un push por ronda de review post-PR, nunca por fix

Las rondas pre-PR (Fase 2.6) **no pushean nada**: los fixes quedan commiteados y viajan en el push inicial. Un-push-por-ronda aplica a las rondas **post-PR** (re-reviews de Fase 3 y reviews sobre PR existente): al cerrar una ronda, consolidar en un **solo push** fixes de blockers de todos los reviewers + sugerencias no bloqueantes auto-aplicadas (regla 2). Nunca pushear fix por fix ni reviewer por reviewer — el orchestrator acumula los commits de los devs y pushea una vez cuando la ronda está completa.

### 5.3 Reproducir localmente antes de re-push en ciclos de fix de CI

Cuando CI falla, el dev (o `build-resolver`) debe **reproducir el check fallido localmente y verlo pasar** antes de pushear el fix. Un run fallido cuesta los mismos minutos que uno verde; CI verifica, no descubre.

**Alcance de la excepción de push directo:** el dev solo pushea directo dentro del ciclo de fix de CI (Fase 2.8). En rondas de review post-PR nunca — ahí siempre consolida el orchestrator (regla 5.2) — y en las pre-PR (Fase 2.6) no pushea nadie. La otra excepción de push del dev es el fallback de budget agotado (ver `rulebooks/agent-budget.md`).

### 5.4 Scans pesados solo en pre-release + schedule

CodeQL, Semgrep y dependency-audit **NO corren en PRs a `dev`** — ahí solo lint + tests + build. Corren en:

- **PRs a `main`** (pre-release) — bloqueantes, como siempre. **Bloqueante de verdad**: los jobs de `security.yml` deben estar enumerados en `required_status_checks.contexts` de la protection de `main` — un scan que corre pero no está listado es informativo y no impide el merge
- **Schedule semanal** (cron) sobre `dev` — con checkout `ref: dev` explícito (los crons corren sobre el default branch)

**Cobertura que se mantiene:** el `security-reviewer` (agente) sigue revisando cada cambio con su checklist — pre-push, en la Fase 2.6 (regla 2) — así que ningún PR entra a `dev` sin revisión de seguridad — solo se mueve el scan automatizado caro al punto de release.

**Respuesta a hallazgos del scan semanal** (un scan cuya salida nadie procesa no acota ninguna ventana):

- Finding HIGH/CRITICAL → crear issue de inmediato (label `security`) y tratarlo como trabajo prioritario de la siguiente sesión
- Mientras exista un HIGH/CRITICAL abierto proveniente del scan, **el próximo PR a `main` está bloqueado** hasta resolverlo o suprimirlo formalmente como falso positivo
- Findings menores → issue de triage agrupado, se procesan como deuda

### 5.5 Workflows eficientes (obligatorio en todos los repos)

Todo workflow de Actions debe tener:

- **`concurrency` por ref con `cancel-in-progress: true`** — un push nuevo al PR cancela el run anterior obsoleto
- **`timeout-minutes`** explícito en cada job — un job colgado no quema la bolsa de minutos
- **Cache de dependencias** (`actions/setup-node` con `cache`, `actions/cache` para pip, etc.)
- Runners `ubuntu-latest` — macOS cuesta 10× minutos, Windows 2×

### 5.6 Branch protection: `dev` sin up-to-date, `main` estricto

- **`dev`**: status checks obligatorios, **SIN** "require branches to be up to date". Mergear un PR no invalida los demás en cola → desaparece el loop `update-branch → CI re-run` por PR.
- **`main`**: estricto completo (checks + up-to-date). Los PRs a `main` son releases: ahí la combinación exacta sí se testea antes de mergear, y son pocos.

**Mitigación del riesgo en `dev`:** un conflicto semántico entre dos PRs (cada uno verde por separado, rotos combinados) se detecta minutos después del merge porque `ci.yml` también corre en push a `dev`. `dev` es rama de integración — romperla un rato es tolerable y el fix es barato.

### 5.7 La retro viaja en el branch del PR

La retro (`.planning/learnings/PR-<N>.md`, un archivo por PR) se escribe en la Fase 4 y se commitea **en el branch del PR, como último commit antes del merge**. Nunca en un PR aparte. En modo multi-PR, un archivo por PR mergeado.

**Por qué:** un PR solo para la retro paga un run completo de CI y una ronda de PR sin cambiar una línea de código. Medido: el PR #179 de easy-quotes — 47 líneas de markdown bajo `.planning/` — disparó 7m23s de runners con backend, frontend, docker-prod y core-isolation completos. Es el mismo modo de falla que la regla 5.1 corrigió para docs, con la retro afuera.

**Costo residual:** el push de la retro es el último del branch y cuesta un run mientras el workflow corra las suites para cualquier diff. Un filtro de "diff sin código (`.planning/**`) → sin suites", con el job agregador reportando verde para que branch protection no se quede esperando, lo baja a segundos.

## Verificación pre-merge

Los 4 checks obligatorios antes de cada merge (threads, reviews, CI y evidencia del review dual pre-push), y el comando de merge según el tipo de branch, están en `rulebooks/orchestrator-runbook.md`, sección "Comandos `gh` específicos".

## Trade-offs aceptados

- **PRs pequeños generan más reviews.** Vale la pena: cada review es rápido (~5 min) y atrapa errores antes de que el usuario los vea.
- **Auto-merge no se usa.** El usuario aprueba cada merge (regla 3). En PRs a `main` aplica además el loop `update-branch + CI wait + merge` por la protection estricta; en `dev` ya no (regla 5.6).
- **El usuario es el checkpoint final.** Significa fricción mínima entre "listo" y "merged", pero garantiza que nada se mergea sin su mirada.
- **La combinación post-merge en `dev` se testea después del merge, no antes.** Costo aceptado a cambio de eliminar el re-run de CI por cada PR en cola (regla 5.6).
- **Vulnerabilidades detectables por scanner pueden vivir en `dev` hasta una semana.** El security-reviewer por PR + scan semanal + scan bloqueante pre-release acotan la ventana; nada llega a `main` sin scan completo (regla 5.4). Incluye a las CVEs de dependencias: en PRs a `dev` el audit lo corre el security-reviewer como check best-effort (no bloqueante); el gate duro de dependencias es el scan semanal y el pre-release.
