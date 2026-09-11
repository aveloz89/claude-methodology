## Review: pre-push `feature/hook-skip-planning-only` — el hook de pre-commit salta suites en commits de solo `.planning/` y exige DB de test propia por worktree

| Campo | Valor |
| --- | --- |
| Branch | `feature/hook-skip-planning-only` |
| Base | `dev` |
| SHA revisado (ronda 1) | `b108ad8` |
| SHA revisado (ronda 2) | `2825e81` |
| Fecha | 2026-09-12 |
| Reviewers | `security-reviewer` (opus) · `qa-backend` (sonnet), en paralelo sobre `git diff dev...HEAD` |
| Ronda 3 (solo tests, sin re-review) | `28370cd` — 271 asserts |
| **Veredicto final** | **APROBADO** (ambos en ronda 2) |

Reportes íntegros: `pre-pr-hook-skip-planning-only-security.md`, `pre-pr-hook-skip-planning-only-qa-backend.md`.

### Resumen

Regla de 3 desde easy-quotes (#212, #247, #253): `pre-commit-guard.sh` gana un salto estricto cuando lo único con cambios locales en el árbol es `.planning/**` y el comando no redirige git a otro árbol; el runbook y los prompts de `qa-*` exigen base de test propia a quien corra suites desde un worktree; `global/CLAUDE.md` y `README.md` documentan la condición.

### Seguridad

Ronda 1: **CAMBIOS REQUERIDOS** — 1 HIGH (el salto se decidía sobre el árbol del cwd aunque el comando commiteara en otro árbol: `cd <wt> && git commit` → exit 0 sin suites; reproducido con worktree real), 1 MEDIUM (invariantes sin pinear), 3 LOW. Sin superficie OWASP; 24 escenarios adversariales de forma del path, todos del lado seguro.
Ronda 2: **APROBADO** — HIGH cerrado (tabla `dev`/`b108ad8`/`2825e81`: vuelve a correr el runner), MEDIUM cerrado con 6 mutaciones (5 mueren), LOW cerrados. Dos LOW nuevos aplicados antes del push: `pushd`/`cd` pelado y el fake `git` del caso fail-closed.

### QA Backend

Ronda 1: **CAMBIOS REQUERIDOS** — `README.md:29` describía el hook sin el salto (DoD anti-drift del runbook). Mutación del salto verificada; 231/231, manifest 19/19, `claude plugin validate --strict .` verde. Hallazgo ambiental confirmado: el hook valida el árbol del cwd de la sesión, no el del comando → issue #73.
Ronda 2: **APROBADO** — README y `global/CLAUDE.md` alineados sobre la misma condición; fix del HIGH quirúrgico; 257/257. Sugerencia aplicada antes del push: rename dentro de `.planning/`.

### Veredicto

**APROBADO** tras 2 rondas.

#### Bloqueantes
- [x] HIGH: no saltar si el comando redirige git a otro árbol (`c0bb1d4`).
- [x] `README.md` describe el salto (`2825e81`).

#### Sugerencias aplicadas antes del push
- [x] Casos pineados: hermanos del prefijo, `.planning` regular, lista vacía, `git status` fallando, renames (`af06933`).
- [x] `(cd|pushd)\s` y `cd` pelado; fake `git` que imprime y sale 1; rename dentro de `.planning/` (ronda 3, solo tests).

#### Diferido
- [ ] #73 — el hook valida el árbol del cwd de la sesión (raíz de #212).

### NO CUBIERTO
- El cwd real del proceso del hook en el harness (ambos reviewers lo modelaron pasándolo explícito).
- `npm audit` (sin cambios de dependencias).
