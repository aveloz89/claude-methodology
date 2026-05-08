# Learnings

Retrospectivas post-merge. El orchestrator **prepend** una entrada (más reciente arriba) después de cada PR mergeado.

## Formato de entrada

```markdown
### [YYYY-MM-DD] PR #N — Título del PR

**Métricas:**
- Review rounds: N
- Hallazgos security: N (critical: N, high: N, medium: N, low: N)
- Hallazgos qa-frontend: N (stubs: N, coverage: N, edge cases: N, otros: N)
- Hallazgos qa-backend: N (stubs: N, coverage: N, edge cases: N, otros: N)
- Errores de build/CI: N
- Self-reflection atrapó: N (cosas que detectó antes del review, o "nada")
- Lotes ejecutados: N / Tareas: M
- Devs involucrados: [db-specialist? backend-dev? frontend-dev?]

**Qué salió bien:**
- [descripción]

**Qué causó re-work:**
- [descripción — y si era prevenible]

**Patrón potencial:** [sí/no — si sí, cuál y cuántas veces se ha visto]
```

Formato canónico vive en `rulebooks/orchestrator-runbook.md`. Si ahí cambia, este archivo debe alinearse.

---

## Entradas

(Las entradas se agregan aquí, la más reciente arriba)
