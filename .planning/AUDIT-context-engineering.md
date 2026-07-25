# Auditoría de context engineering — claude-methodology

**Fecha:** 2026-07-24
**Disparador:** [The new rules of context engineering for Claude 5 generation models](https://claude.com/blog/the-new-rules-of-context-engineering-for-claude-5-generation-models)
**Alcance:** `CLAUDE.md`, `rules/`, `rulebooks/`, `agents/`, `settings.json`, `README.md`

---

## 0. Método

Se leyó el repo completo (13 agentes, 4 rulebooks, 11 rules, ambos `settings.json`, `install.sh`) y se clasificó cada bloque en tres categorías:

| Categoría | Definición | Qué se hace |
|---|---|---|
| **Gotcha** | Conocimiento no derivable del código ni del sentido común. Se ganó con dolor. | Se queda. Vale cada token. |
| **Decisión** | Preferencia explícita del usuario sobre cómo debe operar el sistema. | Se queda intacta. El post no aplica. |
| **Andamiaje** | Existe porque un modelo anterior no razonaba bien solo. | Candidato a poda. |

La distinción clave: el post dice "reemplaza reglas rígidas por criterio del modelo", pero eso aplica a **andamiaje**, no a decisiones. "Nunca mergees sin mi aprobación" no es una compensación por un modelo débil — es una política. Se queda.

---

## 1. Hallazgo estructural: qué se carga en cada sesión

### El mecanismo (confirmado en la documentación)

`~/.claude/rules/*.md` se carga automáticamente. El frontmatter `paths:` decide **cuándo**:

- **Con `paths:`** → solo entra en contexto cuando Claude toca archivos que matchean.
- **Sin `paths:`** → entra en **todas las sesiones, de todos los proyectos**.

Los docs son explícitos: *"Rules load into context every session or when matching files are opened. For task-specific instructions that don't need to be in context all the time, use skills instead."* Y para CLAUDE.md: *"target under 200 lines"*.

### El estado actual

| Archivo | Líneas | `paths:` | ¿Siempre en contexto? |
|---|---|---|---|
| `CLAUDE.md` | 252 | — | Sí (es CLAUDE.md) |
| `rules/implementation-principles.md` | 130 | **no** | **Sí** |
| `rules/self-reflection.md` | 93 | **no** | **Sí** |
| `rules/pr-workflow.md` | 149 | **no** | **Sí** |
| `rules/typescript.md`, `python.md`, `go.md`, `rust.md`, `csharp.md`, `html.md`, `css.md`, `docker.md` | — | sí | No — solo al tocar el lenguaje |

**Total permanente: 624 líneas / ~6.700 palabras**, en cada sesión, aunque la tarea sea leer un blog post.

Las 8 rules por lenguaje están bien construidas: tienen `paths:` y cargan solo cuando corresponde. El problema son las 3 que quedaron sin frontmatter — probablemente porque se escribieron antes de que existiera el mecanismo.

**Peor caso concreto:** `pr-workflow.md` (149 líneas) incluye el presupuesto de minutos de CI, la configuración de branch protection y la política de scans semanales. Es 100% relevante en Fase 2.7–3 y 0% relevante mientras un dev escribe un test.

---

## 2. Contradicciones detectadas (el anti-patrón #1 del post)

El post nombra explícitamente el contexto contradictorio como el peor anti-patrón. Hay siete instancias reales, no hipotéticas. Todas son consecuencia del cambio de presupuesto de CI (PR #44), que movió el push+PR del dev al orchestrator pero no actualizó todo lo que lo describía.

### C1 — `agent-budget.md` quedó stale respecto al flujo actual (bloqueante)

`rulebooks/agent-budget.md` define el Definition of Done de cada dev:

> **Done = todos los commits per-tarea hechos + push + PR** *(línea 61)*

y en el fallback de budget: *"4. Push de todo"* (línea 67), más *"push final ocurren al cierre de la invocación"* (línea 51).

Los tres dev agents dicen lo contrario, en negrita:

> **En NINGÚN caso haces push ni creas PR** — `backend-dev.md:185`, `frontend-dev.md:176`, `db-specialist.md:208`

Y los tres agentes **referencian `agent-budget.md` como fuente de verdad** en su sección "Reglas heredadas". Es decir: el dev recibe la instrucción y su negación, ambas marcadas como autoritativas.

### C2 — Cada dev agent se contradice a sí mismo

El mismo archivo que dice "en NINGÚN caso haces push" instruye a pushear en el fallback de budget:

- `backend-dev.md:269` → "3. Push del branch"
- `frontend-dev.md:270` → "3. Push del branch"
- `db-specialist.md:311` → "4. Push del branch"
- `refactor.md:366` → "3. Push del branch"

Puede que sea intencional (el caso de budget agotado es excepcional y justifica pushear el WIP), pero **no está dicho en ningún lado**. Tal como está, el dev tiene que adivinar cuál gana.

### C3 — `wip:` vs `WIP:`

`CLAUDE.md` define el prefijo `wip:` en minúscula y prohíbe que llegue a `dev`/`main`. `agent-budget.md:66` dice `WIP:` en mayúscula. Los dev agents usan `wip:`. Trivial, pero es exactamente el tipo de ruido que el post pide eliminar.

### C4 — El architect declara un modelo distinto al que documenta CLAUDE.md

`agents/architect.md` tiene `model: fable` en su frontmatter. `CLAUDE.md` lo documenta como **opus** en la tabla del equipo, y la sección "Degradación de modelo cuando opus está rate-limited" dice *"architect → esperar y reintentar (no degradar)"* — una regla que solo tiene sentido si el architect corre en opus. O el frontmatter está mal, o CLAUDE.md describe un sistema que ya no existe.

### C5 — CLAUDE.md documenta hooks que no están instalados fuera de este repo

La tabla "Comandos bloqueados" de `CLAUDE.md` afirma que estos hooks bloquean:

| Hook | ¿En `.claude/settings.json` (este repo)? | ¿En `settings.json` (el que instala `install.sh`)? |
|---|---|---|
| `pre-commit-guard.sh` | sí | **sí** |
| `pre-push-guard.sh` | sí | **sí** |
| `block-admin-merge.sh` | sí | **no** |
| `block-force-push.sh` | sí | **no** |
| `block-hard-reset.sh` | sí | **no** |
| `pre-merge-check.sh` | sí | **no** |
| `pre-release-sweep.sh` | sí | **no** |

`install.sh` symlinkea `settings.json` a `~/.claude/settings.json`. Ese archivo registra 2 de los 7 hooks de `PreToolUse`. **En cualquier proyecto que no sea este, `gh pr merge --admin`, `git push --force` y `git reset --hard` no están bloqueados**, aunque CLAUDE.md diga que sí.

Es el peor tipo de contradicción: no confunde al modelo, le da una garantía de seguridad falsa. Y `governance-playbook.md` §4 ("Hook falla silenciosamente → verificar en settings.json que el hook está configurado") describe exactamente este caso sin que nadie lo haya corrido.

### C6 — El checklist obligatorio del security-reviewer no está en el security-reviewer

`rules/pr-workflow.md` §2 define un "**Checklist obligatorio para security-reviewer**" con 4 puntos (rate limiting en rutas de mutación, shell injection, prototype pollution, reflected input) y explica por qué existe: *"CodeQL atrapó missing rate limiting en rutas que el security-reviewer no detectó"*.

`agents/security-reviewer.md` no lo menciona. El agente que debe ejecutarlo tiene 396 líneas de checklist OWASP y ninguno de esos 4 puntos.

Esto es literalmente el mito #4 del post invertido: la instrucción vive lejos de la herramienta que la ejecuta. La corrección de un fallo real quedó archivada en un documento de proceso.

### C7 — El cheat sheet de CLAUDE.md admite ser redundante

La sección "Referencia rápida" abre con: *"Mezcla recap del cuerpo con reglas que solo viven aquí. **En conflicto con el cuerpo, el cuerpo gana**."*

Esa cláusula de desempate existe porque hay duplicación consciente. De los 14 puntos, la mayoría son recap (1, 3, 4, 5, 6, 7, 9, 11, 12, 13 tienen su versión larga arriba). Solo unos pocos aportan algo nuevo (2, 8, 10, 14).

### Extra (cosmético) — `README.md` está desactualizado

Dice "Agentes (8)" cuando hay 13, lista `orchestrator` como agente (no existe el archivo), y "Skills (1)" cuando hay 2. No entra en contexto, así que no afecta al modelo — pero es la primera pantalla del repo.

---

## 3. Duplicación medida

| Bloque | Copias | Tamaño típico | Total aprox. |
|---|---|---|---|
| "Debugging sistemático" (4 fases: evidencia → patrones → hipótesis → fix) | 7 agentes | 32 líneas en los devs, 10 en QA | ~140 líneas |
| Bloque Gitflow ("el orchestrator ya creó el branch…") — idéntico palabra por palabra | 5 agentes | 12 líneas | ~60 líneas |
| "Correcciones post-review" (6 pasos idénticos) | 4 agentes | 8 líneas | ~32 líneas |
| "Budget agotado a mitad de lote" | 4 agentes | 14 líneas | ~56 líneas |
| Criterios `db-specialist` vs `backend-dev` (las mismas 9 viñetas) | **6 archivos**: `CLAUDE.md`, `orchestrator-runbook.md`, `backend-dev.md`, `db-specialist.md`, `qa-backend.md`, `architect.md` | 10 líneas | ~60 líneas |
| Templates de reporte fill-in-the-blank | `qa-backend` (85 líneas), `qa-frontend` (75), `security-reviewer` (60), + 7 más | — | ~350 líneas |

Los criterios de DB en 6 lugares son el caso más caro: si el umbral de ">1M filas" cambia alguna vez, hay que acertarle a los 6.

---

## 4. Clasificación por archivo

### `CLAUDE.md` (252 líneas — objetivo: <200)

| Bloque | Categoría | Acción |
|---|---|---|
| "REGLA FUNDAMENTAL: no escribes código" | **Decisión** | Queda. Es el rol, no una limitación del modelo |
| Gitflow, formato de commits, `--no-ff`, no borrar `dev` | **Decisión** | Queda |
| Dual review bloqueante, 80% coverage, TDD obligatorio | **Decisión** | Queda |
| Idioma (comunicación español / código inglés) | **Decisión** | Queda |
| Jerarquía de conflicto security vs QA | **Gotcha** | Queda — es una zona gris real, resuelta |
| Política de E2E flaky (1 re-run, 2 fallos = real, issue al 2º flake) | **Gotcha** | Queda |
| Criterios db-specialist vs backend-dev | Duplicado ×6 | Dejar solo el resumen de 1 línea + link |
| Tabla de hooks | **Desactualizada** | Corregir (ver C5) |
| Tabla de agentes con modelos | **Desactualizada** | Corregir (ver C4) |
| Cheat sheet (14 puntos) | **Andamiaje** | Borrar los 10 que son recap; los 4 únicos suben al cuerpo |
| Inicio de sesión (3 comandos) | **Andamiaje** | El hook `session-start-context.sh` ya lo hace; el propio texto lo admite ("úsalo como fallback") |
| Tabla de reglas por lenguaje (extensión → archivo) | **Andamiaje** | El frontmatter `paths:` ya resuelve el ruteo. La tabla replica a mano lo que el mecanismo hace solo |

### `rules/` — las tres siempre-on

| Archivo | Veredicto |
|---|---|
| `implementation-principles.md` | **Mayormente gotcha.** La definición de "boundary" (qué validar y qué no) es la clase de calibración que evita falsos positivos recurrentes. La sección "Brief vs principios" resuelve un conflicto real de autoridad. **Se queda íntegro — pero necesita `paths:`** de código |
| `self-reflection.md` | **Mixto.** El proceso (clasificar trivial / controvertida / legacy → arreglar o issue) es decisión, se queda. El detalle mecánico (tope de ~50 líneas, umbral de >15 archivos para agrupar por lenguaje) es andamiaje: son heurísticas que el modelo aplica solo. **Necesita `paths:`** |
| `pr-workflow.md` | **Decisión pura, ubicación equivocada.** Cada regla es una preferencia explícita, muchas fechadas y justificadas (2026-07-19). Nada que podar del contenido. Pero es el archivo menos aplicable a una sesión promedio y el segundo más grande. **Candidato #1 a skill** |

Gotchas de `pr-workflow.md` que valen su peso en oro y hay que preservar textual:

- *"jsdom no renderiza CSS, no aplica `@media`/`@page`, no ejecuta `<dialog>`/top-layer, no negocia Content-Type real"* → con los 3 bugs concretos que se escaparon. Explica **por qué** el E2E es obligatorio, no solo que lo es.
- *"Distinguir bug de código vs bundle stale: HMR + service worker de PWA pueden servir módulos viejos. Reiniciar el contenedor ANTES de escalar al dev."*
- *"Los crons corren sobre el default branch → hace falta `ref: dev` explícito."*
- *"Un scan que corre pero no está en `required_status_checks.contexts` es informativo, no bloqueante."*

### `rulebooks/`

| Archivo | Líneas | Veredicto |
|---|---|---|
| `orchestrator-runbook.md` | 619 | **Bien diseñado.** Ya es revelación progresiva: se lee bajo demanda y su encabezado lo dice. Contiene los formatos exactos y los comandos `gh` — justo lo que el post recomienda diferir. Sin cambios |
| `agent-budget.md` | 83 | **Stale (C1).** Contenido válido, DoD contradictorio. Arreglar |
| `governance-playbook.md` | 169 | Decision trees, casi todos = decisión del usuario. Se queda. §4 aplica a C5 |
| `validation-schedule.md` | 45 | Sin observaciones |

### `agents/` (13 archivos, ~33.000 palabras)

Cada uno se carga solo cuando se invoca ese agente, así que el costo es por invocación, no permanente. Aun así:

| Bloque | Categoría | Acción propuesta |
|---|---|---|
| "Debugging sistemático" ×7 | **Andamiaje** | Es método general de ingeniería que un modelo Claude 5 aplica sin que se lo pidan. Borrar de los 7. Si preocupa perderlo, dejar una línea: *"debuggea con evidencia → hipótesis → verificación, nunca por prueba y error"* |
| Gitflow ×5, post-review ×4, budget ×4 | **Duplicación** | Extraer a `rulebooks/dev-common.md`, referenciado desde "Reglas heredadas" (patrón que los agentes ya usan y funciona) |
| Templates de reporte exhaustivos | **Andamiaje** | Reducir al esqueleto (Scope / Findings / Veredicto / Bloqueantes / Sugerencias). Los checklists `[OK/ISSUE]` sección por sección fuerzan a reportar 20 líneas de "OK" aunque no aplique nada |
| Listas de patrones de `latent-bugs-sweep` (TS/Py/Go/Rust/C#, ~175 líneas) | **Mixto** | Los patrones específicos y no obvios se quedan; los genéricos ("no ignores el error") sobran |
| Checklist OWASP de `security-reviewer` | **Gotcha** | Se queda. Las calibraciones de severidad (MD5/SHA256 → CRITICAL aunque tenga salt; `Allow-Origin: *` + credentials) son exactamente el tipo de opinión que el post dice codificar |
| "Validación en boundaries: matiz crítico" (`qa-backend:49`) | **Gotcha excelente** | Se queda tal cual. Previene un falso positivo concreto y recurrente |
| Prefijos de env var por framework (`NEXT_PUBLIC_`/`VITE_`) | **Gotcha** | Se queda |
| `CREATE INDEX CONCURRENTLY` no va dentro de transacción | **Gotcha** | Se queda |

Nota de estilo menor: hay voseo mezclado con tuteo dentro del mismo archivo (`security-reviewer.md`: "Ignorá", "Usá", "Reservá", "trazás" junto a "verifica", "reporta"; `qa-backend.md`: "indicá", "evaluás", "Usá"). No afecta comportamiento; se limpia gratis en el mismo paso.

---

## 5. Propuesta

Cinco fases, ordenadas por relación impacto/riesgo. Cada una es un PR independiente.

### Fase 1 — Coherencia (riesgo cero, impacto alto)

Nada de esto cambia el diseño; solo elimina información falsa o contradictoria.

1. `agent-budget.md`: DoD y fallback alineados al flujo actual (dev commitea, orchestrator pushea). Aclarar explícitamente si el push del WIP por budget agotado es la excepción. Unificar `wip:`.
2. Dev agents: hacer explícita la excepción de push (C2) o eliminarla.
3. `architect.md` vs `CLAUDE.md`: decidir el modelo real y dejar una sola versión (C4).
4. **`settings.json`: registrar los 5 hooks faltantes** (C5). Es el punto de mayor impacto de toda la auditoría y no tiene nada que ver con el post — es un agujero de seguridad en la instalación.
5. Mover el checklist de seguridad de `pr-workflow.md` §2 a `agents/security-reviewer.md` (C6).
6. `README.md`: 13 agentes, 2 skills, sin `orchestrator`.

### Fase 2 — `paths:` en las tres rules siempre-on (riesgo bajo)

Agregar frontmatter con globs de código a `implementation-principles.md` y `self-reflection.md`. Ambas hablan de escribir código; en una sesión que no toca código no aportan nada.

**Riesgo real a evaluar:** el disparo es "cuando Claude toca archivos que matchean". Si un dev planifica antes de abrir el primer archivo, la rule podría entrar tarde. Mitigación: los dev agents ya listan ambas en "Reglas heredadas", así que el agente las carga explícitamente igual. La carga automática es red de seguridad, no el mecanismo primario. **Verificar con `/context` después del cambio.**

### Fase 3 — `pr-workflow.md` → skill (riesgo bajo, ahorro mayor)

Partir en dos:

- **Se queda en `CLAUDE.md`** (3–4 líneas, son invariantes que no pueden llegar tarde): no se mergea sin aprobación explícita; no se mergea con CI en rojo; una fase = un PR; review dual obligatorio antes de merge.
- **Skill `pr-review`** (el resto: presupuesto de CI, branch protection, política de scans, E2E pre-release, aplicación de sugerencias), invocado al entrar a Fase 2.7. Es literalmente el caso de uso que la doc de Claude Code describe para skills.

Ahorro: ~140 líneas permanentes.

### Fase 4 — `CLAUDE.md` bajo 200 líneas

Borrar el recap del cheat sheet (subiendo al cuerpo los 4 puntos únicos), la tabla de extensión→rules (el frontmatter `paths:` ya la implementa), el bloque de inicio de sesión (el hook lo cubre) y las 9 viñetas de criterios de DB (dejar el resumen de una línea + link al runbook).

### Fase 5 — Adelgazar agentes

Extraer los 4 bloques duplicados a `rulebooks/dev-common.md`. Borrar "Debugging sistemático" de los 7. Reducir templates de reporte al esqueleto. Limpiar voseo.

Es la fase más grande y la de mayor riesgo de regresión: los templates de reporte, aunque verbosos, dan consistencia entre invocaciones. Sugerencia: hacerla **después** de las otras cuatro, con un agente a la vez, y correr `tests/adversarial/` entre medio para confirmar que QA y security siguen detectando lo que deben.

---

## 6. Lo que NO se toca

Para que quede por escrito, porque el post podría leerse como licencia para podar esto:

- Toda la regla 3 de `pr-workflow.md` (aprobación explícita para mergear). Es política, no andamiaje.
- El presupuesto de CI completo. Es contexto de negocio (minutos agotados en 15 días) que el modelo no puede inferir.
- E2E bloqueante solo en PRs a `main`, con su justificación fechada.
- TDD obligatorio, 80% de coverage, dual review.
- El cap de 5 tareas por lote.
- Los gotchas listados en §4 (jsdom, bundle stale, cron en default branch, required_status_checks, MD5 no es KDF, prefijos de env var, CONCURRENTLY).
- `orchestrator-runbook.md`: ya está bien.

---

## 7. Herramienta complementaria

`claude doctor` existe en el CLI (verificado). La versión completa, que además propone fixes, es `/doctor` dentro de sesión. Vale correrlo **después** de la Fase 1 para no mezclar sus sugerencias con las contradicciones ya identificadas acá.
