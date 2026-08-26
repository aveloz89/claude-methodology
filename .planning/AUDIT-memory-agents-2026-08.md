# Informe: gestión de memoria y agentes en 2026 vs claude-methodology

**Fecha:** 2026-08-13
**Método:** 4 investigaciones paralelas — (1) docs oficiales de Claude Code, (2) blog de ingeniería de Anthropic 2024-2026, (3) foros y práctica de la comunidad (HN, Reddit, GitHub), (4) Notion AI/MCP y backends de memoria externa — contrastadas contra el inventario real del repo y la auditoría previa (`.planning/AUDIT-context-engineering.md`, 2026-07-24).

---

## 1. Veredicto ejecutivo

**La metodología NO está obsoleta. Está alineada con el patrón que ganó en 2026.** La línea editorial completa de Anthropic (11 artículos, 2024-2026) y el consenso de la comunidad convergen exactamente en lo que este repo ya hace: orchestrator que delega sin implementar, estado persistente en archivos markdown versionados en git, subagentes con contexto aislado que devuelven resúmenes, review con contexto fresco separado del que escribió, y detalle cargado bajo demanda (skills/rulebooks) en vez de contexto permanente.

**Notion AI sería overhead neto para este equipo.** Los datos son contundentes (§5): ~26.000 tokens de definiciones de tools por sesión, ~18.000 tokens por copiar un documento, pérdida del versionado atómico estado-código, y su valor diferencial (visibilidad para no-técnicos, colaboración multi-persona) no existe con un solo usuario. Los agentes de Notion 3.x operan *dentro* de Notion, no sobre el repo.

**Lo que sí hay que hacer** no es reemplazar el sistema sino incorporar 6-7 mejoras puntuales que 2026 dejó disponibles (§6-§8): hooks de tipos nuevos (`PreCompact`, `SessionEnd`, prompt-based), memoria por agente (`memory: true`), JSON para el estado que los agentes mutan, smoke test al retomar sesión, empaquetar la metodología como plugin, y vigilar (sin adoptar aún) Agent Teams.

---

## 2. El principio rector que atraviesa todo lo investigado

Anthropic lo formuló dos veces en 2026 y es la vara para evaluar cada pieza del sistema:

> *"Every component in a harness encodes an assumption about what the model can't do on its own, and those assumptions are worth stress testing as models improve."* — [Harness design for long-running apps](https://www.anthropic.com/engineering/harness-design-long-running-apps) (mar-2026)

Su propio harness de 3 agentes se simplificó cuando mejoró el modelo. La comunidad vivió lo mismo: los frameworks pesados de 2025 (claude-flow/SPARC, spec-kit ceremonioso, memory-MCPs con knowledge graphs) murieron o se replegaron, y el péndulo volvió a la simplicidad — el artefacto viral de 2026 fue un CLAUDE.md de ~65 líneas estilo Karpathy, no un framework. La auditoría de julio ya aplicó este principio (poda de andamiaje); este informe lo usa para separar qué conservar y qué modernizar.

---

## 3. Panorama oficial: qué existe hoy en Claude Code (ago-2026)

### 3.1 Memoria estratificada — tres capas oficiales

| Capa | Quién escribe | Dónde vive | Nuestro equivalente |
|---|---|---|---|
| **CLAUDE.md** (managed → user → project → local) | El humano | Git, versionado | ✅ Lo usamos (196 líneas, bajo el target oficial de 200) |
| **Auto-memory** (`MEMORY.md` índice + archivos por tema; solo las primeras 200 líneas/25KB del índice cargan solas) | Claude | `~/.claude/projects/<repo>/memory/` | ✅ Lo usamos, con el patrón índice+archivos recomendado |
| **Memory tool API** (`memory_20250818`, GA sep-2025; 84% ahorro de tokens + 39% mejora en benchmark interno) | El agente | Server-side / storage propio | ➖ No aplica: es para agentes custom vía API, no para Claude Code CLI |

Dato clave: el memory tool oficial de la API **es un directorio de archivos** que el agente lee al arrancar y actualiza al avanzar. Su system prompt inyectado dice literalmente *"ASSUME INTERRUPTION: your context window might be reset at any moment"*. Es la productización de nuestro `.planning/` — Anthropic construyó como producto lo que este repo hace por convención.

### 3.2 Contexto — lo nuevo que ya nos beneficia solo

- **1M de contexto** GA en Fable 5 / Sonnet 5 / Opus 4.6+ (ya lo usamos: `claude-fable-5[1m]` en settings.json).
- **Compresión multi-nivel** automática: tool search deferral (schemas MCP bajo demanda), microcompact (borra outputs de tools preservando que la call ocurrió), path-scoped rules, CLAUDE.md anidados lazy.
- **Matiz importante para nosotros:** las path-scoped rules **no sobreviven a un compact** (recargan solo si se vuelve a tocar un archivo que matchea). Nuestros dev agents ya mitigan esto listándolas en "Reglas heredadas" — mantener esa redundancia deliberada.

### 3.3 Subagentes y Agent Teams

- Subagentes (`.claude/agents/*.md`): sin cambios estructurales, pero con frontmatter nuevo relevante: **`memory: true`** da memoria persistente propia por agente en `~/.claude/projects/<repo>/agents/<name>/memory/`.
- **Agent Teams** (experimental, off por defecto, `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`): lead + teammates con contexto propio, task list compartida y mailboxes. Es la nativización de nuestro patrón orchestrator+workers. Limitaciones actuales documentadas: sin `/resume`, task status con lag, shutdown lento, un team por sesión, reportes de mensajes perdidos entre teammates (feb-mar 2026). **Recomendación: vigilar, no adoptar** — nuestro orchestrator ya cubre el caso de uso y es más controlable; reevaluar cuando salga de experimental.

### 3.4 Hooks — el área con más novedades sin explotar

Nuestros 11 hooks son todos `type: command` sobre 3 eventos (PreToolUse/PostToolUse/SessionStart). Hoy existen **~20 eventos** y **5 tipos** de hook:

- **Eventos nuevos útiles para nosotros:** `PreCompact` (snapshot de estado antes de compactar), `SessionEnd` (cierre ordenado), `SubagentStart`/`SubagentStop` (contabilidad real del budget de invocaciones de `agent-budget.md`), `TaskCreated`/`TaskCompleted` (enforcement del tracker de sesión), `PostToolUseFailure`.
- **Tipos nuevos:** `prompt` (evaluación single-turn con LLM que responde ok/reason), `agent` (verificación multi-turn con tools), `http`, `mcp_tool`. Los guards deterministas (block-admin-merge, etc.) deben seguir siendo `command` — el determinismo es el punto. Pero un hook `prompt` habilita checks semánticos que hoy no tenemos (p. ej. "¿este diff toca auth/crypto/pagos?" para decidir la degradación del security-reviewer).
- Cambio de plataforma a favor nuestro: `git push --force`, `--amend` y `--no-verify` **ya no se auto-aprueban** a nivel harness (v2.1.229) — defensa en profundidad que se suma a nuestros guards, no los reemplaza.

### 3.5 Skills y plugins

- **SKILL.md es ahora un estándar abierto** (dic-2025, agentskills.io), soportado por ~40 productos. Migrar `pr-workflow` a skill (hecho en julio) fue exactamente la dirección correcta.
- **Plugins** empaquetan skills + agents + hooks + MCP servers, con marketplaces oficial y comunitario. **Esto es relevante para este repo:** hoy distribuimos la metodología con `install.sh` y symlinks; el mecanismo nativo 2026 para distribuir exactamente este bundle es un plugin. Resolvería de paso el follow-up abierto del 2026-05-08 sobre carga global vs por proyecto.
- Advertencia de seguridad real: la auditoría ToxicSkills de Snyk (feb-2026) encontró fallas en el **36% de ~4.000 skills públicas** escaneadas. Instalar skills de terceros sin auditar es el nuevo `curl | bash`. Nosotros solo usamos skills propias — mantenerlo así o auditar antes de instalar.

---

## 4. Doctrina Anthropic y comunidad: validaciones y matices

### 4.1 Validado explícitamente (no tocar)

1. **Orchestrator que no implementa y construye el paquete de contexto** — prescripción literal del [multi-agent research system](https://www.anthropic.com/engineering/multi-agent-research-system): cada delegación debe llevar *objective, output format, guidance on tools, task boundaries*. Nuestro handoff por paquete es eso.
2. **Estado en archivos markdown en git** — "structured note-taking / agentic memory" ([context engineering](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents)), progress file + git como memoria ([effective harnesses](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents)), comunicación entre agentes 100% por archivos ([harness design](https://www.anthropic.com/engineering/harness-design-long-running-apps)).
3. **Review dual con contexto fresco** — doble validación: *"a fresh context improves code review since Claude won't be biased toward code it just wrote"* (best practices) y el **self-evaluation problem** (mar-2026): los agentes que evalúan su propio trabajo lo aprueban aunque sea mediocre; separar el que hace del que juzga "proves to be a strong lever". Bonus que ya sufrimos y resolvimos: el QA out-of-the-box *"identifies legitimate issues, then talks itself into approving anyway"* — nuestros reviewers bloqueantes con criterios explícitos son la mitigación correcta.
4. **Una feature a la vez, completo solo tras verificación real, no tocar tests, entorno limpio al cerrar** — textual en el harness de nov-2025 y en las docs del memory tool.
5. **Memoria por capas** — el patrón que la comunidad consolidó (paddo.dev): archivo de plan para *esta ejecución* / issue tracker para el *proyecto* / memoria para conocimiento *acumulado*. Mapea 1:1 a `.planning/STATE.md` / GitHub Issues (`latent-bug`, `flaky-test`) / `MEMORY.md`+`LEARNINGS.md`. Los setups que mezclan las tres capas en un archivo degeneran.
6. **Tracker nativo de tareas** — Claude Code absorbió el patrón de beads en Tasks nativo (ene-2026); nuestro tracker de sesión obligatorio con TaskCreate/TaskUpdate ya usa el mecanismo ganador.
7. **CLI > MCP para servicios externos** — best practices oficial: *"CLI tools are the most context-efficient way to interact with external services"*, recomienda `gh` antes que el GitHub MCP. Nuestro flujo entero es `gh`. ✅

### 4.2 Matices que nos corrigen (los únicos hallazgos "en contra")

1. **Multi-agente cuesta ~15x tokens** y *"most coding tasks involve fewer truly parallelizable tasks than research"*. Nuestra regla de paralelizar solo lotes marcados independientes por el architect es la mitigación correcta — el riesgo es la deriva hacia paralelizar por defecto. Añadir a la doctrina: escalar el número de agentes a la complejidad (tarea simple = 1 agente).
2. **JSON > Markdown para estado que los agentes mutan**: hallazgo de Anthropic (nov-2025) — *"the model is less likely to inappropriately change or overwrite JSON files compared to Markdown"*. Aplica al checklist de lotes/fases con estado pass-fail dentro de `STATE.md`; la prosa (BRIEF, DESIGN, LEARNINGS) sigue en markdown.
3. **Falta un smoke test al retomar sesión**: la secuencia oficial de inicialización (nov-2025) es leer git log + progress file **+ correr un test básico antes de tocar nada**, para cazar bugs no documentados por la sesión anterior. Nuestro flujo de resume (hook + HANDOFF) hace lo primero pero no lo segundo.
4. **Spec drift es el modo de fallo #1 de las metodologías con documentos** (la crítica que hundió a spec-kit: *"it keeps drifting until you have duplication and contradictions across specs"*). Nos pasó: la auditoría de julio encontró 7 contradicciones reales post-PR#44. La lección no es tener menos documentos sino **reconciliarlos como parte del Definition of Done** de cada cambio de proceso.
5. **Los reviews con mínimos forzados generan ruido** (caso BMAD issue #1332: mínimo de 3 issues por review → nitpicks infinitos). Nuestros reviewers no tienen mínimos — verificar que los templates no los induzcan implícitamente.
6. **LEARNINGS.md → skills**: Anthropic recomienda destilar lo aprendido en artefactos ejecutables — *"ask Claude to capture its successful approaches and common mistakes into reusable context and code within a skill"* — no solo en notas. Cuando un learning es procedural y recurrente, promoverlo a skill.

### 4.3 Lo que murió en 2025-2026 (y esquivamos bien)

- **claude-flow/SPARC, hive-minds, jerarquías de >2 niveles**: declarados obsoletos por su propia comunidad. La orquestación pesada externa fue canibalizada por el harness nativo.
- **Knowledge graphs / memory-MCPs para un solo repo** (mem0, Graphiti, claude-mem): veredicto comunitario = sobre-ingeniería para memoria de proyecto de código; ~18k tokens/turno de overhead. Los archivos en git ganaron esta ronda.
- **SDD ceremonioso** (spec-kit con 16 criterios de aceptación para un bug): "waterfall en markdown". Specs sí, framework de specs no.
- **Wrappers acoplados a huecos del producto**: Anthropic los cierra en ciclos de 3-6 meses (beads→Tasks, memory-bank→auto-memory, orchestrators→Agent Teams). Invertir poco en scaffolding que compita con el roadmap del harness.

---

## 5. Notion AI y memoria externa: análisis y veredicto

**Qué es hoy:** Notion 3.x se reconstruyó alrededor de Agents (trabajo autónomo ~20 min, custom agents con triggers desde feb-2026, GA may-2026). Requiere plan Business ($20/usuario/mes) + créditos aparte ($10/1.000) para custom agents. Sus agentes operan **dentro de Notion** (docs, reportes, routing); la única intersección con Claude Code es el MCP server.

**El MCP server de Notion, medido:**
- ~21 tools ≈ **26.000 tokens de contexto** antes de hacer nada (de ahí nacieron notion-slim y better-notion-mcp, que existen literalmente para mitigar esto).
- **~18.000 tokens** por copiar un markdown a una página; queries a DBs devuelven >55K caracteres de JSON anidado.
- Sin edición a nivel de bloque (reemplaza páginas completas → riesgo de pisar ediciones concurrentes), 404 silenciosos si la página no fue compartida con la integración, ~180 req/min, OAuth no-headless (incompatible con crons/CI sin PAT).

**Casos reales de Notion como memoria de agentes de código:** solo experimentos individuales y proyectos de un challenge de DEV.to (mar-2026). **Cero equipos documentados en producción** usando Notion como equivalente de `.planning/`. El caso ganador del challenge usó API directa para lecturas y MCP solo para escrituras — reconocimiento implícito de que el roundtrip MCP es caro. El patrón que emerge donde se usan ambos: *Notion/Linear para planeación humana, markdown en repo para contexto del agente* — dos capas, no un reemplazo.

**Comparación de fondo** (repo vs backend externo):

| Criterio | Archivos en repo | Notion/externo |
|---|---|---|
| Costo por acceso | ~0 (un `Read`) | 26k tokens de setup + miles por roundtrip |
| Sincronización con el código | Atómica (mismo commit) | Divergencia silenciosa garantizada |
| Offline / disponibilidad | Total | OAuth que expira, rate limits, outages |
| Review de cambios de estado | Diff en el PR | Historial opaco |
| Visibilidad no-técnicos | Mala | **Buena** (el único punto fuerte real) |
| Multi-persona concurrente | Vía git | **Nativa** |

**Veredicto:** para un equipo de una persona con metodología en el repo, Notion es costo sin beneficio. Coincidimos con lo que Anthropic implementa en su propio memory tool y documenta como best practice. **Trigger para reevaluar:** si aparece un stakeholder no-técnico o un segundo colaborador no-dev, el paso correcto es GitHub Issues (vía `gh`, ya en el flujo) o Linear MCP **para el backlog humano** — el estado del agente se queda en el repo igual.

---

## 6. Comparación componente a componente

| Componente nuestro | Estado del arte 2026 | Veredicto |
|---|---|---|
| CLAUDE.md 196 líneas, invariantes + detalle diferido | Target oficial <200, "podar sin piedad" | ✅ Alineado (post-auditoría julio) |
| `rules/` con `paths:` + `rulebooks/` bajo demanda | Path-scoped rules + progressive disclosure | ✅ Es el mecanismo recomendado |
| `.planning/` (STATE/BRIEF/DESIGN/HANDOFF/LEARNINGS) | Structured note-taking, progress files, handoff artifacts, memory tool oficial | ✅ Validado por 4 artículos + docs | 
| Checklist de lotes/fases en markdown | JSON para estado que agentes mutan | ⚠️ Migrar la parte mutable a JSON |
| Flujo resume (hook + HANDOFF) | Ídem + smoke test antes de tocar código | ⚠️ Falta el smoke test |
| Auto-memory (MEMORY.md índice) | Patrón índice + archivos por tema | ✅ Alineado |
| 13 subagentes especializados, paquete de contexto | Orchestrator-workers, resúmenes condensados | ✅ Validado; añadir doctrina de escalar esfuerzo a complejidad |
| Sin memoria por agente | `memory: true` en frontmatter | ⚠️ Oportunidad puntual (e2e-runner, architect) |
| 11 hooks `command` en 3 eventos | ~20 eventos, 5 tipos | ⚠️ Eventos nuevos sin explotar (PreCompact, SubagentStop, SessionEnd) |
| 3 skills propias | SKILL.md estándar abierto, marketplace | ✅ Alineado; no instalar de terceros sin auditar |
| Distribución por install.sh + symlinks | Plugins (bundle skills+agents+hooks) | ⚠️ Evaluar empaquetar como plugin |
| Tracker de sesión con Tasks nativo | Tasks nativo absorbió a beads | ✅ Alineado |
| Estado externo: ninguno (todo en repo + gh) | "CLI > MCP", archivos > backends externos | ✅ Alineado; Notion descartado con datos |
| Paralelización solo si architect la marca | Multi-agente = 15x tokens, coding poco paralelizable | ✅ Correcto; vigilar la deriva |
| tests/adversarial + validation-schedule | "Stress-test harness assumptions as models improve" | ✅ Existe el mecanismo; usarlo también para probar QUITAR piezas |

---

## 7. Lo que NO hay que cambiar

Explícitamente, porque todo lo investigado lo confirma: el rol de orchestrator sin escribir código, el estado en `.planning/` versionado, el review dual bloqueante con contexto fresco, los guards deterministas como hooks `command`, el flujo por `gh` CLI sin MCPs de estado, TDD + coverage como gates, el cap de lotes, y la política de merge con aprobación humana explícita. Nada de esto es andamiaje que caducó: son decisiones y mitigaciones que la doctrina 2026 valida o directamente prescribe.

---

## 8. Plan de acción priorizado

Orden por relación impacto/esfuerzo. Ninguno es urgente; ninguno cambia la arquitectura.

1. **No adoptar Notion.** Decisión cerrada con datos; documentar el trigger de reevaluación (stakeholder no-técnico / segundo colaborador) en `ARCHITECTURE.md` para no reabrir el debate sin causa. *(esfuerzo: nulo)*
2. **Smoke test en el resume**: añadir al runbook (sección Pause/Resume) el paso "correr el test suite básico antes de retomar", alineado con la secuencia oficial de inicialización. *(esfuerzo: una línea en el runbook)*
3. **JSON para el estado mutable**: el checklist de lotes/fases de `STATE.md` pasa a un bloque/archivo JSON (`state.json` o fenced block); prosa sigue en markdown. *(esfuerzo: bajo — formato en el runbook)*
4. **Hooks nuevos**: `PreCompact` → snapshot de STATE/HANDOFF antes de compactar (protege el flujo pause/resume); `SubagentStop` → log de invocaciones para hacer medible el budget de `agent-budget.md`; opcional `SessionEnd` → recordatorio de STATE.md desactualizado. *(esfuerzo: medio — 2-3 scripts pequeños)*
5. **`memory: true` selectivo**: e2e-runner (tracking de flaky entre sesiones — hoy es responsabilidad suya sin mecanismo persistente propio) y quizás architect (decisiones recurrentes que hoy van a ARCHITECTURE.md). Evaluar con cuidado: fragmenta la memoria; probar con e2e-runner primero. *(esfuerzo: bajo, riesgo: fragmentación)*
6. **Regla anti-drift de proceso**: todo PR que cambie el flujo (como PR#44) incluye grep de los documentos que lo describen — es el Definition of Done de cambios de metodología. Las 7 contradicciones de julio eran todas de esta clase. *(esfuerzo: una regla en el runbook)*
7. **Evaluar empaquetar la metodología como plugin** (skills + agents + hooks + settings en un bundle instalable): mecanismo nativo de distribución, resuelve el follow-up del 2026-05-08 (carga global vs por proyecto) y elimina la clase de bug C5 de la auditoría (hooks documentados pero no instalados). *(esfuerzo: alto — proyecto propio)*
8. **Stress-test de supuestos** (recomendado por Anthropic, cadencia trimestral): en un branch, quitar una pieza de andamiaje (p. ej. un template de reporte, el detalle de debugging) y correr `tests/adversarial/` para ver si el modelo actual la necesita. Lo que sobreviva sin la pieza, se poda. *(esfuerzo: recurrente, bajo por iteración)*
9. **Vigilar Agent Teams**: no adoptar mientras sea experimental; reevaluar cuando tenga `/resume` y salga de flag. Nuestro orchestrator es hoy más controlable. *(esfuerzo: nulo)*

---

## 9. Fuentes principales

**Oficiales:** [Memoria](https://code.claude.com/docs/en/memory.md) · [Context window](https://code.claude.com/docs/en/context-window.md) · [Subagentes](https://code.claude.com/docs/en/sub-agents.md) · [Agent Teams](https://code.claude.com/docs/en/agent-teams.md) · [Skills](https://code.claude.com/docs/en/skills.md) · [Hooks](https://code.claude.com/docs/en/hooks-guide.md) · [Plugins](https://code.claude.com/docs/en/discover-plugins.md) · [Best practices](https://code.claude.com/docs/en/best-practices) · [Memory tool API](https://platform.claude.com/docs/en/agents-and-tools/tool-use/memory-tool)

**Blog de ingeniería Anthropic:** [Building effective agents](https://www.anthropic.com/engineering/building-effective-agents) (dic-2024) · [Multi-agent research system](https://www.anthropic.com/engineering/multi-agent-research-system) (jun-2025) · [Context engineering](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents) (sep-2025) · [Writing tools for agents](https://www.anthropic.com/engineering/writing-tools-for-agents) (sep-2025) · [Agent Skills](https://www.anthropic.com/engineering/equipping-agents-for-the-real-world-with-agent-skills) (oct-2025) · [Code execution with MCP](https://www.anthropic.com/engineering/code-execution-with-mcp) (nov-2025) · [Effective harnesses](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents) (nov-2025) · [Harness design](https://www.anthropic.com/engineering/harness-design-long-running-apps) (mar-2026) · [Managed agents](https://www.anthropic.com/engineering/managed-agents) (abr-2026)

**Comunidad:** [Framework Wars — HN](https://news.ycombinator.com/item?id=45155302) · [Swarms — HN](https://news.ycombinator.com/item?id=46743908) · [SDD/Spec-Kit — HN](https://news.ycombinator.com/item?id=45610996) · [From Beads to Tasks](https://paddo.dev/blog/from-beads-to-tasks/) · [Beads — Yegge](https://steve-yegge.medium.com/introducing-beads-a-coding-agent-memory-system-637d7d92514a) · [planning-with-files](https://github.com/othmanadi/planning-with-files) · [Scott Logic sobre Spec Kit](https://blog.scottlogic.com/2025/11/26/putting-spec-kit-through-its-paces-radical-idea-or-reinvented-waterfall.html) · [ToxicSkills/ecosistema de skills](https://agentman.ai/blog/agent-skills-ecosystem-report-2026)

**Notion/externos:** [Notion MCP overview](https://developers.notion.com/guides/mcp/overview) · [StackOne deep dive](https://www.stackone.com/blog/notion-mcp-deep-dive/) · [KanseiLink deep dive](https://kansei-link.com/en/insights/notion-mcp-deep-dive-2026) · [Notion 3.0](https://www.notion.com/blog/introducing-notion-3-0) · [MCP token limits](https://deploystack.io/blog/mcp-token-limits-the-hidden-cost-of-tool-overload) · [GitHub-native agent loop](https://saulius.io/blog/claude-code-github-native-agent-issue-to-merge-loop) · [basic-memory](https://github.com/basicmachines-co/basic-memory) · [Skills vs MCP — Willison](https://simonw.substack.com/p/claude-skills-are-awesome-maybe-a)
