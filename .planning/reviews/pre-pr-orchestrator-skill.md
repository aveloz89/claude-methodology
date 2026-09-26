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
