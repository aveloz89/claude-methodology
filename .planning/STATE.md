# STATE

El estado mutable (fase, lotes, progreso) vive en `state.json`.

## Estado actual

- **Feature:** followups-sweep — cerrar los ocho follow-ups accionables en un solo PR, por pedido del usuario
- **Última actualización:** 2026-08-25

## Decisiones

- [D-01] Barrido de ocho ítems en un PR, con precedente en el PR #55. La heurística de corte no cuenta commits sino diffs irrevisables: un commit atómico por ítem y el PR body agrupado por naturaleza mantienen la navegabilidad.
- [D-02] Dos lotes en paralelo sobre el mismo branch con archivos disjuntos: el dev en `hooks/` y `tests/`, el orchestrator en `rules/`, `rulebooks/`, `agents/` y `skills/`. El dev evitó tocar `.planning/` por eso mismo, sin que se lo pidieran.
- [D-03] El fix del `--repo` osciló cinco rondas entre cortar de más y cortar de menos. La regla final no elige mejor dónde cortar: **una ventana indeterminada no es una ventana y bloquea**. Decisión del usuario entre tres opciones, con el falso positivo aceptado (un backslash legítimo sin comillas bloquea igual).
- [D-04] El parser de la ventana se hizo en perl y no en un loop de bash porque el dev midió que el loop es cuadrático en este intérprete: 100 KB no terminaba en 2 minutos. Perl mide lineal, con `alarm(5)` como red.
- [D-05] `README.md` y el `CLAUDE.md` raíz quedan fuera del ruteo por capa salvo en este repo: son meta-documentación, no reglas que los agentes consuman. El grep del DoD sí los cubre — son mecanismos distintos, uno busca drift y el otro decide a quién invocar.
- [D-06] El conteo mal reportado del dev (1 test en rojo cuando eran 3) se corrige en el registro y no reescribiendo la historia: el branch ya había avanzado y `git reset --hard` está bloqueado por hooks.
- [D-07] Docs (Fase 2.5) saltada: cuatro de los ocho ítems SON documentación normativa, y los otros cuatro no tienen superficie documentada fuera de sus comentarios.

## Blockers

- ninguno
