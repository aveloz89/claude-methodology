# Review dual pre-push — feature/pre-pr-reviews (Fase 2.6)

**Branch:** feature/pre-pr-reviews · **Base:** dev (`2f7d6f9`) · **SHA revisado:** `b22c664` (veredictos sobre `0d8a9cc` + ronda de fixes validada por tests, regla de cambio menor) · **Fecha:** 2026-08-14

> Primer review dual ejecutado bajo el flujo nuevo: sobre el diff local, ANTES del push/PR. Este registro se reconcilia a `PR-<N>.md` en Fase 2.7.

## security-reviewer (remoto, rol inyectado) — APROBADO

0 CRITICAL/HIGH. 2 MEDIUM "urgentes por baratas": (1) CASO A sin anclaje al SHA revisado — evidencia stale si se agregan commits post-review (el caso operativamente probable) y spoofing barato de 2 campos; (2) `feature` de state.json interpolado sin sanitizar en el output del hook (canal de alta confianza). 2 LOW (`2>/dev/null`, cobertura de caminos de creación de PR fuera del harness) + 1 sugerencia legacy adoptada por política del usuario: 4º check pre-merge verificando la evidencia machine-readable del review. Verificado sólido: fail-toward-review en TODOS los caminos enumerados del hook, gates de merge intactos en global/governance/pr-workflow, tests aislados en sandbox.

## qa-backend (remoto, rol inyectado) — APROBADO

0 bloqueantes. Contrato #2 del hook implementado exacto (incluida la señal extra de detached HEAD → CASO B); suite 119/119 corrida en su entorno con los 9 tests del hook verificados como reales (asserts positivos Y negativos); coherencia narrativa confirmada en los 9+ documentos ("misma historia"); convención del registro idéntica en runbook, global y output del hook; condición verificable del caso remoto bien escrita. 3 sugerencias menores (calificador post-PR en global L101, `head -1` en PR_URL, lista histórica del DESIGN) + gap declarado: detached HEAD sin test.

## Ronda de fixes local (6 commits, SIN push — estreno de la regla)

`9bc7cfd` anclaje por SHA (review_sha hex-validado + ancestro + delta solo-.planning) · `b2d51c7` sanitización slug/branch/URL con allowlists `case` · `0b4b14e` tests detached HEAD + fuera de repo · `e7b6eb3` 4º check pre-merge en runbook (+refs "las 4") · `198bd51` precisiones QA · `b22c664` README adversarial.

## Verificación de cierre

`test-hooks.sh` **128/128** · `test-plugin-manifest.sh` **19/19** · shellcheck limpio · re-review no requerido (sugerencias aplicadas = cambio menor validado por tests, per skill pr-workflow). Los fixes viajan en el push inicial: **cero runs de CI consumidos por este review**.
