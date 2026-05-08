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

### [2026-05-08] Suavizar regla de env vars en rules/docker.md
La regla actual prefiere "URLs completas con esquema (`postgres://...`)" sobre piezas separadas (`DB_HOST`/`DB_PORT`/`DB_USER`/`DB_PASS`). Es opinable — separadas dan flexibilidad para rotar credenciales sin tocar URL completa o para distintos orquestadores. Suavizar a "URL completa cuando aplique; piezas separadas cuando se rotan independientemente".
Origen: PR #24 review

### [2026-05-08] Refinar excepción USER nonroot en dev (UID mismatch)
La regla dice "documentar con comentario" si se usa root en dev por bind mounts. Eso abre la puerta a "OK, corre como root en dev". Más preciso: preferir build arg `--build-arg UID=$(id -u)`; root solo si el build arg no resuelve. Reescribir la excepción.
Origen: PR #24 review

### [2026-05-08] Decidir si `agents:` en frontmatter de rules/*.md es funcional o documentativo, y uniformar
`rules/docker.md` introdujo un campo `agents:` listando los lectores (`backend-dev`, `qa-backend`, etc.). Los demás `rules/*.md` (typescript, python, html, css, go, rust, csharp) solo tienen `paths:`. Si el campo lo procesa algún hook/agente, agregarlo a todos. Si es solo metadata documentativa, igual conviene uniformar para no tener dos estilos en el mismo directorio.
Origen: PR #24 review

### [2026-05-08] Deduplicar criterios de migración DB simple/complejo
La lista de criterios "qué califica como migración compleja" está duplicada en `agents/orchestrator.md`, `agents/backend-dev.md` y mencionada brevemente en `rulebooks/orchestrator-runbook.md`. Tres copias que se van a desincronizar. Mover a fuente única — opciones: `rules/db.md` (no existe), `rulebooks/db-migration-policy.md` nuevo, o sección dedicada del runbook — y que los demás referencien.
Origen: PR #24 review
