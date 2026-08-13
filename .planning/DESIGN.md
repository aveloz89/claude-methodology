# Diseño: Modernización 2026 de memoria y agentes

## Resumen

Tres hooks nuevos no-bloqueantes (`PreCompact`, `SubagentStop`, `SessionEnd`) con sus tests adversariales y registro en ambos settings, migración del estado mutable de `.planning/` a `state.json`, y las actualizaciones de proceso derivadas de la auditoría 2026-08 (smoke test en resume, regla anti-drift, stress-test trimestral, piloto `memory: true` en e2e-runner, docs y limpieza de FOLLOWUPS).

## Search-first

Saltado con criterio del propio agente: el BRIEF ya especifica la tecnología (hooks `command` en shell sobre eventos documentados del harness) y es extensión de código existente. Lo que sí se reutiliza del propio repo:

- **Patrón de hook existente**: stdin JSON + `jq`, sin `set -e`, `exit 0` incondicional (estilo `context-monitor.sh`); resolución de repo vía `git rev-parse` (estilo `session-start-context.sh`).
- **Patrón de test existente**: `tests/adversarial/test-hooks.sh` con helpers `assert_*`; se extiende con helpers de sandbox (repo git temporal + `HOME` override), no se reescribe.
- **Formato de log**: JSONL (append-only, una línea = un evento). Estándar de facto para telemetría; `jq`-friendly y sin read-modify-write (elimina el riesgo de corrupción por escritura concurrente que tendría un JSON único).

## Arquitectura

No cambia: este repo es la metodología misma (shell hooks + docs de proceso + definiciones de agentes). Se siguen las convenciones existentes. **Decisión recurrente nueva** (persistida en `ARCHITECTURE.md`): los artefactos operativos que generan los hooks (logs, snapshots, markers) viven **fuera del worktree**, bajo `~/.claude/methodology/`, nunca dentro del repo del usuario.

---

## Decisiones de diseño (las 4 pedidas)

### D1 — Contrato común de los 3 hooks

Los tres comparten estas reglas (cada hook las implementa; el contrato específico está en su sección):

| Aspecto | Contrato |
|---|---|
| Input | JSON por stdin (`INPUT=$(cat)`). Tolerante: stdin vacío o malformado nunca rompe el hook. |
| Exit code | **Siempre `exit 0`**, en todo camino, incluido error interno. Sin `set -e`. Nunca emiten `{"decision":"block"}` — son observabilidad, no guards. |
| Dependencias | Si falta `jq` o `git` → exit 0 silencioso. |
| Resolución de repo | `TOPLEVEL=$(git rev-parse --show-toplevel 2>/dev/null)`. `PreCompact` y `SessionEnd` exigen repo git **y** `$TOPLEVEL/.planning/` — si falta cualquiera, no-op limpio (exit 0 sin efectos). `SubagentStop` no lo exige (ver D2). |
| Salidas | Solo bajo `~/.claude/methodology/` (usar `$HOME`, nunca `~` literal ni paths hardcodeados — los tests hacen override de `HOME`). |
| Slug de repo | `SLUG=$(echo "$TOPLEVEL" | tr '/' '-')` → p. ej. `-Users-alas-Proyectos-claude-methodology`. Misma convención que los directorios de proyectos de Claude Code; sin colisiones entre repos. |
| Timestamps | UTC ISO-8601: `date -u +%Y-%m-%dT%H:%M:%SZ`. |
| Portabilidad | mtime con helper dual: `stat -f %m` (BSD/macOS) con fallback `stat -c %Y` (GNU/Linux). |

Layout de artefactos (una sola raíz que documentar y limpiar):

```
~/.claude/methodology/
├── logs/subagent-invocations.jsonl        # SubagentStop (global, todos los repos)
├── snapshots/<slug>/<ts>-<trigger>/       # PreCompact (por repo, máx 5)
└── session-end/<slug>.json                # SessionEnd (por repo, solo el último)
```

**Justificación de "fuera del worktree"**: un log/marker dentro de `.planning/` ensuciaría `git status` en cada invocación de subagente, se colaría en commits per-tarea de los devs y metería ruido en cada PR; gitignorearlo desde un hook global sería invasivo en repos del usuario. Fuera del worktree: cero ruido git, sobrevive al cleanup de `.planning/`, y permite agregar métricas entre proyectos.

### D2 — Log de SubagentStop: ubicación y formato

- **Ubicación:** `~/.claude/methodology/logs/subagent-invocations.jsonl` — **un solo archivo global** con campo `repo` por línea. Un archivo por repo fragmentaría las queries de budget sin beneficio; filtrar con `jq 'select(.repo == ...)'` es trivial.
- **Alcance:** loguea en **cualquier** cwd (con o sin `.planning/`): el budget de `agent-budget.md` aplica a todos los proyectos donde se usa la metodología, y el log no toca el worktree, así que no hay costo en loguear siempre. Campos de repo en `null` si no hay repo git.
- **Formato por línea** (JSONL, append con `>>`):

```json
{"ts":"2026-08-13T18:30:00Z","agent":"backend-dev","session":"abc-123","repo":"/Users/alas/Proyectos/miapp","branch":"feature/x","transcript":"/path/al/transcript.jsonl"}
```

| Campo | Fuente | Fallback |
|---|---|---|
| `ts` | `date -u` | — |
| `agent` | stdin: `.agent_type // .subagent_type // "unknown"` (defensivo ante variación del nombre de campo entre versiones del harness) | `"unknown"` |
| `session` | stdin: `.session_id` | `null` |
| `repo` | `git rev-parse --show-toplevel` | `null` |
| `branch` | `git branch --show-current` | `null` |
| `transcript` | stdin: `.agent_transcript_path // .transcript_path` (útil para post-mortem de cortes `BUDGET LIMIT`) | `null` |

La línea se construye con `jq -n --arg ...` (nunca interpolación manual de strings en JSON).

- **Rotación:** si el archivo supera **1 MB** al entrar el hook, `mv` a `subagent-invocations.jsonl.old` (pisando el `.old` anterior) y empezar archivo nuevo. ~1 MB ≈ 5.000 invocaciones: meses de historia con techo duro de 2 MB totales.
- **Consumo:** en Fase 4 (retro), el orchestrator llena las métricas de `LEARNINGS.md` (lotes ejecutados, devs involucrados) con una query documentada en `agent-budget.md` (nueva subsección "Cómo se mide"), p. ej.:

```bash
jq -s '[.[] | select(.repo == "'"$(git rev-parse --show-toplevel)"'")] | group_by(.agent) | map({agent: .[0].agent, invocaciones: length})' ~/.claude/methodology/logs/subagent-invocations.jsonl
```

### D3 — Estado mutable en `.planning/state.json`

**Decisión: archivo separado `state.json`, no bloque fenced dentro de STATE.md.** El hallazgo de Anthropic es sobre archivos JSON; un bloque JSON embebido en markdown mantiene el riesgo de que el modelo reescriba la prosa circundante o rompa el fence al mutar. Además un archivo puro es parseable por hooks (`session-start-context.sh` lo renderiza) sin extraerlo de un .md.

**Reparto de responsabilidades:**

- `state.json` → todo lo **mutable con estado enumerable**: fase del pipeline, checklist de lotes con pass/fail, metadata de la feature (branch, PR).
- `STATE.md` → solo **prosa**: Decisiones (`[D-NN]`), Blockers descritos, contexto libre. Pierde las secciones "Estado actual" y "Progreso" (migran al JSON) y gana una línea de puntero: `El estado mutable (fase, lotes, progreso) vive en state.json.`

**Schema (contrato autoritativo — versión 1):**

```json
{
  "schema": 1,
  "feature": "slug-corto-de-la-feature",
  "branch": "feature/slug",
  "pr": null,
  "updated": "2026-08-13T18:30:00Z",
  "phases": {
    "brainstorming": "done",
    "design": "in_progress",
    "implementation": "pending",
    "docs": "pending",
    "pr": "pending",
    "ci": "pending",
    "review": "pending",
    "e2e": "skipped",
    "merge": "pending"
  },
  "batches": [
    {
      "id": 1,
      "name": "pre-compact-snapshot",
      "agent": "backend-dev",
      "status": "in_progress",
      "tasks_done": 2,
      "tasks_total": 5,
      "current_task": "3: no-op limpio sin .planning"
    }
  ]
}
```

Reglas del schema:

- **Enum de status** (phases y batches): `pending | in_progress | done | failed | skipped`. Ningún otro valor.
- `phases` es un **objeto de claves fijas** (las 9 de arriba, siempre presentes — `skipped` para las que no aplican, p. ej. `e2e` sin UI). Claves fijas = mutación mínima ("cambiar un valor"), menos corruptible que un array.
- `batches` refleja el plan del architect: `id`/`name`/`agent` los siembra el orchestrator al cerrar el diseño; `status`, `tasks_done`, `current_task` mutan durante la ejecución.
- **Quién escribe qué:** el orchestrator crea el archivo al cerrar el diseño y transiciona `phases` y `batches[].status`; el dev actualiza `tasks_done`/`current_task` de **su** batch antes de empezar cada tarea (reemplaza la regla 3 de `agent-budget.md` de "STATE.md actualizado entre tareas"). `pr` se llena en Fase 2.7. `updated` se refresca en toda escritura.
- **Formato en el runbook:** la sección `### STATE.md` de `orchestrator-runbook.md` se reemplaza por `### STATE.md + state.json` con este schema, el reparto prosa/JSON y la tabla de quién-escribe-qué. `agent-budget.md` regla 3 y CLAUDE.md ("Estado persistente: .planning/") se reconcilian (regla anti-drift aplicada en este mismo PR).
- **No se migra el `state` de la feature en vuelo:** el STATE.md actual de esta feature sigue en markdown; el formato nuevo aplica desde la siguiente feature. Migrar a mitad de ejecución agrega riesgo sin beneficio (descartado explícitamente).

### D4 — Snapshot de PreCompact: qué y a dónde

- **Qué:** copia **completa** de `$TOPLEVEL/.planning/` (recursiva, incluye `reviews/`). Razón: los archivos en riesgo son los que tienen ediciones sin commitear al momento del compact — y eso puede incluir un DESIGN.md recién escrito, no solo STATE/HANDOFF. `.planning/` pesa decenas de KB; la copia total es más simple y robusta que elegir archivos.
- **A dónde:** `~/.claude/methodology/snapshots/<slug>/<YYYYmmdd-HHMMSS>-<trigger>/` donde `trigger` viene del stdin (`.trigger`: `auto` | `manual`; fallback `unknown`).
- **Metadata:** el snapshot incluye un `meta.json` generado por el hook:

```json
{"ts":"2026-08-13T18:30:00Z","trigger":"auto","branch":"feature/x","head":"abc1234","repo":"/Users/alas/Proyectos/miapp"}
```

- **Retención (evita acumulación infinita):** tras crear el snapshot, conservar solo los **5 más recientes** por slug. Orden lexicográfico del nombre (= cronológico por el prefijo timestamp): `ls -1 | sort -r | tail -n +6 | xargs rm -rf` (portable; `head -n -5` no existe en macOS).
- **Restauración:** manual, bajo demanda — no hay hook de restore. Si post-compact el orchestrator detecta STATE/HANDOFF corrupto o inconsistente, copia de vuelta desde el snapshot más reciente. Se documenta en la fila nueva de "Errores comunes" del runbook.

---

## Contratos por hook

### `hooks/pre-compact-snapshot.sh` — evento `PreCompact`

| | |
|---|---|
| Lee | stdin JSON: `.trigger` (opcional). No usa env vars. |
| Gate | Repo git con `.planning/` en el toplevel. Si no → exit 0 sin efectos. |
| Hace | Snapshot según D4 + retención de 5. |
| Escribe | `~/.claude/methodology/snapshots/<slug>/<ts>-<trigger>/` (copia de `.planning/` + `meta.json`). |
| Stdout | Nada (o una línea informativa; no alimenta al modelo en este evento). |
| Errores | exit 0 siempre. Un `cp` parcial no se reintenta. |
| Timeout | 15s (copia de archivos). |

### `hooks/subagent-stop-log.sh` — evento `SubagentStop`

| | |
|---|---|
| Lee | stdin JSON: `.agent_type` / `.subagent_type`, `.session_id`, `.agent_transcript_path` / `.transcript_path`. |
| Gate | Ninguno de repo (loguea siempre). Solo requiere `jq`; sin `jq` → exit 0. |
| Hace | Append de una línea JSONL según D2 + rotación a 1 MB. |
| Escribe | `~/.claude/methodology/logs/subagent-invocations.jsonl` (+ `.old` al rotar). |
| Stdout | Nada. |
| Errores | exit 0 siempre; stdin malformado → no escribe nada (nunca una línea corrupta). |
| Timeout | 10s. |

### `hooks/session-end-check.sh` — evento `SessionEnd`

| | |
|---|---|
| Lee | stdin JSON: `.reason` (opcional: `clear`, `logout`, `prompt_input_exit`, `other`). |
| Gate | Repo git con `.planning/STATE.md`. Si no → exit 0 sin efectos. |
| Hace | Heurística de staleness. `STATE_MTIME` = max(mtime de `STATE.md`, mtime de `state.json` si existe). Señales: **S1** `git log -1 --format=%ct` > STATE_MTIME (hubo commits después de la última actualización de estado); **S2** existe algún archivo en `git status --porcelain` fuera de `.planning/` con mtime > STATE_MTIME (hubo trabajo sin commitear posterior). Si S1 ∨ S2 → escribe marker. |
| Escribe | `~/.claude/methodology/session-end/<slug>.json` — **sobrescribe** (solo importa el último cierre; sin acumulación): `{"ts":"...","reason":"other","branch":"...","head":"abc1234","signals":["commits_after_state","dirty_files_after_state"]}` |
| Stdout | Nada (la sesión ya terminó; no hay modelo que lea). |
| Errores | exit 0 siempre. |
| Timeout | 10s. |

### Extensión de `hooks/session-start-context.sh` (cierre del loop)

Dos adiciones al hook existente, manteniendo su estilo:

1. **Consumo del marker de SessionEnd**: si existe `~/.claude/methodology/session-end/<slug>.json` para este repo → imprimir `⚠️ La sesión anterior cerró con STATE posiblemente desactualizado (señales: <signals>). Verifica .planning/STATE.md y state.json antes de continuar.` y **borrar el marker** (consume-once — un aviso, una vez).
2. **Render de `state.json`**: si existe `.planning/state.json` → imprimir resumen vía `jq`: fase activa + una línea por batch (`[status] id name — tasks_done/tasks_total`). Complementa (no reemplaza) el `head -30 STATE.md` actual.

---

## Infraestructura de settings (registro de hooks)

Los 3 hooks se registran en **ambos** archivos (lección C5: hook documentado ≠ hook instalado). Sin `matcher` (los tres eventos aplican siempre).

**`settings.json` raíz** (se instala a `~/.claude/`):

```json
"PreCompact":    [{ "hooks": [{ "type": "command", "command": "~/.claude/hooks/pre-compact-snapshot.sh", "timeout": 15 }] }],
"SubagentStop":  [{ "hooks": [{ "type": "command", "command": "~/.claude/hooks/subagent-stop-log.sh",    "timeout": 10 }] }],
"SessionEnd":    [{ "hooks": [{ "type": "command", "command": "~/.claude/hooks/session-end-check.sh",    "timeout": 10 }] }]
```

**`.claude/settings.json`** (proyecto, paths relativos): mismos tres eventos con `"command": "bash hooks/<nombre>.sh"`, sin `statusMessage` (eventos no interactivos).

Además, el `settings.json` raíz ya tiene en el working tree `effortLevel: "xhigh"` y `agentPushNotifEnabled: true` (D-05 del BRIEF): viajan en el commit del Lote 1 (mismo archivo). Tras cada edición de settings: `jq . <archivo>` como validación de sintaxis.

Sin variables de entorno nuevas; no aplica `.env.example`. `install.sh` no cambia (symlinkea el directorio `hooks/` completo; los archivos nuevos se propagan solos).

## Archivos afectados

| Archivo | Cambio |
|---|---|
| `hooks/pre-compact-snapshot.sh` | **Nuevo** — snapshot de `.planning/` pre-compactación |
| `hooks/subagent-stop-log.sh` | **Nuevo** — log JSONL de invocaciones de subagentes |
| `hooks/session-end-check.sh` | **Nuevo** — marker de STATE desactualizado al cerrar |
| `hooks/session-start-context.sh` | Consume marker de SessionEnd + renderiza `state.json` |
| `settings.json` | Registro de 3 eventos nuevos (+ `effortLevel`/`agentPushNotifEnabled` ya en worktree) |
| `.claude/settings.json` | Registro de 3 eventos nuevos (paths relativos) |
| `tests/adversarial/test-hooks.sh` | Helpers de sandbox + casos de los 3 hooks + marker |
| `rulebooks/orchestrator-runbook.md` | Sección `STATE.md` → `STATE.md + state.json` (schema D3); subsección "Retomar (resume)" con smoke test; sección "Anti-drift: DoD de cambios de proceso"; fila en Errores comunes (restore de snapshot); TOC actualizado |
| `rulebooks/agent-budget.md` | Regla 3 apunta a `state.json`; subsección "Cómo se mide" con query jq |
| `rulebooks/validation-schedule.md` | Sección "Stress-test trimestral de supuestos del harness" |
| `agents/e2e-runner.md` | Frontmatter `memory: true` + uso de memoria en sección "Tests flaky" |
| `README.md` | Tabla de hooks 11→14 + árbol de estructura |
| `CLAUDE.md` | Sección Hooks (3 nuevos en la lista de background), Pause/Resume (smoke test), Estado persistente (`state.json`) |
| `.planning/FOLLOWUPS.md` | Retirar los 6 items que este PR implementa |

## Contratos API / Esquema DB / Frontend

No aplican (repo de metodología: shell + markdown). El "contrato" de esta feature son los schemas de D1–D4 de este documento.

## Contenido nuevo en rulebooks (guía para el dev)

- **Runbook — "Retomar (resume)"** (subsección nueva junto al formato de `HANDOFF.md`): pasos al retomar = (1) leer HANDOFF + STATE + state.json; (2) **smoke test antes de tocar código**: correr el test suite básico del proyecto — misma detección de runner que `pre-commit-guard.sh` (pnpm/yarn/npm test, pytest); si no hay runner, se omite explícitamente y se anota; si está rojo, diagnosticar ANTES de retomar la tarea pendiente (el rojo puede ser el bug no documentado de la sesión anterior); (3) eliminar HANDOFF.md.
- **Runbook — "Anti-drift: DoD de cambios de proceso"** (sección nueva): todo PR que cambie el flujo (fases, hooks, formatos de `.planning/`, reglas de agentes) incluye como parte de su Definition of Done: grep de los términos afectados en `CLAUDE.md`, `README.md`, `rulebooks/`, `agents/` y `skills/`, y reconciliación de todo documento que describa el comportamiento cambiado. Las 7 contradicciones de la auditoría de julio eran todas de esta clase.
- **validation-schedule.md — "Stress-test trimestral de supuestos"**: cada trimestre (o al cambiar de modelo base): (1) elegir UNA pieza de andamiaje (template de reporte, sección de detalle de un agente, un hook informativo); (2) quitarla en un branch; (3) correr `tests/adversarial/` + un prompt canónico de `tests/validation/`; (4) si el comportamiento sobrevive sin la pieza → PR que la poda; si no → documentar en VALIDATION-LOG.md que sigue siendo necesaria.
- **e2e-runner — memoria persistente**: frontmatter `memory: true`. En la sección "Tests flaky": al iniciar cualquier corrida, consultar la memoria propia por flakes previos de los tests del scope; al detectar un flaky, registrar en memoria `{test, fecha, PR, conteo de ocurrencias}`. La memoria es el tracking **entre sesiones** (hoy inexistente); la issue `flaky-test` en GitHub sigue siendo la fuente visible para el equipo — la memoria decide cuándo un flake es reincidente (>1 vez) y por tanto exige issue.

## Plan de implementación

**Estrategia de PR:** single-PR — decidida por el usuario (BRIEF D-01): branch existente `feature/harden-pre-merge-check`, un único PR a `dev` que lleva el hardening ya commiteado + esta feature. Excepción consciente a "un PR por objetivo", documentada.

**Todos los lotes: `backend-dev`** (shell + markdown; no hay frontend ni DB). **Todos secuenciales**: los lotes 1–3 editan los mismos archivos compartidos (`settings.json`, `.claude/settings.json`, `tests/adversarial/test-hooks.sh`) y los lotes 4–5 tocan ambos `CLAUDE.md`/rulebooks — paralelizar garantizaría conflictos. Cada hook se registra en settings en su propio lote (nunca hay una referencia colgante a un hook que aún no existe).

**Nota TDD por lote:** los hooks de los lotes 1–3 siguen Red→Green con `tests/adversarial/test-hooks.sh` (obligatorio: caso de test primero, correr y ver fallar, implementar, ver pasar, commit). Las tareas marcadas **[config]** o **[docs]** están exentas de TDD literal (configuración/documentación, per CLAUDE.md); su verificación es `jq .` para JSON y grep de consistencia para markdown.

#### Lote 1 — Hook PreCompact + infra de test sandbox (backend-dev)
**Depende de:** ninguno
**PR:** PR único

- [ ] Tarea 1: Extender `test-hooks.sh` con infraestructura de sandbox para hooks no-bloqueantes: helper que crea repo git temporal con `.planning/` poblado, override de `HOME` a un dir temporal, y helper `assert_exit0` que verifica exit 0 + un efecto esperado (o su ausencia) en filesystem. Verificable con un caso trivial que la usa.
- [ ] Tarea 2: `pre-compact-snapshot.sh` crea snapshot completo de `.planning/` + `meta.json` en `~/.claude/methodology/snapshots/<slug>/<ts>-<trigger>/` (test: tras invocar con `{"trigger":"auto"}`, el snapshot existe con los archivos y el meta correcto).
- [ ] Tarea 3: No-op limpio: sin `.planning/`, fuera de repo git, o con stdin vacío/malformado → exit 0 sin crear nada (tests de los tres casos).
- [ ] Tarea 4: Retención: con 6 snapshots existentes para el slug, tras invocar quedan exactamente los 5 más recientes (test).
- [ ] Tarea 5: **[config]** Registrar `PreCompact` en `settings.json` raíz y `.claude/settings.json`; el commit incluye `effortLevel`/`agentPushNotifEnabled` ya presentes en el worktree. Verificación: `jq .` en ambos archivos.

#### Lote 2 — Hook SubagentStop (backend-dev)
**Depende de:** Lote 1 (helpers de sandbox en test-hooks.sh)
**PR:** PR único

- [ ] Tarea 1: `subagent-stop-log.sh` appendea línea JSONL con `{ts, agent, session, repo, branch, transcript}` a `~/.claude/methodology/logs/subagent-invocations.jsonl`, construida con `jq -n` (test: invocar con `agent_type: "backend-dev"` → línea válida con esos campos).
- [ ] Tarea 2: Robustez: `agent_type` ausente → `agent: "unknown"` (probando fallback `.subagent_type`); stdin malformado → exit 0 sin appendear nada; `jq` ausente en PATH → exit 0 (tests).
- [ ] Tarea 3: Rotación: con un log >1MB preexistente, al invocar se mueve a `.old` y la línea nueva queda en un archivo fresco (test con archivo inflado por `dd`/loop).
- [ ] Tarea 4: **[config]** Registrar `SubagentStop` en ambos settings. Verificación `jq .`.
- [ ] Tarea 5: **[docs]** `agent-budget.md`: subsección "Cómo se mide" con la ubicación del log, el schema por línea y la query jq de ejemplo para la retro de Fase 4; actualizar la sección "Cómo se valida" para referenciarla.

#### Lote 3 — Hook SessionEnd + integración en session-start (backend-dev)
**Depende de:** Lote 2 (mismos archivos settings/tests)
**PR:** PR único

- [ ] Tarea 1: `session-end-check.sh` escribe marker JSON en `~/.claude/methodology/session-end/<slug>.json` cuando hay señal S1 (test: sandbox con `STATE.md` de mtime viejo — `touch -t` — y un commit posterior → marker con `signals: ["commits_after_state"]`).
- [ ] Tarea 2: Señal S2 y caso fresco: archivo dirty fuera de `.planning/` con mtime posterior → marker con `dirty_files_after_state`; STATE.md/state.json más recientes que todo → NO se escribe marker; sin `.planning/` → exit 0 sin efectos (tests). Marker se sobrescribe, no acumula.
- [ ] Tarea 3: `session-start-context.sh` consume el marker: si existe para el slug del repo, imprime el aviso con las señales y lo borra (test: output contiene el aviso y el archivo desaparece; segunda invocación ya no avisa).
- [ ] Tarea 4: `session-start-context.sh` renderiza `.planning/state.json` si existe: fase activa + línea por batch con status y progreso (test: sandbox con state.json de ejemplo → output contiene el resumen).
- [ ] Tarea 5: **[config]** Registrar `SessionEnd` en ambos settings. Verificación `jq .`.

#### Lote 4 — Rulebooks: state.json, resume, anti-drift, stress-test (backend-dev)
**Depende de:** Lote 3 (el render de state.json ya existe; el schema documentado debe coincidir con lo implementado)
**PR:** PR único

- [ ] Tarea 1: **[docs]** Runbook: reemplazar la sección `### STATE.md` por `### STATE.md + state.json` con el schema completo de D3 (enums, claves fijas de phases, tabla quién-escribe-qué, regla "prosa en .md, estado en .json") y actualizar el TOC.
- [ ] Tarea 2: **[docs]** Runbook: subsección "Retomar (resume)" con el smoke test (detección de runner como `pre-commit-guard.sh`; sin runner → se omite y anota; rojo → diagnosticar antes de retomar) + fila nueva en "Errores comunes": estado de `.planning/` corrupto post-compact → restaurar del snapshot más reciente en `~/.claude/methodology/snapshots/<slug>/`.
- [ ] Tarea 3: **[docs]** Runbook: sección "Anti-drift: DoD de cambios de proceso" (grep + reconciliación de documentos que describen el flujo, como DoD de todo PR que cambie el proceso); actualizar TOC. `agent-budget.md` regla 3: el dev actualiza `state.json` (su batch) entre tareas, no STATE.md.
- [ ] Tarea 4: **[docs]** `validation-schedule.md`: sección "Stress-test trimestral de supuestos del harness" con el proceso de 4 pasos (elegir pieza → quitarla en branch → correr adversarial + validation → podar o documentar).
- [ ] Tarea 5: **[docs]** `CLAUDE.md`: añadir el smoke test a "Pause / Resume" y `state.json` a "Estado persistente: .planning/" (una línea cada uno — mantener el archivo bajo las ~200 líneas).

#### Lote 5 — Piloto memory, docs de hooks y cierre anti-drift (backend-dev)
**Depende de:** Lote 4
**PR:** PR único

- [ ] Tarea 1: **[docs]** `agents/e2e-runner.md`: frontmatter `memory: true` + instrucciones en "Tests flaky": consultar memoria al iniciar, registrar `{test, fecha, PR, conteo}` al detectar flaky, usarla para decidir reincidencia (>1 → issue `flaky-test`); la issue sigue siendo la fuente visible, la memoria es el tracking entre sesiones.
- [ ] Tarea 2: **[docs]** `README.md`: tabla de hooks 11→14 (los 3 nuevos con evento y descripción) + los 3 archivos en el árbol de estructura.
- [ ] Tarea 3: **[docs]** `CLAUDE.md`: sección "Hooks", lista de background: añadir snapshot de `.planning/` antes de compactar, log de invocaciones de subagentes y verificación de STATE al cerrar sesión.
- [ ] Tarea 4: **[docs]** `.planning/FOLLOWUPS.md`: retirar los 6 items implementados por este PR (smoke test, JSON de estado, hooks nuevos, piloto memory, anti-drift, stress-test trimestral). Quedan: plugin, Agent Teams y los previos de mayo/abril.
- [ ] Tarea 5: **[docs]** Cierre anti-drift (aplicación inmediata de la regla nueva): grep de `PreCompact|SubagentStop|SessionEnd|state.json|STATE.md` en `CLAUDE.md`, `README.md`, `rulebooks/`, `agents/`, `skills/` y verificación de que ningún documento quedó describiendo el flujo viejo; correr `bash tests/adversarial/test-hooks.sh` completo como verificación final del PR (este es el último lote → `last_batch=true`).

### Riesgos

- **Los nombres de campo del stdin pueden variar entre versiones del harness** (`agent_type` vs `subagent_type`, `agent_transcript_path`) → jq defensivo con fallbacks en cadena y `"unknown"`/`null` como default; el hook nunca falla por un campo ausente. Si el log muestra `unknown` sistemático, es señal de ajustar el nombre del campo (una línea).
- **Portabilidad macOS/Linux de `stat` y `head -n -N`** → helper dual de mtime y `sort -r | tail -n +6` (documentados en D1/D4); los tests corren en macOS localmente y el diseño evita todo GNU-ismo.
- **Tres lotes editan `settings.json`, `.claude/settings.json` y `test-hooks.sh`** → mitigado con ejecución estrictamente secuencial y `jq .` tras cada edición de settings.
- **Falso positivo del aviso de SessionEnd** (p. ej. commit de docs que legítimamente no toca STATE) → el aviso es informativo, consume-once, y pide "verifica" en vez de afirmar corrupción. Costo de un falso positivo: una lectura de STATE.md.
- **`test-hooks.sh` usa `set -e` global**: los helpers nuevos de sandbox deben capturar exit codes con `|| exit_code=$?` como los existentes para no abortar la suite — el dev del Lote 1 hereda ese patrón, no lo cambia.
- **Snapshot durante compact con `.planning/` grande** → timeout de 15s sobra para decenas de KB; si un futuro `.planning/` fuera enorme, el hook expira sin bloquear la compactación (no-bloqueante por diseño de evento).
- **Deriva doc-código sobre el schema de state.json** → el runbook documenta exactamente el schema de D3 y el render del Lote 3 lo consume; la tarea 5 del Lote 5 hace el grep de reconciliación final.
