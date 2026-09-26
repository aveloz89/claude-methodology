## Brief: audit-best-practices

### Objetivo
Alinear la metodología con las prácticas oficiales de Anthropic, según la auditoría `AUDIT-best-practices-2026-09.md`. Se busca bajar el contexto que carga cada subagente, corregir defectos técnicos del plugin y los hooks, y reducir el overhead multi-agente donde no aporta.

### Alcance
- Incluye:
  1. **Dividir el rol de orchestrator.** En `global/CLAUDE.md` queda una regla corta, siempre cargada: la sesión principal coordina y delega, no escribe código; los subagentes implementan lo que se les asigna. Se redacta para que ningún dev la lea como prohibición propia. El manual detallado (tabla de agentes, fases 0-5, lotes, tracker, degradación de modelo) pasa a una skill `orchestrator` cargada bajo demanda al iniciar trabajo de feature o fix. `CLAUDE.md` dice cuándo cargarla y el hook de sesión lo recuerda para evitar olvidos.
  2. Dejar en `global/CLAUDE.md` solo lo que aplica siempre y a todos (idioma, gitflow, formato de commits, TDD, invariantes de merge, reglas operativas). Objetivo: bajar sustancialmente de los 20.963 bytes actuales, medido.
  3. Fixes técnicos de la auditoría: `memory: true` → `project`; quitar `permissionMode` ignorado; `maxTurns` (y `effort` si aplica) o corregir `agent-budget.md`; migrar los hooks del `decision: block` deprecado; `pre-commit-guard` fail-closed ante timeout; matcher de SessionStart `startup|resume|clear|compact`; `if` en hooks Bash como optimización; `disable-model-invocation` en skills con efectos secundarios; corregir la validación del plugin (`plugin.json`, advertencia del CLAUDE.md raíz) y la instrucción en `CLAUDE.md` del repo; corregir el texto "Corren en background" del pre-commit.
  4. **Evaluar y ejecutar fusión de agentes** donde la guía "dividir por límites de contexto" lo justifique. Candidatos: `docs`, `build-resolver`, `db-specialist` vs `backend-dev`, ui-ux + architect en UI chica. El architect decide con argumentos y el usuario aprueba en el diseño.
  5. Bajar el tono agresivo (mayúsculas, "NUNCA", negritas en exceso) en los archivos que se toquen, dejando el énfasis para las 2-3 reglas que lo ameritan.
- NO incluye:
  - El agente de producto/PM: va en un feature y PR aparte, después de este.
  - Los issues abiertos #71, #73, #77.
  - Agent Teams.

### Usuarios y permisos
El usuario de la metodología (autor y terceros que instalan el plugin). Terceros reciben los cambios por plugin + `install.sh`; la skill nueva se distribuye por plugin.

### Flujo principal
1. El usuario abre sesión. `CLAUDE.md` corto y el hook de inicio fijan el rol del orchestrator y recuerdan cargar la skill.
2. Al iniciar una feature o fix, el orchestrator carga la skill `orchestrator` y sigue las fases.
3. Los subagentes cargan solo el `CLAUDE.md` corto + su prompt + lo que les pasa el handoff.

### Reglas de negocio
- Las invariantes (merge con aprobación explícita, CI verde, review dual bloqueante, gitflow) siguen siempre cargadas; no se mueven a la skill.
- Toda afirmación sobre el comportamiento de la plataforma se verifica ejecutándola; si no se puede, se escribe como no verificada.

### Edge cases discutidos
- Que el orchestrator olvide cargar la skill: mitigado por la línea en `CLAUDE.md` + el recordatorio del hook. Si al delegar nota que no la tiene, la carga.
- La doc dice que el `additionalContext` de SessionStart también llega a los subagentes. El recordatorio del hook debe ser corto y no contradecir el rol de los subagentes. **Verificar con prueba real.**
- Instalaciones existentes: `install.sh` copia `global/CLAUDE.md`; el cambio llega al reinstalar.
- Referencias cruzadas: rulebooks, agentes y skills que apunten a secciones de `CLAUDE.md` que se mueven deben actualizarse (DoD anti-drift, `orchestrator-runbook.md`).

### Decisiones tomadas
- [D-01] (usuario) Atacar la auditoría antes que el agente PM, para que el PM nazca con frontmatter y tono corregidos.
- [D-02] (usuario) Incluir la división de `CLAUDE.md` y la fusión de agentes en este trabajo.
- [D-03] (usuario) Opción 1: rol corto siempre cargado en `CLAUDE.md` + manual como skill `orchestrator` bajo demanda + recordatorio del hook de sesión.

### Descartado explícitamente
- **Agente principal vía `agent`/`--agent`:** reemplaza todo el system prompt de Claude Code y requiere configuración por proyecto; la doc no muestra que un plugin pueda activarlo.
- **`omitClaudeMd` en subagentes:** también les quita el `CLAUDE.md` del proyecto (comandos de test, stack).
- **Inyectar el manual por SessionStart:** según la doc llega a los subagentes, así que no ahorra nada.
