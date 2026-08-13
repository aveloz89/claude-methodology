# Learnings

Retrospectivas post-merge. El orchestrator **prepend** una entrada (más reciente arriba) después de cada PR mergeado.

## Formato de entrada

```markdown
### [YYYY-MM-DD] PR #N — Título del PR

**Métricas:**
- Review rounds: N
- Hallazgos security: N (critical: N, high: N, medium: N, low: N)
- Hallazgos qa-frontend: N (stubs: N, coverage: N, edge cases: N, otros: N)
- Hallazgos qa-backend: N (stubs: N, coverage: N, edge cases: N, otros: N)
- Errores de build/CI: N
- Self-reflection atrapó: N (cosas que detectó antes del review, o "nada")
- Lotes ejecutados: N / Tareas: M
- Devs involucrados: [db-specialist? backend-dev? frontend-dev?]

**Qué salió bien:**
- [descripción]

**Qué causó re-work:**
- [descripción — y si era prevenible]

**Patrón potencial:** [sí/no — si sí, cuál y cuántas veces se ha visto]
```

Formato canónico vive en `rulebooks/orchestrator-runbook.md`. Si ahí cambia, este archivo debe alinearse.

---

## Entradas

(Las entradas se agregan aquí, la más reciente arriba)

### [2026-08-13] PR #49 — Modernización 2026: hooks de observabilidad, state.json y anti-drift

**Métricas:**
- Review rounds: 1 completa + 1 re-review acotado al diff de fixes + 1 ronda test-only
- Hallazgos security: 9 (critical: 0, high: 0, medium: 1 + 2 legacy, low: 5 + 1 legacy) → 3 issues legacy creados (#50–#52)
- Hallazgos qa-frontend: no aplica (sin UI)
- Hallazgos qa-backend: 1 bloqueante (portabilidad GNU de `stat -f %m` — reproducido en Docker) + 3 sugerencias + 1 observación de datos (log con duplicados y unknowns)
- Errores de build/CI: 0 (repo sin CI; suite adversarial local 56/56 en macOS y ubuntu:22.04)
- Self-reflection atrapó: 2 antes del review — el ciclo TDD del Lote 1 se rehízo para preservar RED genuino, y el test de rotación del Lote 2 destapó que `jq -n` sin `-c` rompía el contrato JSONL
- Lotes ejecutados: 5 / Tareas: 25 (+7 de ronda de fixes +1 test-only)
- Devs involucrados: backend-dev (todos los lotes), docs, architect (fable)

**Qué salió bien:**
- Presupuesto explícito en prompts de reviewers (memoria del PR #48 aplicada): security cerró en ~20 min con NO CUBIERTO declarado, re-review de QA en ~10 min acotado al delta. Cero rondas de 40 min.
- La regla anti-drift pagó en su PR de estreno: el grep del Lote 5 encontró drift adicional en el propio runbook (template de handoff, Fase 3) además de los 4 agents que el Lote 4 ya había señalado.
- El usuario empujó a no diferir la calidad del log a la retro → diagnóstico con evidencia en el momento (doble registro user+project scope = doble disparo; unknowns = subagentes anidados) y fix en el mismo PR (dedupe + `raw_keys`).
- QA verificó portabilidad empíricamente (Docker ubuntu:22.04), no solo por análisis — así se confirmó el blocker y después el fix.

**Qué causó re-work:**
- El DESIGN declaraba "helper dual de stat" como patrón portable, pero una de las tres implementaciones usó la forma con espacio (`stat -f %m`) que en GNU falla en silencio. Prevenible: shellcheck no ve semántica de binarios externos; la verificación cross-platform necesita ejecución real (Docker), no solo lint. El fix costó 1 ronda extra.
- El PR body inicial atribuía al PR los commits de hardening que ya estaban mergeados en dev vía PR #48 (branch reutilizado por decisión de single-PR). El security-reviewer lo detectó; corregido con `gh pr edit`. Prevenible comparando `git log dev..HEAD` contra el diff real antes de redactar el body.

**Patrón potencial:** sí, dos. (1) "Portabilidad declarada ≠ portabilidad verificada" — 1ª vez; si reaparece, agregar a la verificación pre-commit de hooks un run en contenedor Linux. (2) La suite adversarial manipula el repo REAL (`git stash`/`checkout` en tests de guards) — casi causa pérdida de estado durante el re-review; follow-up creado para sandboxearla como los hooks nuevos.
