# Brief: Cierre de todos los issues abiertos (#47, #50, #51, #52)

## Objetivo

Un PR a `dev` que arregle los 4 issues abiertos del repo — sin crear issues nuevos: el usuario quiere arreglar, no acumular.

## Alcance

Incluye:

1. **#47** — `block-admin-merge.sh` y `pre-commit-guard.sh`: mismo matching frágil sobre `.tool_input.command` que ya se corrigió en `pre-merge-check.sh` (falso negativo con comandos compuestos en una línea; falso positivo con menciones quoted/heredoc). Fix de referencia: saneo de spans quoted/heredoc + ancla de posición de comando `(^|&&|\|\||;|\||\$\()` + regression tests.
2. **#50** — `pre-merge-check.sh` falla ABIERTO si faltan `perl` o `jq`: pasa a fail-closed (bloquea con "guard no operativo") — el bloqueo debe emitirse sin depender de jq.
3. **#51** — títulos de issues de terceros se inyectan verbatim en el contexto de sesión (`session-start-context.sh`, bloque `gh issue list`): truncar + strippear control chars (reusar `sanitize_text()` existente) + delimitador explícito de datos.
4. **#52** — `.gitignore` mínimo: agregar patrones defensivos de secrets (`.env`, `.env.*`, `*.pem`, `*.key`, `credentials.*`).

NO incluye: nada fuera de esos 4 issues. No se crean issues nuevos.

## Decisiones tomadas

- [D-01] **Helper compartido** `hooks/lib/guard-matching.sh` (saneo + ancla) extraído de `pre-merge-check.sh`, consumido por los 3 guards — una sola regex sutil con tres consumidores es el caso exacto de la regla anti-drift. `pre-merge-check.sh` se refactoriza para consumirlo: refactor pequeño necesario, dentro del scope, documentado en el PR body. `install.sh` symlinkea `hooks/` completo, así que `lib/` viaja solo; resolución vía `$(dirname "$0")`.
- [D-02] Brainstorming y architect saltados con justificación: bug fixes con causa raíz identificada y remediación especificada en los propios issues; la única decisión de diseño es D-01 (proporcionalidad — doctrina "escalar esfuerzo a la complejidad", LEARNINGS PR #49).
- [D-03] Estreno del formato `state.json` (schema D3 del PR #49): esta es la "siguiente feature" desde la que aplica.
- [D-04] El merge a `dev` no auto-cierra issues (default branch es `main`): se cierran manualmente post-merge con referencia al commit.

## Reglas de negocio / restricciones

- Los guards son bloqueantes: TDD obligatorio con regression tests por hook en `tests/adversarial/test-hooks.sh` (falso negativo compuesto, falso positivo quoted), sin romper los 56 tests existentes.
- El fail-closed de #50 nunca debe romper la emisión del JSON de bloqueo (sin jq disponible → printf de JSON estático).
- `session-start-context.sh` no debe romper su output actual (hay tests de regresión).
