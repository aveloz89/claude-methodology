# STATE

El estado mutable (fase, lotes, progreso) vive en `state.json`.

## Estado actual

- **Feature:** hook-merge-repo-y-fila-dod — PR #76: `hooks/pre-merge-check.sh` acepta una forma única de merge y verifica el repo que se mergea (cierra #72), más la fila del PR #75 en el DoD anti-drift. Review dual APROBADO en 4 rondas; pendiente de aprobación de merge del usuario. Retro en `learnings/PR-76.md`
- **Última actualización:** 2026-09-17

## Decisiones

Detalle y contexto de D-01 a D-04 en `BRIEF.md`.

- [D-01] (usuario) Endurecer el hook en vez de documentar la limitación: un bloqueo falso entrena a pedir bypass.
- [D-02] La fila del PR #75 registra las dos violaciones del mismo PR, las dos encontradas por la pasada externa.
- [D-03] (usuario, tras ronda 1) Meter a este PR los huecos preexistentes `gh -R x pr merge` y `GH_REPO`.
- [D-04] (usuario, tras ronda 2) **Forma única, sin `cd`**: solo `gh pr merge <N>` con flags de una lista cerrada, en una línea, validada sobre el texto crudo; todo lo demás bloquea. Modelo de amenaza: errores honestos (`hooks/lib/guard-matching.sh:19-22`); lo disfrazado queda documentado como fuera de alcance.
- [D-05] (usuario, tras ronda 3) Los merges que el saneo compartido borra se documentan en el header y se arreglan aparte en el issue #77, que también reúne los pendientes no bloqueantes de las rondas 3 y 4.
- [D-06] (usuario, tras ronda 3) Cerrar sin más rondas amplias: la ronda 4 solo confirmó los bloqueantes pendientes y el delta del último lote.

**Pendiente:** #77 — saneo compartido de `guard-matching.sh` (merges que el hook no ve y bloqueos falsos en heredocs).

## Feature anterior

`regla-verificacion-visual` (PR #75): decisiones y aprendizajes en `learnings/PR-75.md` y `BRIEF-regla-verificacion-visual.md`. Su pendiente propuesto, la fila del DoD, entró en el PR #76.

## Blockers

- ninguno
