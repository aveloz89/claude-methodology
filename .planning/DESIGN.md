## Diseño: audit-best-practices

### Resumen

Alinear la metodología con la doc oficial en tres grupos independientes: (1) fixes técnicos de hooks, frontmatter y validación del plugin; (2) partir `global/CLAUDE.md` en un núcleo corto siempre cargado + skill `orchestrator` bajo demanda; (3) fusionar `build-resolver` y `db-specialist` en rulebooks que cargan los devs (sujeto a aprobación del usuario). Tres PRs secuenciales, seis lotes, todos para `backend-dev`.

### Search-first

No aplica librería externa: es un cambio de proceso y de scripts Bash sobre el propio repo. Se investigó la doc oficial (hooks, sub-agents, skills, plugins CLI, memory, permissions; copias en el scratchpad de esta sesión) y se verificó el comportamiento real de la CLI 2.1.274 en directorios temporales. Las decisiones de abajo citan lo verificado, no lo leído.

### Verificaciones empíricas (ejecutadas, CLI 2.1.274, modo `-p`)

| # | Pregunta | Método | Resultado |
|---|---|---|---|
| a | ¿El stdout/`additionalContext` de `SessionStart` llega a los subagentes? | Repo temporal con hook `SessionStart` (matcher `startup\|resume\|clear\|compact`) que loguea su stdin e imprime `MARKER-ZEBRA-7731`; agente `probe` (haiku) que responde si ve el marker; `claude -p` pide lanzarlo | **No llega.** El hook corrió **una sola vez** (`source: startup`, sin `agent_type`), `SubagentStart` sí disparó, y el subagente respondió `SEEN: no`. La frase de la doc ("applies to subagents") describe hooks de tool events (`PreToolUse`, etc.), no `SessionStart`. Límite: verificado en `-p`; en sesión interactiva el mecanismo es el mismo evento por sesión, no se probó |
| b | Tokens reales del `CLAUDE.md` | `claude -p --model haiku --output-format json "Reply ok"` en dos repos temporales, uno con `global/CLAUDE.md` copiado como `CLAUDE.md` de proyecto y otro sin; suma de `input + cache_creation + cache_read` | **44.430 − 38.034 = 6.396 tokens** para 20.963 bytes (3,28 B/token). El método es reproducible y es el que usa el lote 4 para medir el "después" |
| c | ¿`Agent(security-reviewer)` matchea `methodology:security-reviewer`? | Plugin temporal `tp` con agente `probe` (`--plugin-dir`); `permissions.deny` en tres variantes | `deny: ["Agent(probe)"]` → el agente **corrió** (`PROBE-RAN`). `deny: ["Agent(tp:probe)"]` → **denegado**. Sin deny → corrió sin pedir permiso. Conclusión: el nombre pelado no matchea; la forma correcta es `Agent(methodology:<agente>)`. Además, el tool `Agent` no pidió permiso en ningún caso: `allowed-tools` con `Agent(...)` es hoy un no-op en la práctica; se corrige por corrección, no porque desbloquee algo |
| d | ¿Qué validación es la correcta y cómo resolver la advertencia del `CLAUDE.md` raíz? | `claude plugin validate --strict` sobre `.`, `.claude-plugin/plugin.json`, `agents`, `skills` en el repo y en tres plugins temporales (CLAUDE.md en raíz / en `.claude/` / ambos manifests) | Con `marketplace.json` presente, `validate .` valida **solo el marketplace** (doc: "marketplace.json, when it exists; otherwise plugin.json"). La validación del plugin es `--strict .claude-plugin/plugin.json`, y hoy falla por el `CLAUDE.md` raíz. Con el archivo en **`.claude/CLAUDE.md`** pasa `--strict` y sigue cargando como instrucciones del proyecto (verificado: una regla puesta ahí cambió la respuesta de `claude -p`). El dev-loop no cambia: el symlink `~/.claude/skills/methodology` carga el plugin por `plugin.json`, no por el CLAUDE.md. Hallazgo extra: `validate agents` pasa con `memory: true` y `permissionMode: plan` — el validador no detecta valores inválidos ni campos ignorados; hace falta un lint propio |
| e | ¿El campo `if` funciona con comandos compuestos y dentro del `hooks.json` de un plugin? | Hook `if: "Bash(git *)"` que loguea el comando; en settings de proyecto y en plugin vía `--plugin-dir` | Disparó para `echo hi && git status --short`, `git -C . log …` y `cd . && git status`; no disparó para `echo bye`. `--strict` no objeta el campo. Es seguro usar `Bash(git *)` / `Bash(gh *)` como superconjunto de lo que cada guard matchea |

Otros hechos verificados que condicionan el diseño:

- `tests/adversarial/test-hooks.sh` (321 asserts, verde) **no tiene ningún test** de `block-force-push.sh`, `block-hard-reset.sh` ni `pre-release-sweep.sh`. La migración de formato de esos hooks empieza en rojo real.
- `.claude/settings.json` (trackeado) registra los 14 hooks a nivel proyecto **además** de `hooks/hooks.json`: en este repo cada hook dispara dos veces (el dedupe de `subagent-stop-log.sh` lo admite). Contradice el `CLAUDE.md` del repo ("el registro vive únicamente en `hooks/hooks.json`"). Fuera del brief; ver Riesgos.
- Log de invocaciones (`~/.claude/methodology/logs/`, 2.926 líneas, 2026-08 → 2026-09-26, 4 repos): `frontend-dev` 107, `backend-dev` 79, `security-reviewer` 55, `qa-frontend` 41, `qa-backend` 31, `ui-ux` 27, `docs` 24, `architect` 14, `e2e-runner` 8, **`db-specialist` 2, `build-resolver` 2**, `refactor` 2, `latent-bugs-sweep` 2. 2.505 líneas `unknown` (subagentes anidados o payload sin `agent_type`): la proporción entre agentes nombrados es la señal, no los absolutos.

### Arquitectura

Proyecto existente; se mantiene el layout plugin + `install.sh` residual (`ARCHITECTURE.md`, 2026-08-14). Cambios estructurales de este diseño:

- **Progressive disclosure en tres niveles** para el orchestrator: `global/CLAUDE.md` (siempre, ≤10 KB) → `skills/orchestrator/SKILL.md` (al iniciar trabajo que termina en PR, <500 líneas) → `rulebooks/orchestrator-runbook.md` (formatos exactos, bajo demanda, sin cambios de contenido).
- **Especialidades como rulebooks, no como agentes**, cuando no hay frontera de contexto (ver "Fusión de agentes").

### Archivos afectados

**PR 1 — fixes técnicos** (branch existente `feature/audit-best-practices`)

- `hooks/block-force-push.sh`, `hooks/block-hard-reset.sh`, `hooks/block-admin-merge.sh`, `hooks/pre-release-sweep.sh`, `hooks/pre-merge-check.sh` — salida `exit 2` + stderr en vez de `{"decision":"block"}`; `exit 0` sin stdout en vez de `{"continue":true}`.
- `hooks/pre-commit-guard.sh` — watchdog interno fail-closed.
- `hooks/hooks.json` — `if` por handler, matcher de `SessionStart`, timeout de `pre-commit-guard`.
- `agents/e2e-runner.md`, `agents/security-reviewer.md`, `agents/latent-bugs-sweep.md` — frontmatter; `effort: high` solo en los reviewers sonnet (`qa-frontend`, `qa-backend`) — decisión del usuario D-05.
- `skills/new-project/SKILL.md`, `skills/refactor-scan/SKILL.md` — `disable-model-invocation: true`; `skills/pr-workflow/SKILL.md`, `skills/review-pr/SKILL.md`, `skills/refactor-scan/SKILL.md` — `Agent(methodology:…)`.
- `rulebooks/agent-budget.md` — línea 3 (`maxTurns` no existe; el techo es el contexto y el corte).
- `CLAUDE.md` → `.claude/CLAUDE.md` (git mv) + instrucción de validación corregida; `README.md` (Estructura, línea 143; sección Release).
- `global/CLAUDE.md` — solo el texto de "Corren en background".
- `tests/adversarial/test-hooks.sh`, `tests/adversarial/test-plugin-manifest.sh`, **nuevo** `tests/adversarial/test-frontmatter.sh`.

**PR 2 — división del CLAUDE.md** (branch nuevo `feature/orchestrator-skill`, desde `dev` tras mergear PR 1)

- `global/CLAUDE.md` — reescritura al núcleo.
- **nuevo** `skills/orchestrator/SKILL.md`.
- `hooks/session-start-context.sh` — recordatorio de una línea.
- `rulebooks/orchestrator-runbook.md` (líneas 3, 42, 261, 263, 531, 786, 794), `rulebooks/governance-playbook.md` (147), `README.md` (7, 46-52, Estructura), `.claude-plugin/marketplace.json` (descripción), `tests/validation/agent-validation.md` (sección Orchestrator), `tests/adversarial/test-plugin-manifest.sh`.

**PR 3 — fusión de agentes** (branch nuevo `feature/merge-agents`, desde `dev` tras mergear PR 2; solo si el usuario aprueba)

- **borrar** `agents/build-resolver.md`, `agents/db-specialist.md`; **nuevos** `rulebooks/build-errors.md`, `rulebooks/db-migrations.md`.
- `agents/backend-dev.md`, `agents/architect.md`, `agents/qa-backend.md`, `agents/frontend-dev.md`, `agents/e2e-runner.md`, `agents/refactor.md`, `agents/security-reviewer.md`, `agents/latent-bugs-sweep.md` (menciones), `rulebooks/dev-common.md`, `rulebooks/orchestrator-runbook.md`, `rulebooks/governance-playbook.md`, `skills/orchestrator/SKILL.md`, `skills/pr-workflow/SKILL.md`, `README.md`, `.claude-plugin/marketplace.json`.

### Contratos

No hay API. Los contratos son de formato:

**Hooks PreToolUse (uno solo para todos):** bloquear = mensaje en stderr + `exit 2`; permitir = `exit 0` sin stdout. Se elige `exit 2` sobre `hookSpecificOutput.permissionDecision` porque: (1) la doc lo prescribe para policy ("If your hook is meant to enforce a policy, use exit 2") y dice que bloquea aunque otro JSON diga `allow`; (2) permissions.md: un hook con exit 2 se evalúa **antes** de las allow rules; (3) `pre-commit-guard.sh` y `pre-push-guard.sh` ya lo usan y los helpers `assert_blocked_cmd`/`assert_allowed_cmd` de la suite son por exit code — queda **un** mecanismo y una familia de asserts; (4) no depende de `jq` para serializar el motivo (hoy `block()` de `pre-merge-check.sh` sí). Costo: los 6 `assert_pre_merge_*` y los 2 `assert_bam_*` que hoy grepean `"decision":"block"` pasan a exit code + grep de stderr. La doc pide no mezclar mecanismos por hook: ningún hook migrado imprime JSON.

**`hooks/hooks.json` (PreToolUse):**

```json
{ "type": "command", "if": "Bash(git *)", "command": "${CLAUDE_PLUGIN_ROOT}/hooks/block-force-push.sh", "timeout": 10 }
```

| Hook | `if` | Por qué es superconjunto del guard |
|---|---|---|
| block-force-push, block-hard-reset, pre-push-guard, pre-commit-guard | `Bash(git *)` | los cuatro exigen el token `git` en posición de comando |
| block-admin-merge, pre-merge-check, pre-release-sweep | `Bash(gh *)` | los tres exigen `gh` en posición de comando |

`if` es optimización de latencia (verificación e): cada script sigue validando el comando completo; el header de cada hook lo dice en una línea.

`SessionStart.matcher`: `"startup|resume|clear|compact"`. `pre-commit-guard.timeout`: `600`.

**`pre-commit-guard.sh` fail-closed:** la suite corre en background; un bucle espera hasta `PRECOMMIT_TEST_BUDGET` segundos (default `540`, env sobreescribible); al vencer, mata el grupo de procesos y termina con `BLOCKED: la suite superó ${PRECOMMIT_TEST_BUDGET}s; el hook no falla abierto. Acotá la suite o subí PRECOMMIT_TEST_BUDGET.` + `exit 2`. Como 540 < 600, el watchdog interno siempre gana al timeout del harness (que descartaría la salida y dejaría pasar el commit — doc "Timeouts"). Patrón de watchdog ya existente en `hooks/lib/guard-matching.sh` (perl); reusar la forma, no la lib.

**Frontmatter de agentes (lint en `tests/adversarial/test-frontmatter.sh`):** claves permitidas = `name, description, model, tools, disallowedTools, maxTurns, skills, memory, background, omitClaudeMd, effort, isolation`; prohibidas por ignoradas en plugin = `permissionMode, hooks, mcpServers, initialPrompt`; `memory ∈ {user, project, local}`; `effort ∈ {low, medium, high, xhigh, max}`; `model ∈ {sonnet, opus, haiku, fable, inherit}`; `name` = nombre del archivo. **Skills:** toda entrada `Agent(x)` en `allowed-tools` tiene forma `Agent(methodology:<agente>)` con `<agente>` ∈ `agents/`; `disable-model-invocation: true` obligatorio en `new-project` y `refactor-scan`, prohibido en `pr-workflow`, `review-pr` y `orchestrator`. **Referencias:** todo `methodology:<x>` y toda mención `` `<agente>` `` de la lista histórica (`build-resolver`, `db-specialist`, …) en `agents/ rulebooks/ skills/ README.md .claude/CLAUDE.md` debe corresponder a un archivo en `agents/` (este check es el RED del PR 3).

**Valores propuestos por agente:**

| Agente | `effort` | `maxTurns` | Cambio de frontmatter |
|---|---|---|---|
| architect (fable), ui-ux, security-reviewer (opus) | hereda | no | security-reviewer: quitar `permissionMode` |
| backend-dev, frontend-dev, qa-frontend, qa-backend, docs, refactor, e2e-runner, latent-bugs-sweep, (db-specialist, build-resolver mientras existan) | `high` | no | e2e-runner: `memory: project`; latent-bugs-sweep: quitar `permissionMode` |

Justificación: el autor corre la sesión en `xhigh` y los subagentes lo heredan; `high` en los sonnet acota costo donde el trabajo es de ejecución, sin tocar diseño ni seguridad. **No** se define `maxTurns`: corta a mitad de un ciclo TDD y devuelve salida parcial; el control de budget real es el cap de 5 tareas + commit por tarea. Se corrige `agent-budget.md` línea 3 para que no atribuya el techo a un `maxTurns` que nadie configura.

### Schemas de validación

No aplica (sin código de aplicación). Los contratos de formato de arriba se verifican con los tests listados.

### Esquema DB

No aplica.

### División de `global/CLAUDE.md`

**Qué se queda (núcleo, objetivo ≤ 10.240 bytes y ≤ 130 líneas, test de regresión en `test-plugin-manifest.sh`):**

| Sección | Bytes hoy → estimado | Nota |
|---|---|---|
| Título + intro + Convenciones generales | 716 → 600 | idioma; `rules/` vs `rulebooks/` en dos líneas |
| Rol de la sesión principal (nuevo) | 644 → 700 | redacción abajo |
| Workflow obligatorio (brainstorming, diseño, TDD, review dual, 80 %) | 1.608 → 1.200 | las condiciones para saltar brainstorming van a la skill |
| PR y merge: invariantes | 1.067 → 1.000 | sin cambios de fondo |
| Gitflow + formato de commits | 1.167 → 1.100 | |
| Hooks | 1.405 → 900 | texto de "Corren en background" corregido ya en PR 1 |
| Verificación pre-commit (devs) | 1.184 → 900 | aplica a todo subagente que commitea |
| Estado `.planning/` | 916 → 300 | solo qué es y "una feature a la vez"; detalle en skill |
| Reglas operativas comunes | 2.863 → 1.300 | quedan: escribe simple, tarea atómica, frontend delgado, debugging, verificar antes de afirmar |
| Reglas por lenguaje | 407 → 350 | |
| **Total** | **20.963 → ≈ 8.400 bytes (≈ 2.600 tokens, −59 %)** | |

**Qué se mueve a la skill:** rol detallado del orchestrator, Lotes, Equipo de subagentes (tabla + degradación de modelo), Handoff/context isolation, Flujo de trabajo por fases y sus reglas clave, Pause/Resume, tracker de sesión, "reporta al usuario", "toda decisión con opciones (AskUserQuestion)", governance.

**Redacción exacta de la regla corta del rol** (sección nueva, reemplaza "Tu rol como orchestrator"):

```markdown
## Rol de la sesión principal

La sesión principal —el *orchestrator*— coordina: entiende el pedido, hace diseñar,
reparte lotes a los subagentes, corre los reviews y mergea. No escribe código de
producción ni tests; eso lo hacen los subagentes que reciben un lote. Esta regla
describe a quien delega. Si estás leyendo esto como subagente, tu prompt define tu
trabajo y esta sección no te aplica.

Al empezar una feature, un fix o cualquier trabajo que termine en un PR, la sesión
principal carga la skill `orchestrator` (`/methodology:orchestrator`) antes de
delegar nada. Si al ir a delegar notás que no la tenés cargada, cargala en ese
momento. El hook de inicio de sesión lo recuerda.
```

**Skill `skills/orchestrator/SKILL.md`** (objetivo ≈ 220 líneas, tope 500; test de regresión):

```yaml
---
name: orchestrator
description: Manual de la sesión principal para coordinar una feature o un fix de punta a punta — fases 0 a 5, qué subagente invocar en cada una, lotes y handoff, tracker de sesión, pause/resume. Cargar al iniciar cualquier trabajo que termine en un PR, antes de delegar el primer lote.
user-invocable: true
allowed-tools: Read, Grep, Glob, Bash
argument-hint: "[feature|fix] <descripción corta>"
---
```

Sin `disable-model-invocation` (el modelo debe poder cargarla solo). Sin `Agent(...)` en `allowed-tools`: verificación c muestra que el tool no pide permiso; listar once agentes sería mantenimiento sin efecto. Sin `context: fork`: la skill es conocimiento para la sesión, no una tarea aislada.

Estructura (cada sección enuncia lo accionable y remite al runbook por nombre de sección; **nada del runbook se copia**):

1. Rol y alcance (≈10 líneas) — cuándo aplica, qué no hace.
2. Mapa del flujo (≈30) — tabla `Fase → qué hacés → artefacto → sección del runbook`, fases 0 a 5 como hoy en CLAUDE.md, con las reglas clave (setup del branch una vez, `last_batch`, un push por ronda, fixes en el mismo branch, re-lanzar solo reviewers con issues, 3 intentos de CI, E2E flaky).
3. Brainstorming (≈10) — condiciones para saltarlo (las cuatro actuales) y "en cualquier duda, brainstormea".
4. Equipo de subagentes (≈30) — tabla actual (agente, modelo, rol, cuándo) + degradación de modelo + criterio db-complejo (puntero al runbook).
5. Lotes y handoff (≈25) — cap 5, lote ≠ PR, validación del plan (3 reintentos), context isolation en cinco líneas, puntero al template del runbook.
6. Tracker de sesión (≈10) — qué tareas crear y cuándo marcar `completed`; puntero.
7. Estado `.planning/` y Pause/Resume (≈25) — lista de archivos, cleanup, pausar/retomar (puntero a "Retomar (resume)").
8. Cómo hablás con el usuario (≈15) — reporta progreso, decisiones con `AskUserQuestion` y opciones, governance ante lo inesperado.
9. Cuándo abrir el runbook (≈10) — tabla situación → sección.

**Recordatorio del hook** (`session-start-context.sh`, una línea antes del cierre `===`, siempre que haya repo git):

```bash
echo "Sesión principal: si este turno arranca una feature, un fix o algo que termine en PR, cargá la skill methodology:orchestrator antes de delegar."
```

El prefijo "Sesión principal:" es defensa en profundidad; la verificación a muestra que el texto no llega a los subagentes. Test: en el sandbox de `test-hooks.sh`, la salida del hook contiene `methodology:orchestrator`.

**Referencias cruzadas a actualizar en el PR 2:**

| Archivo | Línea(s) | Cambio |
|---|---|---|
| `rulebooks/orchestrator-runbook.md` | 3 | "el comportamiento esencial vive en `CLAUDE.md` raíz" → en la skill `orchestrator` |
| | 42, 261, 263, 531 | "regla operativa de `CLAUDE.md`" / "invariante 3 de `CLAUDE.md`" / "Gitflow en `CLAUDE.md`" / "Pause / Resume en `CLAUDE.md`" → las invariantes y Gitflow siguen en CLAUDE.md (sin cambio); AskUserQuestion y Pause/Resume → skill |
| | 786, 794 | el grep anti-drift agrega `skills/orchestrator/SKILL.md`; "nunca en `global/CLAUDE.md`" queda y se refuerza con el test de tamaño |
| `rulebooks/governance-playbook.md` | 147 | Pause/Resume → skill |
| `agents/security-reviewer.md` 18, `agents/qa-backend.md` 13, runbook 609 | lista de documentos normativos: ya incluye `skills/`; agregar la skill por nombre para que el diff mixto la clasifique como normativo |
| `agents/backend-dev.md` 65, `agents/qa-backend.md` 143 | "exclusiones de coverage en CLAUDE.md raíz" — se quedan en el núcleo (Workflow #5); sin cambio, verificar |
| `rulebooks/dev-common.md` 16, `agents/*` "formato de commits en CLAUDE.md raíz" | se queda en el núcleo; sin cambio, verificar |
| `README.md` | 7, 46-52, Estructura | orchestrator "definido en `global/CLAUDE.md` + skill `orchestrator`"; tabla Skills (5); árbol |
| `.claude-plugin/marketplace.json` | 9 | "5 skills" |
| `tests/validation/agent-validation.md` | Orchestrator | expected behavior: carga la skill antes de delegar |
| `install.sh` | — | sin cambio: la skill viaja por el plugin; `global/CLAUDE.md` se sigue symlinkeando |
| `tests/adversarial/test-plugin-manifest.sh` | — | skill existe, <500 líneas, frontmatter sin `disable-model-invocation`; `global/CLAUDE.md` ≤ 10.240 bytes y ≤ 130 líneas |

### Fusión de agentes (decisión del usuario)

Criterio aplicado (guía oficial): un agente aparte se justifica cuando **necesita un contexto que el invocador no tiene o no debería cargar** (fresco, aislado, o de otro tamaño), no por ser otro tipo de problema. Datos: log de invocaciones arriba.

| Candidato | Recomendación | Argumento | Qué cambia |
|---|---|---|---|
| **`build-resolver`** | **Fusionar** → `rulebooks/build-errors.md` | 2 invocaciones en ~2.900. El error de build nace en el contexto del dev que lo produjo; el "fix mínimo" necesita exactamente ese contexto (qué cambió, por qué). Un agente fresco tiene que reconstruirlo. Lo que aporta el prompt (clasificación del error, criterio de dependencias, escalaciones, anti-patrones) es conocimiento, no frontera de contexto: cabe en un rulebook que el dev lee cuando el build falla | Borrar `agents/build-resolver.md`; crear `rulebooks/build-errors.md` (mismo contenido, tono bajado); `dev-common.md` sección "Build roto" (leer el rulebook; 3 intentos; escalar al orchestrator); runbook Fase 2 "si un dev reporta error de build" → re-invocar al mismo dev con el rulebook, y Fase 2.8 asignación de fixes; `governance-playbook.md`; `pr-workflow` (quitar `Agent(methodology:build-resolver)` y el texto); README (12 agentes), `marketplace.json`, tabla de la skill. Invocación directa del usuario ("me atoré con el build"): la sesión delega a `backend-dev`/`frontend-dev` con el rulebook |
| **`db-specialist`** | **Fusionar** en `backend-dev` → `rulebooks/db-migrations.md` | 2 invocaciones frente a 79 de `backend-dev`. Trabaja sobre el mismo contexto (`DESIGN.md` sección de datos + schema actual) que el dev que después consume el schema; la separación existía por especialidad y por orden (schema primero), y el orden lo garantiza el plan de lotes, no el agente. El prompt de 18,6 KB se paga entero en cada invocación aunque la tarea sea una migración | Borrar `agents/db-specialist.md`; crear `rulebooks/db-migrations.md` (criterios de complejidad, testing de DB, expand-contract, EXPLAIN, estado de la DB de test en HANDOFF, sección DB de `ARCHITECTURE.md`); `backend-dev.md` sección "Lote de DB complejo: leé el rulebook"; `architect.md`: el plan marca el lote `db-complejo` y va primero; runbook: "Criterios completos: db-specialist vs backend-dev" → "Cuándo un lote es DB complejo" + handoff template incluye el rulebook; menciones en `qa-backend`, `frontend-dev`, `e2e-runner`, `refactor`, `security-reviewer`, `latent-bugs-sweep`, `dev-common.md`, README, `marketplace.json`, skill |
| **`docs`** | **Mantener**, con criterio de salto | 24 invocaciones ≈ una por feature (7 % del total). Sí es frontera de contexto: lee el diff completo con contexto fresco; en features multi-dev el último dev solo tiene su slice y llega con el budget más gastado (5 tareas hechas). Fusionarlo en `last_batch=true` ahorra ~1 invocación por feature y carga al eslabón más débil | Solo en la skill/runbook Fase 2.5: el orchestrator salta `docs` cuando `git diff --stat` no toca superficie pública (solo tests, `.planning/`, código interno sin cambios en README/API/CLI/config) |
| **`ui-ux` + `architect` en UI chica** | **Mantener separados**, endurecer el disparador | 27 invocaciones de `ui-ux` contra 14 del architect: se invoca más de lo que el criterio actual prevé. Es frontera de contexto real: produce el design system (archivos grandes) y el architect solo necesita el bloque "Para incluir en el brief". Fusionarlos cargaría al architect (fable) con diseño visual que no necesita | Skill/runbook Fase 0.5: invocar `ui-ux` solo si no existe `design-system/<proyecto>/MASTER.md` o el brief introduce una página crítica o un patrón nuevo; en UI chica el architect referencia `MASTER.md` y el frontend-dev aplica su checklist. `ui-ux.md` "Cuándo NO invocarte" ya lo dice; sin cambio ahí |

Si el usuario aprueba solo una de las dos fusiones, el PR 3 se reduce al lote correspondiente; el test de referencias del PR 1 sigue válido.

### Tono: criterio para los archivos que se toquen

Aplica a cada archivo tocado en los tres PRs, y lo verifica `qa-backend` con los mismos greps:

1. **Mayúsculas de énfasis** (`NUNCA`, `NO`, `SIEMPRE`, `SOLO`, `OBLIGATORIO`, `BLOQUEANTE`) solo en las invariantes: no mergear sin aprobación explícita, no mergear con CI en rojo, nunca push directo a `main` ni `--force`, la sesión principal no escribe código. Todo lo demás en minúscula y con el porqué: "no hagas X" → "X rompe Y; hacé Z".
2. **Negritas**: como máximo una por párrafo o ítem, y solo sobre el término que decide (archivo, flag, estado). Nunca frases completas.
3. **Listas de anti-patrones en imperativo negativo** ("NO agregues…") → tabla "en vez de → hacé" o prosa con la razón.
4. Métrica de cierre por archivo tocado: `grep -c NUNCA` ≤ 1 (`global/CLAUDE.md` ≤ 3, uno por invariante); `grep -oE '\bNO\b'` = 0 fuera de encabezados del tipo "Cuándo NO invocar"; negritas ≤ 1 cada 10 líneas. Hoy: `CLAUDE.md` 4/3/75, `build-resolver.md` 0/25/65, `orchestrator-runbook.md` 1/18/157 (el runbook no se toca en tono salvo las líneas editadas).

### Infraestructura Docker

No aplica.

### Frontend

No aplica.

### Plan de implementación

**Estrategia de PR:** multi-PR (3), secuenciales.
**Justificación:** (1) los grupos son genuinamente independientes en propósito y casi disjuntos en archivos; (2) cada uno es shippeable solo; (3) juntos superan 1.000 LoC de naturaleza mixta (bash + frontmatter + reescritura de prosa + borrado/creación de agentes). Además la metodología no mezcla refactor y feature: el PR 3 es un refactor estructural del sistema de agentes y requiere aprobación aparte del usuario; el PR 1 son bug fixes; el PR 2 es un cambio de proceso. Se secuencian (no en paralelo) porque los tres tocan `README.md`, `marketplace.json` y `test-plugin-manifest.sh`. El branch actual `feature/audit-best-practices` es el del PR 1; los siguientes se crean desde `dev` después de cada merge.

Todos los lotes los toma `backend-dev` (bash + markdown; reglas `bash.md`). Review dual: `security-reviewer` en opus (los hooks son guards de seguridad; no degradar) + `qa-backend` (diff normativo).

#### Lote 1 — Hooks: formato de bloqueo, `if`, matcher y fail-closed (backend-dev)
**Depende de:** ninguno
**PR:** PR 1 · `last_batch=false`

- [ ] Tarea 1: `block-force-push.sh` y `block-hard-reset.sh` bloquean con stderr + `exit 2` y permiten con `exit 0` sin stdout. RED: tests nuevos con `assert_blocked_cmd`/`assert_allowed_cmd` (hoy no existe ninguno para estos hooks): `git push --force`, `git push -f origin x`, `cd a && git push --force` bloquean; `git push`, `git reset --soft HEAD~1` pasan.
- [ ] Tarea 2: `block-admin-merge.sh` y `pre-release-sweep.sh` migran al mismo contrato; los `assert_bam_*` pasan a exit code + grep de stderr; `pre-release-sweep` gana tests (bloquea con issue `latent-bug` CRÍTICO sobre archivo del diff usando el `gh` fake existente; pasa sin issues; pasa si el comando no es `gh pr create --base main`).
- [ ] Tarea 3: `pre-merge-check.sh` — `block()` escribe el motivo en stderr y `exit 2`; los seis `{"continue":true}` pasan a `exit 0`; `assert_pre_merge_blocked/continue` y variantes pasan a exit code (el motivo sigue verificable en stderr).
- [ ] Tarea 4: `hooks.json` — `if` por handler según la tabla, `SessionStart.matcher = "startup|resume|clear|compact"`, `pre-commit-guard.timeout = 600`; `test-plugin-manifest.sh` verifica los tres con `jq` (RED antes del cambio). Nota de una línea en el header de cada hook: `if` es optimización, el script valida el comando completo.
- [ ] Tarea 5: `pre-commit-guard.sh` fail-closed por tiempo: watchdog `PRECOMMIT_TEST_BUDGET` (default 540); test en sandbox con `pyproject.toml` + `pytest` fake que duerme 5 s: con `PRECOMMIT_TEST_BUDGET=1` → `exit 2` y sin proceso huérfano; con `=10` → `exit 0`.

#### Lote 2 — Frontmatter, skills y validación del plugin (backend-dev)
**Depende de:** Lote 1 (mismo `test-plugin-manifest.sh`)
**PR:** PR 1 · `last_batch=true`

- [ ] Tarea 1: **nuevo** `tests/adversarial/test-frontmatter.sh` con el lint de agentes (claves permitidas/prohibidas, `memory`, `effort`, `model`, `name` = archivo). RED con el repo actual (`memory: true`, `permissionMode`); GREEN: `e2e-runner` `memory: project`, quitar `permissionMode` en `security-reviewer` y `latent-bugs-sweep`.
- [ ] Tarea 2: `effort: high` solo en `qa-frontend` y `qa-backend` (decisión del usuario D-05: los devs quedan en default para no subir el costo; el lint lo acepta) y `rulebooks/agent-budget.md` línea 3 reescrita: el techo es la ventana de contexto y el corte de la invocación, no un `maxTurns` configurado; se explica por qué no se configura.
- [ ] Tarea 3: el lint cubre skills: `Agent(...)` namespaced y existente, `disable-model-invocation: true` en `new-project` y `refactor-scan`, ausente en `pr-workflow` y `review-pr`; corregir las cuatro skills. Incluye el check "toda referencia a un agente en `agents/ rulebooks/ skills/ README.md` existe en `agents/`" (pasa hoy; es el RED del PR 3).
- [ ] Tarea 4: `git mv CLAUDE.md .claude/CLAUDE.md`; `test-plugin-manifest.sh` corre `claude plugin validate --strict .claude-plugin/plugin.json` **y** `--strict .` (RED: el primero falla hoy); instrucción de validación en `.claude/CLAUDE.md` y README (sección Release + árbol) actualizadas.
- [ ] Tarea 5: `global/CLAUDE.md` sección Hooks: "commit sin suite verde" pasa de "Corren en background" a "Bloquean el comando" (con la omisión de solo-`.planning/`); tono según criterio en las líneas tocadas de este PR (headers de hooks, `agent-budget.md`).

#### Lote 3 — Skill `orchestrator`, núcleo del CLAUDE.md y recordatorio (backend-dev)
**Depende de:** PR 1 mergeado (branch nuevo `feature/orchestrator-skill`)
**PR:** PR 2 · `last_batch=false`

- [ ] Tarea 1: crear `skills/orchestrator/SKILL.md` con el frontmatter y la estructura de nueve secciones; contenido movido desde `global/CLAUDE.md`, remitiendo al runbook por nombre de sección sin copiarlo; tono según criterio. Test: existe, <500 líneas, `name: orchestrator`, sin `disable-model-invocation`, `user-invocable: true`.
- [ ] Tarea 2: reescribir `global/CLAUDE.md` al núcleo con la redacción exacta del rol; test: ≤ 10.240 bytes y ≤ 130 líneas (RED: hoy 20.963/190). Verificar que la lista de "lo que se mueve" no queda en ninguno de los dos lados dos veces.
- [ ] Tarea 3: recordatorio en `session-start-context.sh`; test en sandbox: la salida contiene `methodology:orchestrator`; sigue sin imprimirse fuera de un repo git.
- [ ] Tarea 4: referencias cruzadas en rulebooks (`orchestrator-runbook.md` 3, 42, 261, 263, 531, 786, 794; `governance-playbook.md` 147; `dev-common.md` verificar).
- [ ] Tarea 5: referencias en agentes (`security-reviewer` 18, `qa-backend` 13/143, `backend-dev` 65: verificar que lo citado sigue en el núcleo), README (7, tabla Skills, árbol), `marketplace.json` ("5 skills"), `agent-validation.md` (Orchestrator: "carga la skill antes de delegar").

#### Lote 4 — Medición y cierre del PR 2 (backend-dev)
**Depende de:** Lote 3
**PR:** PR 2 · `last_batch=true`

- [ ] Tarea 1: medir tokens del `CLAUDE.md` nuevo con el método de la verificación b (dos repos temporales, `claude -p --output-format json`), registrar antes/después en `.planning/STATE.md` y en el body del PR; si el resultado supera 3.200 tokens, recortar antes de cerrar.
- [ ] Tarea 2: grep anti-drift del DoD (runbook "Anti-drift") sobre los términos movidos (`Equipo de subagentes`, `Flujo de trabajo: nueva feature`, `Tracker de tareas`, `Pause / Resume`, `Degradación de modelo`) en `agents/ rulebooks/ skills/ README.md .planning/`; reconciliar lo que quede apuntando al lugar viejo.
- [ ] Tarea 3: `claude plugin validate --strict .claude-plugin/plugin.json` y la suite completa (`test-hooks.sh`, `test-plugin-manifest.sh`, `test-frontmatter.sh`) verdes; métricas de tono del criterio sobre `global/CLAUDE.md` y la skill.

#### Lote 5 — `build-resolver` → `rulebooks/build-errors.md` (backend-dev)
**Depende de:** PR 2 mergeado y aprobación del usuario (branch nuevo `feature/merge-agents`)
**PR:** PR 3 · `last_batch=false`

- [ ] Tarea 1: crear `rulebooks/build-errors.md` desde `agents/build-resolver.md` (clasificación, causa raíz, criterio de dependencias, escalaciones, fix mínimo, 3 intentos) con el tono bajado (la tabla de anti-patrones pasa a "en vez de → hacé"); borrar el agente. RED: el check de referencias del lint falla hasta la tarea 3.
- [ ] Tarea 2: `dev-common.md` sección "Build roto" (leer el rulebook, 3 intentos, escalar); runbook Fase 2 y 2.8 (re-invocar al mismo dev con el rulebook; CI: build → dev del PR); `governance-playbook.md`; `pr-workflow` (allowed-tools y texto).
- [ ] Tarea 3: skill `orchestrator` (tabla de equipo), README (tabla y "Agentes (12)"), `marketplace.json`; el lint de referencias vuelve a verde.

#### Lote 6 — `db-specialist` → `rulebooks/db-migrations.md` en `backend-dev` (backend-dev)
**Depende de:** Lote 5
**PR:** PR 3 · `last_batch=true`

- [ ] Tarea 1: crear `rulebooks/db-migrations.md` desde `agents/db-specialist.md` (criterios de complejidad, división de schemas con el architect, testing de DB y coverage, expand-contract, EXPLAIN, estado de la DB de test en HANDOFF, sección DB de `ARCHITECTURE.md`); borrar el agente. RED por el lint de referencias.
- [ ] Tarea 2: `backend-dev.md` sección "Lote de DB complejo" (cargar el rulebook; el lote DB va primero y el siguiente lote consume el schema sin modificarlo); `architect.md` (marca `db-complejo` en el plan en vez de asignar `db-specialist`); runbook ("Criterios completos" → "Cuándo un lote es DB complejo"; handoff template; Fase 2 orden de lotes).
- [ ] Tarea 3: menciones en `qa-backend`, `frontend-dev`, `e2e-runner`, `refactor`, `security-reviewer`, `latent-bugs-sweep`, `dev-common.md`, skill, README ("Agentes (11)"), `marketplace.json`; lint verde.
- [ ] Tarea 4: verificación final del branch: suite completa, `validate --strict`, métricas de tono sobre los dos rulebooks nuevos y los agentes tocados.

### Riesgos

- **Migrar cinco guards de formato en un lote** → cada hook tiene test de bloqueo y de paso antes de tocarlo (tareas 1-3 empiezan en rojo); el guard de no-contaminación de la suite protege el repo real.
- **`if` demasiado estrecho abriría un hueco** (el hook ni corre) → se usa `Bash(git *)`/`Bash(gh *)`, superconjunto de todos los anclajes; verificado con compuestos y `git -C`; queda documentado como optimización.
- **Watchdog de `pre-commit-guard` mata suites legítimamente largas** → 540 s default y env sobreescribible; el mensaje dice cómo subirlo. Antes, esas mismas suites hacían pasar el commit sin tests.
- **`.claude/settings.json` duplica los 14 hooks a nivel proyecto** → fuera del brief; abrir issue `stale-docs`/`latent-bug` para quitar el bloque `hooks` (el plugin ya los provee vía skills-dir) y dejar solo `permissions`. Mientras tanto, en este repo el `SessionStart` sin matcher ya dispara en todas las fuentes.
- **El orchestrator no carga la skill** → línea en el núcleo + recordatorio del hook + descripción de la skill con el disparador en la primera frase; `agent-validation.md` lo vuelve verificable a mano.
- **Contradicción residual entre núcleo, skill y runbook** → tarea 2 del lote 4 (grep anti-drift) y el test de tamaño del núcleo evitan que el detalle vuelva a subir.
- **Fusiones rechazadas a medias** → cada una es un lote independiente; el PR 3 puede llevar solo uno.
- **`effort: high` no disponible en algún modelo** → la doc dice que Claude Code corre el nivel que puede; sin efecto adverso.
- **Instalaciones existentes de terceros** → `global/CLAUDE.md` se reinstala con `./install.sh`; la skill llega por `claude plugin update`. README ya lo dice; no cambia.
