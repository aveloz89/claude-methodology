# STATE

El estado mutable (fase, lotes, progreso) vive en `state.json`.

## Estado actual

- **Feature:** reviewer-sandbox-rule (PR #84 abierto, review dual aprobado, retro en `learnings/PR-84.md`; pendiente de aprobación de merge): regla en `qa-backend`, `qa-frontend` y `security-reviewer` para que toda prueba que escriba sobre el repo corra en un worktree desechable fuera del repo, y para que no lancen `claude` ni otro agente CLI con permisos ampliados. Origen: patrón potencial de `learnings/PR-82.md`.
- **Última actualización:** 2026-09-26

## Decisiones

- [D-01] Brainstorming y architect saltados: el pedido del usuario define texto, ubicación y test; no cambia contratos públicos ni agrega dependencias. Un solo lote.
- [D-02] El test exige que el bloque de la regla sea idéntico en los tres prompts, no solo que exista (patrón de `learnings/PR-82.md`: una condición en N documentos se busca en los N y se compara).
- [D-03] Docs (Fase 2.5) saltada: el README resume cada agente en una línea y la regla vive en los propios prompts, que son la documentación normativa.
- [D-04] Sugerencias del review dual aplicadas antes del push: la regla cubre cualquier escritura (no una lista cerrada), prohíbe `git stash` por ser compartido entre worktrees y formula los permisos como invariante (el hijo no tiene más permisos que el reviewer), incluido `acceptEdits` y `--allowedTools`.

## Serie en paralelo: cerrar issues abiertos

Otra sesión trabaja la serie #78 → #71 → #73 → #77, un PR cada uno (`BRIEF-close-issues.md`). #78 mergeado en el PR #83 (`learnings/PR-83.md`). Decisiones del usuario: (D-01) un PR por issue en ese orden; (D-02) #77 completo, incluidas las formas disfrazadas; (D-03) #78 autorizado a quitar el bloque `hooks` de `.claude/settings.json`.

## Feature anterior

`product-reviewer` (PR #82, mergeado): `BRIEF-product-reviewer.md`, `DESIGN-product-reviewer.md` y `learnings/PR-82.md`.

## Blockers

- ninguno
