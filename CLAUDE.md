# CLAUDE.md — claude-methodology

La metodología operativa (workflow, gitflow, dual review, TDD, formato de commits, hooks, `.planning/`, reglas por lenguaje) vive en [`global/CLAUDE.md`](global/CLAUDE.md), instalada como `~/.claude/CLAUDE.md` — ya está cargada en esta sesión junto con este archivo. Este documento cubre solo lo que es específico de este repo: cómo se edita a sí mismo y cómo se desarrolla/libera el plugin. **Prohibido duplicar contenido de `global/CLAUDE.md` aquí.**

## `rules/` vs `rulebooks/` — al editar ESTE repo

- `rules/` → reglas idiomáticas por lenguaje + principios de implementación que aplican al código.
- `rulebooks/` → procesos meta del sistema de agentes (budget, governance, validación, runbook). Aplican al *cómo trabajan los agentes*, no al código en sí.

**Cómo se cargan las `rules/`** (no obvio, y determina el costo de contexto): `~/.claude/rules/*.md` se carga solo. El frontmatter `paths:` decide cuándo — **con** `paths:` entra al tocar archivos que matchean; **sin** `paths:` entra en todas las sesiones de todos los proyectos. Un archivo nuevo en `rules/` sin frontmatter se vuelve contexto permanente sin que nadie lo note. Los `rulebooks/` no se cargan solos: se leen bajo demanda.

## Desarrollo del plugin

Este repo es plugin y marketplace de Claude Code a la vez (`.claude-plugin/plugin.json` + `.claude-plugin/marketplace.json`; hooks registrados en `hooks/hooks.json` vía `${CLAUDE_PLUGIN_ROOT}`). Reglas al tocarlo:

- **Paridad hooks.json**: cada `hooks/*.sh` (salvo `hooks/lib/`) debe estar registrado exactamente una vez en `hooks/hooks.json`, con el mismo evento/matcher/timeout que en `settings.json`. `tests/adversarial/test-plugin-manifest.sh` lo verifica; agregar/quitar un hook sin actualizar `hooks.json` rompe el registro del plugin en silencio.
- **Autor (dev-loop)**: se desarrolla con el symlink `~/.claude/skills/methodology` → raíz de este repo (`install.sh` lo crea), que carga en vivo como `methodology@skills-dir` sin version bump. No instalar el plugin propio vía marketplace en la misma máquina — duplicaría la carga.
- **Terceros**: instalan vía `claude plugin marketplace add` + `claude plugin install methodology@claude-methodology`, y corren `./install.sh` para el residual que el plugin no cubre (`global/CLAUDE.md`, `rules/`, `rulebooks/`, `statusline.sh`).
- **Release**: bump de `version` en `.claude-plugin/plugin.json` → `claude plugin tag` (valida consistencia plugin.json ↔ marketplace.json y crea el tag `methodology--v<version>`) → push del tag.
- **Validar antes de commitear cambios de manifest o agentes**: `claude plugin validate --strict .`

## Salud del sistema de agentes (recomendado, no bloqueante)

- **Adversarial Testing** (`tests/adversarial/`): valida que QA y security detecten code smells y vulnerabilidades plantadas adrede.
- **Validación periódica** (`tests/validation/`): prompts canónicos con expected behaviors documentados.

Frecuencia recomendada: mensualmente, antes de cada release significativo, o después de modificar prompts de agentes.
