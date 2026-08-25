# Review dual pre-push — feature/followups-sweep (Fase 2.6)

**Branch:** feature/followups-sweep · **Base:** dev · **Fecha:** 2026-08-25 · Presupuesto: ~12 min/reviewer ronda 1, decreciente hasta ~6 en la última

Barrido de **ocho follow-ups** en un solo PR, por pedido del usuario. Un commit atómico por ítem. Cuatro de shell (dev) y cuatro de documentación normativa (orchestrator).

## Los ocho ítems

| # | Ítem | Quién |
|---|---|---|
| 1 | `pre-merge-check.sh` honra `--repo` — ningún PR de otro repo se podía mergear desde una sesión | dev |
| 2 | `grep` en el check de dependencias del mismo guard, que fallaba **abierto** sin él | dev |
| 3 | La rama literal de `workspace-scope.sh` verifica `package.json`, igual que la de glob | dev |
| 4 | Entrada hostil sobre `guard_sanitize`: comillas sin terminar, continuaciones, payload de 600 KB | dev |
| 5 | `.planning/` sumado al grep del DoD anti-drift | orchestrator |
| 6 | Scope de `qa-backend` fijado para diffs de metodología | orchestrator |
| 7 | Las etiquetas de agentes creadas en el scaffold de `new-project` | orchestrator |
| 8 | `rules/bash.md`, el único lenguaje sin reglas idiomáticas | orchestrator |

## El ítem 1 se llevó cinco rondas, y esa es la historia del PR

El fix del `--repo` osciló entre dos fail-opens espejo. Las cuatro direcciones tienen la misma raíz: **intentar adivinar el límite de una ventana de texto que ya perdió estructura en el saneo.** Cada intento de adivinar mejor destapó su contrario.

| Ronda | Dirección | Síntoma |
|---|---|---|
| 1 | `--repo` no anclado a la invocación de merge | `gh pr list --repo victima/otro && gh pr merge 3` → el guard verificó `victima/otro#3`, lo encontró limpio y devolvió `continue:true` |
| 1 | El parseo no modelaba a `gh` | `-R` no se detectaba; ganaba el primero y no el último; valor comillado destruido por el saneo caía al cwd |
| 2 | La ventana cortaba en cualquier `)`/`}`/backtick | `--match-head-commit $(git rev-parse HEAD) --repo real/repo` perdía el `--repo` real y caía al cwd. **Regresión**: el código de la ronda 1 lo resolvía bien |
| 3 | El contador no miraba su estado al llegar a fin de ventana | `--body \(` dejaba la profundidad en >0, `;` dejaba de cortar, la ventana se comía el comando vecino y su `--repo` ganaba |
| 4 | Cierre o separador **escapado** en profundidad cero | `--body foo\)` cortaba temprano y caía al cwd en silencio. Lo encontró el **dev**, verificado, y lo reportó sin arreglarlo |

**La regla que terminó la oscilación no elige mejor dónde cortar: reconoce que una ventana indeterminada no es una ventana.** Cualquier backslash que llegue al tokenizer, o cualquier abridor sin cerrar dentro de la ventana, la vuelve indeterminada y bloquea. Decisión del usuario entre tres opciones, con el falso positivo aceptado explícitamente: un backslash legítimo sin comillas bloquea igual.

## Veredictos

**security-reviewer** — ronda 1 BLOQUEADO (3 HIGH, 3 MEDIUM, 4 LOW) · ronda 2 BLOQUEADO (1 HIGH nuevo, introducido por el fix) · ronda 3 BLOQUEADO (1 HIGH, la imagen espejo) · **ronda 4 APROBADO sin findings**.

Además de las direcciones del `--repo`, encontró tres errores míos en `rules/bash.md`, el archivo contra el que se van a revisar todos los hooks de este sistema: el idioma `grep -cv` escrito de forma ambigua y falso bajo la lectura natural; `${var:?}` recomendado sin la excepción de hooks que sí tiene `set -e`, cuando produce el mismo fail-open; y la regla de la cadena vacía escrita como absoluto, contradiciendo al propio `pre-merge-check.sh`, donde el texto crudo tampoco es seguro porque el consumidor **extrae un dato**. Escribí reglas de shell sin ejecutarlas.

En el cierre verificó el perl nuevo del tokenizer —el foco que le pedí, porque entraba perl al path caliente de un guard justo donde vivía el ReDoS de esta mañana— y salió limpio: sin backtracking, lineal hasta 1 MB medido, `alarm(5)` degradando a bloqueo antes de tocar el cwd.

**qa-backend** — ronda 1 BLOQUEADO (3 bloqueantes) · **ronda 2 APROBADO**.

Sus tres bloqueantes fueron los más estructurales del PR:

1. **Contradicción de etiquetas, agravada por este mismo PR.** `global/CLAUDE.md` era el único archivo que seguía diciendo `scoped-out-violation`; los otros seis dicen `controversial-fix`. Rastreó el origen a un commit de mayo que renombró sin tocarlo. Mi scaffold heredó el lado muerto: creaba la etiqueta que ningún agente lee y omitía la que usa el paso 6 del pre-commit — el modo de falla exacto que ese ítem venía a cerrar.
2. **Siete de los ocho follow-ups que este PR cierra seguían listados como pendientes.** Autocontradictorio dentro del mismo diff.
3. **La clasificación por capa no ruteaba shell ni metodología**, que es la sección que decide si `qa-backend` se invoca. Las reglas nuevas de este PR eran inalcanzables por el ruteo automático: en esta sesión funcionó solo porque las pedí a mano.

## Verificación del orchestrator (no delegada)

- Suite corrida en cada ronda: 147 → 176 → 188 → 200 → 206 → **213 pasando**, `test-plugin-manifest.sh` 19/19.
- El idioma `grep -cv` verificado con datos antes de reescribir la regla — el matiz: en mi fixture los conteos dieron 1 y 2, no idénticos como ilustró security; su ejemplo era un artefacto de su archivo. El punto de fondo se sostiene igual.
- Rastreo del rename de la etiqueta confirmado con `git show` antes de corregir.

## Acoplamiento que queda documentado en el código

La regla del backslash sólo es viable porque `guard_sanitize` une las continuaciones de línea **antes** del tokenizer. Un refactor que cambie ese orden convierte el chequeo en un over-block masivo: bloquearía todo merge multilínea. Lo encontró security y quedó escrito en el bloque.

## Corrección de un reporte del dev

Para el fix de `grep` (`efa7e95`) el dev reportó "1 test en rojo" y son **3**: el mismo commit cambió el mensaje esperado del helper compartido. Lo detectó qa-backend, el dev lo verificó y lo corrigió en el mensaje del commit siguiente. No se reescribió la historia: el branch ya había avanzado con commits de otro agente y `git reset --hard` está bloqueado por hooks. Queda acá.

## Cierre

Veredictos limpios en la última ronda de cada reviewer. La etiqueta *no verificable* del corolario se invocó tres veces en este PR y las tres fueron legítimas: los tests hostiles (cobertura nueva, sin defecto que arreglar), el test de la forma Enterprise (documenta comportamiento preexistente) y el comentario del acoplamiento.
