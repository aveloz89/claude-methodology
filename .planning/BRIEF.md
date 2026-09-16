# Brief: lo visual se verifica en un navegador, no leyendo el archivo (2026-09-16)

> Branch `docs/regla-verificacion-visual` sobre `dev`. Origen: **regla de 3** en easy-quotes — el mismo patrón apareció en tres retros seguidas, y el usuario aprobó el cambio (AskUserQuestion, 2026-09-15). Fase anterior archivada en `BRIEF-hook-skip-planning-only.md`.

## Objetivo

Que una afirmación sobre lo que se **ve** (color, fuente, recorte de texto, desborde) no se dé por verificada sin ejecutar el camino real: valores computados en un navegador.

## Evidencia (tres retros de easy-quotes)

| Retro | Verificación por proxy | Qué pasó |
|---|---|---|
| `PR-263.md` | Una altura calculada restando posiciones de una medición previa | El elemento se apilaba distinto a 390 px: el Total quedaba fuera del recorte |
| `PR-269.md` | `document.fonts.check()` como prueba de render; la herencia del `allowList` deducida del síntoma; el fix de un issue basado en la API aparente de una promesa | Los subsets de fuentes duplicaban las descargas por página; un comentario afirmaba lo contrario de lo que hace la librería |
| `PR-270.md` | Tests de CSS que leen el archivo; contraste "medido" leyendo tokens; un recorte a 2 líneas supuesto sin pintarlo | Una regla `<tabla> td { color }` anulaba los modificadores y el gris de la spec nunca se pintó, probablemente desde antes; a 320 px el recorte cortaba el folio en 5 de 6 filas |

En los tres casos hubo tests en verde y review dual aprobado. Lo que faltó fue ejecutar el camino real.

## Alcance

- **Incluye:**
  1. `rules/implementation-principles.md` §5: una viñeta nueva con el criterio, en la lista de "Qué exige, en concreto".
  2. `agents/ui-ux.md`: el mismo criterio donde ya habla de contraste y del recorrido visual.
  3. `agents/qa-frontend.md`: idem, donde valida accesibilidad y design system.
  4. `agents/frontend-dev.md` (agregado en la ronda de review, D-03): contraste entra a su lista de mínimos de accesibilidad, con su evidencia. Sin esto, el reviewer exige algo que al productor nunca se le pidió.
  5. `rules/css.md` y `rules/html.md` (agregado por decisión del usuario, D-04): donde ya piden probar contraste, qué cuenta como evidencia, remitiendo a §5.
- **NO incluye:**
  - Un archivo nuevo en `rules/` (sin `paths:` se volvería contexto permanente de toda sesión de todo proyecto; con `paths:` duplicaría §5).
  - Cambiar el proceso de review ni agregar un gate nuevo.
  - Tocar `global/CLAUDE.md`: el detalle vive en `rules/` y en los agentes, no en el núcleo que se carga siempre.

## Decisiones

- [D-01] **Enunciar una vez en §5 y remitir desde los dos agentes.** Es la regla de anti-drift del propio repo ("enunciar una vez, remitir el resto"), y §5 ya es el lugar de "verificar antes de afirmar". Los agentes conservan su enunciado accionable —qué medir y con qué— y remiten al principio.
- [D-02] **El criterio se redacta como verificable**, no como consejo: qué vale de evidencia (valor computado en el navegador, en el ancho donde se afirma) y qué no (leer el archivo de CSS, un check que puede dar `true` sin ejercer el camino).
- [D-03] (ronda de review, bloqueante de security) **Quien exige la evidencia no es quien la produce.** `qa-frontend` nunca recibe un stack corriendo y es read-only, así que su línea pide el valor computado **al `frontend-dev`**, con el patrón que el propio diff ya usaba dos secciones más abajo; el checklist admite «no verificable» como tercer estado (`implementation-principles.md:185`) para que «no llegó evidencia» no se resuelva como `OK` silencioso. Y contraste entra a los mínimos de `agents/frontend-dev.md`: la obligación se cambia en todas sus capas.
- [D-04] (usuario, AskUserQuestion 2026-09-16) **El criterio también va donde se escribe el CSS:** `rules/css.md` y `rules/html.md`, donde ya piden probar contraste, dicen ahora qué cuenta como evidencia y remiten a §5. Es el hueco exacto que originó el incidente del PR #270. Descartadas: dejarlo solo en §5 y los dos prompts, o registrarlo como issue aparte.

**Corrección factual del orchestrator (la encontró qa-backend):** en el encargo al reviewer afirmé que `rules/implementation-principles.md` no tiene frontmatter `paths:` y que por eso se carga en toda sesión de todo proyecto. Es falso: sí lo tiene, con una lista amplia de extensiones, así que entra solo cuando el diff las toca. No cambia el alcance ni la decisión D-01, pero queda registrado porque es justo el tipo de afirmación sin verificar que este PR persigue.

## Definition of Done (anti-drift del repo, `rulebooks/orchestrator-runbook.md`)

1. Grep de los términos afectados en `CLAUDE.md`, `README.md`, `rulebooks/`, `agents/`, `skills/` y `.planning/`.
2. Reconciliar todo documento que describa el comportamiento cambiado.
3. Enunciar una vez, remitir el resto.
4. Releer el diff completo aplicando la regla nueva: si el propio cambio afirma algo visual, debe traer su evidencia.

## Verificación

- El repo no tiene CI: el gate es el review dual (`qa-backend`, por ser documentos normativos) más los tests locales del repo (`tests/adversarial/`, `tests/validation/`) si el cambio los toca — no es el caso, pero `claude plugin validate --strict .` sí aplica porque se tocan prompts de agentes.
