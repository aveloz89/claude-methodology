# STATE

## Estado actual

- **Feature:** Modernización 2026 de memoria y agentes (+ hardening pre-merge ya commiteado en el mismo branch)
- **Fase:** listo para merge — esperando aprobación explícita del usuario. Security APROBADO, QA APROBADO (re-review de la ronda de fixes), suite 56/56 (macOS + ubuntu:22.04)
- **Branch:** feature/harden-pre-merge-check
- **PR:** (pendiente — único PR a dev con hardening + modernización)
- **Última actualización:** 2026-08-13

## Progreso

- [x] Investigación completada (AUDIT-memory-agents-2026-08.md)
- [x] Decisión Notion documentada en ARCHITECTURE.md
- [x] Brainstorming: saltado con justificación (ver BRIEF.md)
- [x] BRIEF.md escrito
- [x] DESIGN.md del architect validado (5 lotes × 5 tareas, secuenciales, todos backend-dev)
- [x] Lotes implementados (5/5, TDD, suite adversarial 40/40)
- [x] Documentación (Fase 2.5 — 1 commit: tests/adversarial/README.md)
- [x] Push + PR (Fase 2.7 — PR #49 a dev)
- [x] CI: no aplica (el repo no tiene workflows de Actions; verificado con gh pr checks)
- [x] Review dual aprobado (security APROBADO 0 blockers + 3 issues legacy #50–#52; qa-backend APROBADO tras 1 blocker corregido — stat GNU — y ronda de fixes verificada)
- [ ] Merge aprobado por el usuario

## Notas para la retro (Fase 4)

- Log de invocaciones: verificar post-merge que el dedupe eliminó las entradas duplicadas y que los `unknown` traen `raw_keys` (siguiente aparición identifica el campo real del harness).
- La suite adversarial hace `git stash`/`checkout` sobre el repo REAL en los tests de pre-push-guard — casi causa pérdida de estado durante el re-review de QA (bind mount en Docker). Candidato a sandboxearse como los hooks nuevos.
- El presupuesto explícito en prompts de reviewers funcionó: security ~20 min con NO CUBIERTO declarado, QA re-review ~10 min.

## Decisiones

- [D-01] Usuario: todo en un solo PR sobre feature/harden-pre-merge-check (excepción consciente a "un PR por objetivo").
- [D-02] Notion y backends externos de memoria descartados — decisión con triggers de reevaluación en ARCHITECTURE.md.
- [D-03] Piloto de memory: true limitado a e2e-runner.
- [D-04] Los guards existentes siguen siendo hooks command (determinismo); los tipos prompt/agent no se adoptan en este PR.
- [D-05] effortLevel: xhigh (cambio pendiente en settings.json) viaja en este PR.

## Blockers

- ninguno
