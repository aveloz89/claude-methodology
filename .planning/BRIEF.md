# Brief: Barrido de follow-ups + plugin de distribución

## Objetivo

Un PR a `dev` que ataque TODOS los follow-ups accionables de `.planning/FOLLOWUPS.md` (9 de 10), incluyendo la implementación completa del plugin de Claude Code como mecanismo de distribución de la metodología. Decisión explícita del usuario (2026-08-14): todo en un solo PR, plugin incluido.

## Alcance

**Grupo A — Plugin y carga global (el proyecto grande):**

1. Empaquetar la metodología como **plugin de Claude Code**: skills + agents + hooks (+ settings que aplique) en bundle instalable.
2. Resolver la **carga global vs por proyecto** de la metodología (follow-up 2026-05-08). Restricción de plataforma conocida (verificar): los plugins empaquetan skills, agents, hooks y MCP servers — **NO distribuyen CLAUDE.md ni `rules/` ni `rulebooks/`**. El architect debe diseñar el híbrido: plugin para lo que el plugin cubre + mecanismo para instrucciones/rules/rulebooks (opciones conocidas: symlink de un CLAUDE.md global curado a `~/.claude/CLAUDE.md` — la jerarquía oficial carga managed → user → project → local, todos a la vez, con override por proximidad; `install.sh` residual para rules/rulebooks; import con `@`).
3. Destino de `install.sh`: coexiste, se reduce a lo que el plugin no cubre, o se deprecia — decisión del architect con justificación.

**Grupo B — Hooks y tests:**

4. **Slug + hash del toplevel** en los 4 hooks que derivan slug (`session-start-context.sh`, `pre-compact-snapshot.sh`, `subagent-stop-log.sh`, `session-end-check.sh`): `tr '/' '-'` no es inyectivo, repos distintos pueden colisionar y pisarse artefactos. Sufijo de 8 chars de hash del toplevel. Actualizar la decisión de convención en ARCHITECTURE.md. Los 4 hooks deben cambiar juntos (mismo slug derivado) + migración/compat de artefactos existentes: decisión del architect (¿se migran, se abandonan, se lee ambos?).
5. **Sandboxear los tests de guards** de `tests/adversarial/test-hooks.sh`: hoy hacen `git stash` + `git checkout main` sobre el repo REAL (casi pérdida de estado en PR #49). Migrar al patrón sandbox que ya usan los tests de observabilidad (repo git temporal + HOME override).

**Grupo C — Skill nueva:**

6. **Skill `/review-pr`**: re-disparo manual del review dual (security + qa según capas tocadas) sobre un PR existente, sin pasar por el flujo completo del orchestrator. Diseñar contrato: input (número de PR), qué lanza, formato de reporte.

**Grupo D — Docs/rules (chicos, texto ya especificado en los follow-ups):**

7. `rules/docker.md`: suavizar regla de env vars → "URL completa cuando aplique; piezas separadas cuando se rotan independientemente".
8. `rules/docker.md`: reescribir excepción USER nonroot en dev → preferir `--build-arg UID=$(id -u)`; root solo si el build arg no resuelve.
9. Quitar el frontmatter `agents:` de `rules/docker.md` y `rules/implementation-principles.md` (verificado: nada lo procesa; decisión del usuario: quitar, no uniformar agregando).
10. Deduplicar criterios de migración DB simple/complejo: `agents/backend-dev.md` referencia al runbook (fuente canónica) en vez de repetir la lista.

**NO incluye:** Agent Teams (vigilancia con trigger documentado — sigue en FOLLOWUPS como único item). Al cierre del PR, FOLLOWUPS queda solo con ese item.

## Decisiones tomadas

- [D-01] Usuario: todo en un solo PR, plugin incluido (aceptando el costo de diff grande; el PR body debe estar organizado por grupos para navegabilidad).
- [D-02] Usuario: `agents:` se quita, no se uniformiza agregando.
- [D-03] El cambio de convención del slug está autorizado (ARCHITECTURE.md se actualiza como parte del PR).
- [D-04] Formato `state.json` en uso (segunda feature con él).

## Restricciones

- TDD para todo lo de hooks/tests (grupos B): la suite adversarial está en 91/91 y debe terminar verde con los tests nuevos.
- El plugin no debe romper la instalación actual del usuario (que usa symlinks de install.sh) — la transición debe ser explícita y documentada.
- Review dual bloqueante al final, con presupuesto proporcional (el diff será grande: organizar por grupos).
- CLAUDE.md del repo se mantiene ≤~200 líneas.

## Datos de investigación para el architect (2026-08, docs oficiales — verificar localmente lo verificable)

- Plugins: bundle de skills+agents+hooks+MCP; scopes user/project/local; instalación `/plugin install <nombre>@<marketplace>`; un repo puede servir de marketplace; validación con pinning SHA en el marketplace comunitario. La CLI local puede tener `claude plugin --help` para verificar el surface real.
- Jerarquía CLAUDE.md: managed (`/Library/Application Support/ClaudeCode/`) → user (`~/.claude/CLAUDE.md`) → project (`./CLAUDE.md`) → local (`./CLAUDE.local.md`); TODOS cargan; override por proximidad. Imports con `@path` (hasta 4 niveles; imports externos piden aprobación la primera vez).
- `~/.claude/rules/*.md` se auto-carga (con `paths:` condicional); los plugins NO las distribuyen.
- Skills de plugin llevan namespace `/plugin-name:skill-name`.
