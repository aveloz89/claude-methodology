---
name: orchestrator
description: Manual de la sesión principal para coordinar una feature o un fix de punta a punta — fases 0 a 5, qué subagente invocar en cada una, lotes y handoff, tracker de sesión, pause/resume. Cargar al iniciar cualquier trabajo que termine en un PR, antes de delegar el primer lote.
user-invocable: true
allowed-tools: Read, Grep, Glob, Agent(methodology:architect), Agent(methodology:ui-ux), Agent(methodology:backend-dev), Agent(methodology:frontend-dev), Agent(methodology:docs), Agent(methodology:security-reviewer), Agent(methodology:qa-frontend), Agent(methodology:qa-backend), Agent(methodology:e2e-runner), Agent(methodology:code-sweep)
argument-hint: "[feature|fix] <descripción corta>"
---

# Orchestrator

Manual operativo de la sesión principal. El rol y sus invariantes viven en `global/CLAUDE.md` ("Rol de la sesión principal", "Workflow obligatorio", "PR y merge", "Gitflow") — acá está el cómo, fase por fase.

## 1. Rol y alcance

El rol y sus invariantes viven en `global/CLAUDE.md`, sección "Rol de la sesión principal" — no lo redefinimos acá para que no diverja. Carga esta skill al empezar cualquier feature, fix o trabajo que termine en un PR, antes de delegar el primer lote. Si ya estás a mitad de un flujo y no la cargaste, cárgala ahora, no esperes al siguiente lote.

## 2. Mapa del flujo

| Fase | Qué haces | Artefacto | Sección del runbook |
|---|---|---|---|
| 0. Brainstorming | Preguntas en rondas hasta tener claridad; confirmación explícita antes de avanzar | `.planning/BRIEF.md` | "Fase 0" |
| 0.5. Design system | Invocas `ui-ux` solo si no existe `MASTER.md` o el brief trae página crítica/patrón nuevo; si no, el `architect` referencia `MASTER.md` | `design-system/<proyecto>/MASTER.md` | "Fase 0.5" |
| 1. Diseño | El `architect` diseña y parte en lotes | `.planning/DESIGN.md` | "Fase 1" |
| 2. Implementación | Invocas devs por lote, con `last_batch=true|false` | commits locales | "Fase 2" |
| 2.5. Documentación | Invocas `docs` sobre el diff local, sin push; salta `docs` si el diff no toca superficie pública (registra el salto en el body del PR); cambios en hooks, permisos, auth o controles de seguridad siempre invocan `docs` | docs actualizados | "Fase 2.5" |
| 2.6. Review dual local | `security-reviewer` + `qa-*` en paralelo sobre el diff local; fixes sin push hasta veredictos limpios | `.planning/reviews/<slug>.md` | skill `pr-workflow` |
| 2.7. Push + PR | Push + `gh pr create` (lo haces tú) | PR abierto | "Comandos `gh` específicos" |
| 2.8. Monitoreo CI | `gh pr checks --watch --fail-fast` | CI verde | "Fase 2.8" |
| 3. Post-PR | Re-reviews solo si CI obligó fixes sobre código ya revisado; `e2e-runner` Modo B si el PR va a `main` | reviews actualizados | "Fase 3" |
| 5. Merge | Verificación pre-merge + merge; `state.json` local con `phases.merge=done` después del merge | PR mergeado | "Fase 5" |

**Reglas clave** (detalle en el runbook, sección "Fase 2: Implementación", y en la skill `pr-workflow`):

- Creas el branch una sola vez (`git checkout dev && git checkout -b feature/<slug>`); los devs trabajan sobre ese branch existente.
- La `description` de cada dev empieza con `Lote N: ` (§5); los lotes de fixes se añaden a `state.json` con el id siguiente.
- Modo single-PR por default: todos los lotes en el mismo branch, último lote con `last_batch=true`. Modo multi-PR solo si el `architect` lo justificó — cada grupo con su branch + PR propio.
- Un push por ronda de review (las de Fase 2.6 no pushean); docs va en el push inicial.
- Cuando un lote de `backend-dev` es `db-complejo`: va primero (schema), el resto de `backend-dev` lo consume, luego `frontend-dev`. Back/front pueden paralelizarse si son archivos disjuntos.
- Fixes de review siempre en el mismo PR/branch — nunca un branch nuevo.
- Re-lanzas solo los reviewers que marcaron issues, no los que aprobaron.
- Conflicto entre reviewers: security gana en seguridad, QA gana en UX/accesibilidad/contratos; zona gris → escalas al usuario (`governance-playbook.md` §7).
- Máximo 3 intentos de fix automático en CI por PR, después escalas al usuario (matices en "Fase 2.8" del runbook).
- E2E flaky: un re-run automático por test fallido; dos fallos seguidos es fallo real y bloquea el merge; flakeo repetido → issue `flaky-test` (lo trackea `e2e-runner`).
- Si el PR cambia una regla de flujo, hooks o formatos de `.planning/`: grep de los términos afectados en `global/CLAUDE.md`, `README.md`, `rulebooks/`, `agents/`, `skills/` y reconcilia cada mención; enuncia una vez y remite el resto.
- Una lección accionable se convierte al momento en cambio de regla o en issue — no se guarda para después.

## 3. Brainstorming

Preguntas en rondas (alcance, edge cases, integraciones, prioridad) hasta tener claridad; no saltas a diseño después de una sola ronda. La ronda de cierre suma, para features nuevas, tres preguntas obligatorias: **¿vale la pena?** (problema real hoy, alternativa más barata), **resultado esperado** (una frase para el usuario + señal de éxito observable) y **criterios de aceptación medibles** (sí/no). Cierras con `AskUserQuestion`: avanzar al diseño u otra ronda. Se puede saltar **solo** si se cumplen a la vez las cuatro condiciones:

- Bug fix con causa raíz ya identificada, o cambio técnico sin nueva funcionalidad.
- No cambia contratos públicos (API, schema de DB, props de componentes exportados).
- No agrega dependencias nuevas.
- El usuario describió la tarea con precisión suficiente para implementar sin supuestos.

En cualquier duda, brainstormeas igual. Con confirmación explícita, escribes `.planning/BRIEF.md` (formato en el runbook) y avanzas.

## 4. Equipo de subagentes

| Agente | Modelo | Rol | Cuándo invocar |
|--------|--------|-----|----------------|
| `architect` | fable (fallback: opus) | Diseña soluciones, define contratos/schemas, entrega plan de lotes | Antes de implementar feature nueva |
| `ui-ux` | opus | Genera design system y valida flujos | Después del brainstorming, ANTES del architect, si hay UI |
| `backend-dev` | sonnet | Implementa backend con TDD, incluyendo migraciones simples y complejas (lotes `db-complejo`) | Lotes con trabajo server-side |
| `frontend-dev` | sonnet | Implementa frontend (capa delgada, cero lógica de negocio) | Lotes con trabajo client-side |
| `security-reviewer` | opus | Auditoría OWASP, secrets, dependencias (read-only). Bloqueante | Fase 2.6 y re-reviews post-PR |
| `qa-frontend` | sonnet | UX, accesibilidad, componentes, tests frontend, coverage. Bloqueante si toca frontend | Diff con archivos de UI |
| `qa-backend` | sonnet | Contratos API, lógica, datos, tests backend, coverage. Bloqueante si toca backend | Diff con archivos de servidor |
| `e2e-runner` | sonnet | Tests E2E con Playwright. Modo A: usuario, branch propio. Modo B: pre-release a `main`, branch del PR | Pre-release o invocación directa |
| `code-sweep` | sonnet | Escanea el repo: modo `bugs` (issues `latent-bug`) o `smells` (reporte). Read-only | Pedido del usuario, o Fase 3 en PR a `main` |
| `docs` | sonnet | Genera/actualiza documentación a partir del diff | Después del último lote, antes del push + PR |

**Degradación de modelo cuando opus está rate-limited:** `security-reviewer` → sonnet solo si el PR no toca auth/crypto/secrets/pagos; `ui-ux` → sonnet aceptable siempre. El `architect` nunca degrada a sonnet: si fable no está disponible, sube a opus (el plan de lotes es la decisión de mayor apalancamiento del flujo).

**Cuándo un lote es `db-complejo`:** backfill, cambio de tipo, particionamiento, queries lentas, >1M filas, constraints sobre datos existentes — lo sigue haciendo `backend-dev`, marcado y ordenado primero en el plan. Lo simple (tabla nueva sin datos, columna nullable, índice simple, FK) es un lote normal. Criterios completos: runbook, "Cuándo un lote es DB complejo".

## 5. Lotes y handoff

Un lote agrupa hasta 5 tareas atómicas que un dev ejecuta como unidad — el cap es budget de invocación (`rulebooks/agent-budget.md`). Un lote no es un PR: varios lotes pueden vivir en el mismo PR (modo single-PR, el default). El `architect` valida su propio plan (cada lote ≤5 tareas); si no cumple, hasta 3 reintentos y después escalas al usuario.

**Context isolation en el handoff:** cada subagente recibe un paquete que armas tú — documento(s) relevantes + descripción específica de la tarea —, nunca el historial completo ni outputs de fases ya cerradas. Los devs no se autoinvocan. Si un agente necesita algo que no recibió, te lo pide; no adivina ni le pregunta al usuario.

**Clave del lote en la invocación.** Toda invocación de `backend-dev` o `frontend-dev` lleva en la `description` del `Agent` el prefijo exacto `Lote N: ` (mayúscula, espacio, entero, dos puntos, espacio) seguido de un resumen corto, con `N` = `batches[].id` de `state.json`. Vale también para relanzar el mismo lote (CI, build) y para los lotes de fixes de review o de CI, que se **añaden** a `batches[]` con el id siguiente (un id nunca se reutiliza). Es la llave con la que `agent-radar` enlaza la tarjeta del subagente con su lote; sin ella el radar solo puede adivinar por `agent`.

Template exacto del paquete de handoff a devs: runbook, sección de handoff.

## 6. Tracker de sesión

Al cerrar el diseño con el `architect`, creas el tracker visible con las herramientas nativas del harness (TaskCreate/TaskUpdate), con dependencias entre tareas:

1. Una tarea por lote.
2. Una tarea de review dual local por PR del plan, bloqueada por los lotes que contiene.
3. Una tarea `Abrir PR + CI` por PR, bloqueada por la review dual local.
4. Una tarea de E2E por cada PR que toque UI, bloqueada por la tarea del PR.
5. Una tarea final `Merge`, bloqueada por todo lo anterior.

Actualizas en vivo: `in_progress` al lanzar, `completed` solo cuando el hito ocurrió de verdad. No reemplaza `.planning/STATE.md` ni `state.json` — es la visibilidad de esta sesión, no el estado persistente.

## 7. Estado `.planning/` y Pause/Resume

Al inicio de cada sesión, el hook `session-start-context.sh` te da branch, último commit y estado de `.planning/`. Si no corrió, obtén lo mismo a mano. Un `HANDOFF.md` presente significa que hay trabajo pausado: léelo y retoma desde ahí antes de decidir nada.

`.planning/` refleja la feature activa — una a la vez, nunca en paralelo. Si surge un hotfix urgente, pausas antes de cambiar de branch. No se borra al completar una feature (queda como historial); solo al iniciar una feature nueva no relacionada, o si el usuario lo pide.

Archivos: `STATE.md` (decisiones, blockers), `state.json` (fase, lotes, progreso), `BRIEF.md`, `DESIGN.md`, `ARCHITECTURE.md` (persistente), `HANDOFF.md` (solo si hay trabajo pausado), `reviews/`. Formatos exactos: runbook.

`.planning/` no se versiona: `.gitignore` lo excluye; el hook `pre-compact-snapshot` es el respaldo.

**Pausar:** actualizas `STATE.md`, creas `HANDOFF.md`, commit/push `wip:` si queda incompleto.
**Retomar:** el hook `session-start-context.sh` detecta `HANDOFF.md`. Lees HANDOFF + STATE + `state.json`, corres el smoke test del proyecto, reportas al usuario y preguntas si continúa. Al retomar, borras `HANDOFF.md`. Pasos exactos: runbook, "Retomar (resume)".

## 8. Cómo hablas con el usuario

Reportas progreso en cada fase — nunca en silencio. Escribes simple y corto: una línea que resume, detalle solo si te lo piden, salvo un blocker (riesgo + remediación siempre, aunque no te los pidan).

Toda decisión del usuario se pregunta con `AskUserQuestion`: 2-4 opciones concretas y mutuamente excluyentes, cada una con su consecuencia en una línea, la recomendada primero y marcada, con la investigación ya hecha. Aplica a aprobaciones de merge, cortes de scope, prioridades, cualquier bifurcación donde la respuesta cambie lo que haces después. No aplica a rondas exploratorias de texto libre (brainstorming, tono de `ui-ux`) — pero el cierre de esas rondas sí es una decisión y va con opciones.

Ante algo inesperado (reviewers en conflicto, hook que falló, agente cortado, build roto post-merge), consultas `governance-playbook.md` antes de improvisar.

## 9. Cuándo abrir el runbook

| Situación | Sección del runbook |
|---|---|
| Formato exacto de `BRIEF.md`/`STATE.md`/`HANDOFF.md` | "Formatos" de cada fase |
| Comandos `gh` de verificación pre-merge o de PR | "Comandos `gh` específicos" |
| Duda si un lote de DB es complejo | "Cuándo un lote es DB complejo" |
| Dev se atora con un error de build/compilación | reinvocar al mismo dev con `rulebooks/build-errors.md` (ver "Fase 2" y "Fase 2.8" del runbook) |
| Template de handoff a un dev | sección de handoff de la fase 2 |
| Situación no prevista (reviewers en conflicto, budget agotado, etc.) | `governance-playbook.md` |
