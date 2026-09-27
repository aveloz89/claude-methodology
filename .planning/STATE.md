# STATE

El estado mutable (fase, lotes, progreso) vive en `state.json`.

## Estado actual

- **Feature:** cerrar issues abiertos, un PR cada uno: #78 → #71 → #73 → #77 (ver `BRIEF.md`). #78 cerrado (PR #83). En curso: #71 (`fix/review-registry-single-writer`).
- **Última actualización:** 2026-09-26

## Decisiones

- [D-01] (usuario) Los 4 issues, un PR cada uno, en ese orden.
- [D-02] (usuario) #77 completo, incluidas las formas disfrazadas.
- [D-03] (usuario) #78 autorizado a quitar el bloque `hooks` de `.claude/settings.json` después de verificar.
- [D-04] (usuario) #71: aclarar y cerrar. Los reviewers no pueden escribir (`Write`/`Edit` prohibidos) y el orchestrator es el único que escribe el registro; se deja explícito en el runbook y en los prompts, con test.

## Feature intercalada: reviewer-sandbox-rule (PR #84)

Otra sesión, en paralelo a esta serie: regla "Pruebas que escriben archivos" en `qa-backend`, `qa-frontend` y `security-reviewer`. Las escrituras sobre el repo van en un worktree desechable fuera del repo, y ningún proceso hijo tiene más permisos que el reviewer. Decisiones y review en `reviews/PR-84.md`; retro en `learnings/PR-84.md`. No toca el estado de esta serie.

## Feature anterior

`product-reviewer` (PR #82, mergeado): `BRIEF-product-reviewer.md`, `DESIGN-product-reviewer.md`, `learnings/PR-82.md`.

## Feature previa

`audit-best-practices` (PRs #79, #80, #81, mergeados): `BRIEF-audit-best-practices.md`, `DESIGN-audit-best-practices.md` y `learnings/PR-79.md` a `PR-81.md`. `global/CLAUDE.md` pasó de 6.436 a 2.593 tokens; quedan 11 agentes.

## Blockers

- ninguno
