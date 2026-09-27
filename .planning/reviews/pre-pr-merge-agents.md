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

Fixes en `8a4e2f0`, `51b6850`, `f03f3ad` y `5caedaf`.

## Ronda 2: delta `5f88e43...5caedaf`

### security-reviewer (opus): APROBADO
- Los 5 hallazgos de la ronda 1 están resueltos: guardas en `dev-common.md:61-63`, principios 9-10 de `db-migrations.md`, referencia corregida, excepción de hooks/permisos/auth en el salto de `docs` y voseo. No hay nada nuevo.

### qa-backend: CAMBIOS NECESARIOS
- Todos los fixes de la ronda 1 están resueltos. Rojo verificado en un worktree con la base: los 14 asserts nuevos fallan con el fix revertido.
- **[BLOQUEANTE]** `assert_no_voseo` forzaba `LC_ALL=en_US.UTF-8`. Sin ese locale generado (probado en Docker Debian), glibc cae en silencio a `C` y aparecen decenas de falsos positivos sobre español correcto. → fix `0922c37`: lista explícita de 32 formas voseantes con delimitadores literales, sin `\b`, sin whitelist y sin forzar locale. El orchestrator verificó 98/98 con `LC_ALL=C` y con `LC_ALL=en_US.UTF-8`. No se relanza: el cambio aplica la remediación propuesta y el resultado es idéntico en los dos locales.
- **[sugerencia]** Whitelist ad-hoc: la elimina el mismo fix.

## Cierre

**Veredicto final:** APROBADO. HEAD revisado `0922c37`. Suites: `test-hooks` 358/358, `test-plugin-manifest` 98/98 (con locale C y UTF-8), `test-frontmatter` 100/100; `validate --strict` pasa.
