# Follow-ups

Ideas, mejoras y pendientes que surgieron durante el trabajo pero no son urgentes ni están listos para ser issues.
Cuando algo madure, se promueve a GitHub Issue y se borra de aquí.

## Formato

```
### [Fecha] Descripción corta
Contexto de dónde surgió y por qué importa.
Origen: [conversación / PR #N / sweep / QA review]
```

## Pendientes

### [2026-04-06] Evaluar skill /review-pr para re-reviews manuales
Actualmente el dual review (QA + security) se dispara automáticamente al crear PR via hook. No hay forma de re-dispararlo manualmente sin pasar por el orchestrator.
Origen: conversación durante implementación del latent-bugs-sweep
