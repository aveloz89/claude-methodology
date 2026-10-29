# Adversarial Tests

Tests que validan que la metodología misma funciona correctamente.

## Estructura

| Archivo | Qué valida |
|---------|-----------|
| `test-hooks.sh` | Los hooks de Claude Code bloquean comandos peligrosos — incluye regresión del matching compartido en `hooks/lib/guard-matching.sh` (`guard_init`/`guard_block`/`guard_session_dir`, comandos compuestos, menciones quoted/heredoc, fallback sin `perl`/`jq`) —, los hooks de observabilidad (`pre-compact-snapshot`, `subagent-stop-log`) producen el efecto esperado en filesystem sin bloquear el evento, el checkpoint `post-pr-create` distingue contra `state.json` el PR ya revisado pre-push (CASO A: fase + branch + `review_sha` ancestro de HEAD sin delta posterior, sin relanzar reviewers) del PR fuera del flujo (CASO B: instruir review dual — incluye fallar hacia el review con state ausente, incompleto, de otro branch, malformado, sin anclaje al SHA revisado, en detached HEAD o fuera de un repo git, sin ruido de `jq`; y resuelve el árbol desde `.cwd` del payload vía `guard_session_dir`, no desde el cwd del proceso del hook: con dos sandboxes, CASO A del repo de `.cwd` (también desde un subdirectorio) aunque el proceso corra en otro sin evidencia; el inverso, un `.cwd` inexistente o que no es repo git y la lib ausente caen a CASO B; `.cwd` vacío/null equivale a ausente), sanitiza slug, branch y URL antes de interpolarlos al output, conserva el passthrough y el WARNING de v1 y degrada a no-op limpio sin `jq` en PATH, `session-start-context.sh` sanitiza datos de terceros (títulos de issues), `hooks/lib/slug.sh` produce slugs determinísticos sin las colisiones de `tr '/' '-'` (y los hooks que lo consumen degradan a no-op limpio si el lib falta), y `pre-merge-check` en sus tres estados (bloquear ante verificación fallida, silencio ante comando que no es merge, `ask` solo tras las tres verificaciones en verde; en modos no interactivos el `ask` se deniega), `session-start-context.sh` renderiza la línea `Tier:` de `state.json` (liviano, ausente cae a completo, valor desconocido a `?`), y `.gitignore` cubre los patrones de secrets defensivos y el estado de `.planning/` (ignorado salvo `ARCHITECTURE.md`). Toda la suite corre en sandboxes temporales — incluido un repo git con remote bare fake para `pre-push-guard` — y un guard final verifica que el repo real quedó intacto (branch y working tree) |
| `test-plugin-manifest.sh` | Paridad `hooks/*.sh` ↔ `hooks/hooks.json`: cada script (excluyendo `hooks/lib/`) registrado exactamente una vez, con demostración RED sobre una copia corrupta del manifest (nunca sobre el real). Además: los 3 manifests del plugin (`.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `hooks/hooks.json`) parsean como JSON válido, y `claude plugin validate --strict .` pasa si la CLI está en PATH (SKIP declarado si no). Incluye `agents/code-sweep.md` (frontmatter read-only, con sandbox RED/GREEN), `rulebooks/reviewer-common.md` (secciones compartidas de los reviewers, incluida la de pruebas que escriben archivos) y `rulebooks/dev-common.md` (Handoff, Reglas heredadas, Flujo de trabajo, Desviaciones), la referencia de cada reviewer/dev a su rulebook común, la coherencia del conteo de agentes, hooks, skills y workflows contra `README.md` y `marketplace.json` (`agents/*.md`, `hooks/hooks.json`, `skills/*/`, `workflows/*.js`; el conteo de hooks existe desde el lote 3 y el de workflows desde el lote 2), un grep de referencias colgantes a piezas ya eliminadas de la metodología (lista de términos en la sección correspondiente del propio script) que usa `dangling_grep` sobre los archivos trackeados por git y falla —no pasa en silencio— si el propio grep da error, tokens retóricos vedados en `global/CLAUDE.md` (mayúsculas imperativas y `obligatorio`/`bloqueante` y variantes), checks estáticos del workflow `workflows/code-sweep.js` (primera sentencia `export const meta`, sin `Date.now()` ni `Math.random()`, `MAX_CONCURRENT = 8`, schema de hallazgo y sintaxis), el assert D-14 de que lo distribuido por el plugin cita `~/.claude/CLAUDE.md` (ruta instalada) y no `global/CLAUDE.md`, la presencia en README e `install.sh` de la configuración recomendada del harness (`fallbackModel`, `baseRef`, `agent-memory`, `security-guidance`) y los topes de líneas de `backend-dev` y `frontend-dev`. El script no usa construcciones de bash 4: corre bajo `/bin/bash` 3.2 de macOS, y el check de cierre exige cero líneas de error de bash en la salida de las tres suites |
| `test-frontmatter.sh` | Lint de frontmatter de `agents/*.md` y `skills/*/SKILL.md`: claves permitidas y sin las que el plugin ignora (`permissionMode`, `hooks`, `mcpServers`, `initialPrompt`), `memory`/`effort`/`model` dentro de su enum, `memory: project` solo en los reviewers (`security-reviewer`, `qa-backend`, `qa-frontend`, que conservan `Write, Edit` vedados) y en `e2e-runner` (memoria preexistente de flakes), sin `memory` en el resto, y el cuerpo documenta `agent-memory`, `name` igual al nombre del archivo, `effort: high` solo en `qa-frontend`/`qa-backend`, `Agent(...)` de las skills con forma `Agent(methodology:<agente>)` apuntando a un agente existente, `disable-model-invocation` obligatorio/prohibido según la skill, y toda referencia `methodology:<x>` del repo resuelve a un agente o skill real |
| `test-qa-detection.md` | Los QA agents (qa-frontend / qa-backend) detectan code smells, stubs y red flags en su capa |
| `test-security-detection.md` | El security-reviewer detecta vulnerabilidades conocidas |

## Cómo ejecutar

### Hook y plugin manifest tests (automatizado)

```bash
cd /path/to/project
bash tests/adversarial/test-hooks.sh
bash tests/adversarial/test-plugin-manifest.sh
bash tests/adversarial/test-frontmatter.sh
```

### QA / Security detection tests (manual)

1. Crear un PR temporal con los fixtures del archivo `.md`
2. Invocar al agente correspondiente:
   - Fixtures Python (1, 2, 3) → `qa-backend`
   - Fixture TypeScript (4) → `qa-frontend` si el fixture está en ruta de UI, `qa-backend` si está en ruta de servidor (Node)
   - Fixtures de seguridad → `security-reviewer`
3. Comparar hallazgos vs "Expected findings" del fixture
4. Si el agente no detecta un problema esperado, ajustar su prompt

### Verificación de cierre (compatibilidad con bash 3.2)

Las tres suites corren bajo `/bin/bash` (3.2 en macOS). Una construcción de bash 4 no rompe el exit code: bash imprime el error y sigue, y el assert afectado desaparece del total. Por eso, antes de cerrar un cambio, corre las tres suites bajo `/bin/bash` y exige cero líneas de error de bash en su salida:

```bash
for s in test-hooks test-plugin-manifest test-frontmatter; do
  /bin/bash tests/adversarial/$s.sh 2>&1
done | grep -cE 'tests/adversarial/[a-z-]+\.sh: line [0-9]+:'   # debe imprimir 0
```

`test-plugin-manifest.sh` además verifica de forma estática que ninguna suite use `declare -A`, `mapfile`, `readarray`, `${var,,}` ni `${var^^}`.

### Checks agregados en los lotes 10 a 12

- **`test-hooks.sh`, `pre-merge-check.sh`**: el fake `gh` suma modos (`threads_null_repo` para un `.pullRequest` nulo en GraphQL, `checks_cancelled` para un check cancelado que cuenta como fallo) y un wrapper de `jq` que falla solo al construir el JSON final (`jq -nc`), para probar que el hook bloquea con exit 2 en vez de dejar pasar el merge.
- **`test-plugin-manifest.sh`, `code-sweep.js` y `agents/code-sweep.md`**: `assert_not_contains` de `--body "` y `--search "` (inyección de shell por comillas dobles) y de `CS_ISSUE_BODY_2`; `assert_contains` del heredoc con delimitador entre comillas simples (`<<'CS_ISSUE_BODY'`) y de `--body-file -`; vedado de `Bash` a los agentes de lectura; `Workflow(methodology:code-sweep)` en `allowed-tools` de la skill orchestrator.
- **Filtro de issues del workflow**: `SAFE_FILE_RE`, `SAFE_PATTERN_RE`, `seenFiles.has` y `excluido de issues` por `assert_contains`, más un test funcional: el script extrae con `grep`/`awk` las constantes y las funciones puras `issueExclusionReason`/`issueSafe` a un directorio temporal y las evalúa en `node` (sin el runtime). Casos: hallazgo válido, `file` con `'` o `$(`, `file` fuera de `seenFiles`, `pattern` con backtick y campos con una línea igual al delimitador. El agente de respaldo lleva las mismas reglas por escrito (`A-Za-z0-9`, `excluido de issues`, `depende del modelo`).
- **`dangling_grep`**: sonda que verifica que un patrón inválido da FAIL con el mensaje de grep en vez de pasar en vacío.
- **Asserts anclados**: los de PII (señal 1) y `phases.docs` (escalada) del runbook y la skill apuntan a frases únicas (`^1\. Toca auth.*pagos, PII, CORS`, `phases.design = "pending"` y `phases.docs = "pending"` juntos); verificado por mutación: quitar `PII` de la señal 1 o `phases.docs` de la escalada da FAIL. Lo mismo con la condición del `security-reviewer` en liviano (`señales 1, 4 u 8`) y el filtro del volcado de memoria (`formato exacto`, `ghp_`).

## Cuándo ejecutar

- Antes de releases
- Después de modificar prompts de agentes (`agents/*.md`)
- Después de modificar hooks (`hooks/*.sh`) o los manifests del plugin (`hooks/hooks.json`, `.claude-plugin/`)
- Después de modificar rules (`rules/*.md`)
- Periódicamente (mensual) como parte de la validación de agentes
