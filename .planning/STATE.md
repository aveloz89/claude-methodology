# STATE

El estado mutable (fase, lotes, progreso) vive en `state.json`.

## Estado actual

- **Feature:** pre-pr-reviews — mover el review dual a antes del push/PR para ahorrar runs de CI
- **Última actualización:** 2026-08-14

## Decisiones

- [D-01] Invariante intacto (review dual bloqueante pre-merge); cambia el momento: pre-push.
- [D-02] post-pr-create.sh queda como checkpoint de respaldo para PRs fuera del flujo.
- [D-03] E2E Modo B sin cambio.
- [D-04] Dogfooding: este PR estrena el orden nuevo.
- [D-05] "Un push por ronda" sobrevive solo post-PR.

## Blockers

- ninguno
