# STATE

El estado mutable (fase, lotes, progreso) vive en `state.json`.

## Estado actual

- **Feature:** regla-verificacion-visual — PR #75: lo visual se verifica con el valor computado en un navegador, no leyendo el archivo. Review dual APROBADO en 3 rondas; pendiente de aprobación de merge del usuario. Retro en `learnings/PR-75.md`
- **Última actualización:** 2026-09-16

## Decisiones

- [D-01] Enunciar una vez en `rules/implementation-principles.md` §5 y remitir desde los agentes y las reglas de lenguaje. Los puntos que remiten conservan su enunciado accionable —qué medir y con qué—, nunca quedan como puntero pelado.
- [D-02] El criterio se redacta como verificable: qué cuenta de evidencia (valor computado en el navegador, en el ancho donde se afirma) y qué no (leer el CSS, un check que puede devolver `true` sin ejercer el camino).
- [D-03] (bloqueante de security, ronda 1) **Quien exige la evidencia no es quien la produce.** `qa-frontend` es read-only y nunca recibe un stack, así que exige el valor computado al `frontend-dev`; contraste entra a los mínimos del dev y a su lista de evidencia de cierre de lote. Una regla que sube el estándar sin nombrar al productor deja el gate incumplible.
- [D-04] (usuario) El criterio también va donde se escribe el CSS: `rules/css.md` y `rules/html.md`, que es donde nació el incidente de easy-quotes.
- [D-05] (ronda 3) El checklist usa la etiqueta propia `SIN EVIDENCIA`, con equivalencia explícita a `ISSUE`, y no `NO VERIFICABLE`: §5 reserva ese término a dos causas donde la evidencia ausente **no** bloquea, y reusarlo habría reproducido el hallazgo de `PR-61.md:35`.
- [D-06] El orchestrator afirmó en un handoff que `rules/implementation-principles.md` no tiene frontmatter `paths:` y que por eso se carga en toda sesión. Es falso; lo encontró `qa-backend`. Queda registrado porque es exactamente el defecto que este PR ataca.

**Pendiente propuesto (no decidido):** agregar la fila de este PR a la tabla del paso 4 del DoD anti-drift (`rulebooks/orchestrator-runbook.md`) — es el quinto caso de un PR que viola la regla que escribe, y esta vez dos veces en el mismo cambio.

## Feature anterior

`followups-sweep` (PR #74 y anteriores): sus decisiones y aprendizajes viven en `learnings/PR-74.md` y en los briefs archivados.

## Blockers

- ninguno
