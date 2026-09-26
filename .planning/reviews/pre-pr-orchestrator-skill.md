# Review dual pre-push: audit-best-practices, PR 2/3 (orchestrator-skill)

- **Branch:** `feature/orchestrator-skill` · **Base:** `dev`
- **Fecha:** 2026-09-26

## Ronda 1: HEAD `e098a9b`

**Veredicto consolidado:** CAMBIOS REQUERIDOS (4 bloqueantes de QA)

### security-reviewer (opus): APROBADO
- Las invariantes siguen en el núcleo (aprobación de merge, CI rojo, `--admin`, push a main, force/reset, review dual, "nunca esquivar un hook").
- **[MEDIUM]** La regla de degradación de security-reviewer (solo a sonnet si el diff no toca auth/crypto/secrets/pagos) quedó solo en la skill (`SKILL.md:67`). → devolverla al núcleo.
- **[MEDIUM]** `SKILL.md:5` tiene `allowed-tools` con `Bash` sin acotar. La skill se carga casi siempre, así que se pierde el permission prompt ante contenido inyectado. No se verificó ejecutando. → acotar a `Bash(git *)`, `Bash(gh *)` y `Bash(jq *)` y verificar con una prueba.
- **[LOW]** La guía "`--repo`, nunca `cd`" salió del núcleo; `pre-merge-check` la muestra al bloquear. → sin cambio.
- **[LOW]** El recordatorio del hook no aparece fuera de un repo git. Es una cadena fija, sin inyección. → sin cambio.
- NO CUBIERTO: tests, runbook, governance y agentes línea por línea.

### qa-backend: CAMBIOS NECESARIOS
- **[BLOQUEANTE]** Las 4 condiciones AND para saltar el brainstorming no están en ningún documento. La skill §3 remite al núcleo, que ya no las tiene, y al runbook Fase 0, que tiene una lista distinta y más laxa. Además, `DESIGN.md:104` pedía llevarlas a la skill. → restaurarlas en la skill y alinear el runbook.
- **[BLOQUEANTE]** `SKILL.md:5` no declara `Agent(methodology:…)` para los agentes que delega; las otras skills sí lo hacen. (Nota del orchestrator: la verificación c del DESIGN mostró que el tool `Agent` no pide permiso, así que hoy es solo por consistencia.)
- **[BLOQUEANTE]** `SKILL.md:75` dice "armado por vos". El test `assert_no_voseo` no cubre el pronombre `vos`, y el commit `5addeab` afirma de más.
- **[BLOQUEANTE]** Se perdió sin puntero "Bash solo para git, gh, lectura de estado y orquestación; si te tienta escribir código porque es rápido, delega". → restaurarlo en el núcleo.
- **[sugerencia]** Se perdió "el paso 1 lo refuerza `pre-commit-guard.sh`; los demás son responsabilidad del dev". → restaurar.
- **[sugerencia]** La skill §1 repite la definición del rol que ya está en el núcleo; riesgo de divergencia. → reducir a un puntero.
- Suites: 54/54, 358/358, 95/95; `validate --strict` pasa.

Fixes en `85b5930`, `c5ec807`, `8cc659c`, `1b07627` y `483cba1`.

## Ronda 2: delta `68f0c39...483cba1`

**Veredicto consolidado:** CAMBIOS REQUERIDOS (1 bloqueante de QA; M2 de security sin resolver)

### qa-backend: CAMBIOS NECESARIOS
- Los 4 bloqueantes y las 2 sugerencias quedaron resueltos. Cada test se rompe al revertir su fix.
- **[BLOQUEANTE, nuevo]** `SKILL.md:5` no declara `Agent(methodology:build-resolver)`, aunque el runbook lo invoca en las Fases 2 y 2.8. → agregarlo. Lo quitará el PR 3, forzado por el lint histórico.

### security-reviewer (opus): APROBADO, con M2 abierto
- M1 resuelto (`global/CLAUDE.md:27`).
- **[MEDIUM] M2 sin resolver, verificado ejecutando** (`claude -p --permission-mode default`, fuera del repo): `allowed-tools` **suma pre-aprobaciones**, no restringe. Sin la skill, `git init` se deniega; con la skill, corre. Con `Bash(git *)`, `git -c alias.x='!uname > pwned.txt' x` ejecutó sin prompt, mientras el harness bloqueaba `touch`. Es decir, `Bash(git *)` ≈ cualquier comando. `Bash(gh *)` pre-aprueba, según la documentación, `gh alias set --shell`, `gh extension install`, `gh repo delete` y `gh secret`. → quitar `Bash` de `allowed-tools`, o dejar solo prefijos de lectura con subcomando fijo.
- **[LOW]** El commit `8cc659c` afirma que "acota/restringe". Es falso: pre-aprueba. → corregir el enunciado en el siguiente commit.
- **[LOW]** El test "allowed-tools acota Bash" fija como correcto un alcance que se puede evadir. → invertirlo.
- **[LOW, legacy]** `pr-workflow/SKILL.md:5` y `review-pr/SKILL.md:6` tienen `Bash` sin acotar; `pr-workflow` se carga en la Fase 2.6.
- Nota: `.claude/settings.local.json` de este repo pre-aprueba `Bash(bash:*)`, `Bash(gh api:*)`, `Bash(git push:*)`, etc., lo que contamina las pruebas de permisos hechas dentro del repo. Se reporta al usuario; no se toca.

**Decisión del orchestrator** (security gana en seguridad): quitar `Bash` de `allowed-tools` en `orchestrator`, `pr-workflow` y `review-pr`, porque la pre-aprobación que dan equivale a cualquier comando; los devs siguen usando Bash con el flujo normal de permisos. El lint lo prohíbe en adelante.
