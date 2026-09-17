# Review pre-push — qa-backend

- **Branch:** `fix/hook-merge-repo-y-fila-dod`
- **Base:** `dev`
- **HEAD:** `1f64d6f`
- **Fecha:** 2026-09-16
- **Veredicto:** **CAMBIOS REQUERIDOS**

## Scope

`git diff dev...HEAD` (3 commits: `5232d0f` hook, `8f5960c` tests, `1f64d6f` fila del DoD + conteo). Dos roles: coherencia normativa/anti-drift sobre `rulebooks/orchestrator-runbook.md` y `agents/security-reviewer.md`, y calidad de código/tests sobre `hooks/pre-merge-check.sh` y `tests/adversarial/test-hooks.sh` (`~/.claude/rules/bash.md`). `.planning/BRIEF.md`, `.planning/BRIEF-regla-verificacion-visual.md` y `.planning/state.json` se leyeron solo como contexto, no como objeto de review normativo (no son documentos que otro agente consuma como regla).

### QA Backend

**1. Tests del hook — evidencia rojo→verde reproducida en worktree desechable, cubre lo que pide el brief.**

Worktree en `1f64d6f` (eliminado al terminar, `git worktree remove --force`): suite completa **279/279** con el fix. Revertido *solo* `hooks/pre-merge-check.sh` a la versión de `dev` (dejando los tests nuevos intactos): **272/279**, exactamente los 7 fallos que declara el commit `8f5960c`, con la razón de bloqueo cayendo al mensaje genérico viejo ("no pude detectar el repo (gh repo view falló)") en vez del mensaje específico nuevo — confirma que el test mide el fix, no una casualidad de fail-closed. El octavo test ("cd, requisito 1": `--repo` explícito gana sobre un `cd` en el mismo comando) se mantiene en verde sin el fix, como corresponde: prueba que el camino de `--repo` explícito —comportamiento preexistente— no se rompió, no depende de la extracción nueva.

Los tres casos que pide el brief están cubiertos y verificados end-to-end contra binarios `gh` falsos que distinguen por `$PWD` (no por texto — mismo número de PR en los dos repos, igual que el incidente real):
- **Incidente** (`cd` a otro repo con PR homónimo, checks distintos entre los dos): valida el repo del `cd`, no el de la sesión.
- **Caso feliz**: `cd` simple sin colisión, cwd de la sesión falla siempre — si el guard no hiciera el `cd`, bloquearía por "no pude detectar el repo"; en cambio continúa.
- **Repo indeterminable** (4 subcasos: ruta comillada, `$(...)`, dos `cd` encadenados, ruta inexistente) + un quinto test que confirma que el bloqueo no es casualidad de "offline": con un `gh` falso que SÍ resolvería `session/repo` de forma sana, el guard igual bloquea en vez de caer al fallback.

Los tests son black-box sobre el hook real (JSON por stdin, `gh` falso por `$PWD`/`FAKE_GH_MODE`, aserciones sobre el JSON de salida) — no reimplementan el parseo de `cd` ni la lógica de ventana del hook.

**2. Bash (`~/.claude/rules/bash.md`) — limpio, con una limitación no documentada (sugerencia, no bloqueante).**

- Quoting consistente: `"$LEADING_CD_TARGET"`, `cd -- "$LEADING_CD_TARGET"` (el `--` evita que un valor con `-` inicial se lea como opción de `cd`, y el allowlist de abajo de hecho permite `-`).
- Allowlist, no blocklist: `^[A-Za-z0-9._/-]+$` para el valor que llega a `cd`, con la razón escrita (evitar `$(...)`/backticks que sobreviven a `guard_sanitize` fuera de comillas).
- Sin `eval` ni ejecución de texto del comando interceptado para resolver el cwd — el `cd` corre en un subshell `$(...)` que no persiste sobre el resto del script.
- Fail-closed consistente con el resto del archivo: target vacío, charset fuera de allowlist, ambigüedad (segundo `cd`) y ruta que no resuelve, los cuatro bloquean con mensaje propio en vez de caer en silencio al comportamiento viejo — verificado empíricamente (punto 1).
- Mensajes de bloqueo explican la acción ("Usa --repo explícito.") en los 4 casos nuevos.
- `shellcheck hooks/pre-merge-check.sh`: los 4 avisos que emite (SC1091, SC2016, SC2181, SC2059) caen todos en líneas preexistentes fuera del diff; cero avisos nuevos en las líneas agregadas.
- Regex anclados a inicio de string a propósito (`^[[:space:]]*cd...`), no a `GUARD_ANCHOR` (posición de comando) — documentado como acotamiento deliberado al patrón del incidente, no una omisión.

**Gap real, no cubierto por los tests (sugerencia — ver detalle abajo):** `CD_STARTS_REGEX` exige un espacio o fin de string inmediatamente después de `cd`. Un `cd` bareado (sin argumento, va a `$HOME`) seguido *sin espacio* de un operador de control — `cd&&gh pr merge 45`, `cd;gh pr merge 45` — no matchea, así que el guard ni siquiera entra a la rama nueva y cae al fallback viejo (`gh repo view` en el cwd de la sesión) sin bloquear ni avisar. Reproducido:

```
$ echo '{"tool_input":{"command":"cd&&gh pr merge 45"}}' | bash hooks/pre-merge-check.sh
{"continue":true}
```

con un `gh` falso que resuelve `session/repo` — exactamente la clase de fallo del issue #72, alcanzable por una variante sintáctica sin espacio en vez de por `cd <ruta> &&`. Verificado que `cd /ruta&&gh pr merge 45` (sin espacio *antes* de `&&`, pero *con* argumento) sí se detecta bien — el hueco es específico al `cd` bareado.

No lo marco bloqueante: es más angosto que el patrón real del incidente (que siempre trae una ruta destino) y el propio archivo documenta que se acota a "el patrón real del incidente y el que este repo recomienda". Pero a diferencia de las demás limitaciones de este archivo (que sí llevan su comentario "Limitación aceptada: ..."), esta no está escrita en ningún lado — vale una línea de comentario o, mejor, extender `CD_STARTS_REGEX` a `cd([[:space:]]|[&;|]|$)` y dejar que el flujo existente de "target vacío" la bloquee igual que ya bloquea `cd && gh pr merge 45` (con espacio).

**3. Anti-drift — drift real encontrado, no reconciliado por este diff.**

El diff actualiza el conteo "cuatro PRs" → "cinco" en dos lugares (`rulebooks/orchestrator-runbook.md`: tabla + párrafo debajo, y `agents/security-reviewer.md:20`), y ambos quedan consistentes entre sí. Pero **`agents/qa-backend.md:45` describe el mismo hecho y no se tocó**:

> "Cuatro PRs seguidos violaron la regla que estaban escribiendo y las cuatro veces lo encontró un reviewer haciendo esto, nunca la autorrevisión del autor."

Es la misma cardinalidad del mismo hecho (paso 4 del DoD anti-drift) en un tercer archivo, ahora divergente: dos dicen "cinco", uno dice "cuatro". Grep confirmado: `grep -rn "cuatro PRs\|en cuatro\|las cuatro" --include="*.md" .` no devuelve más ocurrencias vivas del mismo hecho fuera de esta.

El commit `1f64d6f` documenta el grep que se corrió — "paso 2/3 del propio DoD anti-drift, grep de 'paso 4 del DoD' sin más ocurrencias vivas" — pero ese grep buscó la *etiqueta* ("paso 4 del DoD"), no el *término que cambió* (el conteo/"cuatro"), que es lo que el paso 1 del propio DoD pide: "Grep de los términos afectados [...] cualquier mención del comportamiento viejo es candidata a quedar desactualizada". `agents/qa-backend.md` no menciona "paso 4 del DoD" en ningún lado, así que el grep usado nunca lo iba a encontrar.

No aplica la exigencia especial de "releer el diff aplicando la regla nueva" (paso 4) porque este diff no introduce una regla nueva, solo corrige un conteo — pero sí aplica el criterio general de coherencia normativa de esta review, que es justo lo que el paso 1/2 del DoD pide y lo que el propio diff falló en completar.

**4. Fidelidad de la fila del PR #75 — verificada letra por letra contra `.planning/learnings/PR-75.md`.**

La columna "Lo que se escribía" ("El criterio de verificación visual, §5") corresponde al objetivo de ese PR. La columna "Lo que el review encontró" reproduce con fidelidad la sección "Qué causó re-work" de la retro:
- "afirmación sin verificar en el handoff... que `rules/implementation-principles.md` no tiene frontmatter `paths:` — sí lo tiene" ↔ retro: "El handoff a `qa-backend` decía que ese archivo de reglas no tiene `paths:` [...] Falso, y verificable con las primeras 23 líneas del archivo." — verifiqué el hecho de nuevo yo mismo: el archivo sí tiene `paths:` (línea 2).
- "exigencia incumplible... pedirle a `qa-frontend`, read-only y sin stack, que midiera el valor computado" ↔ retro ("Qué salió bien"): "La primera redacción exigía a `qa-frontend` cerrar el contraste con un valor computado en navegador, cuando ese agente nunca recibe un stack y es read-only por diseño."
- El párrafo bajo la tabla ("cada reviewer encontró, cada uno por su cuenta, una violación distinta") coincide con la retro: `security` encontró la exigencia incumplible leyendo el prompt, `qa-backend` encontró la afirmación sin verificar comprobando el frontmatter — dos hallazgos distintos, dos reviewers distintos.

Formato y voz consistentes con las filas #61/#64/#65/#66 (tres columnas, sin `|` sueltos que rompan la tabla). No hay reconstrucción de memoria: cada cita trae el detalle específico de la fuente (frontmatter `paths:`, "read-only y sin stack"), no una paráfrasis genérica.

**5. Issue #72 — resuelto en su totalidad.**

El issue pide, como remediación: (a) resolver el repo en el directorio del `cd` inicial, o (b) bloquear fail-closed pidiendo `--repo` cuando no se puede determinar con certeza. El diff implementa **ambas**: (a) como camino principal y (b) como fallback para todos los casos ambiguos (ruta comillada, `$(...)`, doble `cd`, ruta inexistente). El escenario de reproducción del issue (`cd ~/Proyectos/claude-methodology && gh pr merge 70 --merge` con PR homónimo en el repo de la sesión) es exactamente el que cubre el test "[incidente PR #75]". `--note` aparte: el `~` (home) queda deliberadamente fuera del allowlist y bloquea fail-closed en vez de expandirse — documentado en el propio hook, coherente con no ejecutar nada del comando para resolver el cwd.

### Contratos / Datos e integridad / Schemas / Migraciones

No aplica: no hay endpoints, DB, ni schemas en este diff — es un hook de shell y su suite de tests, más dos archivos normativos.

### Stub Detection / Implementation Principles

Limpio. Sin `TODO`/`FIXME` sin ticket, sin credenciales, sin código muerto. Scope quirúrgico: el diff toca únicamente la resolución del repo (el objetivo declarado en `.planning/BRIEF.md`), sin refactor colateral sobre el resto del hook (verificado: los únicos cambios fuera de las secciones nuevas son los dos comentarios que documentan el nuevo camino en el bloque de "Detectar owner/repo" preexistente).

### Self-reflection del dev

El commit `5232d0f` declara: "Self-review (rules/bash.md): quoting consistente, allowlist en vez de blocklist [...], sin eval [...], regex anclados sin cuantificadores anidados [...], sin dependencias nuevas." Verificado contra el diff: las cuatro afirmaciones se sostienen (punto 2 arriba). El commit `8f5960c` declara el conteo rojo→verde (7/8, 272→279) — verificado exacto en worktree (punto 1).

### Veredicto

- **CAMBIOS REQUERIDOS**

#### Bloqueantes (deben arreglarse)

- [ ] `agents/qa-backend.md:45` — drift de conteo: sigue diciendo "Cuatro PRs seguidos [...] las cuatro veces" mientras `rulebooks/orchestrator-runbook.md` (tabla + párrafo) y `agents/security-reviewer.md:20` ya dicen "cinco" para el mismo hecho (paso 4 del DoD anti-drift). El grep que declara el commit `1f64d6f` buscó la etiqueta "paso 4 del DoD" en vez del término que cambió ("cuatro"), y por eso no lo encontró. No aplica reasignar a `backend-dev`/`db-specialist` (no hay código de aplicación): reasignar a quien continúe este PR normativo — actualizar el número y, en la misma línea del patrón ya usado en `security-reviewer.md`, considerar reemplazar el detalle completo por un puntero a la tabla del runbook ("tabla completa en el runbook") en vez de repetirlo entero, coherente con el paso 3 del propio DoD ("enunciar una vez, remitir el resto").

#### Sugerencias (opcionales)

- [ ] `hooks/pre-merge-check.sh:438` (`CD_STARTS_REGEX`) — un `cd` bareado (sin argumento, va a `$HOME`) seguido sin espacio de un operador de control (`cd&&gh pr merge 45`, `cd;gh pr merge 45`) no matchea el regex de detección y cae al fallback viejo sin bloquear ni avisar — reproducido con `gh` falso, ver detalle en el punto 2. Más angosto que el patrón del incidente (que siempre trae una ruta), por eso no bloqueante, pero vale documentarlo como limitación aceptada (como el resto del archivo) o extender el regex a `cd([[:space:]]|[&;|]|$)`.
- [ ] `tests/adversarial/test-hooks.sh` — sin caso para `cd` con ruta relativa (`cd ../otro-repo && gh pr merge N`): el allowlist la permite y debería resolver bien contra el cwd de la sesión (igual que el comando real), pero no hay test que lo confirme.

### NO CUBIERTO

- No se auditó línea por línea el resto de la suite preexistente (~270 tests no tocados por este diff); solo se confirmó el conteo agregado (279/279) y se aisló el delta atribuible al fix (7 rojo + 1 verde esperado).
- No se revisaron issues de GitHub más allá del #72 pedido explícitamente.
- No se evaluó el impacto del gap de "cd bareado sin espacio" (sugerencia arriba) sobre los guards hermanos (`block-admin-merge.sh`, `pre-commit-guard.sh`) — no tocan esta lógica en este diff, fuera de scope.
- `.planning/state.json` y `.planning/BRIEF*.md` se leyeron solo como contexto; no se revisó su consistencia interna en detalle (no son documentos normativos que otro agente consuma como regla).
- No se corrió `tests/validation/` (el propio `BRIEF.md` aclara que no aplica a este cambio).

## Ronda 2 — HEAD 98a8cab (2026-09-16)

### QA Backend

**1. Cierre de la ronda 1 — los tres ítems cerrados, uno nuevo abierto por el propio cierre.**

- **Bloqueante `agents/qa-backend.md:45`: RESUELTO.** El commit `8668e31` saca el conteo de `agents/qa-backend.md` y de `agents/security-reviewer.md` (que decía "cinco", ya lo había corregido `1f64d6f` pero seguía repitiendo el número) y deja en ambos una remisión a la tabla del runbook — coherente con el paso 3 del propio DoD ("enunciar una vez, remitir el resto") que la ronda 1 ya había señalado como la solución preferible. Grep de verificación repetido (termino, no etiqueta): el conteo vive solo en `rulebooks/orchestrator-runbook.md:795` y `:805` (tabla + párrafo, internamente consistentes: 5 filas, "las primeras cuatro" se refiere a un subconjunto de esas 5, no es una cardinalidad divergente), más la mención no relacionada de `skills/pr-workflow/SKILL.md:21` ("cinco fases como cinco PRs", presupuesto de CI) que el propio commit `1f64d6f` ya había descartado como hecho distinto. Cero menciones vivas del conteo fuera del runbook.
- **Sugerencia del "cd" pegado a un operador de control sin espacio: RESUELTO.** `CD_STARTS_REGEX` ahora incluye `[&;|]` después de `cd`, así que la forma sin espacio entra a la rama de detección; como no hay ruta clara (`CD_TARGET_REGEX` exige un espacio real, no un operador pegado), cae en `LEADING_CD_TARGET` vacío y bloquea explícitamente ("no pude extraer una ruta clara") en vez de colar en silencio al fallback viejo. Reproducido en worktree: ambos casos bloquean. Test nuevo en `tests/adversarial/test-hooks.sh` (línea ~2457-2460).
- **Sugerencia de ruta relativa: RESUELTO, y ahora bloquea de verdad.** `LEADING_CD_ABSOLUTE` rechaza cualquier `LEADING_CD_TARGET` que no empiece con `/`. Reproducido: una ruta relativa antes del merge bloquea con "no es absoluta". Test nuevo en `tests/adversarial/test-hooks.sh` (línea ~2461-2462) — cierra también la sugerencia de test faltante de la ronda 1.

Hallazgo nuevo (no bloqueante de ronda 1, aparece en el propio commit de docs): incoherencia README.md / global/CLAUDE.md — ver sección "Docs" abajo, bloqueante nuevo.

**2. Tests nuevos — rojo/verde reproducido exacto, marcador verificado, gap combinado confirmado como solo-test.**

Worktree desechable en `98a8cab` (eliminado al terminar):
- Hook + tests de HEAD: **306/306** verde.
- Hook de `8bfdb59` (revertido, tests de HEAD intactos): **278 pass / 28 fail**, exactamente el número que declara el dev. Restaurado el hook a HEAD antes de seguir.
- **Marcador de archivo, verificado que prueba lo que dice.** Los 4 tests de `-R`/`--repo` intercalado usan una función custom que no solo mira el JSON de continuación sino que exige el marcador `checks.ran` escrito por el binario falso dentro de su rama de "pr checks". Corridos contra el hook de `8bfdb59`: los 4 dan continuación sin el marcador — confirma que el hook viejo deja pasar estas formas intercaladas **sin consultar nada del binario real** (bypass ciego, no "consultó y aprobó"). Sin el marcador este test pasaría contra el hook viejo con el mismo JSON final — exactamente la trampa que describe el corolario del principio 5, y el propio mensaje de commit lo declara así. El marcador prueba lo que dice.
- **Test reescrito "dos invocaciones... gana la primera" -> ahora bloquea: legítimo, no ablandado.** Es un endurecimiento: el comportamiento viejo (validar solo la ventana de la izquierda y dejar la segunda invocación sin verificar) se reemplaza por un bloqueo fail-closed cuando hay más de una invocación real en el comando — verificado en el hook que el chequeo corre ANTES de cualquier consulta al binario, y el binario falso del test sale con error ante cualquier subcomando para detectarlo si no fuera así. Coincide con D-03 en `.planning/BRIEF.md` (merges múltiples listado explícitamente). No es un test suavizado para pasar: la nueva expectativa es estrictamente más segura que la vieja.
- **Filas de la tabla de security (ronda 1), todas con fila de test:** los tres HIGH/MEDIUM de la extracción del cd inicial (separadores sueltos, comilla/backslash a mitad de ruta, salto de línea, envoltorios que no arrancan con la palabra cd, dos argumentos de zsh, subshell/llaves/comando previo), el LOW de ruta relativa, y los dos legacy (flag de repo intercalado en dos posiciones + variable de entorno como prefijo de comando, y esa misma variable ignorada por la resolución sin --repo en 4 variantes: comando, export, con --repo explícito presente, y en el entorno del propio proceso). No falta ninguna fila de la tabla de security ronda 1.
- **Hueco combinado (flag de repo intercalado + cd inicial): confirmado que es solo falta de test, no falta de comportamiento.** Reproducido a mano en worktree con el binario falso distinguiendo por directorio de trabajo (dos repos git desechables): la combinación resuelve correctamente contra el repo del flag explícito (el flag explícito gana sin importar el cd, confirmado por el propio código y por la corrida empírica). Sugerencia, no bloqueante — coincide con la autoevaluación del dev.

**3. Bash (regla de estilo de shell) sobre las +283 líneas del hook — limpio salvo el hallazgo de honestidad del punto 4.**

- Quoting consistente en todo lo nuevo.
- Allowlist de caracteres para la ruta del cd: sin cambios respecto a ronda 1, sigue sin blocklist.
- Status code capturado en la línea inmediatamente siguiente en el código nuevo/tocado (ambas asignaciones preexistentes e intactas — no se introdujo una captura tardía nueva).
- Sin `eval` real ni ejecución de texto del comando interceptado — las apariciones de la palabra "eval" en el diff son texto de patrón (parte de la lista de palabras que el guard busca, no ejecución) o prosa de comentario.
- Regex nuevas sin cuantificadores anidados sobre texto solapado — cuantificadores acotados, sin backtracking catastrófico.
- Análisis estático del hook: los mismos 4 avisos de la ronda 1 (fuente no seguida, expresión en comillas simples, chequeo indirecto de status, variable en formato de printf) — los 4 caen fuera de los rangos de los hunks del diff. Cero avisos nuevos.
- Mensajes de bloqueo nuevos son todos accionables (piden usar el flag de repo explícito, o quitar la variable de entorno).
- Verificado contra el binario real (no solo confiado en el comentario): el flag de repo es en efecto persistente en el subcomando de PRs, válido antes y después del subcomando; y la resolución sin flag explícito en efecto ignora esa variable de entorno mientras el subcomando de PRs sí la respeta — las dos afirmaciones del header que sostienen el fix se sostienen contra el binario real, no solo contra el comentario.

**4. Honestidad del código (paragrafo 5 de implementation-principles) — un hallazgo real, nuevo, en el propio header del hook.**

- **La "Limitación aceptada" del nombre del builtin entre comillas está escrita con precisión.** Verificado en worktree: el saneo colapsa el span entrecomillado (comillas incluidas) a espacios, así que el regex de arranque no matchea y el comando cae a la rama que busca envoltorios conocidos, donde el prefijo saneado (solo espacios y la ruta) tampoco matchea porque la palabra ya no está en el texto saneado. Reproducido end-to-end con el binario falso distinguiendo por directorio (dos repos desechables): el caso corriendo desde el repo de sesión resuelve contra ESE repo de sesión (confirmado con un marcador de archivo que registra qué repo consultó), exactamente el hueco que el comentario describe. La explicación técnica es correcta y verificable, no una afirmación de memoria.
- **Pero esa misma limitación contradice, sin reconciliarla, la garantía absoluta que promete el header del punto 7, unas 500 líneas más arriba.** El header dice, en sustancia, que la ÚNICA forma aceptada antes del merge sin flag explícito es "nada" o exactamente "cd más ruta absoluta más el operador de éxito", que "cualquier otra cosa... bloquea", y que "no se enumera qué envoltorios están prohibidos". Esto es falso tal como está escrito: el caso del nombre entrecomillado (documentado 500 líneas más abajo) es precisamente un prefijo que no es "nada" en el sentido de que el shell real sí cambiaría de directorio, y no bloquea — cae en silencio a la rama de "nada" porque sí se enumeran los envoltorios prohibidos (una lista fija de palabras) y ese envoltorio en particular no aparece en la lista tras el saneo. La propia rama que hace esa detección hasta se contradice a sí misma en el mismo bloque de comentarios: dice que en vez de enumerar cada forma de invocar el builtin se busca cualquiera de un set de palabras — "buscar cualquiera de estas palabras" es enumerar. La regla de bash de este repo nombra exactamente este patrón como red flag: un comentario que afirma una garantía absoluta se escribe como inventario de lo verificado, no como absoluto. El header hace esa afirmación absoluta sobre un mecanismo que el propio archivo, más abajo, documenta como no cubierto. El gap en sí es angosto y ya está aceptado (comillar un builtin no tiene uso legítimo conocido) — el problema es que el resumen ejecutivo del header promete más de lo que el detalle entrega, y un lector que solo lea el header se queda con una garantía que no existe.
  - Reasignar a quien continúe este PR normativo/de hook. Fix quirúrgico: acotar la frase del header (reemplazar la afirmación de "no se enumera" por algo como "se reconoce un conjunto verificado de envoltorios que cambian de directorio; un envoltorio con el nombre del builtin entre comillas no se detecta, ver la limitación aceptada más abajo") o simplemente agregar un puntero desde el header hacia esa limitación en vez de afirmar cobertura total.
- El resto de comentarios nuevos (variable de entorno, forma exacta del cd, merges múltiples, flag intercalado) están calificados con verificaciones concretas contra el binario real y no prometen nada que un test no ejerza — cada uno tiene su fila de test confirmada en el punto 2.

**5. Docs (`98a8cab`) — un hallazgo nuevo de coherencia.**

- **`README.md:34` es preciso**: menciona las dos formas aceptadas (flag de repo explícito y cd con ruta absoluta) y dice que cualquier otro prefijo, la variable de entorno mencionada, o más de un merge en el mismo comando bloquea — coherente con el hook.
- **`global/CLAUDE.md:158` NO es coherente con `README.md:34` ni con el hook.** Dice, en sustancia, que para mergear un PR de otro repo se usa el flag explícito y que cualquier otro prefijo o forma no estándar bloquea. Esto omite por completo la forma de cd con ruta absoluta, que es la otra mitad de la allowlist y que el propio hook (y README.md) tratan como legítima. Leído literalmente, "cualquier otro prefijo... bloquea" implica que esa forma de cd también bloquearía — falso, es exactamente la forma que el fix de esta ronda existe para soportar. El commit `98a8cab` es transparente sobre la asimetría en su propio mensaje, pero eso confirma la incoherencia en vez de justificarla: no hay razón declarada para que el núcleo (que se carga en toda sesión) prometa menos de lo que el hook realmente permite, y la redacción actual no remite a la otra fuente, la contradice.
  - Reasignar a quien continúe este PR. Fix quirúrgico: alinear `global/CLAUDE.md:158` con `README.md:34` (mencionar la forma de cd como válida) o, si se prefiere mantener el núcleo corto, reformular para no contradecir la excepción documentada.
- Ningún archivo duplica el detalle del header (variable de entorno, merges múltiples, flag intercalado, por qué cada forma se rechaza) — confirmado, el propio commit lo declara y el grep no encontró contenido de ese nivel fuera del hook.
- Grep de comportamiento viejo en rulebooks/, skills/, rules/ y agents/: ninguna mención describe semántica de resolución de repo desactualizada (todas las menciones son sobre el flujo de merge en sí, no sobre cómo el hook resuelve el repo). El grep del flag de repo solo da falsos positivos de una palabra no relacionada en un archivo de agente.

### Veredicto

**CAMBIOS REQUERIDOS**

#### Bloqueantes

- [ ] `hooks/pre-merge-check.sh`, header punto 7 (líneas ~101-114) — la garantía absoluta ("la ÚNICA forma aceptada... cualquier otra cosa... bloquea", "no se enumera qué envoltorios están prohibidos") es falsa frente al propio código: la rama que detecta envoltorios que no arrancan el comando es una enumeración de palabras, y el caso del nombre del builtin entre comillas, documentado más abajo como "Limitación aceptada", cae en silencio a la resolución por defecto sin bloquear — exactamente lo que el header dice que no puede pasar. Coincide con el red flag explícito de la regla de bash de este repo sobre garantías absolutas. Reasignar a quien continúe este PR: acotar la frase del header o agregar el puntero a la limitación aceptada.
- [ ] `global/CLAUDE.md:158` — incoherente con `README.md:34` y con el hook: omite la forma de cd con ruta absoluta como válida y dice que cualquier otro prefijo bloquea, lo que implica (falsamente) que esa forma también bloquearía. Reasignar a quien continúe este PR: alinear la frase con `README.md:34` o reformularla para no contradecir la excepción documentada.

#### Sugerencias (opcionales)

- [ ] `tests/adversarial/test-hooks.sh` — sin test combinado de flag de repo intercalado + cd inicial en el mismo comando. Verificado a mano en worktree que el comportamiento es correcto (el flag explícito gana sin importar el cd), así que es puramente un hueco de cobertura de test, no de comportamiento — mismo hueco que el propio dev reconoce.

### NO CUBIERTO

- No se re-auditó línea por línea el resto de la suite preexistente de la ronda 1 (~279 tests); solo se verificó el conteo agregado (306/306) y se aisló el delta atribuible a esta ronda (278 pass / 28 fail contra el hook de `8bfdb59`).
- El caso del builtin con nombre entrecomillado y el caso de una invocación indirecta (script fuente que cambiaría de directorio) se verificaron a mano en un worktree desechable con binario falso y repos git desechables, sin dejar un test nuevo (no es mi rol escribirlo).
- No se re-evaluó la severidad de seguridad de ningún hallazgo — corresponde a la ronda 2 de security-reviewer, que corre en paralelo sobre el mismo diff.
- No se corrió la validación estricta del manifiesto del plugin — el archivo de registro de hooks no cambió en este delta, y la ronda 1 ya lo había corrido sobre el estado anterior.
- No se revisó `.planning/state.json` ni `.planning/BRIEF.md` más allá de la cita de la decisión D-03 usada para validar el alcance de "merges múltiples" y los dos huecos legacy.
