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
