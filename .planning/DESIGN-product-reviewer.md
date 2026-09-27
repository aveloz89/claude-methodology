## Diseño: product-reviewer

### Resumen
Agregar el subagente `product-reviewer` (opus, solo lectura, contexto limpio) que corre entre el cierre del brainstorming y `ui-ux`/`architect`, solo en proyectos cuyo `CLAUDE.md` declara `Tipo: producto con usuarios` y solo en features nuevas. Devuelve un reporte corto (veredicto, resultado esperado, criterios de aceptación); el orchestrator lo presenta con `AskUserQuestion` y escribe lo aceptado en dos secciones nuevas de `BRIEF.md`.

### Search-first
Se salta: es un cambio de proceso específico de este repo y el brief ya fija la solución (D-04). Lo único reutilizado es lo que ya existe en el repo: el patrón de agente read-only (`security-reviewer`, `latent-bugs-sweep`: `tools: Read, Grep, Glob` + `disallowedTools`), el patrón de fase condicional (Fase 0.5 de `ui-ux`), y los helpers de test (`assert_contains`, `assert_no_voseo`, sandbox RED) de `tests/adversarial/`.

### Arquitectura
No cambia. Aplica la decisión del 2026-09-26 "agentes solo por frontera de contexto": la frontera que justifica este agente es el **contexto limpio** — su valor es no haber estado en el brainstorming (brief, "Descartado explícitamente"). Un rulebook que leyera el orchestrator no la daría. `global/CLAUDE.md` no se toca: la fase vive en el nivel 2 (skill) y el detalle en el nivel 3 (runbook).

---

### 1. Prompt de `agents/product-reviewer.md`

Contenido completo (≤150 líneas; el dev lo copia tal cual y ajusta solo si un test lo exige):

```markdown
---
name: product-reviewer
description: "Revisor de producto. Cuestiona si una feature vale la pena y deja resultado esperado y criterios de aceptación medibles a partir de BRIEF.md. Lo invoca el orchestrator después del brainstorming y antes de ui-ux y architect, solo en proyectos cuyo CLAUDE.md tiene la línea `Tipo: producto con usuarios` y solo en features nuevas. Solo lee; nunca modifica archivos ni habla con el usuario."
model: opus
tools: Read, Grep, Glob
disallowedTools: Write, Edit, Bash, Agent
---

# Product Reviewer

Eres un product manager senior con contexto limpio: no estuviste en el brainstorming, y eso es a propósito. Tu valor es la mirada independiente sobre un brief que el usuario y el orchestrator ya dan por bueno. Respondes tres preguntas: si vale la pena, qué esperamos obtener y cómo sabremos que funcionó.

## Qué recibes y qué entregas

**Recibes del orchestrator:** `.planning/BRIEF.md` y, si existe, el path al `README.md` del proyecto. Nada más: ni historial, ni diseño técnico.

**Entregas:** un reporte en el formato de abajo, como texto de tu respuesta. No escribes archivos: el orchestrator se lo presenta al usuario y escribe en `BRIEF.md` lo que el usuario acepte.

**Si te falta contexto** que cambia el veredicto, el resultado esperado o un criterio (quién es el usuario, qué hace hoy sin la feature), no supongas: devuelve solo `### Preguntas` (máximo 5, cada una con por qué importa y, si ayuda, 2-3 respuestas posibles) y ningún veredicto. El orchestrator se las pasa al usuario, suma las respuestas al brief y te reanuda. Si no te falta nada, entrega el reporte directo. (D-05, usuario: siempre preguntar antes que suponer.)

## Cómo evalúas

1. **Problema real.** ¿Qué hace hoy el usuario sin esta feature y qué le cuesta? Si el brief no lo dice, esa es la primera razón del veredicto.
2. **Alternativa más barata.** ¿Se obtiene el mismo resultado con menos alcance (un ajuste de copy, una opción que ya existe, un paso manual)? Si sí, el veredicto tiende a "reducir alcance".
3. **Señal de éxito.** ¿Qué cambia de forma observable si la feature funciona? Un número, un evento o un comportamiento que alguien pueda mirar después del release. Si el producto no mide nada todavía, propón la señal más barata de obtener (un evento en logs, un conteo manual a la semana).
4. **Criterios verificables.** Cada criterio de aceptación se responde con sí o no sin interpretar. "Que sea rápido" no es un criterio; "la lista carga en menos de 2 s con 500 elementos" sí. Reescribes los que el brief ya trae y agregas los que faltan, cada uno con su origen.

Lees el brief y el README. Abres código solo para confirmar que algo que el brief da por nuevo ya existe; no auditas el repo.

## Reglas

- **No bloqueas.** Tu veredicto es un insumo; decide el usuario. Aunque digas "repensar", el flujo sigue si el usuario quiere. Por eso el reporte se escribe para decidir en un minuto, no para convencer.
- **Corto.** Reporte de 40 líneas o menos. Si tienes más que decir, prioriza: lo que cambia la decisión va primero; el resto se cae.
- **Sin roadmap, backlog ni PRD.** Evalúas esta feature, no el producto.
- **Español latam estándar con tuteo, sin voseo.** Sin mayúsculas de énfasis; las negritas solo en las etiquetas del formato.
- **Todo criterio y toda señal los puede verificar alguien que no estuvo en la conversación.**

## Formato del reporte

```markdown
## Revisión de producto: <nombre de la feature>

### Veredicto: seguir | reducir alcance | repensar
- <razón 1>
- <razón 2>
- <razón 3, opcional>

### Resultado esperado
- **Para el usuario:** <una frase: qué puede hacer o qué deja de sufrir>
- **Señal de éxito:** <métrica o evento observable, dónde se mide y en qué plazo>

### Criterios de aceptación
1. <criterio verificable> — origen: brief §<sección> | nuevo
2. ...

### Supuestos
- <supuesto que hiciste por falta de contexto, o "ninguno">

### Si reducir alcance o repensar
- <qué sacar del alcance, o qué pregunta responder antes de diseñar; máximo 3 líneas>
```

La última sección se omite cuando el veredicto es "seguir".

## Ejemplo breve

Brief: "exportar el listado de clientes a CSV desde el panel de admin, con filtros, columnas configurables y envío semanal programado".

```markdown
## Revisión de producto: exportar clientes a CSV

### Veredicto: reducir alcance
- El problema declarado es "contabilidad pide la lista a fin de mes"; un export completo con las columnas actuales lo resuelve.
- Columnas configurables y envío semanal no tienen un usuario identificado en el brief.

### Resultado esperado
- **Para el usuario:** contabilidad obtiene la lista de clientes sin pedirla a soporte.
- **Señal de éxito:** cero tickets de "lista de clientes" en soporte en el mes siguiente al release (hoy: 3-4 por mes según el brief).

### Criterios de aceptación
1. El botón "Exportar CSV" descarga todas las filas visibles según los filtros activos — origen: brief §Flujo paso 2
2. El archivo abre en Excel y Google Sheets con acentos correctos (UTF-8 con BOM) — nuevo
3. Con 10 000 clientes, la descarga empieza en menos de 5 s — nuevo

### Supuestos
- Contabilidad usa Excel; si usa otra herramienta, el criterio 2 cambia.

### Si reducir alcance o repensar
- Sacar columnas configurables y envío semanal; reevaluar si aparece un segundo pedido.
```

## Qué no haces

- No hablas con el usuario ni con otros agentes; solo respondes al orchestrator.
- No escribes ni editas archivos; `BRIEF.md` lo actualiza el orchestrator.
- No diseñas la solución técnica, no estimas esfuerzo ni propones stack.
- No priorizas contra otras features ni armas roadmap.
- No repites el brainstorming: el brief ya existe, tú lo cuestionas.
```

**Por qué cada regla:**

| Regla | Por qué |
|---|---|
| `tools: Read, Grep, Glob` + `disallowedTools: Write, Edit, Bash, Agent` | Read-only por contrato (brief: "no edita archivos"). Sin `Bash`: no necesita ejecutar nada y `tools` sí restringe en agentes (a diferencia de `allowed-tools` en skills, PR-80). `Agent` fuera: no se autoinvoca ni delega. |
| `description` con disparador | El orchestrator decide con la description; lleva la condición de activación y el momento (después del brainstorming, antes de `ui-ux`/`architect`). |
| Contexto limpio, sin historial | Es la frontera de contexto que justifica el agente (ARCHITECTURE.md 2026-09-26). |
| Preguntas antes que supuestos (D-05) | Decisión del usuario: un supuesto equivocado sobre el usuario o el problema invalida el veredicto. La ronda extra solo ocurre cuando falta algo que lo cambia. |
| No bloquea | D-02. |
| ≤40 líneas | "Reporte corto: el objetivo es no complicar." Un tope numérico es verificable; "corto" no. |
| Criterio = sí/no sin interpretar, con origen | Es lo que consumen architect (traza a tareas) y QA (cobertura). El origen distingue lo que el usuario ya pidió de lo que el agente agregó. |
| Tuteo sin voseo, sin mayúsculas de énfasis | PR-81 (`assert_no_voseo`) y tono del repo. |
| Ejemplo con veredicto "reducir alcance" | Es el veredicto más útil y el más difícil de escribir bien; "seguir" no necesita ejemplo. |

---

### 2. Detección de "producto con usuarios"

**Línea exacta** en el `CLAUDE.md` del proyecto (raíz o `.claude/CLAUDE.md`), sin negritas ni otro formato, sola en su línea (se admite como ítem de lista con `- ` inicial):

```
Tipo: producto con usuarios
```

Valores que `/new-project` conoce: `producto con usuarios`, `herramienta interna`, `librería o tooling`. **Solo el primero activa** al agente; cualquier otro valor, o la ausencia de la línea, equivale a "no corre".

**Cómo la lee el orchestrator:** el `CLAUDE.md` del proyecto ya está en su contexto en toda sesión. Si duda, `Grep` (ya está en `allowed-tools`) con el patrón `^(- )?Tipo: producto con usuarios$` sobre `CLAUDE.md` y `.claude/CLAUDE.md`. Sin `Bash`.

**Si falta:** no corre y el orchestrator **no pregunta** si agregarla (brief, "Reglas de negocio"). El README documenta la línea para quien quiera activarla a mano en un proyecto existente.

**Cambios a `skills/new-project/SKILL.md`** (paso 3, "Generar CLAUDE.md"):

- Antes de generar el archivo, pregunta con `AskUserQuestion` "¿Qué tipo de proyecto es?" con tres opciones: `producto con usuarios` (recomendada si el stack tiene frontend: "activa la revisión de producto en cada feature nueva"), `herramienta interna` ("sin revisión de producto"), `librería o tooling` ("sin revisión de producto").
- Escribe la línea `Tipo: <valor elegido>` como primera línea después del encabezado del `CLAUDE.md` generado, tal cual, sin negritas.
- Agrega a la lista de contenido del paso 3 el ítem: "Tipo de proyecto (`Tipo: producto con usuarios` activa `product-reviewer`; los otros valores no)".

---

### 3. Integración

#### 3.1 `skills/orchestrator/SKILL.md`

- **`allowed-tools`:** agregar `Agent(methodology:product-reviewer)` (forma exigida por el lint (d)).
- **Mapa del flujo (§2):** nueva fila entre 0 y 0.5:

  `| 0.3. Revisión de producto | Invocas `product-reviewer` solo si el `CLAUDE.md` del proyecto tiene la línea `Tipo: producto con usuarios` y hubo brainstorming (feature nueva, no fix ni cambio técnico); presentas el reporte con `AskUserQuestion`; no bloquea | secciones "Resultado esperado" y "Criterios de aceptación" de `.planning/BRIEF.md` | "Fase 0.3" |`

- **Tabla de equipo (§4):** nueva fila antes de `ui-ux`:

  `| `product-reviewer` | opus | Cuestiona si la feature vale la pena; deja resultado esperado y criterios de aceptación medibles (read-only). No bloquea | Después del brainstorming, antes de `ui-ux` y `architect`, solo si el `CLAUDE.md` del proyecto declara `Tipo: producto con usuarios` |`

  La fila de `ui-ux` pasa a decir "Después del brainstorming (y de `product-reviewer` si corrió), antes del architect, si hay UI".
- **Degradación (§4):** agregar `` `product-reviewer` → sonnet aceptable siempre`` a la frase existente.
- **§9 "Cuándo abrir el runbook":** fila `| Presentar el reporte de `product-reviewer` y qué escribir en `BRIEF.md` | "Fase 0.3" |`.

#### 3.2 `rulebooks/orchestrator-runbook.md`

Nueva subsección entre "Fase 0" y "Fase 0.5":

```markdown
### Fase 0.3: Revisión de producto (solo productos con usuarios)

**Condición (las dos a la vez):**

1. El `CLAUDE.md` del proyecto (raíz o `.claude/CLAUDE.md`) tiene una línea que, sin el `- ` inicial si es ítem de lista, es exactamente `Tipo: producto con usuarios`. Ya lo tienes en contexto; si dudas, `Grep` con `^(- )?Tipo: producto con usuarios$`. Sin la línea, o con otro valor, no corre y no preguntas si agregarla.
2. Hubo brainstorming (Fase 0 no se saltó). Si se saltó —bug fix o cambio técnico— tampoco corre.

**Cómo invocar:** `product-reviewer` recibe solo `.planning/BRIEF.md` y el path a `README.md` si existe. Sin historial, sin `ARCHITECTURE.md`, sin `DESIGN.md`. Una invocación por feature; si el brief cambia de fondo después del reporte (otra ronda de brainstorming), puedes invocarlo una segunda vez, no más.

**Cómo lo presentas:** copias el reporte tal cual (≤40 líneas) y preguntas con `AskUserQuestion`:

- **Incorporar todo** — resultado esperado y criterios van a `BRIEF.md` tal cual. Recomendada si el veredicto es "seguir".
- **Elegir qué incorporar** — segunda pregunta con dos bloques: resultado esperado (incorporar / no) y criterios (todos / solo los de origen brief / solo los nuevos / ninguno). Recomendada si el veredicto es "reducir alcance" o "repensar".
- **Seguir sin cambios** — `BRIEF.md` queda igual salvo la decisión registrada.

Si el usuario quiere replantear la feature, vuelves a Fase 0 (otra ronda); no lo decides por él.

**Qué escribes en `BRIEF.md`:** las secciones `### Resultado esperado` y `### Criterios de aceptación` (formato en "Formatos de archivos") con lo aceptado, y en "Decisiones tomadas" una línea `[D-NN] (usuario) Veredicto de product-reviewer: <veredicto>; se incorporó <todo | resultado esperado y criterios N, N | nada>`. Si el usuario redujo el alcance, actualizas "Alcance" y "Descartado explícitamente" en la misma pasada. El reporte completo no se persiste.
```

Además:

- **"Context isolation":** nueva viñeta `` `product-reviewer` recibe: `BRIEF.md` completo + path a `README.md` si existe. Nada más.``
- **Formato de `BRIEF.md`:** dos secciones nuevas después de "Descartado explícitamente" y antes de "Design System":

  ```markdown
  ### Resultado esperado (si pasó por product-reviewer)
  - **Para el usuario:** [una frase]
  - **Señal de éxito:** [métrica o evento observable, dónde se mide, plazo]

  ### Criterios de aceptación (si pasó por product-reviewer)
  1. [criterio verificable con sí/no] — origen: brief §<sección> | product-reviewer
  [Si no pasó por product-reviewer, omitir ambas secciones]
  ```
- **"Formato de reporte de review"** (secciones QA Frontend / QA Backend): una línea opcional `Criterios de aceptación del brief: cubiertos N de M (lista los no cubiertos). Solo si BRIEF.md los trae; no bloquea por sí solo.`

#### 3.3 Cómo los usan `architect` y QA (referencia, no bloqueo)

- **`agents/architect.md`**, §1 "Análisis de la tarea", viñeta nueva: "Si `BRIEF.md` trae `### Criterios de aceptación`, cada criterio se traza a al menos una tarea atómica de algún lote; anota el número junto a la tarea (`[CA-2]`). Un criterio que no cabe en el plan va a Riesgos con la razón. No bloquea: es la forma de que QA sepa qué mirar."
- **`agents/qa-backend.md` y `agents/qa-frontend.md`**, párrafo nuevo en la sección de handoff (qué recibes) o, si no existe, al inicio del proceso de revisión: "**Criterios de aceptación del brief (referencia).** Si `BRIEF.md` trae `### Criterios de aceptación`, en tu reporte listas cuáles cubre el diff (con test o evidencia) y cuáles no. Un criterio sin cubrir no bloquea por sí solo: lo anotas como observación para que el usuario decida; bloqueas solo por tus criterios de siempre."

#### 3.4 README, marketplace y tests

- **`README.md`:** encabezado `### Agentes (12)` y "estos 12 agentes"; fila `| **product-reviewer** | opus | Cuestiona si la feature vale la pena y deja resultado esperado y criterios de aceptación medibles (read-only, no bloquea). Solo en proyectos con `Tipo: producto con usuarios` |` antes de `ui-ux`; `product-reviewer.md` en el árbol de `agents/`; en el diagrama "Workflow" una línea `→ Product reviewer (solo productos con usuarios): ¿vale la pena?, resultado esperado, criterios de aceptación` después de "Brief"; en "Configuración por proyecto" (línea ~202, "Los agentes detectan el stack…") un párrafo: "Si el `CLAUDE.md` del proyecto tiene la línea `Tipo: producto con usuarios`, el orchestrator invoca `product-reviewer` después del brainstorming de cada feature nueva. Sin la línea no corre; `/new-project` la escribe al preguntar el tipo de proyecto."
- **`.claude-plugin/marketplace.json`:** description `"Metodología completa: 12 agentes, 14 hooks, 5 skills"`. Sin bump de versión (se hace en release).
- **`tests/adversarial/test-frontmatter.sh`:** `product-reviewer` en `HISTORICAL_AGENTS`.
- **`tests/adversarial/test-plugin-manifest.sh`:** asserts nuevos (detalle en el plan): frontmatter read-only del agente con sandbox RED, tope de 150 líneas, palabras del veredicto y encabezados compartidos con `BRIEF.md`, `assert_no_voseo` y lista explícita de mayúsculas de énfasis prohibidas, `product-reviewer` en el loop de `allowed-tools`, Fase 0.3 en skill y runbook, formato de `BRIEF.md`, conteo de agentes derivado de `ls agents/*.md` contra README y marketplace, `Tipo: producto con usuarios` en `new-project`, criterios de aceptación en architect y QAs.
- **`tests/validation/agent-validation.md`:** sección `## Product Reviewer` con prompt canónico (un brief vago de feature en un producto) y expected behaviors (veredicto con 2-3 razones, señal medible, criterios sí/no con origen, ≤40 líneas, no escribe archivos; con un brief al que le falta el usuario o el problema, devuelve solo Preguntas) y red flags (propone stack, arma roadmap, bloquea).

---

### 4. Qué cambia

| Archivo | Cambio | Lote |
|---|---|---|
| `agents/product-reviewer.md` | nuevo, prompt de §1 | 1 (T1) |
| `tests/adversarial/test-frontmatter.sh` | `product-reviewer` en `HISTORICAL_AGENTS` | 1 (T1) |
| `tests/adversarial/test-plugin-manifest.sh` | asserts del agente (read-only + sandbox RED, ≤150 líneas, veredicto/encabezados, voseo/mayúsculas) | 1 (T1-T4) |
| `tests/adversarial/test-plugin-manifest.sh` | `product-reviewer` en loop de `allowed-tools`; asserts de Fase 0.3 en skill y runbook; formato `BRIEF.md`; context isolation | 2 (T1-T4) |
| `skills/orchestrator/SKILL.md` | `allowed-tools`, fila 0.3, fila de equipo, fila `ui-ux`, degradación, §9 | 2 (T1, T2) |
| `rulebooks/orchestrator-runbook.md` | Fase 0.3; context isolation; formato `BRIEF.md`; línea en reporte de review | 2 (T3, T4) |
| `tests/adversarial/test-plugin-manifest.sh` | asserts de new-project, architect/QAs, conteo de agentes, agent-validation | 3 (T1-T4) |
| `skills/new-project/SKILL.md` | paso 3: pregunta tipo y escribe `Tipo:` | 3 (T1) |
| `agents/architect.md` | viñeta de criterios de aceptación en §1 | 3 (T2) |
| `agents/qa-backend.md`, `agents/qa-frontend.md` | párrafo "Criterios de aceptación del brief (referencia)" | 3 (T2) |
| `README.md` | conteo 12, fila, árbol, workflow, párrafo de detección | 3 (T3) |
| `.claude-plugin/marketplace.json` | "12 agentes" | 3 (T3) |
| `tests/adversarial/README.md` | fila de `test-frontmatter.sh`/`test-plugin-manifest.sh` menciona los checks nuevos | 3 (T3) |
| `tests/validation/agent-validation.md` | sección `## Product Reviewer` | 3 (T4) |
| `global/CLAUDE.md` | **no cambia** (tope de tamaño; la fase vive en skill + runbook). Se confirma con el grep DoD | 3 (T5) |
| `.planning/ARCHITECTURE.md` | decisión recurrente (activación por línea en `CLAUDE.md`) | architect, ya escrita |

---

### 5. Plan de implementación

**Estrategia de PR:** single-PR (branch `feature/product-reviewer`, base `dev`).
**Agente de todos los lotes:** `backend-dev` (diff de documentos normativos + bash; QA lo revisa `qa-backend`, runbook "Documentos normativos").
**TDD:** cada tarea agrega primero el assert en `tests/adversarial/test-plugin-manifest.sh` (o el cambio en `test-frontmatter.sh`), lo ve en rojo con `bash tests/adversarial/test-plugin-manifest.sh && bash tests/adversarial/test-frontmatter.sh`, aplica el cambio, lo ve en verde y commitea. Los tests no corren por hook en este repo (no hay `package.json`): el dev los corre a mano antes de cada commit. Reglas de idioma para los `.sh`: `rules/bash.md`; para los asserts de texto, listas explícitas (PR-81).

#### Lote 1 — agente y lint (backend-dev)
**Depende de:** ninguno · **last_batch:** false

- [ ] T1: `agents/product-reviewer.md` existe con el frontmatter de §1 — assert nuevo `assert_agent_read_only <file>`: `model: opus`, `tools:` sin `Write`/`Edit`/`Bash`, `disallowedTools:` con `Write`, `Edit`, `Bash` y `Agent`; más `product-reviewer` en `HISTORICAL_AGENTS` de `test-frontmatter.sh`. Rojo con el archivo ausente; verde al crearlo con el prompt completo de §1.
- [ ] T2: el prompt cumple el contrato de tamaño y formato — asserts: `wc -l` ≤ 150; contiene `seguir | reducir alcance | repensar`, `### Resultado esperado`, `### Criterios de aceptación` y la regla de `### Preguntas` (encabezados compartidos con el formato de `BRIEF.md`).
- [ ] T3: tono — `assert_no_voseo "$REPO_ROOT/agents/product-reviewer.md"` y assert de lista explícita de mayúsculas de énfasis prohibidas (`NUNCA`, `SIEMPRE`, `SOLO`, `OBLIGATORIO`, `NO ` como palabra) ausentes del archivo.
- [ ] T4: sandbox RED de `assert_agent_read_only`: un agente temporal con `tools: Read, Write` y sin `disallowedTools` falla el helper; otro con el frontmatter correcto pasa (mismo patrón que los sandboxes existentes; nunca sobre archivos reales).

#### Lote 2 — orchestrator: skill y runbook (backend-dev)
**Depende de:** Lote 1 (el lint (d) exige que `agents/product-reviewer.md` exista antes de referenciarlo) · **last_batch:** false

- [ ] T1: la skill declara al agente — `product-reviewer` en el loop `for agent in architect ui-ux …` de `test-plugin-manifest.sh` (rojo) → `Agent(methodology:product-reviewer)` en `allowed-tools` (verde; `test-frontmatter.sh` (d) sigue verde).
- [ ] T2: la skill tiene la fase — asserts sobre `SKILL.md`: `0.3. Revisión de producto`, `Tipo: producto con usuarios`, `` `product-reviewer` → sonnet``; cambios de §3.1 (fila del mapa, fila de equipo, fila `ui-ux`, degradación, §9). `assert_no_voseo` de la skill ya existe y debe seguir verde; la skill sigue < 500 líneas.
- [ ] T3: el runbook tiene la Fase 0.3 — asserts: `### Fase 0.3`, `Tipo: producto con usuarios`, `Sin la línea`, `Incorporar todo`, `Elegir qué incorporar`, `Seguir sin cambios`; texto de §3.2. Agregar `assert_no_voseo "$RUNBOOK"` solo si ya pasa sobre el runbook actual (verificarlo ejecutando; si no pasa, dejar el assert acotado a la sección nueva y anotarlo).
- [ ] T4: formatos — asserts: `### Resultado esperado`, `### Criterios de aceptación` y `` `product-reviewer` recibe:`` en el runbook; secciones nuevas de `BRIEF.md`, viñeta de context isolation y línea en "Formato de reporte de review" (§3.2).

#### Lote 3 — new-project, consumidores, README, marketplace, cierre (backend-dev)
**Depende de:** Lote 2 · **last_batch:** true

- [ ] T1: `/new-project` pregunta y escribe el tipo — assert `Tipo: producto con usuarios` en `skills/new-project/SKILL.md`; cambios de §2 (paso 3).
- [ ] T2: architect y QAs referencian los criterios — assert `Criterios de aceptación` en `agents/architect.md`, `agents/qa-backend.md`, `agents/qa-frontend.md`; textos de §3.3.
- [ ] T3: conteo de agentes coherente — assert dinámico: `N=$(ls agents/*.md | wc -l)`; README contiene `### Agentes ($N)` y marketplace `"$N agentes"`; README contiene `product-reviewer` (tabla, árbol, workflow, párrafo de detección); `tests/adversarial/README.md` actualizado.
- [ ] T4: `tests/validation/agent-validation.md` tiene `## Product Reviewer` (assert) con el contenido de §3.4.
- [ ] T5: cierre — grep DoD anti-drift (`11 agentes`, `Agentes (11)`, `ANTES del architect`, `product-reviewer`, `Tipo:`) sobre `global/`, `README.md`, `rulebooks/`, `agents/`, `skills/`, `.planning/` (solo documentos vivos: `STATE.md`, `LEARNINGS.md`); reconciliar restos; confirmar que `global/CLAUDE.md` no cambió; `claude plugin validate --strict .claude-plugin/plugin.json` y `claude plugin validate --strict .`; las tres suites de `tests/adversarial/` en verde. Evidencia (salida del grep y de validate) en el reporte del lote.

---

### Riesgos
- **Referencia antes del archivo:** el lint (d)/(f) falla si la skill declara `Agent(methodology:product-reviewer)` sin `agents/product-reviewer.md` → Lote 1 antes de Lote 2, secuencial.
- **Detección frágil por formato:** `**Tipo:** producto…` o `Tipo: Producto con usuarios` no matchean → `/new-project` escribe la forma exacta, el README la documenta literal, y el patrón tolera solo `- ` inicial. Un falso negativo es la dirección segura (el agente no corre).
- **`AskUserQuestion` con muchos criterios:** el tope de opciones por pregunta obliga a no listar criterios uno por uno → la opción "Elegir qué incorporar" usa bloques (todos / origen brief / nuevos / ninguno), no selección múltiple; el usuario afina en texto libre si hace falta.
- **Drift de tono o tamaño del prompt:** cubierto por tests (≤150 líneas, `assert_no_voseo`, lista de mayúsculas).
- **`assert_no_voseo` sobre el runbook actual puede estar rojo por texto preexistente** (el helper hoy no lo cubre) → Lote 2 T3 lo verifica ejecutando antes de agregarlo; si está rojo, acota el assert y lo anota en el reporte, no lo arregla (cambios quirúrgicos).
- **`global/CLAUDE.md` sin cambio:** intencional por el tope de tamaño; el workflow #1 ya remite a la skill para las condiciones de brainstorming, y la fase 0.3 hereda esa condición. Confirmado por el grep de Lote 3 T5.
- **Segunda invocación por feature:** permitida una sola vez tras un cambio de fondo del brief; más allá es señal de que el brainstorming no cerró, y se vuelve a Fase 0.


### Cambio D-05 (usuario, durante el lote 1)

Siempre preguntar antes que suponer. El agente devuelve solo `### Preguntas` cuando le falta algo que cambia el veredicto; el orchestrator relaya las preguntas al usuario (con `AskUserQuestion` si son cerradas, en prosa si son abiertas), suma las respuestas a `BRIEF.md` y reanuda al mismo agente con `SendMessage` para que conserve el contexto. La sección `### Supuestos` del reporte se elimina. **Lote 2** agrega este ciclo a la Fase 0.3 del runbook y a la skill. **Lote 1** ajusta el prompt y su test. Las secciones 1 y 3.2 de arriba quedan reemplazadas por esta regla donde choquen.
