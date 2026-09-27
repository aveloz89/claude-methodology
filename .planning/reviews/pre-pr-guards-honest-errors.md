# Review dual pre-push: PR final de guards (#77 errores honestos + #86 + D-07)

- **Branch:** `fix/guards-honest-errors` · **Base:** `dev` · **Fecha:** 2026-09-27

## Ronda 1: HEAD `d5fdff6`

**Veredicto consolidado:** los dos APROBADO, sin bloqueantes. Los hallazgos de security entran en este PR por D-07 (lote 6 de reserva).

### security-reviewer (opus): APROBADO
- **Método:** los tests de `dev` corridos contra los hooks de HEAD dan 405/405, así que ningún veredicto de la suite de `dev` cambia. Además, un corpus de unos 120 comandos honestos contra `dev` y HEAD.
- **[MEDIUM, regresión fail-open]** `pre-release-sweep.sh:53`: el sufijo `(\s|$|[;&|])` no incluye `>`, `<`, `)` ni la comilla invertida. `--base main>/tmp/u` pasa de 2 a 0. `URL=$(gh pr create … --base main)` pasa en las dos versiones. → ampliar la clase y agregar tests.
- **[MEDIUM, superficie nueva]** `pre-commit-guard.sh:490-500` (#86): deriva los runners de `git status --untracked-files=all`, así que corre el `test` de un clone anidado sin trackear (`vendor/thirdparty/`, que ejecutó `touch PWNED`) y de fixtures trackeados con `package.json`. → descartar directorios sin trackear o repos anidados, y los directorios de fixtures/vendor.
- **[LOW, falso bloqueo]** `block-force-push.sh:54`: el cluster corto no tiene borde izquierdo, así que `git push -u origin fix/login-form`, `feature/add-feature-flags` y `--no-verify` bloquean (0 → 2). → exigir `(^|\s)` antes del cluster.
- **[informativo]** `git -c k=v push`, `git --no-pager push` y `gh -R o/r pr create --base main` pasan, igual que en `dev`. Son formas honestas → entran por D-07.
- Limpio: los layouts de #86 no pierden corridas de tests, el watchdog compartido falla cerrado, hay fail-closed sin jq/gh, NUL en 5 hooks y no hay inyección por paths.

### qa-backend: APROBADO
- El alcance de #77 y #86 está cubierto y testeado. Negativos verificados ejecutando: heredocs, menciones en commit y `--body`, `--force-with-lease`. #86 funciona en los layouts monorepo y worktree, y `pre-push-guard` toma el branch del `.cwd`. Rojo→verde en 3 muestras de revert. Las docs son coherentes.
- **[sugerencia]** `pre-release-sweep` no resuelve `cd <ruta> && gh pr create` para el diff; está documentado. → sin cambio.
- QA no vio las regresiones de security (en layout y regex, igual que en #73).

Fixes en `18db356`, `2650c29`, `f1fdb96` y `74acb99` (lote 6).

## Ronda 2 (solo security): delta `938d19f...74acb99`

### security-reviewer (opus): APROBADO
- Los 4 hallazgos de la ronda 1 quedaron resueltos y verificados con un corpus de 180+41 casos contra `origin/dev`, `938d19f` y HEAD.
- Casos dev=2/head=0: `git pushx` (no es un subcomando) y `--base main,` (es otra rama). Los dos están bien. No hay falsos bloqueos nuevos.
- **[LOW, fail-open frente a `938d19f`]** `pre-commit-guard.sh:546`: el segmento excluido se evalúa sobre el path del archivo y no sobre el directorio del runner, así que `apps/web/src/__fixtures__/x.json` deja de correr `npm test` en `apps/web`. → evaluarlo sobre el candidato.
- **[LOW]** El orden `-C` antes de `-c` no matchea (`git -C /x -c a=b push --force` pasa), y tampoco `-P`. → una sola alternancia repetida.
- **[LOW, preexistentes]** `--base "main"`/`'main'`, `gh --repo=o/r`, `gh -Ro/r` y `gh pr -R o/r create` no bloquean. `git push origin x && echo -f` se bloquea de forma falsa, porque el `.*` cruza el `&&`.
- **Decisión del orchestrator:** entran todos por D-07 en un lote 7. Es la última ronda de alcance: la ronda 3 solo verifica.
