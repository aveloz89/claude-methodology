# STATE

El estado mutable (fase, lotes, progreso) vive en `state.json`.

## Estado actual

- **Feature:** verification-rule — escribir la regla que la regla de 3 venía pidiendo desde el PR #55: toda afirmación sobre el comportamiento del sistema se verifica ejecutándola
- **Última actualización:** 2026-08-25

## Decisiones

- [D-01] La regla va en **dos** lugares a propósito: `rules/implementation-principles.md` §5 (detalle, se carga con el código) y una regla operativa en `global/CLAUDE.md` (siempre cargada). Tres de las cinco fallas que la motivaron fueron afirmaciones en markdown — runbook, mensaje de commit y tabla de review —, así que una regla que solo se cargue con código no las habría atrapado.
- [D-02] La comprobación del corolario es del **dev**, no del QA: los QA son read-only por frontmatter y la redacción original los obligaba a rodear su propia política de tools con `sed -i`. Hallazgo HIGH de security.
- [D-03] El corolario dice "revertir el cambio del fix", no "borrar la línea": con un fix de un token, borrar la línea rompe la sintaxis y la suite se pone roja por la razón equivocada — el check pasaría vacío simulando la verificación que el principio instala.
- [D-04] `.sh`/`.bash` entran a los `paths:` de **ambos** documentos transversales. Agregarlos solo a uno rompió el espejo que mantienen por convención; lo detectó qa-backend.
- [D-05] `rules/bash.md` NO se escribe en este PR: es otro objetivo. Queda anotado que shell es el único lenguaje del repo sin reglas idiomáticas propias, en un repo que es casi todo shell.
- [D-06] Docs (Fase 2.5) saltada: el diff ES documentación normativa.

## Blockers

- ninguno
