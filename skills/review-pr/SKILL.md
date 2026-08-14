---
name: review-pr
description: Re-dispara manualmente el review dual (security + QA según capas tocadas)
  sobre un PR existente, sin pasar por el flujo completo del orchestrator.
user-invocable: true
allowed-tools: Read, Grep, Glob, Bash, Agent(security-reviewer), Agent(qa-frontend), Agent(qa-backend)
argument-hint: "<número de PR> [security|qa|full]"
---

# Review PR

Re-dispara el review dual sobre un PR existente sin pasar por el flujo completo del orchestrator. Cubre dos casos: revisar un PR que no nació del flujo (o cuyo review automático falló), y **re-lanzar solo los reviewers que marcaron issues** después de una ronda de fixes.

Instalada vía plugin se invoca como `/methodology:review-pr`.

## Argumentos

- `$1` — Número de PR. Si falta, lista los abiertos con `gh pr list --state open` y pregunta al usuario cuál.
- `$2` (opcional) — Alcance del review:
  - `full` (default) — security-reviewer + QA según capas tocadas
  - `security` — solo security-reviewer
  - `qa` — solo QA (qa-frontend y/o qa-backend según capas)

## Flujo

### 1. Validar el PR

Si `$1` no es un entero (`^[0-9]+$`) → **abortar con aviso**: el argumento debe ser el número del PR, no un branch ni una URL.

```bash
gh pr view $1 --json number,title,state,isDraft,baseRefName,headRefName,additions,deletions,files
```

Si `state` es `MERGED` o `CLOSED` → **abortar con aviso**: el review solo aplica a PRs abiertos.

### 2. Detectar capas tocadas

Sobre la lista `files` del PR:

- **Frontend** — extensiones `.tsx .jsx .vue .svelte .html .css .scss`, o dirs `components/ pages/ app/` con UI → lanza `qa-frontend`
- **Backend** — extensiones `.py .go .rs .cs .sh`, dirs `api/ server/ db/ hooks/ migrations/`, o Dockerfile/compose → lanza `qa-backend`
- **Ambas capas** → ambos QA
- **Ninguna clara** (docs/config puros) → `qa-backend` como default (dueño de contratos y procesos)

Si el alcance es `security`, este paso solo informa; no se lanza QA.

### 3. Presupuestar el review (proporcional al diff)

Con `additions + deletions` del paso 1:

| Tamaño del diff | Presupuesto en el prompt del reviewer |
|---|---|
| < 300 LoC | "cierra en ~10–15 min" |
| 300–1000 LoC | "cierra en ~20–25 min" |
| > 1000 LoC | presupuesto por área con prioridades explícitas; profundidad justificada en el prompt |

**Siempre**, sin importar el tamaño, el prompt incluye el mandato de cierre: «veredicto + findings + sección **NO CUBIERTO** declarada — lo que no alcances no lo revises, decláralo». Ping de status a los ~15 min si el reviewer sigue corriendo.

### 4. Lanzar los reviewers en paralelo

Lanza los reviewers del alcance **en paralelo** (single message, multiple Agent calls). Handoff a cada uno:

- Número de PR + branch (`headRefName`)
- Diff del PR (`gh pr diff <N>`)
- `.planning/BRIEF.md` y `.planning/DESIGN.md` si existen (para juzgar el código contra lo que se quería)
- Presupuesto del paso 3
- Formato de salida esperado (paso 5)

### 5. Reporte

Consolida los hallazgos en el formato del runbook («Formato de reporte de review» en `~/.claude/rulebooks/orchestrator-runbook.md`: Resumen / Seguridad / QA Frontend / QA Backend / Veredicto / Bloqueantes / Sugerencias) **+ sección NO CUBIERTO**.

- Publica en el PR: `gh pr comment <N> --body "<reporte>"`
- Copia en `.planning/reviews/PR-<N>.md`. Si el archivo ya existe, **append** de una sección `## Re-review <fecha>` — nunca pisar la historia.

## Qué NO hace esta skill

- **No mergea, no pushea, no fixea.** Solo revisa y reporta.
- Los fixes siguen el flujo normal: mismo branch/PR, y re-review acotado al delta (re-lanzando esta skill con alcance `security` o `qa` según quién marcó los issues).
