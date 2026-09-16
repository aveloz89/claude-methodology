## Review: pre-push `docs/regla-verificacion-visual` — lo visual se verifica en un navegador

- **Branch:** `docs/regla-verificacion-visual` · **Base:** `dev` · **SHA ronda 1:** `d1671c7` · **Fecha:** 2026-09-16
- **Veredicto:** **APROBADO** tras dos rondas (qa-backend aprobó en la ronda 1; security levantó 1 bloqueante en la ronda 1 y aprobó en la ronda 2).
- Reportes por reviewer: `pre-pr-regla-verificacion-visual-security.md` (transcrito por el orchestrator, con sus dos rondas) y `pre-pr-regla-verificacion-visual-qa-backend.md`.

### Resumen

Diff normativo, sin código: §5 de `rules/implementation-principles.md` gana el criterio de verificación visual, y `agents/{ui-ux,qa-frontend,frontend-dev}.md` más `rules/{css,html}.md` conservan su enunciado accionable y remiten. Origen: regla de 3 en easy-quotes (retros PR-263, PR-269 y PR-270), aprobada por el usuario.

### Seguridad

Ronda 1: **CAMBIOS REQUERIDOS**, 1 bloqueante. La línea nueva de `qa-frontend.md:80` exigía un valor computado en navegador a un agente que nunca recibe stack y es read-only por diseño: dejaba un criterio bloqueante sin camino alcanzable. El propio diff ya resolvía bien el caso idéntico dos secciones más abajo (`:89`). Más 4 sugerencias LOW.

Ronda 2: **APROBADO**. Bloqueante cerrado (voz activa, productor nombrado, tercer estado en el checklist) y los 4 LOW resueltos. Verificó además que el cross-reference nuevo de `css.md`/`html.md` solo agrega estándar de evidencia sin degradar ningún gate. 3 sugerencias LOW nuevas, todas de prosa, que se aplican antes del push.

### QA Backend

**APROBADO**, cero bloqueantes, con una corrección factual al encargo del orchestrator: `rules/implementation-principles.md` **sí** tiene frontmatter `paths:` (lista amplia de extensiones), así que no se carga en toda sesión de todo proyecto, como yo había afirmado sin verificar. Con el hecho corregido, la viñeta nueva encaja en el patrón de §5 y no agrega costo de contexto fuera de lo ya asumido.

Verificó además: D-01 cumplido (las instanciaciones conservan enunciado propio y remiten, ninguna es puntero pelado); sin contradicciones vivas en su propio grep; las citas de `PR-269.md` y `PR-270.md` son fieles, no paráfrasis; y corrió `claude plugin validate --strict .` por su cuenta en vez de creerle al dev. Sugirió el cross-reference en `rules/css.md`/`html.md`, que el usuario aprobó y entró como D-04.

### Veredicto

**APROBADO**

#### Bloqueantes
Ninguno (el de la ronda 1 quedó cerrado y verificado en la ronda 2).

#### Sugerencias aplicadas antes del push
- Ronda 1 (security): bloqueante de `:80`/`:288`; contraste en los mínimos de `frontend-dev.md`; ruta completa y escape del paso 3 en `ui-ux.md:292`; y `:229` remitiendo a §5 (qa-backend).
- Ronda 2 (security): canal declarado para la evidencia en el cierre de lote del `frontend-dev`; desambiguar `NO VERIFICABLE` frente a `implementation-principles.md:185`; voz activa en `css.md`/`html.md`. **Aplicadas en `d1f6d36`**, sin re-review por ser prosa: el checklist usa ahora la etiqueta propia `SIN EVIDENCIA`, con equivalencia explícita a `ISSUE` y la aclaración de que no es el caso de *no verificable* de §5 (reusar el término habría reproducido el hallazgo de `PR-61.md:35`, «no verificable ⇒ nada bloquea»); `css.md` y `html.md` pasan a voz activa nombrando al `frontend-dev` como productor y a `qa-frontend` como quien exige; y la evidencia de contraste entra a la lista de cierre de lote del dev. Grep del DoD re-corrido sobre los términos nuevos: `SIN EVIDENCIA` no tenía uso previo y las dos menciones de *no verificable* en §5 quedaron intactas. `claude plugin validate --strict .` → passed.

**Veredicto final: APROBADO.** `review_sha` = `d1f6d36`.

#### No aplicadas
- qa-backend sugirió que `ui-ux.md:258` remita a §5: se dejó como está porque es un umbral de especificación, no una afirmación de verificación ya hecha. Security lo confirmó en la ronda 2.

### NO CUBIERTO (consolidado)
- Ninguno de los dos corrió los tests del repo (`tests/adversarial/`, `tests/validation/`): el diff no toca hooks ni manifiestos. `claude plugin validate --strict .` sí se corrió (dev y qa-backend).
- La eficacia práctica de la regla no es observable desde el diff: se verá en el primer PR de frontend que la ejerza.
- Security no descartó del todo un consumidor aguas abajo que asuma dos estados en el checklist de `qa-frontend`.
