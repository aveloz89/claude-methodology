# Diseño: Barrido de follow-ups + plugin de distribución

## Resumen

Un solo PR a `dev` que: (A) empaqueta la metodología como plugin de Claude Code (repo = plugin + marketplace) con un instalador residual para lo que el plugin no cubre (CLAUDE.md global, rules/, rulebooks/, statusline); (B) cambia la convención de slug de artefactos de hooks a `basename-hash8` y sandboxea los tests de guards que hoy manipulan el repo real; (C) agrega la skill `/review-pr`; (D) aplica 4 ediciones de docs ya especificadas en el BRIEF.

## Search-first

**Verificado localmente contra la CLI real (`claude` 2.1.232), no solo docs:**

- `claude plugin --help` y subcomandos: existen `init`, `validate --strict`, `install --scope user|project|local`, `marketplace add <url|path|repo>`, `tag` (crea tag git `{name}--v{version}` validando plugin.json ↔ marketplace), `details` (inventario de componentes), `update`.
- Scaffold real (`claude plugin init` con HOME aislado): manifest en `.claude-plugin/plugin.json` (`$schema`, `name`, `version`, `description`, `author`), hooks en `hooks/hooks.json` con la **misma estructura de eventos que settings.json** y paths vía `${CLAUDE_PLUGIN_ROOT}`, agents en `agents/*.md`, skills en `skills/*/SKILL.md`.
- **Ciclo completo probado en sandbox** (HOME aislado): un directorio con `.claude-plugin/plugin.json` + `.claude-plugin/marketplace.json` coexistiendo **valida con `--strict` y se instala** end-to-end (`marketplace add <path>` → `install methodology@claude-methodology`). La instalación **copia el source completo** a un cache versionado: `~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/`.
- Inventario de `plugin details`: Skills, Agents, Hooks, MCP, LSP. **Confirmado: los plugins NO cargan `rules/` ni `rulebooks/` ni CLAUDE.md** — el híbrido es obligatorio, como anticipaba el BRIEF.
- Dev-loop oficial: plugins bajo `~/.claude/skills/<name>/` auto-cargan como `<name>@skills-dir` **en vivo desde disco** (es donde `plugin init` scaffoldea). Esto reemplaza el symlink-install para el autor.
- Portabilidad de hash: `shasum` existe en macOS (siempre) y Linux (perl); `sha256sum` solo GNU; `md5` (BSD) vs `md5sum` (GNU). Verificada la trampa señalada en el brief.

**Decisión: adoptar** el mecanismo nativo de plugins para skills+agents+hooks (cero reestructuración: el layout del repo YA coincide con las convenciones del plugin) y **construir** solo lo residual (installer, lib de slug, sandbox de tests, skill nueva) reutilizando patrones existentes del repo (`hooks/lib/` para libs compartidas, helpers `assert_*`/sandbox de `test-hooks.sh`, formato de skill de `pr-workflow`/`refactor-scan`).

## Arquitectura

Sin cambio de arquitectura: el repo sigue siendo una colección de artefactos de configuración + shell, sin build. Lo que cambia es el **mecanismo de distribución** (decisión recurrente registrada en `ARCHITECTURE.md`):

```
Distribución híbrida:
├── Plugin de Claude Code (repo = plugin + marketplace)
│   ├── skills/      → namespace /methodology:<skill>
│   ├── agents/      → 13 agentes
│   └── hooks/       → hooks.json registra los 13 .sh vía ${CLAUDE_PLUGIN_ROOT}
└── install.sh residual (lo que el plugin no puede distribuir)
    ├── global/CLAUDE.md → symlink a ~/.claude/CLAUDE.md   (nuevo, curado)
    ├── rules/           → symlink a ~/.claude/rules        (igual que hoy)
    ├── rulebooks/       → symlink a ~/.claude/rulebooks    (igual que hoy)
    ├── statusline.sh    → symlink                          (igual que hoy)
    └── migración: limpia symlinks legacy y materializa settings.json
```

---

## Grupo A — Plugin de Claude Code

### A.1 Estructura: el repo es plugin Y marketplace a la vez

Verificado que ambos manifests coexisten en `.claude-plugin/` y el ciclo add→install funciona. No se crea repo aparte ni subdirectorio `plugin/`: mover `agents/hooks/skills` a un subdir reestructuraría paths en tests, install.sh y README sin beneficio funcional.

**`.claude-plugin/plugin.json`** (contrato exacto):

```json
{
  "$schema": "https://anthropic.com/claude-code/plugin.schema.json",
  "name": "methodology",
  "version": "1.0.0",
  "description": "Metodología de desarrollo con agentes: orchestrator + workers, TDD, dual review, gitflow",
  "author": { "name": "Alejandro Veloz" }
}
```

Sin claves `skills`/`agents`/`hooks` explícitas: el auto-discovery por convención (`skills/`, `agents/`, `hooks/hooks.json`) ya matchea el layout del repo. **No** agregar `"skills": ["./"]` (eso convertiría la raíz del repo en una skill, como hace el scaffold).

**`.claude-plugin/marketplace.json`**:

```json
{
  "name": "claude-methodology",
  "description": "Marketplace de la metodología de agentes de claude-methodology",
  "owner": { "name": "Alejandro Veloz" },
  "plugins": [
    {
      "name": "methodology",
      "source": "./",
      "description": "Metodología completa: 13 agentes, 14 hooks, 4 skills"
    }
  ]
}
```

**`hooks/hooks.json`** (nuevo): espejo exacto del bloque `hooks` actual de `settings.json` — mismos eventos, matchers y timeouts — con `~/.claude/hooks/` reemplazado por `${CLAUDE_PLUGIN_ROOT}/hooks/`. Los 14 hooks: 7 PreToolUse (block-admin-merge, block-force-push, block-hard-reset, pre-push-guard, pre-merge-check, pre-release-sweep, pre-commit-guard), 3 PostToolUse (post-pr-create, context-monitor, docker-refresh), SessionStart matcher `startup` (session-start-context), PreCompact (pre-compact-snapshot), SubagentStop (subagent-stop-log), SessionEnd (session-end-check). La resolución de libs internas (`${0%/*}/lib/…`) funciona igual bajo el plugin root — no cambia ningún hook.

**Consecuencia aceptada**: `plugin install` copia el repo completo (incl. `tests/`, `docs/`, `rules/`, `.planning/`) al cache versionado. Es inerte y pesa poco; la alternativa (subdir) cuesta más de lo que compra. Bonus: `rules/` y `rulebooks/` viajan físicamente en la copia aunque no se auto-carguen — el installer residual sigue siendo su mecanismo de carga.

### A.2 Instalación y versionado

- **Terceros**: `claude plugin marketplace add aveloz89/claude-methodology` → `claude plugin install methodology@claude-methodology` (scope `user`, default) + `./install.sh` para el residual.
- **Autor (dev-loop)**: symlink `~/.claude/skills/methodology` → raíz del repo (auto-carga como `methodology@skills-dir`, en vivo, sin version bump). El autor **no** instala vía marketplace — evita doble carga. Lo crea install.sh.
- **Release**: bump de `version` en plugin.json → `claude plugin tag` (valida consistencia y crea tag `methodology--v<version>`) → push del tag. Terceros: `claude plugin marketplace update` + `claude plugin update methodology@claude-methodology`.
- **Namespace**: las skills pasan a invocarse `/methodology:pr-workflow`, `/methodology:review-pr`, etc. Las referencias por nombre en CLAUDE.md/runbook siguen resolviendo; documentar el namespace en README.

### A.3 Híbrido: CLAUDE.md global curado (no symlink del entero)

**Decisión: curar, no symlinkear el CLAUDE.md del repo entero.** Razones: (1) symlinkear el entero duplicaría ~200 líneas en cada sesión dentro del propio repo (user + project cargan a la vez); (2) contiene secciones repo-específicas que no aplican a otros proyectos; (3) mantener dos copias con el mismo contenido es una trampa de drift — por eso el global se convierte en **canónico** para el núcleo y el CLAUDE.md del repo queda solo con el delta.

**Nuevo archivo `global/CLAUDE.md`** — núcleo global-safe, instalado como `~/.claude/CLAUDE.md` (se carga en TODA sesión de TODO proyecto; resuelve el follow-up 2026-05-08: los agentes que referencian "CLAUDE.md raíz" ahora tienen las reglas globales garantizadas vía user scope). Reparto de secciones del CLAUDE.md actual:

| Sección actual | Destino |
|---|---|
| Idioma (español/inglés) | global |
| `rules/` vs `rulebooks/` + cómo se cargan las rules | repo (advertencias para EDITAR el repo) — el global conserva 2 líneas: qué son y que se auto-cargan |
| Rol orchestrator + regla fundamental | global |
| Workflow obligatorio (brainstorming, diseño, TDD, dual review, coverage) | global |
| Lotes, equipo de subagentes, degradación de modelos | global |
| Handoff / context isolation | global |
| Flujo nueva feature + reglas clave | global |
| `.planning/`, pause/resume | global |
| PR y merge (invariantes), gitflow, formato de commits | global |
| Hooks (qué bloquean / qué corre en background) | global, sin las referencias a README.md/settings.json del repo |
| Verificación pre-commit | global |
| Reglas operativas | global |
| Salud del sistema (tests/adversarial, tests/validation) | repo |
| Reglas por lenguaje (`rules/`) | global |

**El CLAUDE.md del repo se adelgaza**: encabezado con puntero («la metodología operativa vive en `global/CLAUDE.md`, instalada como `~/.claude/CLAUDE.md` — ya está cargada en esta sesión») + delta repo-específico (convenciones para editar el repo, salud del sistema, y una sección nueva corta: desarrollo del plugin — manifests, paridad hooks.json, proceso de release). Queda muy por debajo de las ~200 líneas. **Prohibido duplicar contenido entre ambos.**

### A.4 Destino de install.sh (residual) y transición

`install.sh` **no se deprecia**: se reduce a lo que el plugin no cubre, más la migración desde la instalación por symlinks. Comportamiento nuevo (idempotente, correr N veces = mismo estado):

1. **Instala residual**: symlink `~/.claude/CLAUDE.md` → `global/CLAUDE.md`. Si existe un archivo real del usuario: **SKIP** — se deja intacto, sin backup `.bak` (más conservador y coherente con la regla dura de §Riesgos: no se borra ni reemplaza nada del usuario); el mensaje final sugiere integrar la metodología vía una línea de import (`@<repo>/global/CLAUDE.md`) o merge manual. Symlinks de `rules/`, `rulebooks/`, `statusline.sh` (igual que hoy).
2. **Migración de legacy**: elimina `~/.claude/agents`, `~/.claude/hooks` **solo si son symlinks que apuntan dentro de este repo** (ahora los provee el plugin); si son directorios reales, no los toca y avisa. `~/.claude/skills`: si es symlink al repo, lo elimina y crea directorio real.
3. **Dev-loop**: crea symlink `~/.claude/skills/methodology` → raíz del repo.
4. **settings.json deja de distribuirse**: si `~/.claude/settings.json` es symlink al repo, lo **materializa como archivo real** (copia del contenido actual) para desacoplar la config viva del working tree. El `settings.json` del repo pierde su bloque `hooks` (los registra el plugin vía hooks.json) y queda documentado como config de referencia del autor, ya no instalable.
5. Mensaje final: pasos restantes manuales (reiniciar Claude Code; para terceros, comandos de plugin).

**Transición sin romper la instalación actual** (documentada en README): el orden dentro del PR mantiene una ventana de **doble registro** de hooks (plugin + settings.json) en lugar de una ventana sin hooks — el doble disparo es inocuo (guards idempotentes; subagent-stop-log ya dedupea). El bloque `hooks` se quita de settings.json en el mismo lote que reescribe install.sh; como `~/.claude/settings.json` del autor es hoy un symlink vivo al repo, la instrucción explícita es **correr `./install.sh` inmediatamente al probar ese lote** (materializa settings y activa el plugin por skills-dir).

---

## Grupo B — Hooks y tests

### B.4 Slug + hash del toplevel

**Convención nueva** (reemplaza `tr '/' '-'`, que no es inyectivo):

```
slug = <basename saneado>-<hash8>
  basename saneado = basename "$TOPLEVEL" | tr -cd 'A-Za-z0-9_-'   (si queda vacío: "repo")
  hash8            = primeros 8 hex de SHA-256 del path completo del toplevel
```

Ejemplo: `/Users/alas/Proyectos/claude-methodology` → `claude-methodology-`+8 hex. Legible (basename primero), corto, y libre de colisiones por el hash del path completo.

**Herramienta de hash — cadena de fallback portable** (la consistencia importa *por máquina* a lo largo del tiempo, no entre máquinas: los artefactos viven en `$HOME`):

```bash
# hooks/lib/slug.sh — contrato
# repo_slug <toplevel-path>  → imprime el slug; return 1 si no hay herramienta de hash
#   hash: shasum -a 256 (macOS siempre, Linux con perl) → sha256sum (GNU)
#         → md5 -q (BSD) → md5sum (GNU)   [md5 solo último recurso: no es cripto,
#         pero para diferenciar paths 8 hex chars dan la misma protección práctica]
#   el path se pasa por stdin (printf '%s'), nunca como archivo
```

**Implementación**: lib compartida `hooks/lib/slug.sh` (mismo patrón que `guard-matching.sh`), sourceada con `LIB="${0%/*}/lib/slug.sh"`. **Hooks afectados: 3, no 4** — verificado con grep: `session-start-context.sh` (lee marker), `pre-compact-snapshot.sh` (escribe snapshots), `session-end-check.sh` (escribe marker). `subagent-stop-log.sh` **no deriva slug** (log compartido con campo `repo` por línea); el BRIEF lo lista por error — no se toca.

**Modo degradado** (lib ausente o sin herramienta de hash): los hooks de observabilidad son no-op `exit 0` (nunca bloquean); `session-start-context.sh` salta **solo** la sección del marker e imprime el resto del contexto. Con tests.

**Artefactos existentes bajo la convención vieja: se abandonan.** Justificación: son datos operativos efímeros y acotados (snapshots = recovery con retención 5; markers = aviso consume-once). Migrarlos es ambiguo para markers (no guardan el path del repo dentro del JSON) y el código de migración viviría para siempre por un evento único; leer ambas convenciones mantendría vivo el bug de colisión. Los slugs viejos son distinguibles (empiezan con `-`); README documenta la limpieza manual opcional (`rm -rf ~/.claude/methodology/snapshots/-* ~/.claude/methodology/session-end/-*`). Pérdida aceptada: un marker de staleness pendiente no se consume una vez.

### B.5 Sandbox de tests de guards

Hoy `test-hooks.sh` líneas 188–215 hace `git stash` + `git checkout main` + commit vacío + `reset` sobre el **repo real** para testear `pre-push-guard.sh` (casi-incidente PR #49). El guard solo inspecciona el string del comando, el branch actual y el subject del último commit — **nunca ejecuta el push ni consulta el remote** — así que el sandbox no necesita red ni remote funcional.

**Diseño del sandbox de push** (nuevo helper en `test-hooks.sh`, junto a `sandbox_create`):

```bash
# sandbox_create_pushrepo: repo git temporal con branch main y remote fake.
#   git init -q -b main  (+ user.email/user.name como sandbox_create)
#   commit inicial non-merge
#   remote fake: git init --bare en otro mktemp -d + git remote add origin <bare>
#     (el guard hoy no toca el remote; el bare blinda los tests si el guard
#      evoluciona y evita accidentes si un test ejecutara el push de verdad)
# Variables globales SANDBOX_REPO / SANDBOX_REMOTE + cleanup que borra ambos.
```

Los asserts reutilizan `assert_blocked_cmd` / `assert_allowed_cmd`, que **ya aceptan `run_cwd`** — se pasan con `run_cwd=$SANDBOX_REPO`. Matriz de casos (cobertura actual preservada + ampliada):

| # | Estado del sandbox | Comando | Esperado | Hoy |
|---|---|---|---|---|
| 1 | `checkout -b feature/test` | `git push origin feature/test` | allowed | existe |
| 2 | main | `git status` | allowed (pass-through) | existe |
| 3 | main, HEAD non-merge | `git push origin main` | blocked | existe, **condicional** (se saltaba si stash fallaba) → pasa a incondicional |
| 4 | main, HEAD = merge commit (`merge --no-ff` de una rama aux) | `git push origin main` | allowed | implícito/frágil → explícito |
| 5 | `git branch -m master`, HEAD non-merge | `git push origin master` | blocked | no existía |

Se elimina **todo** manejo del repo real (`ORIGINAL_BRANCH`, stash, checkout, reset). Además: **guard de no-contaminación de la suite** — capturar al inicio branch actual y `git status --porcelain` del repo real, compararlos al final; si difieren → FAIL explícito. Protege contra cualquier regresión futura de cualquier test, no solo estos.

---

## Grupo C — Skill `/review-pr`

**Archivo**: `skills/review-pr/SKILL.md` (estilo `pr-workflow`/`refactor-scan`).

**Frontmatter**:

```yaml
name: review-pr
description: Re-dispara manualmente el review dual (security + QA según capas tocadas)
  sobre un PR existente, sin pasar por el flujo completo del orchestrator.
user-invocable: true
allowed-tools: Read, Grep, Glob, Bash, Agent(security-reviewer), Agent(qa-frontend), Agent(qa-backend)
argument-hint: "<número de PR> [security|qa|full]"
```

**Contrato**:

- **Input**: `$1` = número de PR (si falta: `gh pr list --state open` y preguntar cuál). `$2` opcional = alcance: `full` (default) | `security` (solo security-reviewer) | `qa` (solo QA) — cubre el caso "re-lanzar solo los reviewers que marcaron issues".
- **Paso 1 — validar**: `gh pr view $1 --json number,title,state,isDraft,baseRefName,headRefName,additions,deletions,files`. Si `state` = MERGED/CLOSED → abortar con aviso.
- **Paso 2 — detección de capas** (sobre `files` del PR):
  - frontend: `.tsx .jsx .vue .svelte .html .css .scss`, dirs `components/ pages/ app/` con UI → lanza `qa-frontend`
  - backend: `.py .go .rs .cs .sh`, dirs `api/ server/ db/ hooks/ migrations/`, Dockerfile/compose → lanza `qa-backend`
  - ambas capas → ambos QA; ninguna clara (docs/config puros) → `qa-backend` como default (dueño de contratos y procesos)
- **Paso 3 — presupuesto proporcional al diff** (memoria `review-budget-proportional`, validado en PRs #48/#49):
  - < 300 LoC → "cierra en ~10–15 min"
  - 300–1000 LoC → "cierra en ~20–25 min"
  - \> 1000 LoC → presupuesto por área con prioridades explícitas, profundidad justificada
  - Siempre en el prompt: mandato de cierre «veredicto + findings + sección **NO CUBIERTO** declarada — lo que no alcances no lo revises, decláralo». Ping de status a ~15 min.
- **Paso 4 — lanzar en paralelo** (single message) los reviewers del alcance. Handoff a cada uno: número de PR + branch, diff (`gh pr diff`), `.planning/BRIEF.md`/`DESIGN.md` si existen, presupuesto, formato de salida.
- **Paso 5 — reporte**: formato del runbook («Formato de reporte de review»: Resumen / Seguridad / QA Frontend / QA Backend / Veredicto / Bloqueantes / Sugerencias) **+ sección NO CUBIERTO**. Publicar con `gh pr comment` y copia en `.planning/reviews/PR-<N>.md`; si el archivo ya existe, **append** de sección `## Re-review <fecha>` — nunca pisar la historia.
- **Qué NO hace**: merge, push, fixes. Los fixes siguen el flujo normal (mismo branch, re-review acotado al delta).

---

## Grupo D — Docs (texto ya especificado en el BRIEF, solo asignación)

1. `rules/docker.md` (~línea 158): env vars → «URL completa cuando aplique; piezas separadas cuando se rotan independientemente».
2. `rules/docker.md` (~línea 45): excepción USER nonroot en dev → preferir `--build-arg UID=$(id -u)`; root solo si el build arg no resuelve.
3. Quitar bloque `agents:` del frontmatter de `rules/docker.md` (líneas 11–15). Verificado: `rules/implementation-principles.md` **no tiene** `agents:` en frontmatter (el grep del BRIEF matcheaba texto del body) — confirmar y no tocar.
4. `agents/backend-dev.md` (sección «Migraciones de DB: simple vs complejo», líneas 67–92): colapsar la lista duplicada → referencia al runbook (`~/.claude/rulebooks/orchestrator-runbook.md`, «Criterios completos: db-specialist vs backend-dev»), conservando la regla rápida y los 2 párrafos de comportamiento propios del agente (escalar al orchestrator, consumir schema del db-specialist) que NO están duplicados.
5. `.planning/FOLLOWUPS.md`: dejar solo el item de Agent Teams.

---

## Archivos afectados

**Nuevos:**
- `.claude-plugin/plugin.json` — manifest del plugin
- `.claude-plugin/marketplace.json` — manifest del marketplace
- `hooks/hooks.json` — registro de los 14 hooks para el plugin
- `hooks/lib/slug.sh` — lib compartida `repo_slug()`
- `global/CLAUDE.md` — núcleo global-safe de la metodología (→ `~/.claude/CLAUDE.md`)
- `skills/review-pr/SKILL.md` — skill nueva
- `tests/adversarial/test-plugin-manifest.sh` — paridad hooks/*.sh ↔ hooks.json + `claude plugin validate --strict` (skip declarado si la CLI no está)

**Modificados:**
- `hooks/session-start-context.sh`, `hooks/pre-compact-snapshot.sh`, `hooks/session-end-check.sh` — slug vía lib
- `tests/adversarial/test-hooks.sh` — sandbox de pre-push-guard + expectativas de slug nuevo + guard de no-contaminación
- `install.sh` — residual + migración (§A.4)
- `settings.json` — pierde bloque `hooks`
- `CLAUDE.md` — adelgazado a delta repo-específico + puntero al global
- `README.md` — instalación por plugin, transición, release, namespace de skills, limpieza de artefactos viejos
- `rules/docker.md`, `agents/backend-dev.md`, `.planning/FOLLOWUPS.md` — Grupo D
- `.planning/ARCHITECTURE.md` — 3 decisiones nuevas (ya escritas por el architect)

**No se tocan:** `hooks/subagent-stop-log.sh` (no deriva slug), los 13 agents (salvo backend-dev.md), skills existentes.

## Contratos API / Schemas / DB / Frontend / Docker

No aplica: sin endpoints, sin DB, sin UI, sin docker-compose. Los contratos de esta feature son los manifests del plugin (§A.1), `repo_slug()` (§B.4) y el contrato de la skill (§C), definidos arriba.

---

## Plan de implementación

**Estrategia de PR:** single-PR (decisión D-01 del usuario). Branch ya creado: `feature/followups-sweep`. Un commit por tarea → el PR queda navegable por grupos aunque el diff sea grande; el PR body lista los lotes por grupo.

**Orden — lo riesgoso primero:** el Lote 1 (sandbox) elimina la manipulación del repo real de una suite que se va a ejecutar decenas de veces durante este mismo PR (los devs la corren al verificar cada tarea de hooks y QA la corre en review — el casi-incidente del PR #49 fue exactamente ese escenario). Después hooks (B4), que congela el contenido que el plugin empaqueta (A), y al final skill + docs.

Todos los lotes son **secuenciales** sobre el mismo branch (comparten archivos: `test-hooks.sh` en L1/L2, `settings.json`/`install.sh`/`CLAUDE.md` en L3/L4). No hay paralelización.

**Nota general de coverage:** el código es bash; el "80% de branches" se materializa como cobertura de casos en la suite adversarial (la métrica de coverage instrumentado no aplica a shell). Restricción del BRIEF: la suite (hoy 91/91) termina verde con los tests nuevos incluidos.

#### Lote 1 — Sandbox de tests de guards (Grupo B5) (backend-dev)
**Depende de:** ninguno
**TDD:** el hook ya existe — no hay Red de producción posible. Criterio: cada test migrado se escribe primero en sandbox y se verifica verde contra el hook actual ANTES de borrar el test viejo equivalente; cobertura nunca decrece; al final, suite completa verde y repo real intacto.

- [ ] Tarea 1: helper `sandbox_create_pushrepo` + cleanup (repo temporal `git init -b main` + commit non-merge + remote fake bare) — smoke test de la infra (el helper produce un repo en main con remote `origin` resoluble)
- [ ] Tarea 2: migrar los 3 casos existentes de pre-push-guard al sandbox (casos 1–3 de la matriz §B.5) y eliminar TODO el manejo del repo real (stash/checkout/reset/ORIGINAL_BRANCH)
- [ ] Tarea 3: casos nuevos de la matriz — main con HEAD merge commit → allowed; master → blocked
- [ ] Tarea 4: guard de no-contaminación de la suite (branch + `git status --porcelain` del repo real idénticos al inicio y al final; si difieren → FAIL)

#### Lote 2 — Slug + hash (Grupo B4) (backend-dev)
**Depende de:** Lote 1 (mismo archivo de tests, y la suite ya no toca el repo real)
**TDD:** Red→Green estricto por tarea.

- [ ] Tarea 1: Red→Green de `hooks/lib/slug.sh` — tests: formato `<basename>-<hash8>`, determinismo, los pares que `tr` colapsaba (`/a/b-c` vs `/a-b/c`) producen slugs distintos, basename con chars raros pasa por allowlist, basename vacío → `repo`, fallback de herramienta de hash (PATH restringido sin shasum → usa sha256sum/md5), sin ninguna herramienta → return 1
- [ ] Tarea 2: migrar `pre-compact-snapshot.sh` a `repo_slug()` (actualizar expectativas de slug en sus tests primero → Red → Green)
- [ ] Tarea 3: migrar `session-end-check.sh` + `session-start-context.sh` juntos (par escritor/lector del marker — mismo slug o el marker se pierde; test de roundtrip write→read)
- [ ] Tarea 4: modo degradado — lib ausente: pre-compact/session-end exit 0 sin artefactos; session-start imprime contexto sin sección de marker (tests con lib renombrada en un HOOKS_DIR copiado al sandbox)

#### Lote 3 — Plugin: manifests y registro de hooks (Grupo A) (backend-dev)
**Depende de:** Lote 2 (empaqueta hooks ya migrados)
**TDD:** manifests = config, exentos de TDD literal; la verificación ejecutable es `claude plugin validate --strict` + el test de paridad (tarea 4, Red→Green real).

- [ ] Tarea 1: `.claude-plugin/plugin.json` (§A.1) — `claude plugin validate --strict .` pasa
- [ ] Tarea 2: `.claude-plugin/marketplace.json` (§A.1) — validate `--strict` pasa con ambos manifests presentes
- [ ] Tarea 3: `hooks/hooks.json` espejo exacto del bloque hooks de settings.json (eventos/matchers/timeouts) con `${CLAUDE_PLUGIN_ROOT}`
- [ ] Tarea 4: `tests/adversarial/test-plugin-manifest.sh` — Red→Green: cada `hooks/*.sh` (excluye `lib/`) registrado exactamente una vez en hooks.json (mata la clase de bug C5 "hook documentado pero no instalado"); corre validate `--strict` si la CLI existe, skip declarado si no

#### Lote 4 — Híbrido global + installer + transición (Grupo A) (backend-dev)
**Depende de:** Lote 3 (el installer migra hacia el plugin ya definido)
**TDD:** docs/config exentos. install.sh: verificación obligatoria con HOME fake (sandbox manual o automatizado si es barato) — correrlo 2 veces deja el mismo estado (idempotencia), nunca toca dirs reales del usuario, y los symlinks legacy solo se borran si apuntan al repo.

- [ ] Tarea 1: crear `global/CLAUDE.md` curado según la tabla §A.3 (global-safe: cero referencias a paths/archivos del repo)
- [ ] Tarea 2: adelgazar `CLAUDE.md` del repo (puntero + delta repo-específico + sección corta de desarrollo del plugin; sin duplicación con el global)
- [ ] Tarea 3: reescribir `install.sh` residual + migración según §A.4 (idempotente, verificado con HOME fake)
- [ ] Tarea 4: quitar bloque `hooks` de `settings.json` (queda solo registro vía plugin) + nota de transición
- [ ] Tarea 5: README — instalación (terceros vía marketplace / autor vía skills-dir), transición desde symlinks, release con `claude plugin tag`, namespace `/methodology:*`, limpieza opcional de artefactos con slug viejo

#### Lote 5 — Skill /review-pr + docs (Grupos C y D) (backend-dev, `last_batch=true`)
**Depende de:** Lote 4 (CLAUDE.md/README ya estabilizados; la skill se empaqueta sola por auto-discovery)
**TDD:** exento (markdown puro); verificación: `claude plugin validate --strict` sigue pasando y los textos del Grupo D son los especificados en el BRIEF.

- [ ] Tarea 1: `skills/review-pr/SKILL.md` con el contrato completo §C
- [ ] Tarea 2: `rules/docker.md` — las 2 ediciones de texto (env vars + USER nonroot dev) según BRIEF
- [ ] Tarea 3: quitar frontmatter `agents:` de `rules/docker.md`; confirmar que `implementation-principles.md` no lo tiene (no tocar)
- [ ] Tarea 4: `agents/backend-dev.md` — dedup de criterios DB → referencia al runbook (conservando lo no-duplicado, §D.4)
- [ ] Tarea 5: `.planning/FOLLOWUPS.md` → queda solo Agent Teams

---

## Riesgos

- **Ventana de settings.json (symlink vivo del autor)**: quitar el bloque hooks del repo desactiva hooks en vivo hasta correr el install.sh nuevo → mitigado: se hace en el mismo lote que reescribe install.sh, con orden que deja doble registro (inocuo: guards idempotentes, subagent-log dedupea) en vez de cero hooks, e instrucción explícita de correr `./install.sh` al probar el Lote 4.
- **Doble carga de skills/agents/hooks** (symlinks legacy + plugin) → install.sh limpia los legacy solo-si-apuntan-al-repo; verificable con `claude plugin details methodology@skills-dir`.
- **install.sh borra algo del usuario** → regla dura: solo elimina symlinks cuyo target resuelve dentro del repo; dirs reales se respetan con aviso; verificación con HOME fake es criterio de aceptación de la tarea.
- **`global/CLAUDE.md` cambia el comportamiento de TODOS los proyectos del usuario** → el contenido es el que ya aplicaba por intención; el review dual debe verificar específicamente que no se filtró nada repo-específico (checklist para los reviewers en el handoff de Fase 3).
- **Cache del plugin congela la versión para terceros** → documentado: release = bump + tag + `plugin update`; el autor no lo sufre (skills-dir en vivo).
- **Markers/snapshots viejos huérfanos** bajo `~/.claude/methodology/` → acotados e inertes; limpieza manual documentada; pérdida aceptada de un aviso de staleness pendiente (una sola vez).
- **`claude plugin validate` no disponible en CI/máquinas viejas** → test-plugin-manifest.sh hace skip declarado (el test de paridad, que es el crítico, no depende de la CLI).
- **Suite adversarial** debe cerrar verde: los 3 tests de pre-push se reemplazan 1:1 + 2 nuevos — el total nunca decrece; el guard de no-contaminación falla ruidosamente si algún test vuelve a tocar el repo real.
