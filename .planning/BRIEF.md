## Brief: cerrar issues abiertos (#78, #71, #73, #77)

### Objetivo
Cerrar los 4 issues abiertos, uno por PR, en orden #78 → #71 → #73 → #77.

### Decisiones tomadas
- [D-01] (usuario) Los 4 issues, un PR cada uno, en ese orden.
- [D-02] (usuario) #77 completo: también se persiguen las formas disfrazadas, no solo los errores honestos. El usuario conoce el costo (retro del PR #76).
- [D-03] (usuario) #78: autorizado a quitar el bloque `hooks` de `.claude/settings.json` después de verificar que el plugin carga los hooks.

### Brainstorming
Se salta: son bug fixes con causa raíz descrita en cada issue.

### #78 (este PR)
- Evidencia de que el plugin carga los hooks: los bloqueos de la sesión 2026-09-26 los atribuye a `methodology@skills-dir plugin`, y el contexto de SessionStart apareció duplicado al inicio de la sesión (plugin + settings.json).
- Cambio: quitar `hooks` de `.claude/settings.json` y dejar `permissions` intacto. Test que impida que vuelva.

### #71
- Decisión D-04: aclarar y cerrar. El registro del review lo escribe solo el orchestrator: consolida los reportes de reviewers que corren en paralelo, porque `security-reviewer`, `qa-backend` y `qa-frontend` tienen `Write`/`Edit` prohibidos. Se agrega una línea al runbook (Fase 2.6, paso 4) y a los 3 prompts: el reviewer devuelve su reporte y no escribe el registro.
