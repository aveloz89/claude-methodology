# Learnings

Retro por PR mergeado. El orchestrator **prepend** una entrada (más reciente arriba) en la Fase 4, como último commit del branch del PR — antes del merge, nunca en un PR aparte.

## Formato de entrada

```markdown
### [YYYY-MM-DD] PR #N — Título del PR

**Métricas:**
- Review rounds: N
- Hallazgos security: N (critical: N, high: N, medium: N, low: N)
- Hallazgos qa-frontend: N (stubs: N, coverage: N, edge cases: N, otros: N)
- Hallazgos qa-backend: N (stubs: N, coverage: N, edge cases: N, otros: N)
- Errores de build/CI: N
- Self-reflection atrapó: N (cosas que detectó antes del review, o "nada")
- Lotes ejecutados: N / Tareas: M
- Devs involucrados: [db-specialist? backend-dev? frontend-dev?]

**Qué salió bien:**
- [descripción]

**Qué causó re-work:**
- [descripción — y si era prevenible]

**Patrón potencial:** [sí/no — si sí, cuál y cuántas veces se ha visto]
```

Formato canónico vive en `rulebooks/orchestrator-runbook.md`. Si ahí cambia, este archivo debe alinearse.

---

## Entradas

(Las entradas se agregan aquí, la más reciente arriba)

### [2026-08-25] PR #63 — Cómo el orchestrator le escribe al usuario y le pide decisiones

**Métricas:**
- Review rounds: 2
- Hallazgos security: 3 (critical: 0, high: 0, medium: 1, low: 2)
- Hallazgos qa-frontend: 0 (no aplica)
- Hallazgos qa-backend: 3 (1 bloqueante, 2 sugerencias) en ronda 1; N/A por scope en ronda 2
- Errores de build/CI: 0 (este repo no tiene Actions)
- Self-reflection atrapó: nada — el DoD anti-drift NO se corrió antes de pedir review, y eso fue el bloqueante
- Lotes ejecutados: 1 / Tareas: 2
- Devs involucrados: ninguno

**Qué salió bien:**
- El pedido del usuario venía con su razón: "muchas veces me pierdo con todo lo que dices y no sé cuándo necesitas algo de mí". Esa frase es el criterio de aceptación de la regla, y quedó en el cuerpo del PR.
- security verificó que la regla de opciones **refuerza** el invariante de aprobación explícita en vez de debilitarlo: seleccionar una opción es un acto afirmativo, mientras que un "ok, dale" ambiguo en prosa podía pasar por consentimiento.
- El bloqueante de qa-backend fue el caso perfecto: el runbook prescribía una pregunta **en prosa citada entre comillas** justo en el paso que la regla nueva convierte en pregunta con opciones.

**Qué causó re-work:**
- No corrí el DoD anti-drift antes de pedir review, en un cambio que el propio DoD clasifica como cambio de flujo. Lo encontró QA. El grep tardó diez segundos cuando finalmente lo corrí.
- Escribí la regla de brevedad sin acotar su alcance: habilitaba reportar un CRITICAL en una línea, sin riesgo ni remediación.

**Patrón potencial:** sí, dos. (1) **El DoD anti-drift se saltea justo en los cambios chicos** — "son dos bullets" fue la excusa implícita, y el cambio de dos bullets contradecía un paso del runbook. 2ª aparición contando el PR #61, donde el espejo de `paths:` se rompió por lo mismo. Candidato: volverlo un paso explícito del checklist pre-review, no una sección del runbook que hay que recordar. (2) **`qa-backend` cambia de criterio de scope entre rondas** ante documentación normativa — 2ª aparición (PR #59 y este). Ya está en follow-ups: o se fija el criterio en su prompt, o se define quién revisa cambios de metodología.

### [2026-08-25] PR #58 — Scoping del pre-commit por workspace, y una garantía que se falseó tres veces

**Métricas:**
- Review rounds: 3
- Hallazgos security: 6 (critical: 0, high: 2, medium: 1, low: 3) + 1 nit retirado por el propio reviewer
- Hallazgos qa-frontend: 0 (no aplica)
- Hallazgos qa-backend: 7 (2 bloqueantes, 5 sugerencias — 4 aplicadas, 1 derivada a issue)
- Errores de build/CI: 0 (este repo no tiene Actions)
- Self-reflection atrapó: el dev distinguió shellcheck preexistente de regresión propia; omitió la revisión idiomática con razón (no existe `rules/bash.md`)
- Lotes ejecutados: 1 / Tareas: 4
- Devs involucrados: backend-dev

**Qué salió bien:**
- **Primera aplicación real del corolario del principio 5**, mergeado horas antes en el PR #61, y funcionó como se diseñó: qa-backend verificó por su cuenta tres de las cuatro afirmaciones rojo→verde del dev en `git worktree` desechables, sin tocar el árbol del PR, con conteos de FAIL exactos.
- **La etiqueta *no verificable* pasó su primera prueba sin erosionarse.** El dev la invocó para el caso pnpm y QA la adjudicó bien: ahí no hay hunk que revertir porque el skip es comportamiento de `pnpm run`, distinto del resquicio que la regla cierra (alegar "revertir no compila" cuando sí hay hunk propio).
- Tres correcciones de afirmaciones de reviewers, todas por ejecución: el dev refutó la causa raíz de un nit de security —bash no re-escanea el valor sustituido— y security la retiró.
- El review encontró los tres HIGH/MEDIUM yendo a construir el caso, no releyendo el código.

**Qué causó re-work:**
- La afirmación central de la lib se falseó **tres veces seguidas**. Prometía que ningún modo de falla corre menos tests: dos contraejemplos. Reescrita, decía que el path C-quoteado era el único modo conocido: otro contraejemplo, el submódulo. Cada versión la escribió alguien que no había ido a buscar el contraejemplo.
- El branch salía de `dev` anterior al fix del ReDoS: al checkoutearlo, el `guard-matching.sh` vulnerable volvía al árbol. Hubo que mergear `dev` antes de trabajarlo — no es obvio y va a repetirse con cualquier branch viejo.
- La etiqueta `legacy-violation` no existía en el repo y `gh issue create` falla entero con una etiqueta inexistente. Dos de las cuatro que el agente `refactor` lee no estaban.

**Patrón potencial:** sí, dos. (1) **"Una garantía absoluta en un comentario es una promesa que alguien va a falsear"** — 3ª aparición en un mismo archivo. La formulación que sobrevivió no afirma unicidad: enumera lo verificado y dice explícitamente que no es exhaustiva. Candidato a regla: los comentarios de garantía se escriben como inventario de lo verificado, nunca como absoluto. (2) **La taxonomía de etiquetas del agente `refactor` no está materializada en los repos** — el flujo de derivar deuda falla en silencio. 1ª aparición; revisar si el skill `new-project` las crea al hacer scaffold.

### [2026-08-25] PR #61 — La regla de verificar antes de afirmar, y su propia demostración

**Métricas:**
- Review rounds: 2
- Hallazgos security: 5 (critical: 0, high: 2, medium: 0, low: 3)
- Hallazgos qa-frontend: 0 (no aplica)
- Hallazgos qa-backend: 3 (2 bloqueantes, 1 sugerencia)
- Errores de build/CI: 0 (este repo no tiene Actions)
- Self-reflection atrapó: n/a — sin dev, el diff lo escribió el orchestrator
- Lotes ejecutados: 1 / Tareas: 1
- Devs involucrados: ninguno

**Qué salió bien:**
- La regla se escribió **el mismo día** que el patrón llegó a su 5ª aparición, en vez de registrarse por sexta vez. El disparador fue el usuario preguntando "¿por qué esperar?".
- El review dual demostró la tesis del PR con el PR mismo: los dos reviewers bloquearon, y las tres fallas eran afirmaciones que yo no había verificado.
- Las dos sugerencias de la ronda 2 convergieron en el hueco que yo mismo les había pedido buscar — pedir explícitamente "díganme por dónde se rompe esto" produjo mejor review que pedir "revísenlo".

**Qué causó re-work:**
- Escribí una instrucción que obligaba a los QA a modificar el árbol de trabajo sin comprobar sus tools: tienen `Write` y `Edit` denegados por frontmatter. Estaba enseñándoles a rodear su propia política con `sed -i`.
- Definí el corolario como "borrar la línea del fix" sin probar los casos borde. Con un fix de un token, borrar la línea rompe la sintaxis: la suite se pone roja por la razón equivocada y el check pasa vacío. La forma más peligrosa de fallar, porque simula la verificación.
- Agregué `.sh` a un archivo de `rules/` sin mirar su gemelo, y rompí un espejo de `paths:` que se mantenía por convención — el mismo drift que la sección Anti-drift existe para prevenir.

**Patrón potencial:** sí, dos. (1) **"El review dual es lo que sostiene la regla, no la regla"** — el principio 5 no habría atrapado ninguna de las tres fallas de su propio PR, porque las tres eran afirmaciones sobre documentos y frontmatter, no sobre código ejecutable. Lo que las atrapó fue que dos agentes fueran a mirar el archivo vecino y el caso borde. La regla escrita reduce la frecuencia; el review sigue siendo el que la hace cumplir. 1ª aparición formulada así. (2) **Pedir el vector de falla concreto en el prompt del reviewer** ("¿puede esta etiqueta usarse como excusa?", "¿el gate deja pasar un merge real?") produjo hallazgos que un "revisa esto" genérico no produjo — 2ª aparición contando el PR #60, donde la pregunta "¿el regex nuevo sanea de más?" destapó un fail-open que llevaba meses vivo.

### [2026-08-25] PR #60 — ReDoS en guard_sanitize, y el fail-open que escondía

**Métricas:**
- Review rounds: 3
- Hallazgos security: 7 (critical: 0, high: 0, medium: 1, low: 6) + el descubrimiento de un fail-open preexistente en el código viejo
- Hallazgos qa-frontend: 0 (no aplica)
- Hallazgos qa-backend: 5 (2 bloqueantes, 3 sugerencias — 2 aplicadas, 1 diferida)
- Errores de build/CI: 0 (este repo no tiene Actions)
- Self-reflection atrapó: el dev distinguió shellcheck preexistente de regresión propia, y rechazó tres veces un system-reminder que le pedía usar heredocs con el ReDoS activo
- Lotes ejecutados: 1 / Tareas: 4
- Devs involucrados: backend-dev (dos invocaciones; la primera abortada sin commits)

**Qué salió bien:**
- **El bug lo encontró el usuario, no el sistema**: "la mac está super caliente". 128 tests adversariales en verde mientras el sanitizador se colgaba con entrada ordinaria. Ningún test, ningún hook, ningún monitor lo veía.
- Los dos reviewers verificaron **ejecutando**: security corrió 12 payloads contra `bash` real para saber cuáles ejecuta y cuáles trata como literal; QA reconstruyó el regex viejo desde `dev` y borró el fix para comprobar que el test se ponía rojo. Todo lo que se encontró salió de ahí, nada de lectura.
- La pregunta del brief ("¿el regex nuevo sanea de más?") se respondió al revés de lo esperado y destapó un **fail-open real** del regex viejo: dos heredocs con el mismo delimitador se tragaban un `--admin` en 9ms, en silencio, desde que se escribió la lib.
- Segunda aplicación de la regla del PR #59: la retro viaja en el branch.

**Qué causó re-work:**
- Describí mal el exploit al dev (delimitadores distintos en vez del mismo); él lo verificó y me corrigió antes de escribir el test. Después security **retiró su propia tabla** por la misma razón: había marcado "HIDES" donde era "TIMEOUT".
- Pedí meter `pre-merge-check.sh` al scope sin decir dónde iba el check. Quedó bloqueando cualquier comando ante un saneo fallido — `ls -la` incluido. MEDIUM de la ronda 2, daño colateral mío.
- Mi propio watchdog usó `ps -o etimes=`, que no existe en macOS: nunca mató nada y dejó una hora de CPU ardiendo mientras yo lo daba por activo.
- Diagnostiqué el primer intento del dev como "atrapado en el bug que fue a arreglar". Narrativa redonda y falsa: la evidencia estaba en el mismo `ps` que ya había mirado — esos procesos corrían el regex **viejo**, y el archivo ya tenía el nuevo.

**Patrón potencial:** sí, tres. (1) **"Verificar contra el sistema real antes de afirmar" — 5ª aparición**, con cinco instancias dentro de esta sola sesión (mi nota sobre `post-pr-create.sh`, el commit del dev con "5 casos verificados", el test del huérfano, mi `etimes`, la tabla de security). La regla de 3 se alcanzó en el PR #55 y la propuesta **sigue sin escribirse**: el grep confirma que no existe en `rules/`. Registrar el patrón cinco veces no lo corrige. (2) **"El test que protege un fix debe romperse si borras el fix"** — criterio mecánico, verificable, que cazó un bloqueante que dos rondas de lectura no habrían visto. 1ª aparición como criterio explícito; candidato a regla o al prompt de los QA. (3) La suite adversarial no ejercita a los guards con entrada patológica: prueba qué bloquean, no cómo se comportan con input hostil. El ReDoS vivió ahí, en verde.

### [2026-08-24] PR #59 — La retro viaja en el branch del PR, no en un PR aparte

**Métricas:**
- Review rounds: 2
- Hallazgos security: 7 (critical: 0, high: 0, medium: 1, low: 6) + 1 bug funcional fuera de scope de seguridad
- Hallazgos qa-frontend: 0 (no aplica — sin frontend en el diff)
- Hallazgos qa-backend: 3 (1 bloqueante, 2 sugerencias — 1 aplicada, 1 diferida con razón)
- Errores de build/CI: 0 (este repo no tiene GitHub Actions)
- Self-reflection atrapó: n/a — sin dev, el diff lo escribió el orchestrator
- Lotes ejecutados: 1 / Tareas: 1
- Devs involucrados: ninguno

**Qué salió bien:**
- El review dual sobre un diff 100% markdown pagó su costo dos veces: cazó una contradicción semántica con el modo multi-PR que ningún grep detecta, y una afirmación falsa sobre qué hook cubre qué.
- Verificar el comando nuevo del check 4 **ejecutándolo** contra rangos de commits reales (no leyéndolo) confirmó el `0`/`N` esperado y la guarda de `review_sha` vacío.
- El cambio se estrenó a sí mismo: esta entrada viaja en el branch del PR #59.
- El origen fue un dato medido, no una intuición: 7m23s de runners de easy-quotes por 47 líneas de markdown.

**Qué causó re-work:**
- Afirmé que `post-pr-create.sh` ya cubría el commit de retro **sin leer el hook**. Corre en `gh pr create` y no vuelve a mirar el branch. Prevenible con 30 segundos de lectura; costó una ronda de fixes y, mientras existió, dejó una ventana real (push post-review sin ningún guard de contenido).
- Reescribí de paso la cardinalidad de LEARNINGS ("por cada merge exitoso" → "por feature") sin que nadie lo pidiera. Rompió el modo multi-PR y fue el único bloqueante del PR: un cambio no pedido, adyacente al pedido.
- El DoD anti-drift se cumplió y aun así no alcanzó: el grep de términos encuentra residuos léxicos, no contradicciones semánticas. La contradicción la encontró un reviewer leyendo el flujo completo. Y el propio `LEARNINGS.md` decía "retrospectivas post-merge" — quedó fuera del grep porque `.planning/` no estaba en la lista de directorios del DoD.

**Patrón potencial:** sí, dos. (1) **"Verificar contra el sistema real antes de afirmar" — 4ª aparición** (PR #49: `stat` en Docker; PR #54: repo público; PR #55: CLI del plugin; PR #59: comportamiento de `post-pr-create.sh`). La regla de 3 se dio por alcanzada en el PR #55, con propuesta concreta de agregarla a `rules/implementation-principles.md` o al prompt del architect — y **nunca se implementó**: el grep confirma que no existe. Que el patrón reaparezca es la evidencia de que registrarlo no lo corrige. (2) qa-backend cambió de criterio entre rondas del mismo PR — revisó coherencia normativa en la ronda 1 y en la ronda 2 se declaró fuera de scope por ser markdown. Un diff de proceso no tiene reviewer con mandato claro; 1ª aparición, si se repite hay que definir a quién le toca.

### [2026-08-14] PR #56 — Review dual pre-push (Fase 2.6): el PR nace revisado

**Métricas:**
- Review rounds: 1 dual pre-push (estreno del flujo en su propio PR) + 1 ronda de fixes local sin re-review (cambio menor validado por tests)
- Hallazgos security: 2 MEDIUM (anclaje por SHA, sanitización de slug) + 2 LOW + 1 legacy adoptada (4º check pre-merge) — todos aplicados
- Hallazgos qa-backend: 3 sugerencias + 1 gap de cobertura declarado (detached HEAD) — todos aplicados
- Errores de build/CI: 0. **Runs de CI consumidos por el ciclo de review: 0** — el objetivo del cambio, cumplido en su primer uso
- Self-reflection atrapó: el barrido de docs cazó 8 secuencias del flujo viejo que el grep por palabras no podía atrapar (no mencionaban "review")
- Lotes: 3 (15 tareas) + ronda 2.6 (5+1) + docs. Devs: general-purpose con rol inyectado (transición al plugin), architect en fable
- Suites al cierre: 128/128 + 19/19

**Qué salió bien:**
- **El flujo nuevo se revisó a sí mismo y se mejoró en el acto**: el review pre-push de este PR encontró el hueco del anclaje (evidencia stale si hay commits post-review) y el fix entró en la misma ronda local — exactamente el ciclo barato que el cambio promete.
- Decisión del architect de NO renumerar fases (2.6 entra en el hueco existente): el costo anti-drift del cambio bajó drásticamente.
- El 4º check pre-merge estrenó en el propio merge de este PR, verificando evidencia real (`review_sha` ancestro, registro reconciliado).
- Muertes por límite de sesión a mitad de review: reanudar desde transcript preservó el avance (el ángulo del SHA que security venía persiguiendo sobrevivió al corte y terminó siendo el hallazgo principal).

**Qué causó re-work:**
- Nada estructural. La demo en vivo del hook en ESTA sesión requirió invocación manual (la sesión en limbo post-migración registró hooks desde el path viejo) — consecuencia ya conocida y documentada de la transición al plugin.

**Patrón potencial:** el par "review encuentra el hueco de evidencia → la evidencia se vuelve machine-readable → un check mecánico la exige" (checkpoint CASO A + 4º check) es la misma jugada que mató la clase C5 (test de paridad) — 2ª aparición de "convertir invariantes de proceso en verificación mecánica"; si aparece una 3ª, considerar regla explícita de diseño.

### [2026-08-14] PR #55 — Barrido de follow-ups: plugin de distribución, slug con hash, sandbox total y skill review-pr

**Métricas:**
- Review rounds: 1 dual + 1 ronda de sugerencias (sin re-review — cambios menores validados por tests, per skill)
- Hallazgos security: 3 LOW + 1 robustez + 1 adjudicación de contrato — 0 blockers; el checklist crítico (fuga repo-específica en global/CLAUDE.md) salió limpio
- Hallazgos qa-frontend: no aplica
- Hallazgos qa-backend: 4 sugerencias, 0 blockers; verificación empírica completa (suites + 5 escenarios de installer + tests validados por mutación)
- Errores de build/CI: 0 (sin CI; suites 110/110 + 19/19 verificadas por dev, QA remoto y orchestrator)
- Self-reflection atrapó: el validate del plugin destapó YAML roto en ui-ux.md (legacy) — arreglado en el lote, no estacionado
- Lotes ejecutados: 5 (22→24 tareas con las agregadas) + 1 ronda de sugerencias (5) + docs
- Devs involucrados: backend-dev (lotes 1–4), general-purpose con rol inyectado (lote 5, docs, sugerencias — ver hallazgo de transición), architect (fable, con verificación de CLI en vivo)

**Qué salió bien:**
- El architect verificó el formato del plugin contra la CLI real (ciclo add→install en HOME aislado) ANTES de diseñar — cero retrabajo por formatos asumidos.
- La ronda de sugerencias demostró RED real: los symlinks con `..` sí se borraban (el LOW de security era bug genuino, no teoría).
- El pulido del installer se validó con 22 assertions en HOME fake antes de tocar nada real.
- La instrumentación `raw_keys` del PR #54 pagó: primer análisis del log reveló la causa de los `unknown` (payload con `agent_type: null`, forma de evento Stop) — el diagnóstico diferido funcionó como se diseñó.
- **Migración en caliente gestionada**: quitar el bloque hooks del settings symlinkeado + install.sh inmediato dejó doble registro inocuo, nunca ventana sin guards (verificado con plugin details).

**Qué causó re-work:**
- **La migración des-registró los tipos de agente de la sesión corriendo** (el symlink legacy ~/.claude/agents era lo que los cargaba): los lotes 5+, docs y reviews corrieron con general-purpose + rol inyectado desde agents/*.md. Funcionó bien como workaround, pero es fricción. Lección: tras migrar el mecanismo de carga de agentes, la sesión debe reiniciarse — documentado; los flujos de instalación deben avisarlo.
- El watchdog mató un dev (600s sin progreso, probable CLI interactiva colgada) — mitigación que funcionó: reanudar con instrucción de timeout manual + stdin cerrado en toda invocación de `claude`.

**Patrón potencial:** sí, dos. (1) "Verificar contra el sistema real antes de diseñar/afirmar" — 3ª aparición (PR #49: stat en Docker; PR #54: repo público recalibró severidad; PR #55: CLI del plugin + RED del installer). **Regla de 3 alcanzada** → propuesta: añadir a `implementation-principles.md` o al prompt del architect la regla explícita "toda afirmación sobre comportamiento de plataforma/entorno se verifica ejecutando, no se asume de docs". (2) Rol inyectado como fallback de agentes nombrados — funcionó 4 veces; documentarlo en governance-playbook como respuesta estándar a "agente no disponible".

### [2026-08-14] PR #54 — Cierre de todos los issues abiertos: guards endurecidos, fail-closed y sanitización

**Métricas:**
- Review rounds: 3 (1 dual completa + 2 re-reviews acotados al delta)
- Hallazgos security: 7 en ronda 1 (0 critical/high, 4 medium, 3 low) + 1 medium en re-review (regresión espejada) — todos corregidos, cero diferidos
- Hallazgos qa-frontend: no aplica (sin UI)
- Hallazgos qa-backend: 2 bloqueantes marginales (falso positivo silencioso sin perl; dependencia dirname fail-open) — ambos resueltos y verificados empíricamente
- Errores de build/CI: 0 (repo sin CI; suite adversarial 91/91 verificada por dev, por QA en entorno aislado y por el orchestrator en el working tree real)
- Self-reflection atrapó: el TDD del lote 1 destapó que la sanitización línea-por-línea de títulos dejaba pasar payloads con newline embebido (cambiado a iteración por-registro en base64 antes del review)
- Lotes ejecutados: 1 de implementación (5 tareas) + 3 rondas de fixes (5+6+1) + docs (2 commits)
- Devs involucrados: backend-dev, docs

**Qué salió bien:**
- El RED de TDD demostró los bugs reales antes de arreglarlos (el falso negativo de `git fetch && gh pr merge --admin`, el caso espejo de comillas) — evidencia, no suposición.
- **Aislamiento remoto para reviewers**: la máquina del usuario entró en reposo repetidamente y mató 3 intentos del security local; relanzarlo con `isolation: remote` lo resolvió de raíz. Queda como respuesta estándar cuando la máquina puede dormirse.
- Estreno de `state.json`: el orchestrator respondió "¿está haciendo algo el dev?" con datos en vivo (3/5 tareas, tarea actual) en vez de adivinar.
- Directiva del usuario "follow-up = issue, se arregla ahora": las 3 rondas cerraron 13 hallazgos sin diferir ninguno — y el par review→re-review cazó que el primer fix de comillas espejaba el bug en vez de resolverlo.

**Qué causó re-work:**
- El fix de "invertir el orden" de las reglas de saneo de comillas espejó el falso negativo en vez de eliminarlo (1 ronda extra). Prevenible: cuando el fix propuesto es "cambiar el orden de dos reglas", sospechar que el problema es estructural (dos pasadas no modelan anidamiento) — la solución era una pasada con alternancia, como parsea el shell.
- 3 muertes del security-reviewer local por reposo de la máquina (~30 min perdidos). Mitigaciones: `isolation: remote` para tareas largas en background, o `caffeinate` si el usuario se aleja.

**Patrón potencial:** sí — "el reviewer valida al fixer": 2ª vez consecutiva (PR #49: QA cazó el stat GNU tras el fix del dev; PR #54: security cazó el espejo tras su propia sugerencia). El re-review acotado al delta post-fix se confirma como paso no negociable, ya codificado en la skill pr-workflow.

### [2026-08-13] PR #49 — Modernización 2026: hooks de observabilidad, state.json y anti-drift

**Métricas:**
- Review rounds: 1 completa + 1 re-review acotado al diff de fixes + 1 ronda test-only
- Hallazgos security: 9 (critical: 0, high: 0, medium: 1 + 2 legacy, low: 5 + 1 legacy) → 3 issues legacy creados (#50–#52)
- Hallazgos qa-frontend: no aplica (sin UI)
- Hallazgos qa-backend: 1 bloqueante (portabilidad GNU de `stat -f %m` — reproducido en Docker) + 3 sugerencias + 1 observación de datos (log con duplicados y unknowns)
- Errores de build/CI: 0 (repo sin CI; suite adversarial local 56/56 en macOS y ubuntu:22.04)
- Self-reflection atrapó: 2 antes del review — el ciclo TDD del Lote 1 se rehízo para preservar RED genuino, y el test de rotación del Lote 2 destapó que `jq -n` sin `-c` rompía el contrato JSONL
- Lotes ejecutados: 5 / Tareas: 25 (+7 de ronda de fixes +1 test-only)
- Devs involucrados: backend-dev (todos los lotes), docs, architect (fable)

**Qué salió bien:**
- Presupuesto explícito en prompts de reviewers (memoria del PR #48 aplicada): security cerró en ~20 min con NO CUBIERTO declarado, re-review de QA en ~10 min acotado al delta. Cero rondas de 40 min.
- La regla anti-drift pagó en su PR de estreno: el grep del Lote 5 encontró drift adicional en el propio runbook (template de handoff, Fase 3) además de los 4 agents que el Lote 4 ya había señalado.
- El usuario empujó a no diferir la calidad del log a la retro → diagnóstico con evidencia en el momento (doble registro user+project scope = doble disparo; unknowns = subagentes anidados) y fix en el mismo PR (dedupe + `raw_keys`).
- QA verificó portabilidad empíricamente (Docker ubuntu:22.04), no solo por análisis — así se confirmó el blocker y después el fix.

**Qué causó re-work:**
- El DESIGN declaraba "helper dual de stat" como patrón portable, pero una de las tres implementaciones usó la forma con espacio (`stat -f %m`) que en GNU falla en silencio. Prevenible: shellcheck no ve semántica de binarios externos; la verificación cross-platform necesita ejecución real (Docker), no solo lint. El fix costó 1 ronda extra.
- El PR body inicial atribuía al PR los commits de hardening que ya estaban mergeados en dev vía PR #48 (branch reutilizado por decisión de single-PR). El security-reviewer lo detectó; corregido con `gh pr edit`. Prevenible comparando `git log dev..HEAD` contra el diff real antes de redactar el body.

**Patrón potencial:** sí, dos. (1) "Portabilidad declarada ≠ portabilidad verificada" — 1ª vez; si reaparece, agregar a la verificación pre-commit de hooks un run en contenedor Linux. (2) La suite adversarial manipula el repo REAL (`git stash`/`checkout` en tests de guards) — casi causa pérdida de estado durante el re-review; follow-up creado para sandboxearla como los hooks nuevos.
