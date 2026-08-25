# STATE

El estado mutable (fase, lotes, progreso) vive en `state.json`.

## Estado actual

- **Feature:** retro-before-merge — la retro deja de ser un PR aparte: se escribe en la Fase 4 y viaja como último commit del branch del feature, antes del merge
- **Última actualización:** 2026-08-24

## Decisiones

- [D-01] Brainstorming/design/docs saltados: cambio de flujo en 3 archivos, alcance mapeado por grep (DoD anti-drift del runbook); el diff ES documentación. Lo escribió el orchestrator, sin delegar a un dev.
- [D-02] El merge sale de la Fase 3 a una **Fase 5** propia en vez de renumerar el pipeline entero: "Fase 4 = retro" conserva su número y las referencias de `agent-budget.md` siguen válidas.
- [D-03] La retro se escribe pre-merge, no post-merge: al cerrar CI y re-reviews ya se conocen todas las métricas del template; lo único que falta es el merge. La alternativa para mantenerla post-merge (commit directo a `dev`) rompe gitflow.
- [D-04] Hotfix urgente: la retro no bloquea el merge — su entrada viaja en el commit de integración a `dev`, que ya es un push directo sancionado por el runbook.
- [D-05] El filtro de CI "diff sin código → sin suites" queda FUERA de este PR (objetivo distinto: `ci.yml` de cada repo + `pre-commit-guard.sh`). Sin él, el push de la retro sigue costando un run completo — está documentado como costo residual, no como supuesto.

## Blockers

- ninguno
