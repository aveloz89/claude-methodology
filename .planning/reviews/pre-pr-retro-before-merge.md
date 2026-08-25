# Review dual pre-push — feature/retro-before-merge (Fase 2.6)

**Branch:** feature/retro-before-merge · **Base:** dev · **SHA revisado:** `912a022` · **Fecha:** 2026-08-24 · Presupuesto: ~5 min/reviewer (diff +70/−40, 100% documentación de proceso)

## security-reviewer — APROBADO

0 CRITICAL/HIGH · 1 MEDIUM · 3 LOW. Gates verificados uno por uno: review dual bloqueante intacto, la verificación pre-merge de 4 checks migra íntegra a la Fase 5 sin recortes, y el gate de CI se **refuerza** (el paso 5 de la Fase 4 obliga a CI verde sobre el HEAD nuevo, y `pre-merge-check.sh` ya bloquea con checks `pending`).

**MEDIUM — la Fase 4 institucionaliza un push post-review sin guard automático sobre su contenido.** Antes del cambio, la última escritura obligatoria al branch caía en o antes de `gh pr create`, donde `post-pr-create.sh` sí valida que el delta post-`review_sha` sea solo `.planning/` y degrada a CASO B si no. El commit de retro ocurre después de ese checkpoint: el hook ya corrió y el check 4 solo verifica ancestría, así que cualquier commit que descienda de `review_sha` pasa. Ventana: código no revisado entrando bajo la etiqueta de "es la retro" (un `git commit -a` distraído alcanza).

**LOW** — la nota del runbook citaba `post-pr-create.sh` como tolerancia que "ya cubre" el commit de retro: error de secuencia temporal, el hook no se ejecuta en ese punto del flujo.

**LOW** — ruta de hotfix: la entrada de LEARNINGS viaja en un push directo a `dev` sin PR ni review; pedir que sea commit propio, nunca amendeado al merge de integración.

**LOW (legacy)** — la Fase 5 nueva es ahora el lugar al que llega el lector para mergear y no reafirmaba el invariante de aprobación explícita del usuario.

Checklist adaptado: sin secrets, sin dependencias, sin código ejecutable, sin hooks tocados (paridad `hooks.json` no afectada).
