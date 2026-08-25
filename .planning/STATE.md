# STATE

El estado mutable (fase, lotes, progreso) vive en `state.json`.

## Estado actual

- **Feature:** pre-commit-workspace-scope (PR #58) — acotar `pre-commit-guard.sh` a las suites de los workspaces tocados en monorepos npm/pnpm
- **Última actualización:** 2026-08-25

## Decisiones

- [D-01] PR creado **fuera del flujo**, sin review dual pre-push. Las tres rondas se hicieron sobre el PR ya abierto; el registro `PR-58.md` las cubre.
- [D-02] Los dos HIGH de la ronda 1 se cierran con `--untracked-files=all`: expande los directorios colapsados a archivos individuales **y** sobrescribe `status.showUntrackedFiles=no` del usuario, porque un flag de línea de comandos gana sobre la config.
- [D-03] El MEDIUM del submódulo se cierra con igualdad exacta en el `case` del match (`"$dir" | "$dir"/*`), no acotando el texto del header. Preferimos volver cierta la garantía antes que documentar la excepción.
- [D-04] La garantía del header ya no afirma unicidad: dice "verificado hasta ahora, no exhaustivo" y consolida los cuatro modos de falla conocidos en un solo lugar. Se falseó dos veces afirmando de más.
- [D-05] Los guards muertos de `_workspace_scope_pnpm_dirs` NO se limpian acá (cambios quirúrgicos): issue #62 con label `legacy-violation` para el agente `refactor`. La etiqueta no existía en el repo y hubo que crearla.
- [D-06] El branch se actualizó con `dev` antes de trabajarlo, para traer el fix del ReDoS: sin eso, el `guard-matching.sh` vulnerable volvía al árbol y el bug renacía para quien trabajara ahí.
- [D-07] Docs (Fase 2.5) saltada: cambio interno de un hook, sin superficie documentada que describa el scoping más allá de la línea del README que el PR ya actualizó.

## Blockers

- ninguno
