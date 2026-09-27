# STATE

El estado mutable (fase, lotes, progreso) vive en `state.json`.

## Estado actual

- **Feature:** cerrar issues abiertos, un PR cada uno: #78 → #71 → #73 → #77 (ver `BRIEF.md`). #78 cerrado (PR #83), #71 cerrado (PR #85). #73 cerrado (PR #87). PR #88 (#77 + #86 + D-07): review aprobado, retro en `learnings/PR-88.md`; pendiente de merge. Con su merge no quedan issues abiertos.
- **Última actualización:** 2026-09-26

## Decisiones

- [D-01] (usuario) Los 4 issues, un PR cada uno, en ese orden.
- [D-02] (usuario) ~~#77 completo, incluidas las formas disfrazadas.~~ Reemplazada por D-05.
- [D-05] (usuario, 2026-09-27) #77 acotado a errores honestos (`+main`, `-fu`, `git -C … push`, `gh -R … --admin`, bloqueo falso con heredocs, NUL, 4 detalles de docs). Las formas disfrazadas se documentan fuera de alcance, por costo.
- [D-03] (usuario) #78 autorizado a quitar el bloque `hooks` de `.claude/settings.json` después de verificar.
- [D-04] (usuario) #71: aclarar y cerrar. Los reviewers no pueden escribir (`Write`/`Edit` prohibidos) y el orchestrator es el único que escribe el registro; se deja explícito en el runbook y en los prompts, con test.

## Feature intercalada: reviewer-sandbox-rule (PR #84)

Otra sesión, en paralelo a esta serie: regla "Pruebas que escriben archivos" en `qa-backend`, `qa-frontend` y `security-reviewer`. Las escrituras sobre el repo van en un worktree desechable fuera del repo, y ningún proceso hijo tiene más permisos que el reviewer. Decisiones y review en `reviews/PR-84.md`; retro en `learnings/PR-84.md`. No toca el estado de esta serie.

- [D-06] (usuario, 2026-09-27) Todo lo que queda (#77 acotado + #86) va en **un solo PR**.
- [D-07] (usuario, 2026-09-27) Cualquier issue o hallazgo que aparezca durante este trabajo (review, tests, docs) entra en este mismo PR; no se abren issues aparte. Las formas disfrazadas siguen fuera (D-05).

## Feature anterior

`product-reviewer` (PR #82, mergeado): `BRIEF-product-reviewer.md`, `DESIGN-product-reviewer.md`, `learnings/PR-82.md`.

## Feature previa

`audit-best-practices` (PRs #79, #80, #81, mergeados): `BRIEF-audit-best-practices.md`, `DESIGN-audit-best-practices.md` y `learnings/PR-79.md` a `PR-81.md`. `global/CLAUDE.md` pasó de 6.436 a 2.593 tokens; quedan 11 agentes.

## Blockers

- ninguno
