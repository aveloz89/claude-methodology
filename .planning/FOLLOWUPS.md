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
La lista de criterios "qué califica como migración compleja" está duplicada en `agents/backend-dev.md` y `rulebooks/orchestrator-runbook.md`. Fuente canónica: el runbook. Colapsar `backend-dev.md` para que solo referencie al runbook en vez de repetir la lista.
Origen: PR #24 review

### [2026-05-08] Decidir cómo se carga la metodología globalmente vs por proyecto (CLAUDE.md)
Los agentes referencian "CLAUDE.md raíz" sin prefix (queda relativo al CWD). Cuando un agente corre desde un proyecto del usuario (`~/Proyectos/miapp/`), `CLAUDE.md` resuelve al del proyecto del usuario, no al de la metodología. Eso significa que las reglas globales (gitflow, dual review, principio de Frontend delgado, etc.) no se aplican automáticamente — el usuario tendría que copiar/extender el CLAUDE.md de la metodología en cada proyecto.

Opciones a evaluar:
1. **Symlinkear el CLAUDE.md de la metodología a `~/.claude/CLAUDE.md`** (Claude Code lo auto-carga como instrucciones globales del usuario). Agregar al install.sh.
2. **Documentar que cada proyecto debe `import` o copiar el CLAUDE.md** de la metodología.
3. **Cambiar las referencias en los agentes** a path absoluto (`~/Proyectos/claude-methodology/CLAUDE.md`) — pero hardcodea ruta del autor, no portable.

Probablemente opción 1, pero requiere revisar el orden de precedencia de Claude Code (¿qué pasa si el proyecto del usuario también tiene CLAUDE.md? ¿se mergean? ¿override?).
Origen: PR #24 review (path style fix)
