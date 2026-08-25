# Follow-ups

Ideas, mejoras y pendientes que surgieron durante el trabajo pero no son urgentes ni están listos para ser issues.
Cuando algo madure, se promueve a GitHub Issue y se borra de aquí.

## Formato

```
### [Fecha] Descripción corta
Contexto de dónde surgió y por qué importa.
Origen: [conversación / PR #N / sweep / QA review]
```

## Pendientes

### [2026-08-25] `qa-backend` cambia de criterio de scope entre rondas del mismo PR
Ante diffs 100% de documentación normativa, acepta el encuadre "los documentos normativos son el contrato" en una ronda y devuelve N/A en la siguiente. Pasó en el PR #59 (ronda 2), y en el #63 tras haber aceptado el encuadre en la ronda 1 de ese mismo PR. Consecuencia: sus bloqueantes quedan sin re-verificar por un reviewer independiente y los verifica el orchestrator, que es quien escribió el cambio. Opciones: fijar el criterio en el prompt de `qa-backend`, o definir a quién le corresponde revisar cambios de metodología.
Origen: retro PR #60, review PR #63

### [2026-08-25] Entrada literal de `workspaces` no verifica que exista `package.json`
`hooks/lib/workspace-scope.sh:145` — la rama de entrada literal hace `_WS_DIRS+=("$glob")` sin chequear `-f "$glob/package.json"`, a diferencia de la rama de glob, que sí lo hace. Con el match por igualdad exacta agregado en el PR #58, un workspace declarado pero inexistente podría scopear a un `-w` inválido y hacer que npm salga con error. Es fail-closed (bloquea el commit, nunca corre de menos) y requiere un `package.json` mal declarado.
Origen: review del PR #58, ronda 3 (observación fuera del delta)

### [2026-08-25] Faltan dos de las cuatro etiquetas que lee el agente `refactor`
El repo tenía `latent-bug`, `security` y `stale-docs`, pero no `legacy-violation` ni `scoped-out-violation`. `gh issue create` **falla el comando entero** con una etiqueta inexistente, así que hasta hoy cualquier derivación de deuda al refactor se caía en silencio salvo que fuera `latent-bug`. Se creó `legacy-violation` a mano para el issue #62; falta `scoped-out-violation`. Revisar además si el skill `new-project` las crea al hacer scaffold — si no, todo proyecto nuevo nace con el mismo hueco.
Origen: intento de crear el issue #62

### [2026-08-25] `grep` ausente del check de dependencias de `pre-merge-check.sh`
El hook verifica `perl` y `jq` al inicio y sale fail-closed si faltan, pero no `grep`. Sin `grep` en el PATH, el gate nuevo del PR #60 deja pasar un `gh pr merge` real donde antes bloqueaba. Impacto bajo y derivado a otro PR por el propio security-reviewer: el camino dominante del guard (`:119`) también depende de `grep`, así que esto extiende un fail-open preexistente en vez de crear uno nuevo.
Origen: review dual del PR #60, ronda 3

### [2026-08-25] La suite adversarial no ejercita a los guards con entrada hostil
128 tests en verde mientras `guard_sanitize` se colgaba indefinidamente con un heredoc sin terminador. La suite prueba QUÉ bloquean los guards, no cómo se comportan cuando el input está diseñado para romperlos. El PR #60 agrega los primeros casos de esa clase para heredocs; falta el resto de la superficie (spans quoted, continuaciones de línea, tamaño).
Origen: retro PR #60

### [2026-08-25] Criterio "el test debe romperse si borras el fix"
Cazó un bloqueante que dos rondas de lectura no vieron: un test de regresión que reimplementaba el código que decía proteger y seguía en verde con el fix borrado. Es mecánico y verificable — candidato a regla en `rules/` o al prompt de los agentes QA, como paso obligatorio antes de declarar cubierto un fix.
Origen: retro PR #60, review de qa-backend ronda 2

### [2026-08-24] Escribir la regla de "verificar contra el sistema real antes de afirmar"
La regla de 3 se dio por alcanzada en el PR #55 con propuesta concreta (agregarla a `rules/implementation-principles.md` o al prompt del architect) y nunca se implementó: el grep confirma que no existe. El PR #59 es la 4ª aparición del mismo patrón — afirmé el comportamiento de `post-pr-create.sh` sin leer el hook. Registrar el patrón no lo corrige.
Origen: retro PR #59 (LEARNINGS), regla de 3 del PR #55

### [2026-08-24] Filtro de CI "diff sin código → sin suites"
Contraparte de la regla 5.7: mientras el workflow corra las suites para cualquier diff, el push de la retro cuesta un run completo. En easy-quotes el job `changes` tiene un default seguro ("algo fuera de `frontend/`/`backend/` → correr todo") que hace que un diff solo-`.planning/` dispare backend, frontend, docker-prod y core-isolation. El job agregador `ci` ya existe, así que branch protection no se rompe al saltar las suites. `hooks/lib/workspace-scope.sh` calca la misma regla conservadora: el commit de retro también corre la suite local completa.
Origen: PR #179 de easy-quotes (7m23s por 47 líneas de markdown), PR #59

### [2026-08-24] `pre-merge-check.sh` no honra `--repo`
El guard detecta el repo con `gh repo view` sobre el cwd de la sesión e ignora el `--repo` del comando interceptado, así que `gh pr merge <N> --repo otro/repo` siempre sale bloqueado fail-closed (`gh pr view <N>` falla porque el PR no existe en el repo local). Hacer `cd` no ayuda: el hook corre en la raíz de la sesión. Cross-repo merge es imposible desde una sesión de otro proyecto.
Origen: intento de mergear el PR #179 de easy-quotes desde claude-methodology

### [2026-08-24] `.planning/` falta en el grep del DoD anti-drift
El DoD de cambios de proceso lista `CLAUDE.md`, `README.md`, `rulebooks/`, `agents/` y `skills/`. `.planning/LEARNINGS.md` tiene su propio preámbulo normativo ("Retrospectivas post-merge") que quedó desactualizado por el PR #59 y ningún reviewer lo vio: está fuera de la lista.
Origen: retro PR #59

### [2026-08-13] Vigilar Agent Teams (no adoptar mientras sea experimental)
Anthropic nativizó nuestro patrón orchestrator+workers como feature experimental (flag `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`). Limitaciones actuales: sin `/resume`, task status con lag, reportes de mensajes perdidos entre teammates. Reevaluar cuando salga de experimental — parte del valor del runbook casero podría migrar al harness.
Origen: AUDIT-memory-agents-2026-08.md, plan de acción #9
