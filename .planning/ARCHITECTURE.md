# Architecture

Decisiones arquitectónicas recurrentes del proyecto. El `architect` lee este archivo al inicio de cada diseño para mantener consistencia, y lo actualiza al final con decisiones nuevas.

A diferencia de `DESIGN.md` (que vive solo durante una feature), este archivo persiste y acumula decisiones de **alcance recurrente**: stack, patrones, librerías canónicas, convenciones.

## Qué va aquí

- Arquitectura elegida y justificación (Monolito | Modular | Clean | Hexagonal | Microservicios)
- Patrones adoptados (repository, service layer, ports/adapters, etc.)
- Stack confirmado: librerías canónicas para validación, ORM, HTTP client, logging, cache, queue, testing
- Convenciones de nombres y estructura de directorios
- Boundaries entre módulos / bounded contexts

## Qué NO va aquí

- Detalles de la feature actual (eso vive en `DESIGN.md`)
- Decisiones específicas a un PR
- Notas de implementación

## Formato de entrada

```markdown
### [YYYY-MM-DD] Título de la decisión

**Contexto:** qué situación llevó a esta decisión.

**Decisión:** qué se eligió.

**Justificación:** por qué (alternativas evaluadas, tradeoffs).

**Implicación:** qué cambia para futuros diseños / qué patrones se siguen.
```

---

## Decisiones

(Las entradas se agregan aquí, la más reciente arriba)

### [2026-08-13] Artefactos operativos de hooks fuera del worktree, bajo `~/.claude/methodology/`

**Contexto:** los hooks de observabilidad nuevos (PreCompact, SubagentStop, SessionEnd) generan artefactos que mutan constantemente (logs de invocaciones, snapshots, markers entre sesiones). Guardarlos en `.planning/` ensuciaría `git status` en cada evento, se colaría en los commits per-tarea de los devs y metería ruido en cada PR; gitignorearlos desde un hook global sería invasivo en repos del usuario.

**Decisión:** todo artefacto operativo generado por hooks vive bajo la raíz única `~/.claude/methodology/` (`logs/`, `snapshots/<slug>/`, `session-end/`), fuera del worktree. Slug de repo = path del toplevel con `/` → `-` (misma convención que los directorios de proyectos de Claude Code). Todo output acotado: retención de 5 snapshots por repo, rotación del log a 1 MB, markers que se sobrescriben.

**Justificación:** cero ruido git, sobrevive al cleanup de `.planning/`, agregable entre proyectos, y una sola raíz que documentar y limpiar. Alternativa descartada: archivos dentro de `.planning/` (ruido en diffs y riesgo de colarse en commits).

**Implicación:** futuros hooks de observabilidad escriben ahí, usan `$HOME` (nunca `~` literal — los tests hacen override de `HOME` para sandboxear), son siempre `exit 0` (observabilidad ≠ guard), y definen su política de retención/rotación desde el diseño. Lo que debe viajar en el PR (estado de la feature) sigue en `.planning/`.

### [2026-08-13] Estado mutable en JSON (`state.json`), prosa en markdown

**Contexto:** hallazgo de Anthropic (nov-2025): los modelos corrompen/sobrescriben menos JSON que markdown al mutar estado. El checklist de fases/lotes con pass-fail de `STATE.md` es exactamente ese caso.

**Decisión:** el estado enumerable y mutable (fase del pipeline, lotes con status/progreso, branch/PR) vive en `.planning/state.json` (archivo separado, no bloque fenced) con schema versionado (`"schema": 1`), enum cerrado de status y claves fijas. La prosa (decisiones, blockers descritos, BRIEF/DESIGN/LEARNINGS) sigue en markdown.

**Justificación:** un archivo JSON puro minimiza la superficie de mutación y es parseable por hooks (`session-start-context.sh` lo renderiza) sin extraerlo de un .md. Un bloque embebido en markdown mantiene el riesgo de que el modelo reescriba la prosa circundante o rompa el fence.

**Implicación:** todo estado futuro que los agentes muten con frecuencia se diseña como JSON con schema explícito y enum cerrado; markdown queda para contenido que se lee y razona, no que se muta. Formato canónico en `rulebooks/orchestrator-runbook.md`.

### [2026-08-13] Memoria del sistema de agentes: archivos en repo, no backend externo (Notion descartado)

**Contexto:** se evaluó mover la memoria/estado del sistema (`.planning/`, auto-memory) a Notion AI u otro backend externo, ante la duda de si la metodología de archivos markdown quedó obsoleta. Investigación completa en `AUDIT-memory-agents-2026-08.md`.

**Decisión:** la memoria del agente permanece en archivos versionados en el repo. No se adopta Notion ni ningún backend externo de estado.

**Justificación:** el MCP de Notion carga ~26k tokens de definiciones de tools por sesión y ~18k por escritura de un documento; un backend externo rompe el versionado atómico estado-código (divergencia silenciosa); y su valor diferencial real (visibilidad para no-técnicos, edición multi-persona concurrente) no existe con un solo usuario. Archivos-en-repo es además el patrón que Anthropic implementa en su propio memory tool y documenta como best practice; no hay equipos documentados en producción usando Notion como memoria de agentes de código.

**Implicación:** no reabrir el debate sin que cambie el contexto. Triggers de reevaluación: (a) aparece un stakeholder no-técnico que necesita visibilidad del estado, o (b) se suma un colaborador no-dev. En ese caso el paso correcto es GitHub Issues (vía `gh`) o Linear MCP para el backlog humano — el estado del agente sigue en el repo igual.
