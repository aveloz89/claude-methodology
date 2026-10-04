# Claude Code Methodology

Sistema de agentes especializados, hooks de automatización y workflows para desarrollo fullstack con Claude Code.

## Qué incluye

El **orchestrator** no es un subagente: es el Claude de la sesión principal. Las invariantes viven en `global/CLAUDE.md` (instalado como `~/.claude/CLAUDE.md`); el manual operativo — fases 0 a 5, equipo de subagentes, lotes — vive en la skill `orchestrator`. Coordina el flujo (brainstorming → diseño → implementación → review → merge) y delega en estos 10 agentes:

### Agentes (10)
| Agente | Modelo | Rol |
|--------|--------|-----|
| **architect** | fable | Diseña soluciones, define contratos/schemas, descompone en tareas atómicas |
| **ui-ux** | opus | Genera el design system y valida flujos antes de que el frontend implemente |
| **backend-dev** | sonnet | Implementa backend con TDD, gitflow, verificación pre-commit; esquemas complejos, migraciones con backfill y optimización de queries en lotes `db-complejo` |
| **frontend-dev** | sonnet | Implementa frontend (capa delgada, cero lógica de negocio) |
| **security-reviewer** | opus | Auditoría OWASP Top 10, secrets, dependencias (read-only) |
| **qa-frontend** | sonnet | UX, accesibilidad, componentes, estado UI, tests frontend, coverage ≥ 80% |
| **qa-backend** | sonnet | Contratos de API, lógica de negocio, datos, tests backend, coverage ≥ 80% |
| **e2e-runner** | sonnet | Tests E2E con Playwright. Bloqueante en pre-release a `main` |
| **code-sweep** | sonnet | Escanea el repo en modo lectura: `bugs` (bugs latentes) o `smells` (candidatos de refactor). Nunca modifica código |
| **docs** | sonnet | Genera/actualiza documentación a partir del diff, antes del push |

### Hooks (12)
| Hook | Evento | Qué hace |
|------|--------|----------|
| **pre-commit-guard** | PreToolUse (Bash) | Resuelve el árbol al que va el commit —cwd de la sesión o `cd /ruta/absoluta && git commit`, allowlist de dos formas— y corre tests ahí. Node: pnpm/yarn/npm según lockfile. Python: uv solo con `uv.lock` y `uv` en el PATH del hook (`uv run --frozen pytest`) → `.venv/bin/pytest` o `.venv/Scripts/pytest.exe` → si el proyecto declara entorno propio (`uv.lock`, `[tool.uv…]` o carpeta `.venv/`) y su runner no está, bloquea con la razón específica (uv fuera del PATH, `uv sync` pendiente, venv sin pytest) y nunca cae al `pytest` global → `pytest` del PATH solo en proyectos sin entorno declarado → sin nada de lo anterior, bloquea (fail-closed) nombrando el directorio y las tres vías. Un `package.json` sin script `test` usable no tapa un marcador Python del mismo directorio. Busca solo en el directorio del marcador (no sube al toplevel: limitación conocida en workspaces uv, donde `uv sync` deja `uv.lock` y `.venv/` en la raíz y no en el miembro; el miembro necesita un `.venv` local con pytest o, sin `[tool.uv…]` propio, el venv de la raíz activado). Sin marcador de runner (`package.json`/`pyproject.toml`/`setup.py`/`pytest.ini`) en la raíz del árbol resuelto (#86): deriva un candidato por el primer segmento de cada path con cambios locales que sí tenga marcador arriba, corre todos (presupuesto dividido entre ellos) y, si ninguno tiene marcador, pasa sin correr nada (sin marcador no bloquea; marcador sin runner sí). Cualquier otra forma de resolver el árbol (`git -C`, `--git-dir`/`--work-tree`, `pushd`, dos `cd`, ruta con comillas/variables/`~/`) bloquea sin correr, con las formas aceptadas en el mensaje. Watchdog fail-closed: si la suma de las corridas supera `PRECOMMIT_TEST_BUDGET` segundos (default 540, overridable por env), mata el grupo de procesos y bloquea en vez de dejar pasar el commit sin tests |
| **pre-push-guard** | PreToolUse (Bash) | Bloquea push directo a main (branch resuelto del `.cwd` de la sesión, no del cwd del proceso). Detección saneada+anclada: `git commit -m x && git push origin main`, `npm test && git push`. Fail-closed sin jq ni grep (preámbulo común `guard_init`); cualquier redirección (`cd`, `git -C`, `--git-dir`/`--work-tree`, `GIT_DIR=`/`GIT_WORK_TREE=`) bloquea sin resolverla — haz el cd en una llamada previa |
| **block-admin-merge** | PreToolUse (Bash) | Bloquea `gh pr merge --admin` que bypasea branch protections; también `gh -R o/r pr merge --admin` y `gh pr -R o/r merge --admin` |
| **block-force-push** | PreToolUse (Bash) | Bloquea `git push --force` / `-f`, un refspec forzado (`+<ref>`) y un cluster corto con `f` (`-fu`, `-uf`); permite `--force-with-lease` fuera de `main`/`master`/`dev` (branch de `.cwd` y tokens del segmento `push`), y lo bloquea hacia/desde uno de esos tres o fuera de un repo git resoluble |
| **block-hard-reset** | PreToolUse (Bash) | Bloquea `git reset --hard`, incluido `git -C <ruta> reset --hard` |
| **pre-merge-check** | PreToolUse (Bash) | Solo acepta `gh pr merge <N> [flags conocidos]` sola en el comando y en una línea; bloquea con threads de review sin resolver, reviews/checks pendientes, sin número de PR explícito, o si no puede verificar (fail-closed). Para un PR de otro repo, usa `--repo`/`-R` explícito, nunca `cd`. Sin `--repo`, si el cwd de la sesión no coincide con el cwd donde corre el hook (o no existe), bloquea sin consultar y pide `--repo owner/repo` |
| **post-pr-create** | PostToolUse (Bash) | Checkpoint de respaldo al crear un PR: en `state.json`, si el review dual pre-push ocurrió sobre el branch actual y `review_sha` es ancestro de HEAD sin delta posterior, no hace nada; si no hay esa evidencia, instruye lanzar el review (PR fuera del flujo) |
| **session-start-context** | SessionStart | Muestra branch, último commit, estado de `.planning/` y resumen de `state.json` |
| **context-monitor** | PostToolUse (Bash) | Avisa cuando el contexto se está agotando (35% warning, 25% critical) |
| **docker-refresh** | PostToolUse (Bash) | Detecta si servicios Docker necesitan restart/rebuild después de push o PR. Respeta hot reload |
| **pre-compact-snapshot** | PreCompact | Guarda un snapshot de `.planning/` antes de compactar el contexto, para restaurar si el compact deja el estado inconsistente |
| **subagent-stop-log** | SubagentStop | Appendea una línea JSONL por invocación de subagente, para medir el budget de `agent-budget.md` |

Los dos hooks de observabilidad (`pre-compact-snapshot`, `subagent-stop-log`) escriben sus artefactos bajo `~/.claude/methodology/` (`snapshots/`, `logs/`, uno por repo vía slug) con retención acotada (5 snapshots más recientes por repo, log rotado a `.old` al superar 1 MB); el directorio entero se puede borrar sin riesgo — se regenera solo en la siguiente invocación de cada hook.

#### Fuera de alcance de los guards (documentado, no parcheado — #77, D-05)

Los guards de `hooks/` protegen errores honestos del orchestrator y los devs: formas que alguien escribe de buena fe. No son un parser de shell ni un control de evasión. Verificado contra los hooks reales (2026-09-27), estas formas pasan sin bloquear y quedan así por decisión:

- comillas partidas o escapadas que rompen el emparejamiento del saneo: `echo \'; gh pr merge 5; echo \'`, `$'it\'s' && gh pr merge 5`;
- heredoc con delimitador comillado a medias (`<<E"OF"`), delimitador con caracteres fuera de `[A-Za-z0-9_-]`, o una línea del cuerpo que termina en `\` justo antes del terminador;
- la flag o el subcomando en una variable (`F=--force; git push $F`), `eval`, `bash -c '…'`/`sh -c`, alias y funciones de git/gh definidas en el mismo comando o en uno anterior (`w() { gh "$@"; }; w pr merge 5` pasa);
- la palabra del binario alterada o disfrazada: `"gh"`, `g\h`, `env git …`, `/usr/bin/git …`, `command git …` (el `if` de `hooks.json` tampoco dispara para las tres últimas: compara cada subcomando por prefijo y solo descarta asignaciones `VAR=x` al frente; ver la tabla "Bash if matching" de la doc de hooks);
- en `block-force-push`: la flag entre comillas (`git push origin "--force"`, `git push '-f'`) y una redirección honesta (`2>&1`, `>&2`, `&>log`) o un `;` escapado antes de la flag de force.

Si una de estas formas bloquea o se cuela, no es un bug a arreglar acá: la salida es escribir el comando en su forma directa.

### Skills (4)
| Skill | Qué hace |
|-------|----------|
| **orchestrator** | Manual operativo de la sesión principal: fases 0 a 5, equipo de subagentes, lotes y handoff, tracker de sesión, pause/resume — se carga al iniciar cualquier trabajo que termine en un PR |
| **/new-project** | Scaffold de proyecto con gitflow, GitHub Actions CI/CD, CLAUDE.md |
| **/pr-workflow** | Review dual local pre-push, presupuesto de CI, E2E pre-release, branch protection y verificación pre-merge — se invoca en Fase 2.6 o al trabajar sobre un PR existente |
| **/review-pr** | Re-dispara manualmente el review dual (security + QA según capas tocadas) sobre un PR existente, sin pasar por el flujo completo del orchestrator |

## Workflow

```
Idea → Brainstorming (orchestrator pregunta: ¿vale la pena?, resultado esperado, criterios de aceptación) → Brief
  → Architect diseña + escribe schemas/contratos
  → Devs implementan con TDD (Red → Green → Refactor)
  → Review dual local pre-push → Security + QA (qa-frontend y/o qa-backend según capas) en paralelo
  → Si hay issues → Dev corrige en el mismo branch, sin push → Re-review
  → Veredictos limpios → Push + PR (nace revisado) → CI → Merge
```

## Reglas enforced

- **80% test coverage** mínimo para mergear
- **Dual review** obligatorio, pre-push por default (security + QA frontend/backend según capas del diff)
- **TDD** obligatorio (test antes que código)
- **Build debe compilar** antes de commit
- **No push directo a main**
- **No stubs/TODOs** en código mergeado
- **Frontend delgado** — cero lógica de negocio
- **Estado persistente** en `.planning/` — sobrevive cambios de sesión, no se versiona (salvo `.planning/ARCHITECTURE.md`)

> **Proyectos que ya adoptaron esta metodología con `.planning/` versionado (incluidas retros de PRs anteriores)**: agrega `.planning/*` + `!.planning/ARCHITECTURE.md` al `.gitignore` del proyecto, corre `git rm -r --cached .planning` (re-agregando `ARCHITECTURE.md` si existe) y borra del working tree los archivos de retro que ya no se generan — la historia queda igual en git. Antes de mergear este cambio (o de cambiar a la rama base mientras `.planning/` siga versionado ahí), respalda la carpeta fuera del repo, por ejemplo con `mkdir ~/planning-backup-<proyecto> && cp -R .planning/. ~/planning-backup-<proyecto>/` (el `mkdir` falla si ya existe un respaldo previo, evitando mezclarlos), porque el checkout a esa rama la borra del disco; restáurala después con `cp -R ~/planning-backup-<proyecto>/. .planning/`.

## Instalación

Este repo es **plugin y marketplace de Claude Code a la vez**: instala agents/, hooks/ (registrados en `hooks/hooks.json`) y skills/ (namespace `/methodology:<skill>`, ej. `/methodology:pr-workflow`) por el mecanismo nativo de plugins. Los plugins de Claude Code **no** cargan `CLAUDE.md`, `rules/` ni `rulebooks/` — para eso hace falta el `install.sh` residual del repo clonado.

### Terceros

```bash
claude plugin marketplace add aveloz89/claude-methodology
claude plugin install methodology@claude-methodology   # agents, hooks, skills

git clone https://github.com/aveloz89/claude-methodology.git
cd claude-methodology
./install.sh                                            # residual: CLAUDE.md global, rules/, rulebooks/, statusline.sh
```

`install.sh` es idempotente (correrlo N veces deja el mismo estado) y nunca sobreescribe un archivo o directorio real del usuario: si el destino ya existe y no es un symlink hacia este repo, avisa y lo deja intacto.

### Autor (dev-loop)

El autor no instala el plugin propio vía marketplace — duplicaría la carga. `install.sh` crea el symlink `~/.claude/skills/methodology` → raíz del repo, que Claude Code auto-carga en vivo como `methodology@skills-dir`: cualquier cambio en `agents/`, `hooks/` o `skills/` está disponible en la próxima sesión, sin reinstalar ni hacer version bump.

```bash
./install.sh
```

### Transición desde instalaciones por symlink (versiones anteriores)

Antes del plugin, el repo se instalaba symlinkeando `agents/`, `hooks/`, `skills/` y `settings.json` completos a `~/.claude/`. `install.sh` migra esa instalación automáticamente la primera vez que se corre después de actualizar:

- `~/.claude/agents` y `~/.claude/hooks`: si son symlinks a este repo, se eliminan (ahora los provee el plugin). Si son directorios reales, no se tocan — quedan para revisión manual.
- `~/.claude/skills`: si es symlink al repo completo, se reemplaza por un directorio real con el symlink dev-loop `skills/methodology` adentro.
- `~/.claude/settings.json`: si es symlink a este repo, se **materializa** como archivo real (copia del contenido vigente) para desacoplar la config viva del working tree. `settings.json` deja de distribuirse por `install.sh` — el registro de hooks vive en `hooks/hooks.json`.

### Release (para el autor)

1. Validar antes de tocar manifests o agentes: `claude plugin validate --strict .claude-plugin/plugin.json` y `claude plugin validate --strict .` (con `marketplace.json` presente, este segundo valida solo el marketplace).
2. Bump de `version` en `.claude-plugin/plugin.json`.
3. `claude plugin tag` — valida consistencia `plugin.json` ↔ `marketplace.json` y crea el tag git `methodology--v<version>`.
4. Push del tag.

Terceros actualizan con `claude plugin marketplace update` + `claude plugin update methodology@claude-methodology` — el cache del plugin queda fijo en la versión instalada hasta ese punto.

### Limpieza opcional de artefactos con slug viejo

El hook de observabilidad `pre-compact-snapshot` escribe bajo `~/.claude/methodology/snapshots/<slug>/`, con `<slug>` = `basename-hash8` del path del repo (ver `hooks/lib/slug.sh`). Instalaciones de antes de este cambio de convención pueden tener artefactos huérfanos bajo el slug viejo (`tr '/' '-'` del path completo) — son inertes y se pueden borrar sin riesgo. `~/.claude/methodology/` completo también se puede borrar sin riesgo: se regenera solo en la siguiente invocación de cada hook.

## Estructura

```
claude-methodology/
├── .claude/
│   └── CLAUDE.md
├── .claude-plugin/
│   ├── marketplace.json
│   └── plugin.json
├── agents/
│   ├── architect.md
│   ├── backend-dev.md
│   ├── code-sweep.md
│   ├── docs.md
│   ├── e2e-runner.md
│   ├── frontend-dev.md
│   ├── qa-backend.md
│   ├── qa-frontend.md
│   ├── security-reviewer.md
│   └── ui-ux.md
├── global/
│   └── CLAUDE.md
├── hooks/
│   ├── block-admin-merge.sh
│   ├── block-force-push.sh
│   ├── block-hard-reset.sh
│   ├── context-monitor.sh
│   ├── docker-refresh.sh
│   ├── hooks.json
│   ├── lib/
│   │   ├── guard-matching.sh
│   │   └── slug.sh
│   ├── post-pr-create.sh
│   ├── pre-commit-guard.sh
│   ├── pre-compact-snapshot.sh
│   ├── pre-merge-check.sh
│   ├── pre-push-guard.sh
│   ├── session-start-context.sh
│   └── subagent-stop-log.sh
├── rules/
│   ├── bash.md
│   ├── csharp.md
│   ├── css.md
│   ├── docker.md
│   ├── go.md
│   ├── html.md
│   ├── implementation-principles.md
│   ├── python.md
│   ├── rust.md
│   ├── self-reflection.md
│   └── typescript.md
├── rulebooks/
│   ├── agent-budget.md
│   ├── build-errors.md
│   ├── db-migrations.md
│   ├── dev-common.md
│   ├── governance-playbook.md
│   ├── orchestrator-runbook.md
│   └── reviewer-common.md
├── skills/
│   ├── new-project/
│   │   └── SKILL.md
│   ├── orchestrator/
│   │   └── SKILL.md
│   ├── pr-workflow/
│   │   └── SKILL.md
│   └── review-pr/
│       └── SKILL.md
├── settings.json
├── install.sh
└── README.md
```

## Stack-agnóstico

Los agentes detectan el stack del proyecto leyendo CLAUDE.md. Funcionan con:
- **Node.js** (pnpm/yarn/npm) + TypeScript/JavaScript
- **Python** (uv / venv / pip) + pytest
- **Cualquier framework** — el CLAUDE.md del proyecto define convenciones

El architect escribe schemas en la herramienta del proyecto (Zod, Pydantic, Go structs, etc.).
