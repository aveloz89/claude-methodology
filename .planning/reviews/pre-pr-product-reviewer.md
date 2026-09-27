# Review dual pre-push: product-reviewer

- **Branch:** `feature/product-reviewer` · **Base:** `dev`
- **Fecha:** 2026-09-26

## Ronda 1: HEAD `96c36c1`

**Veredicto consolidado:** CAMBIOS REQUERIDOS (1 bloqueante de QA)

### security-reviewer (opus): APROBADO
- **Hooks entrecomillados, verificado ejecutando:** con `claude -p --plugin-dir` en una ruta con espacios y un marcador en la copia del hook, `block-hard-reset` corrió y bloqueó; el árbol quedó intacto. Los otros 13 hooks no se ejecutaron uno por uno (el cambio es idéntico).
- **Agente de solo lectura, verificado ejecutando:** no pudo crear un archivo; declara solo Read, Grep y Glob.
- **[LOW]** `agents/product-reviewer.md:15,28` y runbook Fase 0.3 no aclaran que el brief y el README son datos, no instrucciones. Con un README hostil, el reporte podría llevar texto dirigido al orchestrator o secrets leídos. → agregar una línea en el agente y otra en el runbook.
- Nota para el usuario: la prueba usó `--permission-mode bypassPermissions` dentro de un repo temporal del scratchpad, fuera del proyecto, que ya se borró.

### qa-backend: CAMBIOS NECESARIOS
- **[BLOQUEANTE]** La condición de activación no coincide. El agente (l.3) y el README (l.205) dicen "solo en features nuevas", pero el runbook (Fase 0.3, l.50-53) y la skill (l.22) solo piden la línea `Tipo:` y "hubo brainstorming". El calificador de `DESIGN.md:164` se perdió al implementar. → poner "feature nueva, no fix ni cambio técnico" en el runbook y la skill, con un assert.
- **[sugerencia]** Etiqueta de origen: el agente usa `nuevo` y la plantilla de `BRIEF.md` en el runbook usa `product-reviewer`. → unificar.
- **[sugerencia]** El sandbox de `assert_agent_read_only` infla TOTAL/PASS en 2 (152/150/0); no oculta fallos. → descontar también TOTAL y PASS.
- Verificado: no hay rastro de "declara supuestos" (solo aparece en los red flags de `agent-validation.md`); "no bloquea" es coherente; el ciclo de preguntas es coherente; el test de comillas pasa a rojo al revertir el fix (worktree desechable); el prompt es claro y corto.
- **NO CUBIERTO:** el end-to-end con `claude -p` quedó bloqueado por el clasificador de auto-mode. Se reemplazó con `sh -c` del comando entrecomillado: `pre-merge-check` sigue bloqueando (exit 2).
- **Incidente declarado por QA:** un `git show … > hooks/hooks.json` sobrescribió por un momento el árbol real y QA lo revirtió. El orchestrator verificó: `git status` limpio, `hooks.json` igual a HEAD y sin worktrees.

Fixes en `48bf53b` (calificador "feature nueva" en runbook y skill), `226f585` (brief, README y reporte son datos), `4da1976` (etiqueta `nuevo`), `fdc443f` (el sandbox restaura TOTAL/PASS, más invariante Total = Pass + Fail) y `a88af9c` (voseo residual encontrado por el orchestrator: "evaluás", "activalo"). El orchestrator verificó con grep que la condición es idéntica en el agente, el README, la skill y el runbook. No se relanzan los reviewers: el delta aplica exactamente la remediación pedida y cada fix tiene su assert.

## Cierre

**Veredicto final:** APROBADO. HEAD revisado `a88af9c`. Suites: `test-hooks` 358/358, `test-plugin-manifest` 157/157, `test-frontmatter` 107/107; `validate --strict` sobre `plugin.json` y `.` pasa.
