# QA Backend Review — pre-push (Fase 2.6)

- **Repo**: claude-methodology
- **Branch**: `feature/hook-skip-planning-only`
- **Base**: `dev`
- **SHA revisado**: `b108ad8`
- **Fecha**: 2026-09-12
- **Veredicto**: **CAMBIOS REQUERIDOS**

## Resumen

El diff implementa las dos medidas del brief: (1) salto de suites en `pre-commit-guard.sh` cuando el commit toca solo `.planning/`, con 6 casos nuevos en `tests/adversarial/test-hooks.sh`; (2) instrucción de base de test propia por worktree en `rulebooks/orchestrator-runbook.md`, `agents/qa-frontend.md` y `agents/qa-backend.md`, más la línea de una sola frase en `global/CLAUDE.md`. El código del hook es quirúrgico, reutiliza el parsing ya vetted de `workspace-scope.sh` (mismo slicing `${line:3}`, mismo criterio conservador), y la suite pasa 231/231. Verifiqué por mutación (worktree desechable) que el caso "solo `.planning/`" se pone rojo si se desactiva el salto, y que el marcador `test.ran` prueba invocación real del runner, no un exit code ambiguo.

El bloqueante es documental: el propio DoD anti-drift de `rulebooks/orchestrator-runbook.md` (línea 784) exige grepear y reconciliar `README.md` ante todo cambio de flujo/hooks, y `README.md` describe `pre-commit-guard` en su tabla de hooks sin mencionar el salto nuevo — la misma clase de contradicción entre documentos que ese DoD existe para prevenir.

## Hallazgos con archivo:línea

### 1. `hooks/pre-commit-guard.sh:44-105` — OK, sin bloqueantes
- La función nueva se inserta después de confirmar que el comando sanitizado matchea `git commit` (línea 40-42, ya existente) y antes de la detección del runner (línea 107, ya existente). Diff puramente aditivo — no toca una sola línea del resto del hook (confirmado con `git diff`).
- Camino conservador correcto: `files` vacío → `return 1` (camino normal, corre suites); cualquier archivo fuera de `.planning/` → `return 1`. Solo `return 0` (salta) si la lista no está vacía y **todos** los archivos caen bajo `.planning/`.
- Renames evaluados por ambos lados (`case "${path%% -> *}"` / `case "${path##* -> }"`) — correcto: un rename `.planning/x → src/x` no debe saltar.
- Estilo contra `~/.claude/rules/bash.md`: sin `set -e` (correcto para un hook que debe responder siempre), comillas consistentes (`"$files"`, `"$line"`), `local` en variables de función, prefijo `_` en el nombre de función (convención ya usada por `_workspace_scope_match`, `_workspace_scope_npm_dirs`), fail-safe (no fail-open: si `git status` falla, cae al camino que SÍ corre las suites, nunca al que las salta).
- Reutiliza el comando y el slicing (`${line:3}`) ya usado y auditado en `hooks/lib/workspace-scope.sh:269`, y remite a su comentario en vez de duplicarlo (cumple el paso 3 del propio DoD anti-drift, "enunciar una vez, remitir el resto").

### 2. `tests/adversarial/test-hooks.sh:460-570` — OK, con una sugerencia menor
- 6 casos cubren: solo `.planning/` (a), `.planning/` + archivo fuera (b), untracked fuera (c), `.planning/` modificado + untracked fuera (d), rename hacia afuera (e), mención de `git commit` en heredoc con árbol sucio bajo `.planning/` (f, confirma que el chequeo nuevo no se adelanta al guard de sanitización).
- **Mutación ejecutada y resultado**: en un worktree desechable (`git worktree add`), inserté `return 1` como primera línea de `_guard_planning_only_change` (deshabilita el salto) y corrí la suite completa. Resultado: **2 tests se ponen en rojo**, ambos del caso (a) — `pre-commit-guard: solo .planning/ modificado → salta suites (exit 0)` (exit code 2 en vez de 0) y `... el test runner NO corrió` (`test.ran=yes` en vez de `no`, esperado `no`). Los 229 tests restantes (incluidos los casos b-f) siguen en verde, como se espera de una mutación acotada a la rama "sí es solo planning". Confirma que el test (a) protege de verdad el comportamiento que dice proteger, y que el marcador `test.ran` no es un exit code ambiguo: mide invocación real del runner (el script de test siempre falla con `exit 1` tras escribir el marcador, así que "corrió" y "bloqueó" son eventos independientes y observables por separado). Worktree removido después (`git worktree remove --force`), árbol principal sin tocar.
- **Sugerencia (no bloqueante)**: no hay caso que cubra un rename **dentro** de `.planning/` (ambos lados bajo `.planning/`, p. ej. `.planning/a.md → .planning/b.md`) para confirmar que sí se saltan las suites en ese caso. El caso (e) solo cubre la dirección de riesgo (rename hacia afuera), que es la que importa para no dejar pasar código sin test; el caso simétrico es de menor riesgo pero cerraría la cobertura de la rama de código completa.

### 3. `tests/adversarial/test-plugin-manifest.sh` y `claude plugin validate --strict .` — OK
- 19/19 tests verdes, incluida la paridad `hooks.json` (el diff no toca `hooks.json` ni agrega/quita hooks, consistente con "Fuera de alcance" del brief).
- `claude plugin validate --strict .` → `✔ Validation passed`.

### 4. Documentos normativos (`rulebooks/orchestrator-runbook.md`, `agents/qa-frontend.md`, `agents/qa-backend.md`, `global/CLAUDE.md`) — 1 bloqueante, resto OK

- **`global/CLAUDE.md:160`**: una sola frase agregada a la lista de "Corren en background" — `"(se omiten si el commit toca solo .planning/)"`. Cumple exactamente el punto 3 del brief, sin duplicar detalle (el detalle vive en el hook y en el runbook, no en el núcleo — coherente con la propia regla del repo de que `global/CLAUDE.md` es contexto de toda sesión y no debe cargar detalle).
- **`agents/qa-frontend.md` y `agents/qa-backend.md`**: mismo agregado textual (`", con su propia base de test si corre suites"`) sobre la misma frase preexistente de worktree desechable — mirroreado correctamente entre los dos archivos espejo, sin divergencia de redacción.
- **`rulebooks/orchestrator-runbook.md`**: la instrucción de base de test propia se agrega en los dos puntos que el brief pedía — el paquete de contexto de Fase 2.6 (para reviewers) y el template de handoff a devs (para `db-specialist`/`backend-dev`/`frontend-dev`). Ejemplos de naming distintos (`<base>_<reviewer>` vs `<base>_<lote>`) son solo ilustrativos, no una inconsistencia normativa.
- **`agents/security-reviewer.md`**: no menciona worktrees (confirmado con grep) — el commit `2670933` documenta explícitamente esta decisión ("sin cambios ahí"), correcto: no había nada que actualizar.
- **Regla nueva introducida, aplicada al propio diff**: la instrucción "quien corra suites desde un worktree exporta su propia base de test" es contenido prescriptivo nuevo (antes solo decía "usa un worktree desechable", sin el matiz de aislar la DB). La apliqué a mi propio proceso de mutación: usé un worktree desechable y lo até a `git worktree remove`, pero la regla habla de "base de test" para *suites* — mi mutación corrió `tests/adversarial/test-hooks.sh`, que no usa ninguna base de datos (son repos git temporales vía `mktemp -d`), así que la condición de aislamiento de `TEST_DATABASE_URL` no aplicaba a este caso concreto. No encontré violación de la regla nueva en el propio diff.
- **BLOQUEANTE — `README.md:29`** (fuera de la lista de "Alcance" del brief, pero dentro del DoD que el propio repo se exige): la tabla de hooks describe `pre-commit-guard` así — *"Corre tests antes de cada commit. Detecta pnpm/yarn/npm/pytest. En monorepos npm/pnpm acota la corrida a los workspaces tocados (`hooks/lib/workspace-scope.sh`); si no puede resolverlo con confianza, corre todo"* — sin mencionar el salto nuevo para commits de solo `.planning/`. `rulebooks/orchestrator-runbook.md:786` (paso 1 del DoD anti-drift) lista textualmente `README.md` entre los documentos a grepear y reconciliar ante todo cambio de hooks/flujo, y la propia línea 613 del runbook aclara que para el repo de la metodología, `README.md` sí es scope de `qa-backend` ("ambos describen cómo se edita el sistema y sí van a qa-backend"). Es la misma clase de contradicción entre documentos que el DoD existe para prevenir: dos docs describen el mismo hook, uno refleja el comportamiento nuevo (`global/CLAUDE.md`) y el otro no (`README.md`). Revisé el resto de menciones de `pre-commit-guard` en el repo (`rulebooks/orchestrator-runbook.md:534`, sección de smoke test al retomar) y no aplica — describe un mecanismo distinto (detección de runner al resumir sesión, no el salto por `.planning/`). Las menciones en `.planning/AUDIT-context-engineering.md` y `.planning/reviews/PR-58.md` son registro histórico, no documentación viva — no corresponde reconciliarlas.

### 5. Hallazgo ambiental reportado por el dev (fuera de alcance) — CONFIRMADO
"El hook PreToolUse corre con el cwd del harness (el repo de la sesión), no con el `cd` interno del comando, así que un `cd otro-repo && git commit` se valida contra el repo equivocado." Confirmado por diseño: el hook recibe `tool_input.command` como texto vía stdin (línea 19-20 de `pre-commit-guard.sh`) **antes** de que ese comando se ejecute — cualquier `cd` embebido en el string todavía no corrió cuando el hook mira `package.json`/`git status`, así que esas verificaciones corren relativas al cwd de invocación del hook (fijo para la sesión), no al directorio destino del `cd`. No bloquea este PR — va a issue aparte, como indica el encargo.

## Tests y cobertura
- Suite adversarial: 231/231 pasando (incluye los 6 casos nuevos).
- `test-plugin-manifest.sh`: 19/19 pasando.
- No aplica coverage numérico de branches (repo de metodología, sin runtime JS/TS aplicable a este diff — el equivalente es la suite adversarial, ya verificada por mutación).

## Stub Detection
LIMPIO. Sin TODO/FIXME/HACK, sin credenciales, sin `print`/`console.log` de debug, sin catches vacíos.

## Implementation Principles
LIMPIO. Cambio quirúrgico, sin scope creep (no toca `hooks.json`, no cambia el resto del hook), sin abstracciones especulativas, comentarios explican el *por qué* (referencian los 3 incidentes de origen y remiten a la fuente en vez de duplicar).

## Self-reflection del dev
OK. Los commits no declaran correcciones de self-reflection que requieran verificación cruzada. No encontré violaciones idiomáticas sin documentar en el diff.

## Regresiones
NINGUNA. El hook sigue devolviendo 0/2 en los mismos casos que antes para cualquier commit que no sea 100% `.planning/`; no cambia el contrato de ningún endpoint ni tipo compartido (no aplica en este repo).

## Veredicto
**CAMBIOS REQUERIDOS**

### Bloqueantes (deben arreglarse)
- [ ] `README.md:29` — La tabla de hooks describe `pre-commit-guard` sin el salto nuevo para commits de solo `.planning/`, violando el paso 1/2 del propio DoD anti-drift (`rulebooks/orchestrator-runbook.md:784-786`, que lista `README.md` explícitamente). Reasignar a quien cerró el diff (dev/orchestrator de esta feature) — es un ajuste de una línea en la tabla, no requiere `backend-dev` ni `db-specialist`.

### Sugerencias (opcionales)
- [ ] `tests/adversarial/test-hooks.sh` — agregar un caso de rename **dentro** de `.planning/` (ambos lados bajo `.planning/`) para cerrar la cobertura simétrica del caso (e).

## NO CUBIERTO
- No se evaluó el resto del repo fuera de los archivos del diff (fuera de scope de esta revisión pre-push).
- No se auditó `.planning/BRIEF-retros-por-archivo.md` / rename de `DESIGN.md` / `.planning/state.json` más allá de una lectura superficial: son housekeeping administrativo de `.planning/` (archivado de la feature anterior ya mergeada) sin contenido prescriptivo, fuera del checklist encargado. Nota menor no bloqueante: `state.json` usa `"id": "L1"` (string) para el batch, mientras el ejemplo de formato en `rulebooks/orchestrator-runbook.md:470` usa `"id": 1` (número) — drift de formato pequeño, sin impacto funcional detectado, no verificado si hay algún consumidor que dependa del tipo.

---

## Re-review 2026-09-12 (ronda 2)

- **SHA revisado (delta)**: `b108ad8...2825e81` (`c0bb1d4`, `af06933`, `2825e81`)
- **Fecha**: 2026-09-12
- **Veredicto**: **APROBADO**

### 1. Mi bloqueante (README.md vs global/CLAUDE.md) — RESUELTO

`2825e81` alinea ambos documentos sobre la misma condición (el árbol, no el commit; con la salvedad de redirección):

- `README.md:29`: *"Se omite cuando lo único con cambios locales en el árbol es `.planning/`, y el comando no redirige git a otro árbol"*.
- `global/CLAUDE.md:160`: *"se omiten cuando lo único con cambios locales en el árbol es `.planning/`, y el comando no redirige git a otro árbol"*.

Redacción idéntica salvo número gramatical (singular "se omite" en README describiendo el hook puntual; plural "se omiten" en CLAUDE.md describiendo "tests" en la lista) — no es contradicción, es concordancia con el sujeto de cada frase. Ambas reflejan correctamente el fix del HIGH (`c0bb1d4`): la condición ya no es "el commit toca solo `.planning/`" (redacción vieja, que ignoraba la redirección de árbol) sino "el árbol tiene cambios locales solo en `.planning/` Y el comando no redirige a otro árbol" — coherente con el comentario del hook (`hooks/pre-commit-guard.sh:117-133`) y con el propio mecanismo (`_guard_planning_only_change` + el nuevo `grep` de `cd`/`-C`/`--git-dir`/`--work-tree`).

Grep de otras menciones de `pre-commit-guard` en `README.md`/`docs/`: sin hallazgos nuevos. La única mención de comportamiento es la línea 29 (ya corregida); línea 156 es solo el árbol de archivos del repo (`hooks/pre-commit-guard.sh` listado, sin describir lógica). `rulebooks/orchestrator-runbook.md:534` menciona el hook para un mecanismo distinto (detección de runner al retomar sesión), no el salto — ya confirmado en ronda 1, sigue sin aplicar.

### 2. Mi sugerencia (rename dentro de `.planning/`) — NO CUBIERTO (sigue como sugerencia, no bloqueante)

El delta agrega 26 casos nuevos (`c0bb1d4`: 4 casos de redirección de árbol + defensa en profundidad; `af06933`: 5 invariantes pineados — hermanos del prefijo ×4, `.planning` como archivo regular, lista vacía con árbol limpio, fail-closed de `git status`, rename de afuera hacia `.planning/`). Ninguno de los nuevos es el caso simétrico que señalé (rename con ambos lados bajo `.planning/`, ej. `.planning/a.md → .planning/b.md`, que debería seguir saltando). Sigue siendo cobertura de menor riesgo (la rama de código ya existe y es correcta por lectura — el `case` evalúa cada lado independientemente y ambos caen en `.planning/*`), así que no bloqueo por esto; queda igual que en ronda 1.

### 3. Fix del HIGH (`c0bb1d4`) — quirúrgico, sin regresión, estilo OK

Diff de `hooks/pre-commit-guard.sh` verificado línea por línea (`git diff b108ad8...HEAD -- hooks/pre-commit-guard.sh`):

- **Body de `_guard_planning_only_change` sin tocar**: el fix no cambia una sola línea de la función que evalúan los 6 casos originales de ronda 1 — solo agrega comentario (la salvedad de `git add -f`, puramente documental) antes de la función, y envuelve el `if _guard_planning_only_change; then` original en un `if <redirect-check>; then : ; elif _guard_planning_only_change; then` — el camino "no hay redirección" llega exactamente al mismo chequeo que antes, sin alterar su semántica.
- **Regresión de los 6 casos de ronda 1**: confirmado por ejecución — los 257 tests actuales incluyen los 6 originales (a-f) y pasan en verde con el mismo significado (comandos sin `cd`/`-C`/`--git-dir`/`--work-tree` no entran al `if` nuevo, caen directo al `elif`).
- **Estilo contra `~/.claude/rules/bash.md`**: comillas consistentes (`"$SANITIZED_COMMAND"`), sin `eval`/`sh -c`, anclaje de `cd` y `git -C` con el mismo `${GUARD_ANCHOR}` que el resto del hook (documentado y consistente con el uso existente en el archivo), `--git-dir`/`--work-tree` sin anclaje por ser flags largos y específicos (justificado explícitamente en el comentario: "un falso positivo acá solo corre suites de más" — degradación documentada hacia el lado seguro, cumple "degradar es una decisión, no un accidente"). Sin `set -e` (correcto, hook debe responder siempre). Comentario evita el absoluto: no dice "cubre todos los casos de redirección", acota a los 4 patrones conocidos y remite a `#212` como lo que queda fuera.
- Verificado además con la suite: `af06933` agrega los casos (g)-(j) que ejercitan tanto el bug original (worktree real, cd) como el status quo sin cambio de `git -C`/`--git-dir` en invocación única (`#212`, fuera de alcance, confirmado sin comportamiento nuevo) — 241/241 → 257/257.

### 4. Suites y validación

```
bash tests/adversarial/test-hooks.sh          → 257/257 PASS
bash tests/adversarial/test-plugin-manifest.sh → 19/19 PASS
claude plugin validate --strict .              → ✔ Validation passed
```

### Nuevos issues introducidos
NINGUNO. `af06933` es aditivo puro (solo agrega tests, no toca código de producción). `2825e81` es un cambio de una línea en cada uno de dos archivos de documentación, sin código.

### Veredicto
**APROBADO**

#### Bloqueantes
Ninguno.

#### Sugerencias (opcionales, arrastradas de ronda 1, no bloqueantes)
- [ ] `tests/adversarial/test-hooks.sh` — agregar caso de rename con ambos lados dentro de `.planning/` (ej. `.planning/a.md → .planning/b.md`) para cerrar la cobertura simétrica de la rama de rename del `case`.

### NO CUBIERTO
- No se re-auditó el resto de `rulebooks/orchestrator-runbook.md`, `agents/qa-frontend.md`, `agents/qa-backend.md` ni `agents/security-reviewer.md` — el delta de esta ronda no los toca.
- No se re-verificó el hallazgo ambiental de ronda 1 (cwd del hook vs `cd` interno) — sigue fuera de alcance, sin cambios en el delta.
