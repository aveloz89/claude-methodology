# Review dual pre-push — audit-best-practices (PR 1/3)

- **Branch:** `feature/audit-best-practices` · **Base:** `dev`
- **Fecha:** 2026-09-26

## Ronda 1 — HEAD `9eac8d1`

**Veredicto consolidado:** CAMBIOS REQUERIDOS (1 bloqueante de QA)

### security-reviewer (opus): APROBADO
- CRITICAL 0 · HIGH 0 · MEDIUM 2 · LOW 2 · legacy 2
- **[MEDIUM, nuevo]** `pre-commit-guard.sh:169,183`: si `PRECOMMIT_TEST_BUDGET` no es numérico (p. ej. `abc`) o es ≥ 600, el watchdog nunca corta y gana el timeout del harness (fail-open). → aplicar: validar `^[0-9]+$`, cap < 600, test.
- **[MEDIUM, preexistente en archivo tocado]** `block-force-push.sh:26-27` y `block-hard-reset.sh:20-21` dejan pasar si falta jq; `block-admin-merge` bloquea. → aplicar: mismo check fail-closed + test.
- **[LOW, regresión del PR]** `git push origin "--force"` / `'-f'` ya no bloquean (`guard_sanitize` borra lo que está entre comillas); en `dev` sí bloqueaban. → aplicar el fix o documentarlo como limitación.
- **[LOW]** Quitar `permissionMode` no cambia nada; la restricción de solo lectura con `Bash` depende del prompt (ya era así). → sin cambio.
- **[legacy]** `block-admin-merge` no detecta `gh -R o/r pr merge --admin` (lo cubre `pre-merge-check`); `pre-release-sweep` sin anclaje y fail-open sin jq/gh. → comentario en #77.
- NO CUBIERTO: docs/normativos, lógica API de `pre-merge-check`, rojo al revertir en `test-frontmatter`/`test-plugin-manifest`, premisa de que el harness deja pasar al vencer el timeout.

### qa-backend: CAMBIOS NECESARIOS
- **[BLOQUEANTE]** `test-frontmatter.sh:207-224`: el check de referencias implementa solo `methodology:<x>`. Falta la mitad del contrato de `DESIGN.md:83`: las menciones `` `<agente>` `` de la lista histórica. Hay 35 menciones de `build-resolver`/`db-specialist` sin prefijo que quedarían colgando en el PR 3. → `backend-dev` extiende el check.
- **[sugerencia]** `global/CLAUDE.md` tiene 4 `NUNCA` (techo 3); es preexistente. → PR 2.
- Verificado por QA: watchdog rojo→verde al revertir el fix (worktree desechable); `.claude/CLAUDE.md` sigue cargando (`claude -p`); suites 335/31/91 en verde; ambos `validate --strict` pasan.
- NO CUBIERTO: `guard-matching.sh` en profundidad, entornos sin jq/perl/claude.
