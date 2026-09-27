---
name: pr-workflow
description: Proceso de review, creación y merge de pull requests — review dual local pre-push, presupuesto de CI, verificación E2E pre-release, branch protection y verificación pre-merge. Invocar al llegar a Fase 2.6 (review dual local, antes del push + PR) o al revisar/mergear un PR existente.
user-invocable: true
allowed-tools: Read, Grep, Glob, Agent(methodology:security-reviewer), Agent(methodology:qa-frontend), Agent(methodology:qa-backend), Agent(methodology:e2e-runner)
argument-hint: "[número de PR, si es sobre uno existente]"
---

# PR Workflow

Proceso para crear, reviewear y mergear pull requests. Aplica a TODOS los proyectos.

Las cuatro reglas invariantes (un PR por objetivo con commits atómicos por tarea, review dual bloqueante, nunca mergear sin aprobación explícita, nunca mergear con CI en rojo) viven en `CLAUDE.md` porque no pueden llegar tarde. Este documento tiene el detalle operativo.

## 1. Un PR por unidad coherente, commits atómicos por tarea

Varias fases que persiguen el mismo objetivo viajan en **un solo PR**, con **un commit por tarea** (un comportamiento/una idea = un commit; nunca un commit gigante — destruye la trazabilidad).

**Cómo aplicar:** un branch por objetivo, no por fase; las fases se acumulan ahí como series de commits atómicos. El PR body lista las fases con un párrafo cada una, para que el reviewer navegue commit por commit.

**Cuándo SÍ separar en PRs distintos** (cualquiera de estas basta):

- **Refactor y feature nunca se mezclan.** Sigue siendo intocable: un refactor colateral dentro de un PR de feature hace irrevisable el diff.
- El trabajo es **genuinamente independiente y shippeable solo** — podría ir a `dev` sin lo demás.
- El diff se vuelve irrevisable: **>1000 LoC de naturaleza mixta que el PR body no logra agrupar de forma navegable**; el número de commits atómicos no es señal de corte.
- Una fase **depende del review de la anterior** para decidir su alcance. Si el feedback puede cambiar lo que viene, no lo adelantes.
- El riesgo de revert es asimétrico: una fase que quizás haya que revertir sola no debe arrastrar a las demás.

**Excepción legítima:** un refactor pequeño necesario para implementar la feature correctamente está dentro del scope. Documentarlo en el PR body.

## 2. Review dual local antes del push (Fase 2.6)

Al terminar docs (Fase 2.5), lanzar **security-reviewer + qa** (qa-frontend y/o qa-backend según lo que toque el diff) **sobre el diff local (`git diff <base>...HEAD`), en paralelo automáticamente, sin pedir confirmación al usuario** — ANTES del push y de crear el PR. Las rondas de fixes ocurren sin pushear nada: **el PR nace revisado** y el caso normal cuesta un solo run de CI.

**Cuándo y cómo lanzar:** en el mismo turn donde cierro Fase 2.5 (docs commiteado), lanzo los agents en paralelo (single message, multiple Agent calls). Son subagentes locales: leen el working tree con `git diff <base>...HEAD` — no necesitan el branch pusheado ni número de PR. Reporto findings al usuario después (detalle operativo — presupuesto, paquete de contexto, registro — en `rulebooks/orchestrator-runbook.md`, Fase 2.6).

**Si hay blockers:** los fixea el dev correspondiente en el MISMO branch, sin push; re-corro solo los reviewers que marcaron issues, acotados al delta local; avanzo a Fase 2.7 solo cuando todo verde.

**Sugerencias no bloqueantes: aplicarlas antes del push.**
Cuando un reviewer marca sugerencias (no bloqueantes) que son baratas, sin riesgo y trazables al scope del diff, aplicarlas en el MISMO branch antes del push inicial — no diferirlas ni solo anotarlas. Las que cambien comportamiento, requieran decisión de diseño, o sean scope de otra fase, NO se aplican: se anotan como issue o handoff en `.planning/STATE.md`. Después de aplicar, re-correr solo el reviewer que las marcó (o los tests si es cambio menor). Fixes, sugerencias aplicadas y registro del review viajan en el push inicial.

**Post-PR solo hay re-reviews condicionales** (Fase 3): únicamente si CI obligó fixes que cambian código ya revisado — acotados al delta del fix, re-lanzando solo los reviewers de la capa afectada. Si CI pasó a la primera, no se relanza nada.

El usuario sigue siendo el checkpoint del **merge** (invariante 3 de `global/CLAUDE.md`), no de cada pulido.

El checklist de infraestructura que el security-reviewer debe correr (rate limiting, shell injection, prototype pollution, reflected input) vive en `agents/security-reviewer.md`, en el prompt del agente que lo ejecuta.

**Caso remoto (excepción):** si un reviewer corre en un entorno cloud/aislado que necesita clonar el repo, está permitido pushear el branch **sin crear PR** antes del review, con esta **condición verificable**: ningún workflow del repo dispara con `on: push` sobre branches que matcheen `feature/*`/`hotfix/*` (verificar con grep de los triggers en `.github/workflows/*.yml` antes del push; bajo el scaffold de `new-project` se cumple siempre). Flujo: push del branch (0 runs) → review remoto → fixes locales → push de fixes (0 runs) → `gh pr create` (primer y único run). Si la condición NO se cumple: corregir el trigger (filtro de branches) o caer al modo local — nunca pagar runs por review. El default del flujo es siempre el modo local.

### Verificación E2E real obligatoria en PRs a main (pre-release)

**Decisión del usuario 2026-07-19:** la verificación E2E completa (suite Playwright + flujos en navegador real) es obligatoria y bloqueante **solo en PRs a `main`** (pre-release). En PRs de feature a `dev` NO se corre E2E por default — basta con security + qa + tests unitarios + build. Razón: el ciclo dev es más ágil sin el gate más caro; la suite E2E se actualiza y corre una sola vez por release, contra el acumulado.

Consecuencia aceptada: la suite `e2e/` puede quedar temporalmente desactualizada respecto a `dev` entre releases; ponerla al día es parte del PR a `main` (lote del e2e-runner, bloqueante ahí). El usuario puede seguir invocando E2E puntual en dev cuando lo pida explícitamente.

Para el PR a main, la regla original aplica íntegra:

Antes de aprobar el merge a main de cambios que tocan UI (componentes, páginas, flujos de usuario), **ejecutar el flujo real en un navegador contra el backend levantado** — no basta con tests unitarios ni con verificación por `curl`.

**Por qué es obligatorio:** los tests de frontend mockean `fetch` y corren en jsdom, que NO renderiza CSS, NO aplica `@media`/`@page`, NO ejecuta las reglas nativas de `<dialog>`/top-layer, y NO negocia `Content-Type` real con el servidor. La "verificación en vivo por `curl`" ejercita la API pero nunca la UI. En una sola fase (catálogos) se escaparon a review 3 bugs que ningún test veía: un modal que no cerraba en desktop (CSS sin scope a `[open]`), archivado completamente roto (`Content-Type: application/json` en POST sin body → Fastify lo rechazaba), y un falso positivo de test que afirmaba renderizar un botón que en el DOM real no estaba.

**Cómo aplicar:** preferente, invocar `e2e-runner` sobre el flujo del PR (crea/corre tests Playwright contra los servicios en Docker), bloqueante si falla; mínimo, manejar el flujo en un navegador real contra `docker compose up` — happy path + mutaciones, confirmadas en el DOM real, no en screenshot. Si algo no se ve como el código dice, reiniciar el contenedor de frontend (HMR/service worker sirven módulos viejos) y re-verificar antes de escalar. Restaurar datos de seed si la verificación ensució el entorno de dev.

**Qué NO requiere E2E real:** PRs sin superficie de UI (backend puro, migraciones, docs, config). Ahí basta con tests + la verificación en vivo por `curl`/API que ya hacen los devs.

## 3. Presupuesto de CI (repos privados)

Los minutos de Actions son finitos; el flujo minimiza runs sin sacrificar los gates de calidad.

### 3.1 Docs viaja en el push inicial

El agente `docs` se invoca **después del último lote y ANTES del push + PR** (Fase 2.5). Lee el diff local, commitea al branch y NO pushea — viaja en el push inicial junto con el review (Fase 2.6). Evita un run de CI extra solo por documentación.

### 3.2 Un push por ronda de review post-PR, nunca por fix

Las rondas pre-PR (Fase 2.6) **no pushean nada**: los fixes viajan en el push inicial. Post-PR (re-reviews de Fase 3, reviews sobre PR existente): al cerrar una ronda, consolidar en un **solo push** los fixes de todos los reviewers + sugerencias auto-aplicadas. Nunca pushear fix por fix — el orchestrator acumula y pushea una vez que la ronda está completa.

### 3.3 Reproducir localmente antes de re-push en ciclos de fix de CI

Cuando CI falla, el dev debe **reproducir el check fallido localmente y verlo pasar** antes de pushear el fix (build, con `rulebooks/build-errors.md`). El dev solo pushea directo dentro del ciclo de fix de CI (Fase 2.8) — en rondas post-PR siempre consolida el orchestrator (regla 3.2), en pre-PR no pushea nadie. La otra excepción es el fallback de budget agotado (`rulebooks/agent-budget.md`).

### 3.4 Scans pesados solo en pre-release + schedule

CodeQL, Semgrep y dependency-audit **NO corren en PRs a `dev`** — ahí solo lint + tests + build. Corren en PRs a `main` (pre-release, bloqueantes — los jobs de `security.yml` deben estar en `required_status_checks.contexts` de `main`) y en schedule semanal (cron) sobre `dev` con checkout `ref: dev` explícito. El `security-reviewer` (agente) sigue revisando cada cambio pre-push en Fase 2.6, así que ningún PR entra a `dev` sin revisión de seguridad — solo el scan automatizado caro se mueve al release.

**Respuesta a hallazgos del scan semanal**: HIGH/CRITICAL → issue inmediato (label `security`), prioritario en la siguiente sesión, y bloquea el próximo PR a `main` hasta resolverlo o suprimirlo como falso positivo. Findings menores → issue de triage agrupado, deuda.

### 3.5 Workflows eficientes (obligatorio en todos los repos)

Todo workflow de Actions debe tener:

- **`concurrency` por ref con `cancel-in-progress: true`** — un push nuevo al PR cancela el run anterior obsoleto
- **`timeout-minutes`** explícito en cada job — un job colgado no quema la bolsa de minutos
- **Cache de dependencias** (`actions/setup-node` con `cache`, `actions/cache` para pip, etc.)
- Runners `ubuntu-latest` — macOS cuesta 10× minutos, Windows 2×

### 3.6 Branch protection: `dev` sin up-to-date, `main` estricto

- **`dev`**: status checks obligatorios, **SIN** "require branches to be up to date". Mergear un PR no invalida los demás en cola → desaparece el loop `update-branch → CI re-run` por PR.
- **`main`**: estricto completo (checks + up-to-date). Los PRs a `main` son releases: ahí la combinación exacta sí se testea antes de mergear, y son pocos.

**Mitigación del riesgo en `dev`:** un conflicto semántico entre dos PRs (cada uno verde por separado, rotos combinados) se detecta minutos después del merge porque `ci.yml` también corre en push a `dev`. `dev` es rama de integración — romperla un rato es tolerable y el fix es barato.

## Verificación pre-merge

Los 3 checks obligatorios antes de cada merge (threads, reviews y CI), y el comando de merge según el tipo de branch, están en `rulebooks/orchestrator-runbook.md`, sección "Comandos `gh` específicos".

## Trade-offs aceptados

- **PRs pequeños generan más reviews.** Vale la pena: cada review es rápido (~5 min) y atrapa errores antes de que el usuario los vea.
- **Auto-merge no se usa.** El usuario aprueba cada merge (invariante 3 de `global/CLAUDE.md`). En PRs a `main` aplica además el loop `update-branch + CI wait + merge` por la protection estricta; en `dev` ya no (regla 3.6).
- **El usuario es el checkpoint final.** Significa fricción mínima entre "listo" y "merged", pero garantiza que nada se mergea sin su mirada.
- **La combinación post-merge en `dev` se testea después del merge, no antes.** Costo aceptado a cambio de eliminar el re-run de CI por cada PR en cola (regla 3.6).
- **Vulnerabilidades detectables por scanner pueden vivir en `dev` hasta una semana.** El security-reviewer por PR + scan semanal + scan bloqueante pre-release acotan la ventana; nada llega a `main` sin scan completo (regla 3.4). Incluye a las CVEs de dependencias: en PRs a `dev` el audit lo corre el security-reviewer como check best-effort (no bloqueante); el gate duro de dependencias es el scan semanal y el pre-release.
