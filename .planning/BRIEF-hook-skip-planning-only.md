# Brief: el hook de pre-commit deja de estorbar en commits de solo `.planning/` y en worktrees (2026-09-12)

> Branch `feature/hook-skip-planning-only` sobre `dev`. Origen: regla de 3 en easy-quotes — el hook `pre-commit-guard.sh` estorbó en tres PRs seguidos: #212 (no sabe de worktrees: valida el árbol principal desde un commit del worktree), #247 (un flake bloqueó un commit de puro markdown en `.planning/`) y #253 (colisionó con la suite de backend que un reviewer corría en su worktree desechable contra la misma base de test). El usuario eligió **las dos** medidas.

## Objetivo

Que un commit que solo toca `.planning/**` no pague ~2 min de suites (ni pueda ser bloqueado por un flake), y que ningún agente en worktree pise la base de test del árbol principal.

## Alcance

### Incluye
1. `hooks/pre-commit-guard.sh`: tras detectar `git commit`, si **todos** los archivos con cambios locales (staged, sin stagear y untracked — la misma unión y el mismo motivo PreToolUse que `_workspace_scope_match` en `hooks/lib/workspace-scope.sh`) caen bajo `.planning/`, avisa por stderr y sale con 0 sin correr suites. Conservador: lista vacía o cualquier archivo fuera de `.planning/` → camino normal. Renames se evalúan por ambos lados. Tests en `tests/adversarial/test-hooks.sh`.
2. Base de test propia por worktree: `rulebooks/orchestrator-runbook.md` (template de handoff a devs y paquete de contexto de la Fase 2.6) y los prompts de `agents/qa-frontend.md`, `agents/qa-backend.md` (y `security-reviewer.md` si menciona worktrees): quien corra suites de backend desde un worktree desechable exporta una base de test propia (`TEST_DATABASE_URL` o el equivalente del proyecto).
3. `global/CLAUDE.md`, sección Hooks: una línea que diga que las suites se omiten cuando el commit solo toca `.planning/`.

### Fuera de alcance
- Que el hook corra las suites del worktree en vez de las del árbol principal (issue aparte si se quiere).
- Cambios en `hooks/hooks.json` (el hook ya está registrado; `test-plugin-manifest.sh` verifica paridad).

## Decisiones
- [D-01] Sin brainstorming ni architect: causa raíz identificada, sin contrato público nuevo ni dependencias, descrito con precisión suficiente (condiciones del `CLAUDE.md` global).
- [D-02] La condición de salto es estricta: solo `.planning/**`; nada de "docs" en general.

## Riesgos
- Un salto demasiado laxo dejaría pasar código sin tests: por eso la lista se calcula con la sobreestimación segura de `git status --porcelain --untracked-files=all`, igual que el scoping por workspace.
