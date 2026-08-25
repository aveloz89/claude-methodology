# STATE

El estado mutable (fase, lotes, progreso) vive en `state.json`.

## Estado actual

- **Feature:** retro-before-merge — **mergeada en el PR #59**. La retro deja de ser un PR aparte: se escribe en la Fase 4 y viaja como último commit del branch del PR, antes del merge
- **Última actualización:** 2026-08-24

## Decisiones

- [D-01] Brainstorming/design/docs saltados: cambio de flujo en 3 archivos, alcance mapeado por grep (DoD anti-drift del runbook); el diff ES documentación. Lo escribió el orchestrator, sin delegar a un dev.
- [D-02] El merge sale de la Fase 3 a una **Fase 5** propia en vez de renumerar el pipeline entero: "Fase 4 = retro" conserva su número y las referencias de `agent-budget.md` siguen válidas.
- [D-03] La retro se escribe pre-merge, no post-merge: al cerrar CI y re-reviews ya se conocen todas las métricas del template; lo único que falta es el merge. La alternativa para mantenerla post-merge (commit directo a `dev`) rompe gitflow.
- [D-04] Hotfix urgente: la retro no bloquea el merge — su entrada viaja en el commit de integración a `dev`, que ya es un push directo sancionado por el runbook.
- [D-06] La cardinalidad de `LEARNINGS.md` es **una entrada por PR mergeado**, no por feature: en multi-PR cada grupo corre su propia Fase 4, y el template indexa por `PR #N`. Bloqueante de qa-backend en la ronda 1.
- [D-07] El commit de retro toca SOLO `.planning/`, y el check 4 de la verificación pre-merge lo verifica: es el único push post-review que ningún hook mira (`post-pr-create.sh` valida al crearse el PR y no vuelve a mirar el branch). Hallazgo MEDIUM de security.
- [D-05] El filtro de CI "diff sin código → sin suites" queda FUERA de este PR (objetivo distinto: `ci.yml` de cada repo + `pre-commit-guard.sh`). Sin él, el push de la retro sigue costando un run completo — está documentado como costo residual, no como supuesto.

## Blockers

- ninguno
