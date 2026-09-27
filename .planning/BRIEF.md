## Brief: cerrar issues abiertos (#78, #71, #73, #77)

### Objetivo
Cerrar los 4 issues abiertos, uno por PR, en orden #78 → #71 → #73 → #77.

### Decisiones tomadas
- [D-01] (usuario) Los 4 issues, un PR cada uno, en ese orden.
- [D-02] (usuario) ~~#77 completo~~ → reemplazada por D-05: #77 acotado a errores honestos; las formas disfrazadas se documentan fuera de alcance, por costo.
- [D-03] (usuario) #78: autorizado a quitar el bloque `hooks` de `.claude/settings.json` después de verificar que el plugin carga los hooks.

### Brainstorming
Se salta: son bug fixes con causa raíz descrita en cada issue.

### #78 (este PR)
- Evidencia de que el plugin carga los hooks: los bloqueos de la sesión 2026-09-26 los atribuye a `methodology@skills-dir plugin`, y el contexto de SessionStart apareció duplicado al inicio de la sesión (plugin + settings.json).
- Cambio: quitar `hooks` de `.claude/settings.json` y dejar `permissions` intacto. Test que impida que vuelva.

### #71
- Decisión D-04: aclarar y cerrar. El registro del review lo escribe solo el orchestrator: consolida los reportes de reviewers que corren en paralelo, porque `security-reviewer`, `qa-backend` y `qa-frontend` tienen `Write`/`Edit` prohibidos. Se agrega una línea al runbook (Fase 2.6, paso 4) y a los 3 prompts: el reviewer devuelve su reporte y no escribe el registro.

### #73
- Alcance: `pre-commit-guard.sh` debe validar el árbol al que va el commit (`cd <ruta> && git commit`, `git -C <ruta> commit`, `--work-tree`/`--git-dir`, worktrees), no el cwd de la sesión. Si no puede resolverlo con seguridad, bloquea con un mensaje claro. Incluye la detección de repo de `pre-merge-check.sh` sin `--repo` (comentario del issue y #77 §4), que usa el cwd del hook.
- Coordinación: #77 viene después y toca el mismo saneo (`hooks/lib/guard-matching.sh`); este PR no reescribe el saneo compartido.

### PR final: #77 (errores honestos, D-05) + #86 (D-06: un solo PR)
- **#77, entra:**
  - `block-force-push`: `+main` (force por refspec), `-fu` (flags combinadas) y `git -C <ruta> push --force`.
  - `block-admin-merge`: `gh -R o/r pr merge --admin`.
  - `pre-release-sweep`: anclaje de `guard-matching` (`cd x && gh pr create --base main`) y fail-closed si falta jq o gh.
  - Bloqueo falso en vivo con heredocs que citan `gh pr merge` o `git commit`: primero un caso mínimo reproducible, cubierto como test que pasa.
  - NUL en el comando → bloquear.
  - Docs: header de wrappers `gh()` (`w() { gh "$@"; }` pasa), `--help`/`-h` en README y `global/CLAUDE.md`, ruta de `hooks/pre-merge-check.sh` en `global/CLAUDE.md` que no existe en un proyecto instalado, y mensaje contradictorio de `GH_REPO`/`GH_HOST`.
  - Verificar qué formas deja pasar el filtro `if` de `hooks.json` (LOW del review de #78: `env git`, `/usr/bin/git`).
- **#77, fuera de alcance (se documenta, no se arregla):** las formas disfrazadas de la sección 1 del issue (comillas partidas `\'`, `$'…'`, heredoc con delimitador comillado a medias, comentario con apóstrofo), la flag guardada en una variable, `eval`, `bash -c` y alias de git.
- **#86:** con la sesión en la raíz de un monorepo sin runner en la raíz, `git commit` pasa sin tests. Resolver con `workspace-scope.sh` (runners de los workspaces afectados por los archivos staged) o bloquear con un mensaje si hay cambios de código y no se encuentra runner.
