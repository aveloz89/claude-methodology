# Adversarial Tests

Tests que validan que la metodología misma funciona correctamente.

## Estructura

| Archivo | Qué valida |
|---------|-----------|
| `test-hooks.sh` | Los hooks de Claude Code bloquean comandos peligrosos |
| `test-qa-detection.md` | El QA agent detecta code smells, stubs y red flags |
| `test-security-detection.md` | El security-reviewer detecta vulnerabilidades conocidas |

## Cómo ejecutar

### Hook tests (automatizado)

```bash
cd /path/to/project
bash tests/adversarial/test-hooks.sh
```

### QA / Security detection tests (manual)

1. Crear un PR temporal con los fixtures del archivo `.md`
2. Invocar al agente correspondiente (QA o security-reviewer)
3. Comparar hallazgos vs "Expected findings" del fixture
4. Si el agente no detecta un problema esperado, ajustar su prompt

## Cuándo ejecutar

- Antes de releases
- Después de modificar prompts de agentes (`agents/*.md`)
- Después de modificar hooks (`hooks/*.sh`)
- Después de modificar rules (`rules/*.md`)
- Periódicamente (mensual) como parte de la validación de agentes
