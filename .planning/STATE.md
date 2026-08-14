# STATE

El estado mutable (fase, lotes, progreso) vive en `state.json`.

## Estado actual

- **Feature:** align-atomic-commits — alinear la letra de la regla de commits con la práctica real (commit por tarea) y recalibrar la heurística de corte de PRs
- **Última actualización:** 2026-08-14

## Decisiones

- [D-01] Brainstorming/design/docs saltados: cambio de redacción de 3 archivos, alcance mapeado por grep (8 puntos), sin decisiones estructurales; el diff ES documentación.
- [D-02] La decisión histórica del 2026-07-24 en pr-workflow NO se reescribe — se enmienda con nota fechada 2026-08-14 (los registros de decisiones no se falsifican).
- [D-03] La heurística de corte deja de contar commits (commits atómicos = más navegabilidad, no menos) — la señal es el diff irrevisable: >1000 LoC de naturaleza mixta sin agrupación navegable en el PR body.
- [D-04] Tracker de sesión omitido (criterio del harness: <3 pasos no se trackea).

## Blockers

- ninguno
