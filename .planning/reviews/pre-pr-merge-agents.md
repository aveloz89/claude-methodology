# Review dual pre-push: audit-best-practices, PR 3/3 (merge-agents)

- **Branch:** `feature/merge-agents` · **Base:** `dev`
- **Fecha:** 2026-09-26

## Ronda 1: HEAD `369af83`

**Veredicto consolidado:** CAMBIOS REQUERIDOS (1 bloqueante de QA)

### security-reviewer (opus): APROBADO
- Las guardas de los agentes borrados siguen en los rulebooks: dependencias (escalar si es nueva, major o downgrade), no silenciar checks, 3 intentos, expand-contract, backup, transacciones, DB real en tests.
- **[MEDIUM]** Las guardas "dependencia nueva/major/downgrade → escalar" y "nunca silenciar checks" viven solo en `build-errors.md`, y la l.23 excluye los errores que no son de build. Un dev en un lote normal no las ve. → llevar una línea a `dev-common.md`, que siempre se lee.
- **[LOW]** El salto de `docs` puede omitir cambios en hooks, permisos o auth clasificados como "código interno". → esos siempre invocan `docs`.
- **[LOW]** `db-migrations.md:7` apunta a la sección renombrada de `backend-dev.md`, que a su vez apunta de vuelta: referencia circular. → apuntar al runbook, "Cuándo un lote es DB complejo".
- **[LOW]** `build-errors.md:23` ("sos") y `:59` ("Hacé"): el diff viola su propia regla de tuteo y `assert_no_voseo` no las detecta. → corregir y ampliar el patrón.
- **[LOW, legacy]** `db-specialist` tampoco tenía guardas contra correr migraciones en producción ni contra secrets en migraciones o seeds. → dos líneas en `db-migrations.md` (baratas, en alcance).

### qa-backend: CAMBIOS NECESARIOS
- **[BLOQUEANTE]** Se perdió la "normalización pragmática: 3NF por defecto, desnormalizar solo con justificación de performance en `ARCHITECTURE.md`" (principio #5 de `db-specialist`). → agregarla a `db-migrations.md`, "Principios de migración".
- **[sugerencia]** Falta la desviación específica de DB: ajustar un índice simple a compuesto o parcial cuando la query real lo exige, documentándolo en `ARCHITECTURE.md`. → agregar.
- **[sugerencia]** Falta el template de reporte de fix de build. Bajo impacto: lo cubre el reporte de cierre de lote. → no se aplica.
- **[sugerencia]** "El frontend-dev aplica su checklist": `frontend-dev.md` no usa esa palabra. → alinear el término con "lee `MASTER.md` y aplica sus constraints".
- Verificado: flujo `db-complejo` coherente (architect lo marca, backend-dev + rulebook, orden garantizado por el plan); cero menciones colgando; el lint (g) falla si queda alguna; desviación de `qa-backend.md` §5 correcta. Suites 100/85/358.
