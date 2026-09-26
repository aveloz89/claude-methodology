# STATE

El estado mutable (fase, lotes, progreso) vive en `state.json`.

## Estado actual

- **Feature:** audit-best-practices: alinear la metodología con las prácticas oficiales de Anthropic (auditoría en `AUDIT-best-practices-2026-09.md`). Brief cerrado; en diseño con el architect.
- **Última actualización:** 2026-09-26

## Decisiones

Detalle en `BRIEF.md`.

- [D-01] (usuario) La auditoría va antes que el agente PM.
- [D-02] (usuario) Incluye partir `CLAUDE.md` y la fusión de agentes.
- [D-03] (usuario) Rol corto en `CLAUDE.md` + skill `orchestrator` bajo demanda + recordatorio del hook de sesión.

**Pendiente después:** agente de producto/PM (feature aparte).

## Feature anterior

`hook-merge-repo-y-fila-dod` (PR #76): `learnings/PR-76.md` y `BRIEF-hook-merge-repo-y-fila-dod.md`.

## Blockers

- ninguno
