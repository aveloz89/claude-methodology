## Review: pre-push `fix/hook-merge-repo-y-fila-dod` — el hook de merge verifica el repo que se mergea, y la fila del DoD

- **Branch:** `fix/hook-merge-repo-y-fila-dod` · **Base:** `dev` · **SHA ronda 1:** `1f64d6f` · **SHA final:** `e47a5da` · **Fechas:** 2026-09-16 / 2026-09-17
- **Veredicto:** **APROBADO** tras cuatro rondas (security: cambios requeridos en rondas 1 y 2, aprobado en 3 y 4; qa-backend: cambios requeridos en rondas 1, 2 y 3, aprobado en 4).
- Reportes por reviewer: `pre-pr-hook-merge-repo-y-fila-dod-security.md` (transcrito por el orchestrator, cuatro rondas) y `pre-pr-hook-merge-repo-y-fila-dod-qa-backend.md` (cuatro rondas).

### Resumen

Origen: el hook `pre-merge-check.sh` bloqueó en falso el merge del PR #75 porque resolvía el repo por el cwd de la sesión (issue #72). El diff cambia `hooks/pre-merge-check.sh` y sus tests, agrega la fila del PR #75 a la tabla del paso 4 del DoD anti-drift y reconcilia docs y agentes.

El camino cambió dos veces por decisión del usuario:
- **D-01 → ronda 1:** parsear un `cd` inicial. Abrió divergencias nuevas.
- **D-03:** meter los dos huecos legacy (`gh -R x pr merge`, `GH_REPO`).
- **D-04, tras la ronda 2:** abandonar el parseo y aceptar una **forma única** validada sobre el texto crudo — `gh pr merge <N>` con flags conocidos, en una línea, sin nada antes ni después; todo lo demás bloquea. Modelo de amenaza: errores honestos (`hooks/lib/guard-matching.sh:19-22`).

### Seguridad

- **Ronda 1** (`1f64d6f`): CAMBIOS REQUERIDOS — 2 HIGH (separadores no exigidos; ruta que no es la del shell), 1 MEDIUM, 2 LOW, 2 legacy.
- **Ronda 2** (`98a8cab`): CAMBIOS REQUERIDOS — 5 HIGH (prefijo disfrazado, `[ \t]` en ERE, argumento comillado, segundo merge en otra línea, valor de `--repo` truncado). La suite pasaba 306/306 con los cinco abiertos. El prompt de esa ronda pidió contar la evasión deliberada sin contrastarlo con el modelo documentado (error del orchestrator, registrado en D-04).
- **Ronda 3** (`32ab443`, hook completo contra `dev`): **APROBADO**. Todo lo de la ronda 2 bloquea con 0 consultas a `gh`; ningún comando que calce la gramática actúa sobre otro repo, PR u host; sin falsos positivos en comandos habituales; lógica de checks/threads/reviews idéntica a `dev`.
- **Ronda 4** (delta `32ab443..e47a5da`): **APROBADO**. La excepción `--help`/`-h` no abre camino de merge; el bloqueo de caracteres de control matchea exactamente los bytes pedidos.

### QA Backend

- **Ronda 1:** CAMBIOS REQUERIDOS — drift del conteo en `agents/qa-backend.md:45`. Rojo→verde reproducido (272/279).
- **Ronda 2:** CAMBIOS REQUERIDOS — header con garantía absoluta contradicha; `README.md` y `global/CLAUDE.md` incoherentes.
- **Ronda 3:** CAMBIOS REQUERIDOS — header «Fuera de alcance» falso para la mayoría de sus ejemplos; 4 escenarios preexistentes de `dev` borrados sin test; test B5 duplicado.
- **Ronda 4** (`e47a5da`): **APROBADO**. Los tres cerrados y verificados ejecutando el hook; 321/321.

### Veredicto

**APROBADO**

#### Bloqueantes
Ninguno abierto.

#### Sugerencias no aplicadas
Por decisión del usuario (no abrir más rondas), van al issue de seguimiento del saneo compartido:
- Merges que el saneo de `guard-matching.sh` borra y el shell ejecuta (security ronda 3, HIGH legacy), documentados como fuera de alcance en el header.
- Falso positivo en vivo: el hook bloqueó a qa-backend (rondas 3 y 4) al escribir su reporte con heredocs que citaban el comando.
- NUL antes de `--help` o `--repo` (security ronda 4, MEDIUM, mitigado por Node).
- Header que afirma que todo wrapper `gh()` bloquea; docs sin la excepción `--help` y con ruta relativa al repo de la metodología; mensaje de `GH_REPO`/`GH_HOST` que se contradice (security ronda 4, LOW).
- cwd del proceso del hook frente al que persiste la herramienta Bash (security ronda 3, MEDIUM sin verificar).

**Veredicto final: APROBADO.** `review_sha` = `e47a5da`.

### NO CUBIERTO (consolidado)
- Ningún merge real contra GitHub: todo con `gh` falso; el `gh` real solo en lecturas.
- Cómo el harness pasa el comando al shell (argv/`eval`), su validación de caracteres de control y el cwd con que lanza el hook.
- Snapshot del shell, `.zshenv`, aliases y funciones de sesión: fuera de alcance por D-04.
- Opciones de zsh (`AUTO_CD`, `CDPATH`), hosts Enterprise y `GH_CONFIG_DIR` con `gh` real.
