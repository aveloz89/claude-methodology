# STATE

El estado mutable (fase, lotes, progreso) vive en `state.json`.

## Estado actual

- **Feature:** fix-open-issues — cierre de los 4 issues abiertos (#47, #50, #51, #52) en un PR a dev
- **Última actualización:** 2026-08-13

## Decisiones

- [D-01] Helper compartido `hooks/lib/guard-matching.sh` para el matching de los 3 guards (anti-drift; ver BRIEF).
- [D-02] Brainstorming y architect saltados con justificación (bug fixes con causa raíz y remediación en los issues).
- [D-03] Primer uso del formato `state.json` (schema D3).
- [D-04] Issues se cierran manualmente post-merge (el merge a dev no auto-cierra; default branch es main).

## Blockers

- ninguno
