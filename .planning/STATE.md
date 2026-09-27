# STATE

El estado mutable (fase, lotes, progreso) vive en `state.json`.

## Estado actual

- **Feature:** audit-best-practices: alinear la metodología con las prácticas oficiales de Anthropic (auditoría en `AUDIT-best-practices-2026-09.md`). Diseño aprobado: multi-PR secuencial (PR 1 fixes técnicos, lotes 1-2; PR 2 skill orchestrator + núcleo, lotes 3-4; PR 3 fusiones, lotes 5-6). PR 1 = #79, mergeado a `dev` (retro en `learnings/PR-79.md`). PR 2 = #80: review dual aprobado en 2 rondas, retro en `learnings/PR-80.md`; pendiente de aprobación de merge. Siguiente: PR 3 (fusiones, lotes 5-6).
- **Medición PR 2** (`claude -p --output-format json`, dos repos temporales, delta contra baseline): `global/CLAUDE.md` pasa de **6.436 → 2.593 tokens** (−60 %) por cada sesión y cada subagente. 21.081 → 8.466 bytes; 190 → 87 líneas.
- **Última actualización:** 2026-09-26

## Decisiones

Detalle en `BRIEF.md`.

- [D-01] (usuario) La auditoría va antes que el agente PM.
- [D-02] (usuario) Incluye partir `CLAUDE.md` y la fusión de agentes.
- [D-03] (usuario) Rol corto en `CLAUDE.md` + skill `orchestrator` bajo demanda + recordatorio del hook de sesión.
- [D-04] (usuario) Aprobado el plan de 3 PRs y las fusiones: `build-resolver` → rulebook, `db-specialist` → `backend-dev` + rulebook; `docs` y `ui-ux` se mantienen con disparadores más estrictos.
- [D-05] (usuario) `effort: high` solo en reviewers sonnet (`qa-*`); devs en default por costo.

**Issue a abrir:** `.claude/settings.json` de este repo duplica los 14 hooks del plugin.

**Pendiente después:** agente de producto/PM (feature aparte).

## Feature anterior

`hook-merge-repo-y-fila-dod` (PR #76): `learnings/PR-76.md` y `BRIEF-hook-merge-repo-y-fila-dod.md`.

## Blockers

- ninguno
