# Brief: Modernización 2026 de memoria y agentes

## Objetivo

Incorporar al sistema las mejoras accionables identificadas por la investigación del 2026-08-13 (`AUDIT-memory-agents-2026-08.md`, plan de acción §8), en un único PR a `dev`.

## Alcance

Incluye:

1. Hook `PreCompact`: snapshot del estado de `.planning/` (STATE/HANDOFF) antes de una compactación, para proteger el flujo pause/resume.
2. Hook `SubagentStop`: log de invocaciones de subagentes, para hacer medible el budget de `rulebooks/agent-budget.md`.
3. Hook `SessionEnd`: aviso/registro si `STATE.md` quedó desactualizado al cerrar la sesión.
4. Registro de los 3 hooks en **ambos** settings (`settings.json` raíz que instala `install.sh` y `.claude/settings.json` del repo) — lección C5 de la auditoría de julio.
5. Runbook (`rulebooks/orchestrator-runbook.md`): paso de smoke test al retomar en Pause/Resume (correr test suite básico antes de tocar código).
6. Runbook: el estado mutable de `STATE.md` (checklist de lotes/fases pass-fail) pasa a formato JSON — definir el schema (hallazgo: los modelos corrompen menos JSON que markdown al mutar estado).
7. Runbook: regla anti-drift — todo PR que cambie el flujo incluye reconciliar los documentos que lo describen como parte de su DoD.
8. `rulebooks/validation-schedule.md`: stress-test trimestral de supuestos del harness (quitar una pieza de andamiaje en branch + correr `tests/adversarial/`).
9. `agents/e2e-runner.md`: frontmatter `memory: true` + instrucción de usar su memoria persistente para el tracking de flaky tests entre sesiones (piloto).
10. Docs: `README.md` + `CLAUDE.md` reflejando los hooks nuevos.
11. Tests: extender `tests/adversarial/test-hooks.sh` para cubrir los 3 hooks nuevos.
12. `.planning/FOLLOWUPS.md`: retirar los items que este PR implementa (aplicación inmediata de la regla anti-drift).

NO incluye:

- Empaquetar la metodología como plugin (follow-up aparte, esfuerzo alto).
- Adoptar Agent Teams (experimental; solo vigilar).
- Notion/backends externos de memoria (descartado — ver decisión en `ARCHITECTURE.md`).
- `memory: true` en agentes distintos de e2e-runner (evaluar tras el piloto).

## Reglas de negocio / restricciones

- Los 3 hooks nuevos son **no-bloqueantes**: nunca deben impedir una operación ni romper una sesión; ante cualquier error, exit 0 silencioso.
- Deben no-op limpio cuando corren fuera de este repo o sin `.planning/` (se instalan globalmente vía symlink de `install.sh`).
- Los devs editan los archivos del **repo** (`rulebooks/`, `hooks/`, `agents/`), no las copias/symlinks de `~/.claude/`.
- El schema JSON del estado mutable y la ubicación del log de SubagentStop son decisiones del architect.

## Decisiones tomadas

- Usuario (2026-08-13): **todo en un solo PR**, sobre el branch existente `feature/harden-pre-merge-check` (contiene el hardening del pre-merge ya commiteado y sin mergear; el PR único a `dev` lleva ambos objetivos). Excepción consciente a "un PR por objetivo".
- El cambio pendiente de `settings.json` (`effortLevel: xhigh`) se incluye en este PR (mismo archivo que el registro de hooks).
- Brainstorming saltado: cumple las 4 condiciones de CLAUDE.md (cambio técnico sin nueva funcionalidad de producto, sin contratos públicos, sin dependencias nuevas, descrito con precisión por la auditoría).

## Descartado explícitamente

- Hooks de tipo `prompt`/`agent` para los guards existentes: el determinismo de los guards `command` es el punto; no se tocan.
