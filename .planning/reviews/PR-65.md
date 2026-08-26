# Review dual pre-push — feature/seal-state-before-merge (Fase 2.6)

**Branch:** feature/seal-state-before-merge · **Base:** dev · **Fecha:** 2026-08-26 · Presupuesto: ~5 min/reviewer, tres rondas

## Origen: el flujo mandaba bypassear una branch protection

El paso 4 de la Fase 5 mandaba actualizar `.planning/state.json` **después** del merge. Eso obliga a commitear sobre `dev`. Al cerrar el estado del PR #180 en easy-quotes, donde `dev` está protegido con el check `ci` obligatorio, el push devolvió:

```
remote: Bypassed rule violations for refs/heads/dev:
remote: - Required status check "ci" is expected.
```

O sea: el flujo escrito, seguido al pie, produce el mismo bypass que la metodología prohíbe en todos los demás lugares — hay un hook que bloquea `gh pr merge --admin` exactamente por esto.

## La decisión se tomó dos veces, y la segunda con datos reales

**Primera vez**, sobre tres opciones: sellar antes del merge, PR chico post-merge, o aceptar la excepción. El usuario eligió sellar antes, y yo presenté como mitigación que "el hook de STATE desactualizado detecta el estado adelantado al arrancar la próxima sesión".

**Los dos reviewers verificaron esa afirmación ejecutando, y era falsa.** `session-end-check.sh` corre en SessionEnd, compara mtimes y **nunca mira `phases`**; además dispara con el propio commit de retro exista o no el merge, así que es ruido genérico y no una señal del caso. Peor: qa-backend reprodujo con `jq` el `phases` exacto que queda tras sellar y comprobó que `session-start-context.sh` imprime `Fase activa: ninguna` — **enmascaraba** el desfase en vez de señalarlo.

**Segunda vez**: le devolví la decisión al usuario con la mitigación real (ninguna) y tres caminos. Eligió construirla. Este PR la construye.

## Veredictos

**security-reviewer** — ronda 1 APROBADO (3 LOW) · ronda 2 BLOQUEADO (1 HIGH) · **ronda 3 APROBADO**.

Su HIGH fue el hallazgo más instructivo del PR: **arreglé la contradicción del hotfix en un lugar y la dejé viva en el otro.** El procedimiento de integración (línea 673) ya no commiteaba sobre `dev`, pero el bullet "Cuándo saltar Learn" (línea 241) —que es **el punto de decisión**, 400 líneas más arriba— seguía instruyendo el commit posterior a la integración. El orchestrator que salta Learn por urgencia lee ese bullet, no el procedimiento. El camino más probable seguía mandando el push directo.

También verificó que el argumento del dev para no sanitizar `pr` era falso: no hay validador en ninguna parte de la cadena, y reprodujo un payload que falsifica un header de sección dentro del contexto del modelo. El riesgo marginal era nulo —`STATE.md` ya se imprime crudo— pero el argumento no se sostenía.

**qa-backend** — ronda 1 BLOQUEADO (2 bloqueantes) · **ronda 2 APROBADO**.

Sus dos bloqueantes fueron el desmontaje de la mitigación inventada y la ruta de hotfix. Verificó el aviso nuevo ejecutando el hook en sandboxes, no leyéndolo, y probó los estados intermedios: fase a medias no avisa, `pr: null` y `pr` ausente caen a `PR: ninguno`, `dev`/`main` con estado sellado callan. Encontró que un `state.json` malformado da salida confusa y comprobó contra el hook viejo que **eso es preexistente**, no de este PR.

## Un error de orquestación, reportado por el reviewer

qa-backend detectó que había un dev escribiendo sobre el mismo working tree mientras él revisaba: encontró `tests/adversarial/test-hooks.sh` modificado sin commitear, con tests que anticipaban uno de sus propios hallazgos, y el hook sin el código correspondiente — 216/217 en ese estado. No tocó nada, separó ese ruido de su veredicto y pidió confirmación.

Es culpa mía: lancé la ronda de review y después mandé al dev fixes sobre el mismo archivo que el reviewer estaba leyendo. La regla de lotes paralelos exige archivos disjuntos y acá se solaparon.

## Verificación del orchestrator (no delegada)

- Suite: 213 → **217 pasando**, `test-plugin-manifest.sh` 19/19.
- El dev aisló la evidencia rojo→verde **por fix**, revirtiendo cada hunk por separado (216/217 en cada caso), lo que además demuestra que los dos fixes no están acoplados.

## Cierre

Veredictos limpios en la última ronda de cada reviewer. Este PR estrena su propia regla: el commit de retro sella el estado, y después del merge no se escribe nada en `.planning/`.
