# STATE

El estado mutable (fase, lotes, progreso) vive en `state.json`.

## Estado actual

- **Feature:** reviewer-sandbox-rule: regla en `qa-backend`, `qa-frontend` y `security-reviewer` para que toda prueba que escriba archivos corra en un worktree desechable o directorio temporal, y para que no lancen `claude` con permisos saltados. Origen: patrón potencial de `learnings/PR-82.md`.
- **Última actualización:** 2026-09-26

## Decisiones

- [D-01] Brainstorming y architect saltados: el pedido del usuario define texto, ubicación y test; no cambia contratos públicos ni agrega dependencias. Un solo lote.
- [D-02] El test exige que el bloque de la regla sea idéntico en los tres prompts, no solo que exista (patrón de `learnings/PR-82.md`: una condición en N documentos se busca en los N y se compara).

## Feature anterior

`product-reviewer` (PR #82, mergeado): `BRIEF-product-reviewer.md`, `DESIGN-product-reviewer.md` y `learnings/PR-82.md`.

## Blockers

- ninguno
