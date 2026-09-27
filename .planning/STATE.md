# STATE

El estado mutable (fase, lotes, progreso) vive en `state.json`.

## Estado actual

- **Feature:** product-reviewer: subagente de producto que cuestiona si una feature vale la pena y deja criterios de aceptación medibles. No bloquea; solo corre en productos con usuarios reales. Diseño cerrado (fase 0.3, detección `Tipo: producto con usuarios`, 3 lotes en un PR). En lote 1.
- **Última actualización:** 2026-09-26

## Decisiones

Detalle en `BRIEF.md`.

- [D-01] (usuario) No sustituye el brainstorming: funciona como filtro de "vale la pena" y de qué esperamos obtener.
- [D-02] (usuario) No bloquea.
- [D-03] (usuario) Solo en productos con usuarios reales.
- [D-04] (usuario) Subagente entre el brief y el architect, activado por una línea en el `CLAUDE.md` del proyecto.
- [D-05] (usuario) Siempre preguntar antes que suponer: el agente devuelve preguntas, el orchestrator las relaya y lo reanuda.

## Feature anterior

`audit-best-practices` (PRs #79, #80, #81, mergeados): `BRIEF-audit-best-practices.md`, `DESIGN-audit-best-practices.md` y `learnings/PR-79.md` a `PR-81.md`. `global/CLAUDE.md` pasó de 6.436 a 2.593 tokens; quedan 11 agentes.

## Blockers

- ninguno
