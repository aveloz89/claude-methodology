# Brief: Review dual pre-PR (ahorro de minutos de CI)

## Objetivo

Mover el review dual (security + qa-*) de después de crear el PR a **después del último commit de implementación + docs, ANTES del push y del PR**. Motivación del usuario (2026-08-14): cada ronda de fixes post-PR es un push extra = un run extra de GitHub Actions; con el review sobre el diff local, los fixes viajan en el push inicial y el PR nace revisado → un solo run de CI por PR en el caso normal.

## Flujo nuevo (a diseñar en detalle por el architect)

```
Fase 2.5: Documentación (docs sobre diff local, sin push)      [sin cambio]
Fase 2.6: Review dual LOCAL  ← NUEVO: security + qa-* sobre git diff <base>...HEAD
          + rondas de fixes locales (sin push) hasta veredictos limpios
          + sugerencias baratas aplicadas
Fase 2.7: Push + PR          [el PR nace revisado]
Fase 2.8: Monitoreo CI       [sin cambio]
Fase 3:   queda para lo post-PR: E2E Modo B si PR a main; re-reviews
          solo si CI obligó fixes que cambian código ya revisado
Fase 4:   Learn              [sin cambio]
```

## Alcance

1. **`rulebooks/orchestrator-runbook.md`**: renumerar/redefinir Fases 2.6–3; "Context isolation" (los reviewers reciben diff LOCAL, no `gh pr diff`); estructura del tracker ("Review dual local" como tarea separada de "PR + CI"); convención del registro de reviews (nace sin número de PR — el architect define el naming y cuándo se le añade el número).
2. **`skills/pr-workflow/SKILL.md`**: regla 2 reescrita (el review se lanza al terminar docs, no al crear el PR); la regla "un push por ronda" queda solo para rondas post-PR (fixes de CI, re-reviews sobre PR existente); revisar coherencia de 5.1/5.2.
3. **`global/CLAUDE.md`**: la descripción del flujo/review dual donde aparezca (el invariante "review dual bloqueante antes de merge" NO cambia — solo se adelanta el momento).
4. **`hooks/post-pr-create.sh`**: de "instruye lanzar reviews" a **checkpoint de respaldo**: verifica/pregunta si el PR ya pasó review dual pre-push; solo instruye lanzarlo para PRs creados fuera del flujo. Actualizar sus tests si los tiene.
5. **`agents/security-reviewer.md` y `agents/qa-*.md`**: si referencian "diff del PR"/`gh pr diff` como fuente, generalizar a "diff que el orchestrator indique (local o PR)".
6. **Anti-drift completo** (DoD de cambios de proceso): grep de `pr diff|crear el PR|post-pr|Fase 2.7|Fase 2.8|Fase 3` en CLAUDE.md (ambos), README, rulebooks/, agents/, skills/ y reconciliar TODO documento que describa el orden viejo.

NO incluye: cambios a `skills/review-pr` (re-disparo manual post-PR — sigue válido tal cual), a E2E Modo B (queda post-PR, pre-release a main), ni al presupuesto de review proporcional (aplica igual en pre-PR).

## Decisiones tomadas

- [D-01] El invariante de CLAUDE.md global no cambia: review dual bloqueante antes de merge. Cambia el MOMENTO: antes del push inicial.
- [D-02] `post-pr-create.sh` se conserva como red de seguridad para PRs fuera del flujo (no se elimina).
- [D-03] E2E Modo B sin cambio (post-PR a main).
- [D-04] Dogfooding: ESTE MISMO PR estrena el orden nuevo — review dual sobre el diff local antes de su push + PR.
- [D-05] Las rondas de fixes pre-PR no pushean nada; la regla "un push por ronda" sobrevive solo para el caso post-PR.

## Restricciones

- Los reviewers pierden acceso a `gh pr view/diff` en el caso pre-PR: el paquete de contexto debe darles base y branch para `git diff` local (o el diff inline). Los reviewers remotos necesitan el branch PUSHEADO para clonarlo — conflicto con "review antes del push": el architect debe resolverlo (opciones: reviewers locales por defecto; o push del branch SIN crear PR — pushear un branch no gasta Actions si los workflows disparan on: pull_request y no on: push de branches — verificar qué asume la metodología y documentar la condición).
- Suite adversarial verde; si `post-pr-create.sh` tiene tests en test-hooks.sh, actualizarlos con TDD.
- CLAUDE.md del repo ≤~200 líneas; global/CLAUDE.md sigue global-safe.
