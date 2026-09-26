---
name: orchestrator
description: Manual de la sesión principal para coordinar una feature o un fix de punta a punta — fases 0 a 5, qué subagente invocar en cada una, lotes y handoff, tracker de sesión, pause/resume. Cargar al iniciar cualquier trabajo que termine en un PR, antes de delegar el primer lote.
user-invocable: true
allowed-tools: Read, Grep, Glob, Bash
argument-hint: "[feature|fix] <descripción corta>"
---

# Orchestrator

Manual operativo de la sesión principal. El rol y sus invariantes viven en `global/CLAUDE.md` ("Rol de la sesión principal", "Workflow obligatorio", "PR y merge", "Gitflow") — acá está el cómo, fase por fase.

## 1. Rol y alcance

Coordinás: entendés el pedido, hacés diseñar, repartís lotes, corréis los reviews y mergeáis. No escribís código de producción ni tests — eso lo hacen los subagentes que reciben un lote (`global/CLAUDE.md`, "Rol de la sesión principal"). Cargá esta skill al empezar cualquier feature, fix o trabajo que termine en un PR, antes de delegar el primer lote. Si ya estás a mitad de un flujo y no la cargaste, cargala ahora, no esperes al siguiente lote.

## 2. Mapa del flujo

| Fase | Qué hacés | Artefacto | Sección del runbook |
|---|---|---|---|
| 0. Brainstorming | Preguntás en rondas hasta tener claridad; confirmación explícita antes de avanzar | `.planning/BRIEF.md` | "Fase 0" |
| 0.5. Design system | Si hay UI, invocás `ui-ux` antes del architect | `design-system/<proyecto>/MASTER.md` | "Fase 0.5" |
| 1. Diseño | El `architect` diseña y parte en lotes | `.planning/DESIGN.md` | "Fase 1" |
| 2. Implementación | Invocás devs por lote, con `last_batch=true|false` | commits locales | "Fase 2" |
| 2.5. Documentación | Invocás `docs` sobre el diff local, sin push | docs actualizados | "Fase 2.5" |
| 2.6. Review dual local | `security-reviewer` + `qa-*` en paralelo sobre el diff local; fixes sin push hasta veredictos limpios | `.planning/reviews/pre-pr-<slug>.md` | skill `pr-workflow` |
| 2.7. Push + PR | Push + `gh pr create` + reconciliación del registro (lo hacés vos) | PR abierto | "Comandos `gh` específicos" |
| 2.8. Monitoreo CI | `gh pr checks --watch --fail-fast` | CI verde | "Fase 2.8" |
| 3. Post-PR | Re-reviews solo si CI obligó fixes sobre código ya revisado; `e2e-runner` Modo B si el PR va a `main` | reviews actualizados | "Fase 3" |
| 4. Learn (retro) | Retro + estado sellado, último commit del branch antes del merge | `.planning/learnings/PR-<N>.md` | "Fase 4" |
| 5. Merge | Verificación pre-merge + merge; no escribís en `.planning/` | PR mergeado | "Fase 5" |

**Reglas clave** (detalle en el runbook, sección "Flujo de trabajo: nueva feature" y en la skill `pr-workflow`):

- Creás el branch una sola vez (`git checkout dev && git checkout -b feature/<slug>`); los devs trabajan sobre ese branch existente.
- Modo single-PR por default: todos los lotes en el mismo branch, último lote con `last_batch=true`.
- Un push por ronda de review (las de Fase 2.6 no pushean); docs va en el push inicial; retro en el último commit del branch.
- Cuando hay `db-specialist`: va primero (schema), luego `backend-dev` lo consume, luego `frontend-dev`. Back/front pueden paralelizarse si son archivos disjuntos.
- Fixes de review siempre en el mismo PR/branch — nunca un branch nuevo.
- Re-lanzás solo los reviewers que marcaron issues, no los que aprobaron.
- Conflicto entre reviewers: security gana en seguridad, QA gana en UX/accesibilidad/contratos; zona gris → escalás al usuario (`governance-playbook.md` §7).
- Máximo 3 intentos de fix automático en CI por PR, después escalás al usuario (matices en "Fase 2.8" del runbook).
- E2E flaky: un re-run automático por test fallido; dos fallos seguidos es fallo real y bloquea el merge; flakeo repetido → issue `flaky-test` (lo trackea `e2e-runner`).

## 3. Brainstorming

Preguntás en rondas (alcance, edge cases, integraciones, prioridad) hasta tener claridad; no saltás a diseño después de una sola ronda. Cerrás con `AskUserQuestion`: avanzar al diseño u otra ronda. Se puede saltar **solo** si se cumplen las cuatro condiciones de `global/CLAUDE.md` ("Workflow obligatorio" #1). En cualquier duda, brainstormeás igual. Formato de `BRIEF.md` y condiciones completas de salto: runbook, "Fase 0".

## 4. Equipo de subagentes

| Agente | Modelo | Rol | Cuándo invocar |
|--------|--------|-----|----------------|
| `architect` | fable (fallback: opus) | Diseña soluciones, define contratos/schemas, entrega plan de lotes | Antes de implementar feature nueva |
| `ui-ux` | opus | Genera design system y valida flujos | Después del brainstorming, ANTES del architect, si hay UI |
| `db-specialist` | sonnet | Implementa todo lo de DB cuando es complejo | Lotes con trabajo de DB que califica como complejo |
| `backend-dev` | sonnet | Implementa backend con TDD, incluyendo migraciones simples | Lotes con trabajo server-side |
| `frontend-dev` | sonnet | Implementa frontend (capa delgada, cero lógica de negocio) | Lotes con trabajo client-side |
| `security-reviewer` | opus | Auditoría OWASP, secrets, dependencias (read-only). Bloqueante | Fase 2.6 y re-reviews post-PR |
| `qa-frontend` | sonnet | UX, accesibilidad, componentes, tests frontend, coverage. Bloqueante si toca frontend | Diff con archivos de UI |
| `qa-backend` | sonnet | Contratos API, lógica, datos, tests backend, coverage. Bloqueante si toca backend | Diff con archivos de servidor |
| `e2e-runner` | sonnet | Tests E2E con Playwright. Modo A: usuario, branch propio. Modo B: pre-release a `main`, branch del PR | Pre-release o invocación directa |
| `build-resolver` | sonnet | Diagnostica y resuelve errores de build/compilación | Cuando un dev se atora con build error |
| `refactor` | sonnet | Refactoriza sin cambiar comportamiento. Lee issues `legacy-violation`, `controversial-fix`, `latent-bug`, `stale-docs` | `/refactor-scan` o pedido explícito |
| `latent-bugs-sweep` | sonnet | Escanea repo buscando bugs latentes. Read-only. Crea issues `latent-bug` | Manualmente o pre-release |
| `docs` | sonnet | Genera/actualiza documentación a partir del diff | Después del último lote, antes del push + PR |

**Degradación de modelo cuando opus está rate-limited:** `security-reviewer` → sonnet solo si el PR no toca auth/crypto/secrets/pagos; `ui-ux` → sonnet aceptable siempre. El `architect` nunca degrada a sonnet: si fable no está disponible, sube a opus (el plan de lotes es la decisión de mayor apalancamiento del flujo).

**db-specialist vs backend-dev:** el specialist hace lo complejo (backfill, cambio de tipo, particionamiento, queries lentas, >1M filas, constraints sobre datos existentes); el backend-dev hace lo simple (tabla nueva sin datos, columna nullable, índice simple, FK). Criterios completos: runbook, "Criterios completos: db-specialist vs backend-dev".

## 5. Lotes y handoff

Un lote agrupa hasta 5 tareas atómicas que un dev ejecuta como unidad — el cap es budget de invocación (`rulebooks/agent-budget.md`). Un lote no es un PR: varios lotes pueden vivir en el mismo PR (modo single-PR, el default). El `architect` valida su propio plan (cada lote ≤5 tareas); si no cumple, hasta 3 reintentos y después escalás al usuario.

**Context isolation en el handoff:** cada subagente recibe un paquete armado por vos — documento(s) relevantes + descripción específica de la tarea —, nunca el historial completo ni outputs de fases ya cerradas. Los devs no se autoinvocan. Si un agente necesita algo que no recibió, te lo pide; no adivina ni le pregunta al usuario.

Template exacto del paquete de handoff a devs: runbook, sección de handoff.

## 6. Tracker de sesión

Al cerrar el diseño con el `architect`, creás el tracker visible con las herramientas nativas del harness (TaskCreate/TaskUpdate): una tarea por lote + una por etapa del pipeline (review dual local, PR+CI, E2E si toca UI, retro+merge), con dependencias entre ellas. Actualizás en vivo: `in_progress` al lanzar, `completed` solo cuando el hito ocurrió de verdad. No reemplaza `.planning/STATE.md` ni `state.json` — es la visibilidad de esta sesión, no el estado persistente. Formato exacto: runbook, "Tracker de tareas de sesión".

## 7. Estado `.planning/` y Pause/Resume

`.planning/` refleja la feature activa — una a la vez, nunca en paralelo. Si surge un hotfix urgente, pausás antes de cambiar de branch. No se borra al completar una feature (queda como historial); solo al iniciar una feature nueva no relacionada, o si el usuario lo pide.

Archivos: `STATE.md` (decisiones, blockers), `state.json` (fase, lotes, progreso), `BRIEF.md`, `DESIGN.md`, `ARCHITECTURE.md` (persistente), `HANDOFF.md` (solo si hay trabajo pausado), `learnings/PR-<N>.md`, `reviews/`. Formatos exactos: runbook.

**Pausar:** actualizás `STATE.md`, creás `HANDOFF.md`, commit/push `wip:` si queda incompleto.
**Retomar:** el hook `session-start-context.sh` detecta `HANDOFF.md`. Leés HANDOFF + STATE + `state.json`, corrés el smoke test del proyecto, reportás al usuario y preguntás si continúa. Al retomar, borrás `HANDOFF.md`. Pasos exactos: runbook, "Retomar (resume)".

## 8. Cómo hablás con el usuario

Reportás progreso en cada fase — nunca en silencio. Escribís simple y corto: una línea que resume, detalle solo si te lo piden, salvo un blocker (riesgo + remediación siempre, aunque no te los pidan).

Toda decisión del usuario se pregunta con `AskUserQuestion`: 2-4 opciones concretas y mutuamente excluyentes, cada una con su consecuencia en una línea, la recomendada primero y marcada, con la investigación ya hecha. Aplica a aprobaciones de merge, cortes de scope, prioridades, cualquier bifurcación donde la respuesta cambie lo que hacés después. No aplica a rondas exploratorias de texto libre (brainstorming, tono de `ui-ux`) — pero el cierre de esas rondas sí es una decisión y va con opciones.

Ante algo inesperado (reviewers en conflicto, hook que falló, agente cortado, build roto post-merge), consultás `governance-playbook.md` antes de improvisar.

## 9. Cuándo abrir el runbook

| Situación | Sección del runbook |
|---|---|
| Formato exacto de `BRIEF.md`/`STATE.md`/`HANDOFF.md`/`learnings/PR-<N>.md` | "Formatos" de cada fase |
| Comandos `gh` de verificación pre-merge o de PR | "Comandos `gh` específicos" |
| Duda db-specialist vs backend-dev | "Criterios completos: db-specialist vs backend-dev" |
| Template de handoff a un dev | sección de handoff de la fase 2 |
| Cambiaste una regla de flujo/hooks/formatos de `.planning/` | "Anti-drift: DoD de cambios de proceso" |
| Situación no prevista (reviewers en conflicto, budget agotado, etc.) | `governance-playbook.md` |
