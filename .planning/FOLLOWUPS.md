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

### [2026-08-13] Smoke test al retomar sesión (Pause/Resume)
La secuencia oficial de inicialización de Anthropic (effective harnesses, nov-2025) incluye correr un test básico antes de tocar código, para cazar bugs no documentados por la sesión anterior. Nuestro flujo de resume (hook + HANDOFF) lee estado pero no verifica. Añadir el paso al runbook, sección Pause/Resume.
Origen: AUDIT-memory-agents-2026-08.md, plan de acción #2

### [2026-08-13] Migrar el estado mutable de STATE.md a JSON
Hallazgo de Anthropic (nov-2025): los modelos corrompen/sobrescriben menos JSON que markdown al mutar estado. Aplica al checklist de lotes/fases con pass-fail (bloque fenced o `state.json`); la prosa (BRIEF, DESIGN, LEARNINGS) sigue en markdown. Definir formato en el runbook.
Origen: AUDIT-memory-agents-2026-08.md, plan de acción #3

### [2026-08-13] Explotar eventos de hook nuevos: PreCompact, SubagentStop, SessionEnd
Hoy usamos 3 eventos, existen ~20. Candidatos con caso de uso claro: `PreCompact` → snapshot de STATE/HANDOFF antes de compactar (protege pause/resume); `SubagentStop` → log de invocaciones para hacer medible el budget de `agent-budget.md`; `SessionEnd` → recordatorio de STATE.md desactualizado.
Origen: AUDIT-memory-agents-2026-08.md, plan de acción #4

### [2026-08-13] Piloto de `memory: true` en e2e-runner
El frontmatter `memory: true` da memoria persistente propia por agente. El e2e-runner es el candidato ideal: el tracking de flaky tests entre sesiones es su responsabilidad y hoy no tiene mecanismo persistente propio. Evaluar con cuidado antes de extender a otros agentes (fragmenta la memoria); architect sería el segundo candidato.
Origen: AUDIT-memory-agents-2026-08.md, plan de acción #5

### [2026-08-13] Regla anti-drift: DoD de cambios de proceso incluye reconciliar documentos
El spec drift es el modo de fallo #1 de las metodologías con documentos (caso spec-kit), y ya nos pasó: las 7 contradicciones de la auditoría de julio venían todas del PR #44 (cambió el flujo sin actualizar lo que lo describía). Regla para el runbook: todo PR que cambie el flujo incluye grep + actualización de los documentos que lo describen.
Origen: AUDIT-memory-agents-2026-08.md, plan de acción #6

### [2026-08-13] Evaluar empaquetar la metodología como plugin de Claude Code
Los plugins empaquetan skills + agents + hooks + settings en un bundle instalable con marketplace — el mecanismo nativo 2026 para distribuir exactamente lo que hoy reparte `install.sh` con symlinks. Resolvería el follow-up del 2026-05-08 (carga global vs por proyecto) y eliminaría la clase de bug C5 de la auditoría de julio (hooks documentados pero no instalados). Esfuerzo alto: proyecto propio.
Origen: AUDIT-memory-agents-2026-08.md, plan de acción #7

### [2026-08-13] Stress-test trimestral de supuestos del harness
Anthropic (mar-2026): "cada componente de un harness codifica una suposición sobre lo que el modelo no puede hacer solo, y esas suposiciones caducan". En un branch, quitar una pieza de andamiaje (template de reporte, detalle de debugging) y correr `tests/adversarial/` para ver si el modelo actual la necesita; lo que sobrevive sin la pieza, se poda. Encaja con la frecuencia ya recomendada en `validation-schedule.md`.
Origen: AUDIT-memory-agents-2026-08.md, plan de acción #8

### [2026-08-13] Vigilar Agent Teams (no adoptar mientras sea experimental)
Anthropic nativizó nuestro patrón orchestrator+workers como feature experimental (flag `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`). Limitaciones actuales: sin `/resume`, task status con lag, reportes de mensajes perdidos entre teammates. Reevaluar cuando salga de experimental — parte del valor del runbook casero podría migrar al harness.
Origen: AUDIT-memory-agents-2026-08.md, plan de acción #9

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
