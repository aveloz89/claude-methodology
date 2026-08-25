# Review dual pre-push — feature/verification-rule (Fase 2.6)

**Branch:** feature/verification-rule · **Base:** dev · **SHA revisado:** `749d9b2` · **Fecha:** 2026-08-25 · Presupuesto: ~5 min/reviewer ronda 1, ~4 en la ronda 2 (diff 8 archivos, 100% markdown normativo)

## Origen

El patrón "verificar contra el sistema real antes de afirmar" llegó a su **5ª aparición** en `LEARNINGS.md`, con cinco instancias dentro de una sola sesión. La regla de 3 se había dado por alcanzada en el PR #55, con la propuesta concreta de escribirla en `rules/` — y nunca se escribió. Este PR la escribe.

## Ronda 1

### security-reviewer — BLOQUEADO (2 HIGH, 2 LOW)

**HIGH-1 — el corolario obligaba a los QA a violar su propia política de tools.** `qa-backend` y `qa-frontend` tienen `disallowedTools: Write, Edit` y "no escribes código" repetido en su cuerpo. La instrucción "borra la línea del fix y corre la suite" solo era ejecutable rodeando esa política vía Bash (`sed -i`). Además, las dos líneas agregadas a los agentes **omitían el paso de restaurar** que sí estaba en la regla: un agente cortado a la mitad dejaba el fix borrado en el árbol.

**HIGH-2 — "borrar la línea del fix" no es una operación definida.** Falla cuando el fix es un borrado, cuando es multilínea, cuando es configuración sin suite, y sobre todo cuando es un token (`<=` → `<`): ahí borrar la línea entera rompe la sintaxis, la suite se pone roja **por la razón equivocada** y el check pasa vacío — simulando justo la verificación que el principio quiere instalar. Con veredicto binario y bloqueante encima.

Confirmó que el principio 5 no choca con el 3: uno resuelve incertidumbre sobre **intención** (preguntar), el otro sobre **hechos del sistema** (ejecutar). El 5 tapa un hueco del 3, que hasta ahora solo ofrecía preguntar.

### qa-backend — BLOQUEADO (2 bloqueantes)

**Espejo de `paths:` roto.** `implementation-principles.md` y `self-reflection.md` son los dos documentos transversales de `rules/` y mantenían listas de extensiones idénticas por convención. El diff agregó `.sh`/`.bash` solo al primero: tocar un hook cargaba el paso 6 pero no el 5, y el mecanismo de auto-carga por `paths:` dejaba de disparar la revisión idiomática. Es el patrón de drift que la sección Anti-drift existe para prevenir — cometido en el PR que agrega la regla contra afirmar sin verificar.

**Ambigüedad del corolario**, coincidiendo con security desde otro ángulo: sin definición para fixes multilínea, sin señal objetiva de "el diff arregla un bug" que dispare el corolario, y sin salida para el caso en que revertir rompe el build antes de poder correr la suite. Al ser bloqueante para QA, la ambigüedad se traduce en veredictos inconsistentes entre `qa-backend` y `qa-frontend` sobre el mismo PR.

## Ronda de fixes (`bd971bc`)

- La comprobación pasa al **dev** (paso 6 pre-commit, con evidencia rojo→verde en el reporte). El QA exige esa evidencia e inspecciona que el test no reimplemente lo que dice proteger; si quiere correrlo, `git worktree` desechable, jamás el árbol del PR.
- Verbo a **"revertir el cambio del fix"** — el hunk mínimo, no "la línea" — con el caso del fix-por-borrado cubierto explícitamente.
- Trigger definido: aplica cuando el diff **declara** arreglar un defecto (commit, PR o reporte del dev). No se infiere de la forma del diff.
- Salida explícita para los casos sin definición: se reporta *no verificable*, sustituido por inspección.
- Espejo de `paths:` restaurado, verificado con `diff`: bloques idénticos.

## Ronda 2 (delta `f55b334..HEAD`)

**security-reviewer — APROBADO.** Los 2 HIGH y los 2 LOW resueltos, verificados uno por uno contra el frontmatter real de los agentes. Un LOW nuevo: *"nunca se convierte en bloqueante"* no delimitaba su alcance y admitía la lectura floja "no verificable ⇒ nada bloquea" — exactamente el hueco que el orchestrator había pedido buscar.

**qa-backend — APROBADO**, sin issues nuevos. Confirmó que el trigger es objetivo (los dos QA leen la misma evidencia textual, no interpretan el diff) y que la salida no es vía libre, porque la inspección del test sigue siendo obligatoria. Una sugerencia: el claim de "revertir no compila" no tenía contraverificación obligatoria.

## Ronda de fixes (`749d9b2`)

Las dos sugerencias convergían y se aplicaron juntas: el "nunca" quedó atado a su objeto (la ausencia de evidencia no bloquea; la inspección sí puede), la excepción se invoca nombrando `archivo:línea` para poder disputarla, y el QA **debe** comprobar en worktree cuando el hunk es una constante o un valor —donde revertir sí compila— en vez de aceptar la etiqueta.

## Nota para la retro

El PR que prohíbe afirmar sin verificar contenía tres afirmaciones sin verificar: que los QA podían ejecutar lo que se les pedía (no pueden), que "borrar la línea del fix" era una operación definida (no lo es), y que agregar una extensión a un archivo no rompía nada (rompió el espejo con su gemelo). Ninguna la habría detectado una relectura; las tres salieron de que alguien fuera a mirar el frontmatter, el caso borde y el archivo vecino.

## Cierre

Veredictos limpios en ronda 2, con sugerencias aplicadas. `review_sha` = `749d9b2`. Registro reconciliable a `PR-<N>.md` en Fase 2.7.
