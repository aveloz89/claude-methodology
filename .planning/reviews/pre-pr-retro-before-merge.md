# Review dual pre-push — feature/retro-before-merge (Fase 2.6)

**Branch:** feature/retro-before-merge · **Base:** dev · **SHA revisado:** `e981e0b` · **Fecha:** 2026-08-24 · Presupuesto: ~5 min/reviewer (diff +70/−40, 100% documentación de proceso)

## security-reviewer — APROBADO

0 CRITICAL/HIGH · 1 MEDIUM · 3 LOW. Gates verificados uno por uno: review dual bloqueante intacto, la verificación pre-merge de 4 checks migra íntegra a la Fase 5 sin recortes, y el gate de CI se **refuerza** (el paso 5 de la Fase 4 obliga a CI verde sobre el HEAD nuevo, y `pre-merge-check.sh` ya bloquea con checks `pending`).

**MEDIUM — la Fase 4 institucionaliza un push post-review sin guard automático sobre su contenido.** Antes del cambio, la última escritura obligatoria al branch caía en o antes de `gh pr create`, donde `post-pr-create.sh` sí valida que el delta post-`review_sha` sea solo `.planning/` y degrada a CASO B si no. El commit de retro ocurre después de ese checkpoint: el hook ya corrió y el check 4 solo verifica ancestría, así que cualquier commit que descienda de `review_sha` pasa. Ventana: código no revisado entrando bajo la etiqueta de "es la retro" (un `git commit -a` distraído alcanza).

**LOW** — la nota del runbook citaba `post-pr-create.sh` como tolerancia que "ya cubre" el commit de retro: error de secuencia temporal, el hook no se ejecuta en ese punto del flujo.

**LOW** — ruta de hotfix: la entrada de LEARNINGS viaja en un push directo a `dev` sin PR ni review; pedir que sea commit propio, nunca amendeado al merge de integración.

**LOW (legacy)** — la Fase 5 nueva es ahora el lugar al que llega el lector para mergear y no reafirmaba el invariante de aprobación explícita del usuario.

Checklist adaptado: sin secrets, sin dependencias, sin código ejecutable, sin hooks tocados (paridad `hooks.json` no afectada).

## qa-backend — BLOQUEADO (ronda 1)

DoD anti-drift ejecutado (grep de "Fase 3/4/5", "post-merge", "retro", "LEARNINGS", "merge" sobre `global/CLAUDE.md`, `README.md`, `rulebooks/`, `agents/`, `skills/`): sin residuos del comportamiento viejo. Las "Fase 3/4" de `agents/build-resolver.md` son su numeración interna, no el pipeline. `agent-budget.md:81,103` ("la retro de Fase 4") sigue siendo cierto — es exactamente lo que D-02 buscaba al abrir una Fase 5 en vez de renumerar.

**BLOQUEANTE — contradicción de cardinalidad en `LEARNINGS.md`.** La redacción nueva decía "una entrada por feature", pero el modo multi-PR describe la Fase 4 dentro del loop "para cada grupo" (cada grupo = branch + PR propio), y el template de la entrada indexa por `PR #N`. Con la redacción vieja ("por cada merge exitoso") no había ambigüedad; con la nueva, un orchestrator en multi-PR no sabía si escribir una retro por grupo o consolidar una sola. El DoD anti-drift no se había cumplido sobre ese hecho específico.

**Sugerencia** — el mecanismo de la retro en hotfix no estaba mostrado: el procedimiento de integración a `dev` no tenía paso de edición de LEARNINGS, y un `git merge --no-ff` sin `--no-commit` no deja lugar natural para inyectarla.

**Sugerencia NO aplicada (diferida con razón)** — agregar una clave `retro` al enum `phases` de `state.json`: si una sesión se pausa entre "retro pusheada" y "merge hecho", ambos estados colapsan en `merge: pending`. Es un cambio de schema (bump a v2) con radio de impacto en los hooks que leen `state.json` — objetivo distinto de este PR.

## Ronda de fixes (`6479420`)

- **Cardinalidad** → una entrada por PR mergeado, con la aclaración de multi-PR en los cuatro puntos (runbook Fase 4, formato de LEARNINGS, `global/CLAUDE.md`, regla 5.7).
- **MEDIUM de security** → el delta solo-`.planning/` es norma explícita en la Fase 4, y el check 4 de la verificación pre-merge gana el test de contenido que faltaba (`git diff --name-only "$review_sha"..HEAD | grep -v '^\.planning/'` sin salida).
- **LOW cita** → la nota ya no dice que `post-pr-create.sh` cubre el commit de retro: dice que valida al crearse el PR y no vuelve a mirar el branch, y que por eso el check lleva el test.
- **LOW hotfix** → commit propio posterior a la integración, nunca amendeado al merge commit; el procedimiento lo muestra.
- **LOW invariante** → la Fase 5 reafirma que el merge necesita aprobación explícita del usuario.

## Ronda 2 (re-reviews acotados al delta de fixes)

**security-reviewer — APROBADO.** Los cuatro hallazgos de la ronda 1 verificados como resueltos contra el código real de los hooks: confirmó que `post-pr-create.sh` está registrado solo sobre la creación del PR y que `pre-merge-check.sh` no mira el delta, así que la frase "es el único punto donde el contenido de un push post-review no lo mira ningún hook" es fiel. 3 LOW nuevos sobre el comando del check 4, todos en dirección falso-rojo, **aplicados en `e981e0b`**: `review_sha` a variable con guarda de vacío (la línea del delta ya no dependía de que muriera su vecina), `<branch>` consistente en las dos verificaciones, e idioma `grep -cv` + conteo del hook en vez de `grep -v` con el exit code invertido. Además cazó un bug real fuera de seguridad: el snippet de retro del hotfix hacía `git commit` sin `git add`, no stageaba nada.

**qa-backend — APROBADO (N/A).** Se declaró fuera de scope: revisó coherencia normativa en la ronda 1 y en la re-review contestó que un delta de markdown no cae en su capa. Su bloqueante quedó sin re-verificar por el agente; lo verificó el orchestrator con el grep del DoD anti-drift: cero residuos de "por feature" y cardinalidad idéntica en los cuatro puntos normativos. El salto de criterio entre rondas del mismo agente va a la retro.

**Verificación empírica del check 4 nuevo** (no delegada): delta solo-`.planning/` imprime `0`, delta con archivos fuera imprime el conteo real, y la guarda de `review_sha` vacío corta antes de las dos verificaciones.

## Cierre

Veredictos limpios en ronda 2. `review_sha` = `e981e0b`. Registro reconciliable a `PR-<N>.md` en Fase 2.7.
