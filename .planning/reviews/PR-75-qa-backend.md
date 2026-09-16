# Review pre-push — qa-backend

- **Branch:** `docs/regla-verificacion-visual`
- **Base:** `dev`
- **HEAD:** `d1671c7ab1a0d4005104dbb8672ccb6ce2f618be`
- **Fecha:** 2026-09-15
- **Veredicto:** **APROBADO**

## Scope

Diff normativo puro (`git diff dev...HEAD`), sin capa de aplicación: `rules/implementation-principles.md` (§5), `agents/ui-ux.md`, `agents/qa-frontend.md`. Revisado con criterio de coherencia normativa y anti-drift (`rulebooks/orchestrator-runbook.md`, "Anti-drift: DoD de cambios de proceso"), no de capas backend/frontend. `.planning/BRIEF.md` y `.planning/state.json` se leyeron solo como contexto, no como objeto de review (no son documentos normativos consumidos por agentes).

### QA Backend

**1. Enunciar una vez, remitir el resto (D-01) — CUMPLE.**
El argumento completo (qué cuenta como evidencia, qué no, y el ejemplo real) vive únicamente en `rules/implementation-principles.md` §5, línea 147. Los dos agentes remiten con `(...)§5` y **conservan enunciado accionable propio**, no un puntero pelado:
- `agents/qa-frontend.md:80` — "se verifica con el valor computado en el navegador, no leyendo el token ni el CSS" (contraste) + `:89` — "una regla más específica puede anularlo; ante duda, exige el valor computado" (colores del design system). Dos instanciaciones distintas del mismo principio, cada una con su propio caso de falla.
- `agents/ui-ux.md:281` — "se cierra con el valor computado en el navegador en ese mismo ancho, no con la lectura del screenshot a simple vista ni del CSS fuente" — añade un modo de falla que §5 no cubre (lectura de screenshot a ojo), propio del paso 3 de ui-ux (recorrido visual con Playwright). No es duplicación: es la elaboración específica del workflow, que el DoD del propio repo permite y pide (`orchestrator-runbook.md` línea 788: "la remisión conserva siempre el enunciado accionable; lo que se mueve es la elaboración").
- Checklist de reporte `agents/qa-frontend.md:288` retiene el resumen ("computado en navegador, no leído del token/CSS") aun siendo una línea de template terso — correcto para ese formato.

**2. Contradicciones vivas — NO ENCONTRADAS, con una precisión sobre la distinción especificación/verificación.**
Grep propio de `contraste|visual|computed|playwright|render|css` sobre `CLAUDE.md`, `README.md`, `rulebooks/`, `agents/`, `skills/`, `.planning/` (raíz del repo): sin resultados nuevos fuera de los tres archivos tocados y las dos menciones de `agents/ui-ux.md` que el dev declaró dejar intactas.

Confirmo la distinción que reporta el dev sobre las líneas ~229 y ~258 de `agents/ui-ux.md`:
- Línea 229, `[ ] Contraste WCAG AA verificado en texto`, vive dentro de la "Checklist de validación pre-PR" que `ui-ux` **genera como artefacto** (`MASTER.md` del proyecto destino) para que `frontend-dev` la cumpla y `qa-frontend` la valide — es una casilla sin marcar, no una afirmación del propio `ui-ux` de que algo ya fue verificado.
- Línea 258, `Contraste WCAG AA mínimo en todo texto`, es un umbral de especificación ("mínimo"), no una afirmación sobre un render ya observado.
Ninguna de las dos es una claim retrospectiva de la forma que §5 regula ("afirmo que X se ve así"); son contenido prescriptivo hacia otro artefacto/agente. La distinción se sostiene.

Matiz no bloqueante (ver Sugerencias): ninguna de las dos líneas remite a §5 pese a que la 229 es, en efecto, el punto exacto donde `frontend-dev`/`qa-frontend` deberían aplicar el criterio de evidencia al marcar esa casilla.

**3. El diff aplica su propia regla (paso 4 del DoD) — VERIFICADO CONTRA LA FUENTE.**
Las dos citas se contrastaron letra por letra contra `/Users/alas/Proyectos/easy-quotes/.planning/learnings/PR-270.md` y `PR-269.md`:
- `.clients-page__table td { color }` y "el gris nunca llegó a pintarse" (§5) reproducen con fidelidad "`.clients-page__table td { color }` (0,1,1) anulaba los modificadores (0,1,0) en tres tablas [...] el gris de la spec nunca se pintó" (PR-270.md, "Qué causó re-work"). No es paráfrasis que cambie el sentido.
- "un check que puede devolver `true` sin ejercer el camino (como `document.fonts.check()`) tampoco es evidencia" (§5) reproduce "`document.fonts.check()` devuelve `true` cuando no hace falta cargar nada: no prueba qué fuente pinta" (PR-269.md, "Qué causó re-work"). Consistente.
No hay otra afirmación visual nueva en el diff que quede sin evidencia — el resto de las líneas tocadas son remisiones al criterio, no afirmaciones de hecho.

**4. Costo de contexto — CORRECCIÓN FACTUAL AL BRIEFING, sin bloqueante resultante.**
`rules/implementation-principles.md` **sí tiene** frontmatter `paths:` (líneas 1–23: `.ts .tsx .js .jsx .py .go .rs .cs .sql .sh .bash .vue .svelte .css .scss .sass .less .html .htm Dockerfile*`), preexistente al diff — no se toca en este PR. La premisa de que "no tiene `paths:` y por eso carga en toda sesión de todo proyecto" es incorrecta; el propio `CLAUDE.md` raíz del repo dice lo contrario: con `paths:`, la regla carga **solo** al tocar archivos que matchean. El malentendido probablemente viene de leer la sección "NO incluye" de `.planning/BRIEF.md` línea 26 ("un archivo *nuevo* en `rules/` sin `paths:` se volvería contexto permanente"), que habla de un archivo hipotético que el equipo decidió no crear — no de `implementation-principles.md`, que ya existe y ya tiene `paths:`.

Con el hecho corregido, la pregunta de fondo sigue siendo válida pero se responde distinto: el archivo carga en cualquier sesión que toque código (cobertura amplia por diseño — es el archivo de principios de implementación general, no uno de UI), y la viñeta nueva es una instanciación más de una lista que ya mezcla ejemplos de dominios distintos (flags de plataforma, hooks, conteos verificados, timing, y ahora visual) bajo el mismo principio general ("verificar antes de afirmar"). Encaja con el patrón existente del archivo; no es un costo nuevo de la magnitud que plantea la premisa original.

**5. Redacción verificable (D-02) — CUMPLE.**
Las tres instanciaciones dicen explícitamente qué cuenta como evidencia y qué no, no quedan en consejo:
- §5: computado en navegador real, en el ancho afirmado — vs. leer el CSS, o un check que retorna `true` sin ejercer el camino.
- `qa-frontend.md:80`: valor computado en navegador — vs. leer el token o el CSS.
- `qa-frontend.md:89`: valor computado — vs. asumir que coincidir con el token garantiza que se pinta.
- `ui-ux.md:281`: valor computado en el navegador en ese ancho — vs. leer el screenshot a simple vista o el CSS fuente.
Ninguna es un "revisa bien" genérico.

### Verificación propia (§5 aplicado a este review)
- `claude plugin validate --strict .` corrido de forma independiente (no solo tomado de la palabra del dev): salida `✔ Validation passed`, confirmado.
- Grep propio ejecutado sobre el repo completo (no solo sobre lo que el dev reportó haber revisado).
- Citas de PR-269/PR-270 leídas del archivo fuente en `easy-quotes`, no asumidas por el nombre del PR.

### Veredicto
**APROBADO**

#### Bloqueantes
Ninguno.

#### Sugerencias
- [ ] `agents/ui-ux.md:229` — la casilla `[ ] Contraste WCAG AA verificado en texto` (template de `MASTER.md` que `ui-ux` genera) es el punto exacto donde alguien marca una afirmación de verificación ya hecha; no remite a §5 aunque las otras dos instanciaciones en el mismo archivo sí lo hacen. No es una contradicción (es contenido de especificación generado para otro documento, no una claim del propio agente), pero dejarla sin la remisión es una oportunidad perdida de D-01 en el punto donde más importa: cuando `frontend-dev` la marca.
- [ ] `rules/css.md:59` (`**Testea contraste en ambos modos**`) y, en menor medida, `rules/css.md:64` / `rules/html.md:32` — instrucción de "testear" sin decir con qué se cierra esa prueba, exactamente el vacío que originó el incidente de PR-270 (contraste "medido" leyendo tokens). Ambos archivos cargan por `paths:` junto con `implementation-principles.md` en cualquier diff que toque `.css`/`.html`, así que la cobertura práctica ya existe por co-carga — pero un cross-reference explícito a §5 cerraría el loop sin depender de que el lector conecte los dos archivos por su cuenta. No estaba en el alcance declarado en `BRIEF.md` (3 archivos), así que no es bloqueante para este PR.

### NO CUBIERTO
- Contenido de `.planning/BRIEF.md` y `.planning/state.json` (decisiones D-01–D-02, métricas de fase): leídos como contexto, no auditados como documento normativo — no son consumidos por agentes.
- Resto del corpus de `rules/`, `rulebooks/`, `agents/`, `skills/` más allá de los términos griffeados (`contraste`, `visual`, `computed`, `playwright`, `render`, `css`, `WCAG`) — no se releyó cada archivo completo, solo se grepeó.
- No hay CI en este repo (confirmado en `BRIEF.md`); no hay suite que correr más allá de `claude plugin validate --strict .`, que sí se ejecutó.
- No se evaluó el efecto de este cambio sobre sesiones ya en curso de otros agentes (fuera de alcance de un review de diff).
