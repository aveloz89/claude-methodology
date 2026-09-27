# Review dual pre-push: issue #73 (árbol objetivo del commit)

- **Branch:** `fix/pre-commit-target-tree` · **Base:** `dev` · **Fecha:** 2026-09-27

## Ronda 1: HEAD `6d0202b`

**Veredicto consolidado:** CAMBIOS REQUERIDOS (1 HIGH y 1 MEDIUM de security, las dos regresiones fail-open contra `dev`)

### security-reviewer (opus): CAMBIOS NECESARIOS
- **[HIGH]** `pre-commit-guard.sh:260-266`: el hook sube siempre al toplevel antes de buscar el runner. Si el runner está en un subdirectorio (`frontend/package.json` sin `package.json` en la raíz) y la sesión está en `frontend/`, HEAD no encuentra runner y hace `exit 0`: pasa sin tests. En `dev` sí corría y bloqueaba (rc=2). → buscar el runner desde el directorio resuelto hacia arriba hasta el toplevel, con test.
- **[MEDIUM]** `pre-commit-guard.sh:99`: `commit(\s|$)` ya no intercepta `git commit;`, `git commit&&…`, `git commit|…` ni `(git commit)`, que en `dev` sí se interceptaban. → terminadores de comando, con tests.
- **[informativo]** `git -C O -C /abs/R commit`: se toma solo el primer `-C`. → bloquear si hay más de un `-C` en la invocación (barato).
- Limpio, verificado ejecutando: cwd, `cd` abs/rel, `git -C`, worktree, symlink y `..` bloquean con suite en rojo; sin inyección por la ruta; fail-closed con `.cwd` raro y sin jq; `pre-merge-check` solo agrega bloqueos y la excepción de `--repo` es correcta.

### qa-backend: APROBADO
- Issue resuelto, verificado con repos y worktrees reales; el salto de `.planning/` se evalúa sobre el árbol resuelto; las menciones en el mensaje del commit no bloquean; el escape "cd en una llamada previa" funciona; la tabla del DESIGN está cubierta 1:1; rojo→verde con 3 reverts; bash 3.2 OK.
- No vio las dos regresiones de security (layout de runner en subdirectorio y operador pegado). Manda security.

Fixes en `8907589` (runner buscado desde el directorio de la sesión o el resuelto, hacia el toplevel), `28fa408` (más de un `-C` bloquea) y `b60309f` (terminadores de comando).

## Ronda 2 (solo security): delta `41033e1...8907589`

### security-reviewer (opus): APROBADO
- El HIGH quedó resuelto y verificado en 8 escenarios contra `dev` y `6d0202b`: `.cwd` en el subdirectorio, `cd frontend &&`, `git -C frontend`, rutas absolutas a otro repo, `src/` bajo el runner y rutas con `/` o `//`. Todos corren la suite en el directorio correcto y bloquean. Varios de esos casos, `dev` los dejaba pasar.
- El MEDIUM quedó resuelto: los terminadores `;`, `&&`, `)`, `|`, `&` y `>` bloquean; `commit-tree` ya no se intercepta, lo que corrige un falso positivo de `dev`.
- Más de un `-C`: fail-closed; dos invocaciones con la misma ruta siguen resolviendo.
- **[LOW, legacy]** Con la sesión en la raíz de un monorepo y runners solo en subdirectorios, no se encuentra runner y el commit pasa sin tests (igual que `dev`). → issue aparte.
- No se relanza QA: aprobó la ronda 1 y el delta aplica los fixes de security, cada uno con su test.

## Cierre

**Veredicto final:** APROBADO. HEAD `8907589`. Suites: `test-hooks` 415/415, `test-plugin-manifest` 163/163, `test-frontmatter` 107/107.
