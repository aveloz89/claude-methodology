# Review dual pre-push — fix/guard-sanitize-redos (Fase 2.6)

**Branch:** fix/guard-sanitize-redos · **Base:** dev · **SHA revisado:** `723207c` · **Fecha:** 2026-08-25 · Presupuesto: ~8 min/reviewer ronda 1, ~6 y ~5 en las siguientes (diff +188/−3 inicial, 10 commits al cierre)

## Origen

`guard_sanitize()` sanea el texto de CADA comando Bash antes de que los tres guards decidan si bloquean. Su regla de heredocs usaba `(?:(?!^[ \t]*\1$).*\n?)*` bajo `/s`: cuantificador anidado sobre texto solapado, o sea backtracking catastrófico. Con 8 líneas de heredoc sin terminador no terminaba nunca.

No es teórico: durante esta sesión se midieron hasta cinco `perl` simultáneos al 100% de CPU durante nueve minutos, dos veces, hasta matarlos a mano. Cada llamada Bash del harness paga tres saneos (uno por guard), así que un solo comando patológico clava tres núcleos y cuelga la llamada indefinidamente.

## Ronda 1

### security-reviewer — APROBADO (0 CRITICAL/HIGH, 3 LOW)

El hallazgo principal fue en dirección **contraria** a la sospecha del brief: el regex nuevo no sanea de más, sanea de menos — y de paso **cierra un fail-open real del regex viejo**. Payload: dos heredocs bien formados con el mismo delimitador y un `gh pr merge --admin` entre ellos. Bash lo ejecuta; el greedy se estiraba hasta el último `EOF` y se tragaba el comando, así que el guard nunca lo veía. Evasión explotable sin necesidad de colgar nada, viva desde que se escribió la lib.

Verificado contra la verdad de campo, no por lectura: 12 payloads ejecutados con `bash` real (con marcador para distinguir "lo ejecuta" de "lo trata como literal") comparados contra ambos regex. Cero casos donde el nuevo oculte algo que bash ejecuta.

LOW-1: el fail-open cerrado no estaba documentado, y el comentario mezclaba dos propiedades distintas — `[^\n]*\n` da la terminación, lo no-greedy elige el primer terminador como bash. LOW-2: el fallback sin sanear vuelve alcanzable en `pre-merge-check.sh` un camino donde el número de PR se extrae de texto crudo (reproducido: un señuelo en un mensaje de commit hacía validar el PR equivocado). LOW-3: `alarm 2` es margen escaso en máquina cargada; 348 KB en caso lineal tardan 0.0s, así que 5s no debilita nada.

### qa-backend — CAMBIOS NECESARIOS (1 bloqueante)

**Bloqueante:** el mensaje del commit afirmaba verificación de equivalencia en 5 casos de heredocs legítimos; el repo persistía **1**. Dos tenían cobertura incidental por tests viejos de otro propósito y "dos heredocs consecutivos" no tenía ninguna. La verificación vivía en un harness desechable fuera del repo.

**Sugerencia que el orchestrator subió a obligatoria:** el `kill -9` del watchdog del test nuevo no mata al `perl` hijo del pipe — queda huérfano quemando CPU sin límite. Subida porque es exactamente el fallo que la sesión llevaba horas apagando a mano, y quedaría enterrado en el test que existe para atrapar la regresión: en CI reportaría FAIL y dejaría el core ardiendo.

QA verificó sin creerle al dev: reconstruyó el regex viejo desde `dev`, confirmó que no termina en 10s con el payload del test, y comprobó que el mock del fallback usa `exit 142` porque es exactamente lo que devuelve un `alarm` real sin `$SIG{ALRM}`.

## Ronda 2 (delta `17fbcae..HEAD`)

### security-reviewer — APROBADO (1 MEDIUM, 2 LOW)

**Retiró su propia tabla de la ronda 1**, confirmando la corrección del dev: el swallow silencioso exige el **mismo** nombre de delimitador en ambos heredocs (9 ms); con delimitadores distintos el regex viejo no traga, se cuelga (5s, timeout). Donde su tabla decía "HIDES" era "TIMEOUT".

**MEDIUM (causado por decisión del orchestrator):** el bloqueo por saneo fallido quedó **antes** del check de "esto es realmente un `gh pr merge`". Como el hook corre sobre todas las llamadas Bash, un saneo fallido bloqueaba `ls -la`, `cat README.md` o `git status` con un mensaje sobre extracción de números de PR. Alcanzable sin trampas: 4000 aperturas `<<palabra` en 122 KB agotan el `alarm` por sí solas. Fail-closed, sin ventana — daño de disponibilidad, no de integridad.

### qa-backend — CAMBIOS NECESARIOS (1 bloqueante)

**Bloqueante — test que pasa por la razón equivocada:** `assert_watchdog_no_orphan_perl` reimplementaba su propio loop de watchdog en vez de ejercitar `assert_guard_sanitize_bounded`. QA lo verificó borrando el `pkill -9 -P` real: la suite seguía en 140/140 con ese test en verde. Peor: con el regex ya arreglado, ningún payload de la suite dispara el timeout de esa función, así que la rama del kill no tenía cobertura por ningún camino.

## Ronda 3 (delta `1d943b0..HEAD`) — security únicamente

**APROBADO**, sin CRITICAL/HIGH/MEDIUM. Verificó empíricamente que el gate permisivo nuevo no deja pasar ningún merge real: plano, mayúsculas, espacios extra, sin número, encadenado, número en variable, con comentario, y también partido con continuación de línea. Las únicas evasiones que encontró (`A=g; B=h; $A$B pr merge 7`, eval/base64, alias) derrotan por igual al check anclado del camino con perl sano y son preexistentes, no introducidas por este delta.

**LOW, derivado a otro PR por el propio reviewer:** `grep` no está en el check de dependencias del hook. Sin `grep` el gate deja pasar un merge real, pero el guard ya fallaba abierto por el mismo motivo en el camino dominante — extiende un fail-open preexistente, no crea uno nuevo.

qa-backend **no se relanzó** en esta ronda: su bloqueante era de integridad del test y lo verificó el orchestrator con el criterio objetivo acordado (ver Cierre).

## Rondas de fixes

| Ronda | Commits | Qué cerró |
|---|---|---|
| 1 | `3e10863`, `3f9ad63`, `1996c73`, `fd320ca`, `1d943b0` | Bloqueante de QA (equivalencia persistida + regresión del fail-open), huérfano del watchdog, los 3 LOW de security |
| 2 | `5af7203`, `367003f`, `723207c` | Bloqueante de QA (helper de kill compartido), MEDIUM y LOW del `$?`, comentario desactualizado |

## Verificación del orchestrator (no delegada)

- Suite corrida por el orchestrator: `test-hooks.sh` **143/143**, `test-plugin-manifest.sh` **19/19**, sin `perl` huérfanos.
- Criterio objetivo del bloqueante de la ronda 2, exigido antes de darlo por cerrado: **borrar el `pkill` real tiene que poner algún test en rojo**. Evidencia del dev: 139/140 con la línea borrada (falla `assert_guard_sanitize_bounded`), 143/143 con ella. Estructura confirmada por el orchestrator: `guard_sanitize_watchdog_kill` se invoca desde las dos funciones.
- El efecto de `$(...)` sobre el salto de línea final (un byte menos que el pipe directo) se verificó inerte: `GUARD_ANCHOR` es ancla de prefijo y `grep` trabaja por líneas — el `--admin` sigue siendo detectable tras el saneo.

## Cierre

Veredictos limpios. `review_sha` = `723207c`. Registro reconciliable a `PR-<N>.md` en Fase 2.7.
