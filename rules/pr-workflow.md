# PR Workflow

Reglas de proceso para crear, reviewear y mergear pull requests. Aplican a TODOS los proyectos.

## 1. Una fase = un PR separado

Cada fase de implementación (refactor, feature nueva, bugfix, doc audit) debe ir en su propio branch + PR. No acumular múltiples fases en un solo branch.

**Por qué:** PRs incrementales son más fáciles de reviewear, revertir y trazar. Un mega-PR con 5 cambios distintos toma 10× más tiempo de review y si algo se rompe es imposible bisectar.

**Cómo aplicar:**
- Al iniciar nueva fase: crear `feature/<descripción-corta>` desde la base correcta (típicamente `dev`)
- Implementar la fase completa con TDD + self-reflection
- Abrir PR al terminar
- NO empezar la siguiente fase en el mismo branch — esperar merge primero

**Excepción legítima:** un refactor pequeño necesario para implementar la feature correctamente está dentro del scope. Documentarlo en el PR body.

## 2. Review obligatorio antes de mergear

Después de crear cada PR, lanzar **security-reviewer + qa** (qa-frontend y/o qa-backend según lo que toque) **en paralelo automáticamente, sin pedir confirmación al usuario**.

**Cuándo lanzar:**
- En el mismo turn donde creo el PR, lanzo los agents en paralelo (single message, multiple Agent calls)
- Si el siguiente paso natural es rebuildear dev (Docker, etc.), lanzar el rebuild en paralelo con los reviewers — son independientes
- Reportar findings al usuario después

**Si hay blockers:**
- Fixearlos en el MISMO branch/PR (no abrir uno nuevo)
- Re-correr el agent relevante para validar el fix
- Continuar solo cuando todo verde

**Sugerencias no bloqueantes: aplicarlas en el mismo PR antes de pedir merge.**
Cuando un reviewer marca sugerencias (no bloqueantes) que son baratas, sin riesgo y trazables al scope del PR, aplicarlas en el MISMO branch antes de informar "PR listo para tu review" — no diferirlas ni solo anotarlas. Las que cambien comportamiento, requieran decisión de diseño, o sean scope de otra fase, NO se aplican: se anotan como issue o handoff en `.planning/STATE.md`. Después de aplicar, re-correr solo el reviewer que las marcó (o los tests si es cambio menor).

**Por qué:** el patrón "aplicar sugerencias en el mismo PR" apareció en 4 PRs consecutivos como decisión manual del usuario. Formalizarlo evita el ida-y-vuelta de pedir permiso para cada mejora obvia. El usuario sigue siendo el checkpoint del **merge** (regla 3), no de cada pulido.

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

### Checklist de infraestructura del security-reviewer

Vive en `agents/security-reviewer.md`, sección "Checklist de infraestructura". La instrucción va en el prompt del agente que la ejecuta, no en este documento de proceso.

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

El agente `docs` se invoca **después del último lote y ANTES del push + PR** (Fase 2.5 del flujo). Lee el diff local contra la base (`git diff <base>...HEAD`), commitea al branch y NO pushea. Su commit sale en el push inicial que abre el PR.

**Por qué:** el orden anterior (docs después de CI verde) generaba un push extra → un run completo de CI solo por documentación, en cada PR.

### 5.2 Un push por ronda de review, nunca por fix

Al cerrar una ronda de review, consolidar en un **solo push**: fixes de blockers de todos los reviewers + sugerencias no bloqueantes auto-aplicadas (regla 2). Nunca pushear fix por fix ni reviewer por reviewer — el orchestrator acumula los commits de los devs y pushea una vez cuando la ronda está completa.

### 5.3 Reproducir localmente antes de re-push en ciclos de fix de CI

Cuando CI falla, el dev (o `build-resolver`) debe **reproducir el check fallido localmente y verlo pasar** antes de pushear el fix. Un run fallido cuesta los mismos minutos que uno verde; CI verifica, no descubre.

**Alcance de la excepción de push directo:** el dev solo pushea directo dentro del ciclo de fix de CI (Fase 2.8). En rondas de review (Fase 3) nunca — ahí siempre consolida el orchestrator (regla 5.2).

### 5.4 Scans pesados solo en pre-release + schedule

CodeQL, Semgrep y dependency-audit **NO corren en PRs a `dev`** — ahí solo lint + tests + build. Corren en:

- **PRs a `main`** (pre-release) — bloqueantes, como siempre. **Bloqueante de verdad**: los jobs de `security.yml` deben estar enumerados en `required_status_checks.contexts` de la protection de `main` — un scan que corre pero no está listado es informativo y no impide el merge
- **Schedule semanal** (cron) sobre `dev` — con checkout `ref: dev` explícito (los crons corren sobre el default branch)

**Cobertura que se mantiene:** el `security-reviewer` (agente) sigue revisando cada PR con su checklist (regla 2), así que ningún PR entra a `dev` sin revisión de seguridad — solo se mueve el scan automatizado caro al punto de release.

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

## Trade-offs aceptados

- **PRs pequeños generan más reviews.** Vale la pena: cada review es rápido (~5 min) y atrapa errores antes de que el usuario los vea.
- **Auto-merge no se usa.** El usuario aprueba cada merge (regla 3). En PRs a `main` aplica además el loop `update-branch + CI wait + merge` por la protection estricta; en `dev` ya no (regla 5.6).
- **El usuario es el checkpoint final.** Significa fricción mínima entre "listo" y "merged", pero garantiza que nada se mergea sin su mirada.
- **La combinación post-merge en `dev` se testea después del merge, no antes.** Costo aceptado a cambio de eliminar el re-run de CI por cada PR en cola (regla 5.6).
- **Vulnerabilidades detectables por scanner pueden vivir en `dev` hasta una semana.** El security-reviewer por PR + scan semanal + scan bloqueante pre-release acotan la ventana; nada llega a `main` sin scan completo (regla 5.4). Incluye a las CVEs de dependencias: en PRs a `dev` el audit lo corre el security-reviewer como check best-effort (no bloqueante); el gate duro de dependencias es el scan semanal y el pre-release.
