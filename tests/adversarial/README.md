# Adversarial Tests

Tests que validan que la metodología misma funciona correctamente.

## Estructura

| Archivo | Qué valida |
|---------|-----------|
| `test-hooks.sh` | Los hooks de Claude Code bloquean comandos peligrosos — incluye regresión del matching compartido en `hooks/lib/guard-matching.sh` (comandos compuestos, menciones quoted/heredoc, fallback sin `perl`/`jq`) —, los hooks de observabilidad (`pre-compact-snapshot`, `subagent-stop-log`, `session-end-check`) producen el efecto esperado en filesystem sin bloquear el evento, `session-start-context.sh` sanitiza datos de terceros (títulos de issues), y `.gitignore` cubre los patrones de secrets defensivos |
| `test-qa-detection.md` | Los QA agents (qa-frontend / qa-backend) detectan code smells, stubs y red flags en su capa |
| `test-security-detection.md` | El security-reviewer detecta vulnerabilidades conocidas |

## Cómo ejecutar

### Hook tests (automatizado)

```bash
cd /path/to/project
bash tests/adversarial/test-hooks.sh
```

### QA / Security detection tests (manual)

1. Crear un PR temporal con los fixtures del archivo `.md`
2. Invocar al agente correspondiente:
   - Fixtures Python (1, 2, 3) → `qa-backend`
   - Fixture TypeScript (4) → `qa-frontend` si el fixture está en ruta de UI, `qa-backend` si está en ruta de servidor (Node)
   - Fixtures de seguridad → `security-reviewer`
3. Comparar hallazgos vs "Expected findings" del fixture
4. Si el agente no detecta un problema esperado, ajustar su prompt

## Cuándo ejecutar

- Antes de releases
- Después de modificar prompts de agentes (`agents/*.md`)
- Después de modificar hooks (`hooks/*.sh`)
- Después de modificar rules (`rules/*.md`)
- Periódicamente (mensual) como parte de la validación de agentes
