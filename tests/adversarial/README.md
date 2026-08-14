# Adversarial Tests

Tests que validan que la metodología misma funciona correctamente.

## Estructura

| Archivo | Qué valida |
|---------|-----------|
| `test-hooks.sh` | Los hooks de Claude Code bloquean comandos peligrosos — incluye regresión del matching compartido en `hooks/lib/guard-matching.sh` (comandos compuestos, menciones quoted/heredoc, fallback sin `perl`/`jq`) —, los hooks de observabilidad (`pre-compact-snapshot`, `subagent-stop-log`, `session-end-check`) producen el efecto esperado en filesystem sin bloquear el evento, el checkpoint `post-pr-create` (v2) distingue contra `state.json` el PR ya revisado pre-push (CASO A: fase + branch + `review_sha` ancestro de HEAD con delta post-review solo-`.planning/` — reconciliación, sin relanzar reviewers) del PR fuera del flujo (CASO B: instruir review dual — incluye fallar hacia el review con state ausente, incompleto, de otro branch, malformado, sin anclaje al SHA revisado, en detached HEAD o fuera de un repo git, sin ruido de `jq`), sanitiza slug, branch y URL antes de interpolarlos al output, conserva el passthrough y el WARNING de v1 y degrada a no-op limpio sin `jq` en PATH, `session-start-context.sh` sanitiza datos de terceros (títulos de issues), `hooks/lib/slug.sh` produce slugs determinísticos sin las colisiones de `tr '/' '-'` (y los 3 hooks que lo consumen degradan a no-op limpio si el lib falta), y `.gitignore` cubre los patrones de secrets defensivos. Toda la suite corre en sandboxes temporales — incluido un repo git con remote bare fake para `pre-push-guard` — y un guard final verifica que el repo real quedó intacto (branch y working tree) |
| `test-plugin-manifest.sh` | Paridad `hooks/*.sh` ↔ `hooks/hooks.json`: cada script (excluyendo `hooks/lib/`) registrado exactamente una vez, con demostración RED sobre una copia corrupta del manifest (nunca sobre el real). Además: los 3 manifests del plugin (`.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `hooks/hooks.json`) parsean como JSON válido, y `claude plugin validate --strict .` pasa si la CLI está en PATH (SKIP declarado si no) |
| `test-qa-detection.md` | Los QA agents (qa-frontend / qa-backend) detectan code smells, stubs y red flags en su capa |
| `test-security-detection.md` | El security-reviewer detecta vulnerabilidades conocidas |

## Cómo ejecutar

### Hook y plugin manifest tests (automatizado)

```bash
cd /path/to/project
bash tests/adversarial/test-hooks.sh
bash tests/adversarial/test-plugin-manifest.sh
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
- Después de modificar hooks (`hooks/*.sh`) o los manifests del plugin (`hooks/hooks.json`, `.claude-plugin/`)
- Después de modificar rules (`rules/*.md`)
- Periódicamente (mensual) como parte de la validación de agentes
