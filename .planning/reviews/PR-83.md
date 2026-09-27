# Review dual pre-push: issue #78 (hooks duplicados en settings.json)

- **Branch:** `fix/settings-duplicate-hooks` · **Base:** `dev` · **Fecha:** 2026-09-26

## Ronda 1: HEAD `abae30f`

**Veredicto consolidado:** APROBADO.

### security-reviewer (opus): APROBADO
- Comparación uno a uno: los 14 hooks del bloque borrado están en `hooks/hooks.json` con el mismo evento y matcher, y ninguno existía solo en settings.
- Prueba de que el plugin carga los hooks: en `~/.claude/methodology/logs/subagent-invocations.jsonl`, cada SubagentStop de la sesión aparecía dos veces hasta que se quitó el bloque; desde entonces aparece una.
- **[LOW]** Los guards de PreToolUse ya no corren sin el filtro `if` en este repo. Las formas disfrazadas (`env git`, `/usr/bin/git`) podrían no llegar al script. → pasa a #77.
- **[LOW]** Un colaborador sin el plugin queda sin guards y no estaba escrito como requisito. → aplicado en `ba46249` (`.claude/CLAUDE.md`, "Desarrollo del plugin").

### qa-backend: APROBADO
- `permissions` idéntico. El test nuevo falla si vuelve `hooks` o si cambia `permissions` (verificado en un worktree desechable). La documentación ya era consistente. Suites 107/358/159.

`docs` se saltó: la revisión de documentación fue la tarea 3 del lote y no requirió cambios.

## Cierre

**Veredicto final:** APROBADO. HEAD `ba46249`.
