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

### [2026-08-13] Vigilar Agent Teams (no adoptar mientras sea experimental)
Anthropic nativizó nuestro patrón orchestrator+workers como feature experimental (flag `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`). Limitaciones actuales: sin `/resume`, task status con lag, reportes de mensajes perdidos entre teammates. Reevaluar cuando salga de experimental — parte del valor del runbook casero podría migrar al harness.
Origen: AUDIT-memory-agents-2026-08.md, plan de acción #9
