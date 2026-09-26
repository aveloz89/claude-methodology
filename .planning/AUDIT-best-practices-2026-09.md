# Auditoría vs. prácticas oficiales de Anthropic — 2026-09

**Fecha:** 2026-09-26
**Método:** subagente auditor de solo lectura, que contrastó cada práctica con la documentación oficial vía WebFetch. El orchestrator re-verificó en el repo los hallazgos marcados con ✔.

## Fuentes
- https://code.claude.com/docs/en/best-practices.md
- https://code.claude.com/docs/en/sub-agents.md
- https://code.claude.com/docs/en/skills.md
- https://code.claude.com/docs/en/hooks.md
- https://code.claude.com/docs/en/memory.md
- https://code.claude.com/docs/en/plugins-reference.md
- https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices
- https://claude.com/blog/building-multi-agent-systems-when-and-how-to-use-them

## Hallazgos

| Sev. | Hallazgo | Práctica oficial | Recomendación |
|---|---|---|---|
| Alta | ✔ `global/CLAUDE.md` (20.963 bytes, ~6k tokens estimados) se carga en **todos** los subagentes. Su regla "NUNCA escribes código" (l.14-16) choca con el rol de los devs. | sub-agents: todo subagente custom carga CLAUDE.md salvo `omitClaudeMd`. memory: "target under 200 lines… Longer files… reduce adherence". | Dividir: rol corto en CLAUDE.md y manual del orchestrator en una skill (ver BRIEF). |
| Alta | ✔ `claude plugin validate --strict .claude-plugin/plugin.json` falla por "CLAUDE.md at the plugin root is not loaded as project context". `validate --strict .` pasa, pero solo valida `marketplace.json`. El `CLAUDE.md` del repo instruye usar la forma que no valida el plugin. | plugins-reference: `--strict` convierte warnings en fallos. | Que la validación documentada cubra `plugin.json` y resolver o aceptar formalmente la advertencia. |
| Alta | ✔ `block-admin-merge.sh`, `block-force-push.sh`, `block-hard-reset.sh` y `pre-merge-check.sh` bloquean con `{"decision":"block"}` a nivel raíz en PreToolUse. | hooks: esa forma está deprecada en PreToolUse. Usar `hookSpecificOutput.permissionDecision: "deny"` + `permissionDecisionReason`, o `exit 2` + stderr. | Migrar. |
| Media | ✔ `agents/e2e-runner.md:6` tiene `memory: true`, un valor inválido (acepta `user`/`project`/`local`). Viene de la recomendación de `AUDIT-memory-agents-2026-08.md:48`. | sub-agents | `memory: project`. |
| Media | ✔ `permissionMode: plan` en `security-reviewer.md` y `latent-bugs-sweep.md` se ignora en agentes de plugin. | sub-agents: plugin subagents no soportan `hooks`, `mcpServers`, `permissionMode` | Quitarlo; la restricción real es `tools`/`disallowedTools`. |
| Media | Ningún agente define `maxTurns`, pero `rulebooks/agent-budget.md:3` lo menciona. | sub-agents: `maxTurns` corta y marca el output como parcial | Definir `maxTurns` (y evaluar `effort`) o corregir el rulebook. |
| Media | `pre-commit-guard` tiene timeout de 120 s en `hooks.json`. Si la suite tarda más, el commit pasa sin tests. | hooks: en PreToolUse un hook con timeout no bloquea | Fail-closed dentro del script o subir el timeout; documentar. |
| Media | Los 7 hooks PreToolUse `matcher: "Bash"` corren en todo comando Bash. | hooks: campo `if` (p. ej. `"Bash(git *)"`), best-effort | Agregar `if` como optimización de latencia, no como control. |
| Media | 13 agentes divididos por fase. Estimado de overhead fijo: 90–120k tokens por feature de 2 lotes (sin medir). | blog multi-agent: dividir por límites de contexto, no por tipo de problema; multi-agente cuesta 3-10x tokens | Evaluar fusiones: `docs`, `build-resolver`, `db-specialist` vs `backend-dev`, ui-ux+architect en UI chica. Los reviewers sí encajan (patrón de verificación). |
| Media | Ninguna skill usa `disable-model-invocation`; `new-project` y `refactor-scan` tienen efectos secundarios. | skills: usarlo en workflows con side effects | Agregarlo donde aplique; `pr-workflow` debe seguir siendo invocable por el modelo. |
| Baja | ✔ `SessionStart` con `matcher: "startup"` (`hooks.json:69`): no reinyecta contexto ni detecta `HANDOFF.md` en `resume`/`clear`/`compact`. | hooks: matchers `startup\|resume\|clear\|compact` | Ampliar el matcher. |
| Baja | `global/CLAUDE.md:160` pone "tests antes de cada commit" bajo "Corren en background", pero `pre-commit-guard` bloquea de forma síncrona. | — | Corregir el texto. |
| Baja | Tono: ~161 "NO", 23 "NUNCA", 16 "BLOQUEANTE" y ~150 negritas en CLAUDE.md. Peores casos: `build-resolver.md:154-171` y `latent-bugs-sweep.md`. | prompting: bajar el lenguaje agresivo, explicar el porqué; "if you emphasize many lines, none stands out" | Reservar el énfasis para 2-3 reglas. |
| Baja | Las `description` de devs y QA son genéricas. | sub-agents: la description decide la delegación | Poner el disparador en la primera frase. |

## Bien alineado
`rules/` con `paths:`; rulebooks bajo demanda; SKILL.md < 500 líneas; reviewers de solo lectura por `tools`; reglas deterministas en hooks fail-closed; review en contexto fresco; brainstorming con AskUserQuestion; `${CLAUDE_PLUGIN_ROOT}` y test de paridad.

## No verificado
- Si `Agent(security-reviewer)` en `allowed-tools` de skills matchea el agente de plugin `methodology:security-reviewer`.
- Tokens reales por invocación (las cifras son bytes/3,5).
- Si el `additionalContext` del hook SessionStart llega a los subagentes. La doc de hooks dice que sí ("applies to subagents as well as the main session"); no se probó.
- Duración real de las suites frente al timeout de 120 s.
