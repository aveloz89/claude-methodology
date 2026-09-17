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
