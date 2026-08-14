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

### [2026-08-14] PR #56 — Review dual pre-push (Fase 2.6): el PR nace revisado

**Métricas:**
- Review rounds: 1 dual pre-push (estreno del flujo en su propio PR) + 1 ronda de fixes local sin re-review (cambio menor validado por tests)
- Hallazgos security: 2 MEDIUM (anclaje por SHA, sanitización de slug) + 2 LOW + 1 legacy adoptada (4º check pre-merge) — todos aplicados
- Hallazgos qa-backend: 3 sugerencias + 1 gap de cobertura declarado (detached HEAD) — todos aplicados
- Errores de build/CI: 0. **Runs de CI consumidos por el ciclo de review: 0** — el objetivo del cambio, cumplido en su primer uso
- Self-reflection atrapó: el barrido de docs cazó 8 secuencias del flujo viejo que el grep por palabras no podía atrapar (no mencionaban "review")
- Lotes: 3 (15 tareas) + ronda 2.6 (5+1) + docs. Devs: general-purpose con rol inyectado (transición al plugin), architect en fable
- Suites al cierre: 128/128 + 19/19

**Qué salió bien:**
- **El flujo nuevo se revisó a sí mismo y se mejoró en el acto**: el review pre-push de este PR encontró el hueco del anclaje (evidencia stale si hay commits post-review) y el fix entró en la misma ronda local — exactamente el ciclo barato que el cambio promete.
- Decisión del architect de NO renumerar fases (2.6 entra en el hueco existente): el costo anti-drift del cambio bajó drásticamente.
- El 4º check pre-merge estrenó en el propio merge de este PR, verificando evidencia real (`review_sha` ancestro, registro reconciliado).
- Muertes por límite de sesión a mitad de review: reanudar desde transcript preservó el avance (el ángulo del SHA que security venía persiguiendo sobrevivió al corte y terminó siendo el hallazgo principal).

**Qué causó re-work:**
- Nada estructural. La demo en vivo del hook en ESTA sesión requirió invocación manual (la sesión en limbo post-migración registró hooks desde el path viejo) — consecuencia ya conocida y documentada de la transición al plugin.

**Patrón potencial:** el par "review encuentra el hueco de evidencia → la evidencia se vuelve machine-readable → un check mecánico la exige" (checkpoint CASO A + 4º check) es la misma jugada que mató la clase C5 (test de paridad) — 2ª aparición de "convertir invariantes de proceso en verificación mecánica"; si aparece una 3ª, considerar regla explícita de diseño.

### [2026-08-14] PR #55 — Barrido de follow-ups: plugin de distribución, slug con hash, sandbox total y skill review-pr

**Métricas:**
- Review rounds: 1 dual + 1 ronda de sugerencias (sin re-review — cambios menores validados por tests, per skill)
- Hallazgos security: 3 LOW + 1 robustez + 1 adjudicación de contrato — 0 blockers; el checklist crítico (fuga repo-específica en global/CLAUDE.md) salió limpio
- Hallazgos qa-frontend: no aplica
- Hallazgos qa-backend: 4 sugerencias, 0 blockers; verificación empírica completa (suites + 5 escenarios de installer + tests validados por mutación)
- Errores de build/CI: 0 (sin CI; suites 110/110 + 19/19 verificadas por dev, QA remoto y orchestrator)
- Self-reflection atrapó: el validate del plugin destapó YAML roto en ui-ux.md (legacy) — arreglado en el lote, no estacionado
- Lotes ejecutados: 5 (22→24 tareas con las agregadas) + 1 ronda de sugerencias (5) + docs
- Devs involucrados: backend-dev (lotes 1–4), general-purpose con rol inyectado (lote 5, docs, sugerencias — ver hallazgo de transición), architect (fable, con verificación de CLI en vivo)

**Qué salió bien:**
- El architect verificó el formato del plugin contra la CLI real (ciclo add→install en HOME aislado) ANTES de diseñar — cero retrabajo por formatos asumidos.
- La ronda de sugerencias demostró RED real: los symlinks con `..` sí se borraban (el LOW de security era bug genuino, no teoría).
- El pulido del installer se validó con 22 assertions en HOME fake antes de tocar nada real.
- La instrumentación `raw_keys` del PR #54 pagó: primer análisis del log reveló la causa de los `unknown` (payload con `agent_type: null`, forma de evento Stop) — el diagnóstico diferido funcionó como se diseñó.
- **Migración en caliente gestionada**: quitar el bloque hooks del settings symlinkeado + install.sh inmediato dejó doble registro inocuo, nunca ventana sin guards (verificado con plugin details).

**Qué causó re-work:**
- **La migración des-registró los tipos de agente de la sesión corriendo** (el symlink legacy ~/.claude/agents era lo que los cargaba): los lotes 5+, docs y reviews corrieron con general-purpose + rol inyectado desde agents/*.md. Funcionó bien como workaround, pero es fricción. Lección: tras migrar el mecanismo de carga de agentes, la sesión debe reiniciarse — documentado; los flujos de instalación deben avisarlo.
- El watchdog mató un dev (600s sin progreso, probable CLI interactiva colgada) — mitigación que funcionó: reanudar con instrucción de timeout manual + stdin cerrado en toda invocación de `claude`.

**Patrón potencial:** sí, dos. (1) "Verificar contra el sistema real antes de diseñar/afirmar" — 3ª aparición (PR #49: stat en Docker; PR #54: repo público recalibró severidad; PR #55: CLI del plugin + RED del installer). **Regla de 3 alcanzada** → propuesta: añadir a `implementation-principles.md` o al prompt del architect la regla explícita "toda afirmación sobre comportamiento de plataforma/entorno se verifica ejecutando, no se asume de docs". (2) Rol inyectado como fallback de agentes nombrados — funcionó 4 veces; documentarlo en governance-playbook como respuesta estándar a "agente no disponible".

### [2026-08-14] PR #54 — Cierre de todos los issues abiertos: guards endurecidos, fail-closed y sanitización

**Métricas:**
- Review rounds: 3 (1 dual completa + 2 re-reviews acotados al delta)
- Hallazgos security: 7 en ronda 1 (0 critical/high, 4 medium, 3 low) + 1 medium en re-review (regresión espejada) — todos corregidos, cero diferidos
- Hallazgos qa-frontend: no aplica (sin UI)
- Hallazgos qa-backend: 2 bloqueantes marginales (falso positivo silencioso sin perl; dependencia dirname fail-open) — ambos resueltos y verificados empíricamente
- Errores de build/CI: 0 (repo sin CI; suite adversarial 91/91 verificada por dev, por QA en entorno aislado y por el orchestrator en el working tree real)
- Self-reflection atrapó: el TDD del lote 1 destapó que la sanitización línea-por-línea de títulos dejaba pasar payloads con newline embebido (cambiado a iteración por-registro en base64 antes del review)
- Lotes ejecutados: 1 de implementación (5 tareas) + 3 rondas de fixes (5+6+1) + docs (2 commits)
- Devs involucrados: backend-dev, docs

**Qué salió bien:**
- El RED de TDD demostró los bugs reales antes de arreglarlos (el falso negativo de `git fetch && gh pr merge --admin`, el caso espejo de comillas) — evidencia, no suposición.
- **Aislamiento remoto para reviewers**: la máquina del usuario entró en reposo repetidamente y mató 3 intentos del security local; relanzarlo con `isolation: remote` lo resolvió de raíz. Queda como respuesta estándar cuando la máquina puede dormirse.
- Estreno de `state.json`: el orchestrator respondió "¿está haciendo algo el dev?" con datos en vivo (3/5 tareas, tarea actual) en vez de adivinar.
- Directiva del usuario "follow-up = issue, se arregla ahora": las 3 rondas cerraron 13 hallazgos sin diferir ninguno — y el par review→re-review cazó que el primer fix de comillas espejaba el bug en vez de resolverlo.

**Qué causó re-work:**
- El fix de "invertir el orden" de las reglas de saneo de comillas espejó el falso negativo en vez de eliminarlo (1 ronda extra). Prevenible: cuando el fix propuesto es "cambiar el orden de dos reglas", sospechar que el problema es estructural (dos pasadas no modelan anidamiento) — la solución era una pasada con alternancia, como parsea el shell.
- 3 muertes del security-reviewer local por reposo de la máquina (~30 min perdidos). Mitigaciones: `isolation: remote` para tareas largas en background, o `caffeinate` si el usuario se aleja.

**Patrón potencial:** sí — "el reviewer valida al fixer": 2ª vez consecutiva (PR #49: QA cazó el stat GNU tras el fix del dev; PR #54: security cazó el espejo tras su propia sugerencia). El re-review acotado al delta post-fix se confirma como paso no negociable, ya codificado en la skill pr-workflow.

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
