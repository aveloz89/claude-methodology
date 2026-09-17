## Security Review pre-push: `fix/hook-merge-repo-y-fila-dod` — ronda 1

- **Branch:** `fix/hook-merge-repo-y-fila-dod` · **Base:** `dev` · **HEAD:** `1f64d6f` · **Fecha:** 2026-09-16
- **Veredicto:** **CAMBIOS REQUERIDOS**. 2 HIGH, 1 MEDIUM, 2 LOW, 2 vulnerabilidades legacy.
- Transcrito por el orchestrator (el agente no tiene herramienta de escritura).

**Cómo se verificó.** Repos git desechables con remotos de GitHub en el scratchpad y un `gh` falso que registra qué repo consulta el hook y qué repo mergearía `gh pr merge` si el comando corriera de verdad (`zsh -c` y `/bin/bash -c` desde el cwd de la sesión; zsh es el shell real de la herramienta Bash). "Divergencia" = el hook deja pasar el merge y el repo verificado no es el mergeado. Los casos clave se corrieron también contra `git show dev:hooks/pre-merge-check.sh`.

### Seguridad

**[HIGH] Regresión: el hook confía en un `cd` inicial que no es el que rige el cwd del merge**
- `hooks/pre-merge-check.sh:438-439` (`CD_TARGET_REGEX` corta en `&`, `;`, `|` y espacio, pero no revisa qué viene después) y `:501`.

| Comando | Hook en `dev` | Hook en el branch | Repo que mergea |
|---|---|---|---|
| `cd /r/benign \| gh pr merge 5` | session | **benign** | session (zsh y bash) |
| `cd /r/benign & gh pr merge 5` | session | **benign** | session (zsh y bash) |
| `cd /r/benign extra; gh pr merge 5` | session | **benign** | session (zsh: el `cd` falla y `;` sigue) |

- Riesgo: con el PR de `benign` verde y el de la sesión en rojo, el gate deja pasar un merge con CI en rojo.
- El header (`:76-78`) afirma separadores (`&&` / `;` / salto de línea) que el código no exige (§5).
- Remediación: allowlist de la forma completa — solo `cd <una ruta>` seguido de `&&`, `;` o salto de línea, y justo después `gh pr merge`; cualquier otra forma con `cd` bloquea pidiendo `--repo`. Un test por fila, rojo al revertir.

**[HIGH] El fix resuelve una ruta distinta a la que usa el shell**
- `hooks/pre-merge-check.sh:439-458`.
1. La ruta sale del texto saneado: `guard_sanitize` vuelve espacio los tramos entre comillas y une continuaciones. `cd /r/pfx"-real" && gh pr merge 5` (o `'-real'`, o `cd /r/pfx\`↵`-real && …`): el hook verifica `pfx`, `gh` mergea `pfx-real`. El comentario `:433-437` (ruta comillada bloquea) solo es cierto si la comilla abre la ruta.
2. El regex salta de línea (`[[:space:]]+`): `cd`↵`/r/real`↵`gh pr merge 5` verifica `real` mientras el shell hace `cd` a `$HOME` y mergea ahí.
3. El chequeo de ambigüedad es blocklist de una forma (`cd` + espacio): con `cd /r/benign && X /r/real && gh pr merge 5` se verifica `benign` y se mergea `real` para `pushd`, `builtin cd`, `\cd`, `"cd"`, `eval cd`, `chdir` (zsh) y `command cd` (bash).
4. `cd old new` de zsh: `cd /r/session /r/real && gh pr merge 5` verifica `session` y mergea `real`.
- Remediación: la allowlist de forma anterior, más ruta idéntica en texto crudo y saneado (o extraída del crudo, rechazando comillas y backslash) y ruta + separador en la misma línea.

**[MEDIUM — preexistente, en el bloque tocado] Un `cd` que no va al inicio cae sin aviso al cwd de la sesión**
- `hooks/pre-merge-check.sh:443` y `:505-509`. `(cd /r/real && gh pr merge 5)`, `true && cd /r/real && …`, `pushd /r/real && …`, `{ cd /r/real && …; }` verifican `session` y mergean `real`. Igual en `dev`.
- Remediación: cualquier `cd`/`pushd`/`popd` en posición de comando antes del merge que no calce la forma permitida bloquea.

**[LOW] Rutas relativas dependen de que el cwd del hook sea el del shell** — `:501`. Exigir ruta absoluta, o resolver contra el `cwd` del JSON de entrada (no verificado qué trae).

**[LOW] DoD paso 3: el conteo quedó escrito dos veces** — `agents/security-reviewer.md:20` y `rulebooks/orchestrator-runbook.md:795`. En `security-reviewer.md`, remitir a la tabla sin el número. La fila de #75 coincide con sus fuentes (`PR-75-qa-backend.md:38`, `PR-75-security.md:18-20`); la documentación no debilita ninguna instrucción.

**[HIGH — legacy] Formas de merge que el hook no intercepta** — `:147`, regex `gh\s+pr\s+merge`. `gh -R x pr merge N`, `gh pr -R x merge N` y `GH_REPO=x gh pr merge N` pasan sin verificar, igual que en `dev`. Confirmado con `gh` real en solo lectura que las tres formas funcionan.

**[MEDIUM — legacy] `gh repo view` ignora `GH_REPO`, `gh pr` lo usa** — con `GH_REPO` exportado, el hook verifica un repo y `gh` mergea otro. Remediación: bloquear si `GH_REPO` aparece en el comando o en el entorno.

**Lo que resiste (ejecutado):** nada del comando se ejecuta (`$(…)`, backticks, `$IFS` bloquean sin crear archivos; `~`, `$HOME`, globs y `{}` bloquean por la allowlist; sin `eval`). Fail-closed en ruta inexistente, directorio no git, repo sin remoto, remoto de GitLab, `gh repo view` fallando, `cd` sin argumento y ruta que abre con comilla. `cd -` y `cd -P` bloquean. Symlink y `..` verifican y mergean el mismo repo. Sin regresión en `--repo`, `--repo=`, `-R` después de `pr merge`, `gh pr merge 5` sin `cd`, `cd /r/real; gh pr merge 5`, `cd /r/real`↵`gh pr merge 5`, y dos `cd` literales bloquean. `tests/adversarial/test-hooks.sh`: 279/279.

### Veredicto
**CAMBIOS REQUERIDOS**

#### Bloqueantes
- [ ] HIGH: `cd X | gh pr merge`, `cd X & gh pr merge` y `cd X extra; gh pr merge` (zsh) verifican `X` y mergean la sesión; en `dev` estaban bien. El header afirma separadores que el código no exige.
- [ ] HIGH: ruta truncada por el saneo, regex que salta de línea, cambios de cwd que no se escriben `cd ` y `cd old new` de zsh.
- Arreglo común: allowlist de la forma `cd <ruta> (&&|;|\n) gh pr merge …`, igual en crudo y saneado; todo lo demás bloquea. Un test por caso, rojo al revertir.

#### Sugerencias
- [ ] MEDIUM (mismo fix): `cd` que no va al inicio no debe caer sin aviso a la sesión.
- [ ] LOW: ruta absoluta o `cwd` del JSON de entrada.
- [ ] LOW: sacar «cinco» de `agents/security-reviewer.md:20`.
- [ ] LOW: `cd; gh pr merge N` verifica la sesión y mergea en `$HOME` (igual que en `dev`).
- [ ] Legacy HIGH: `gh -R x pr merge`, `gh pr -R x merge`, `GH_REPO=x gh pr merge` no se interceptan.
- [ ] Legacy MEDIUM: `GH_REPO` ignorado por `gh repo view`.

### NO CUBIERTO
- Merge real contra GitHub (se usó `gh` falso; con `gh` real solo lecturas).
- cwd del proceso del hook dentro de Claude Code y contenido del campo `cwd` del JSON de entrada.
- Opciones de zsh del snapshot de la herramienta Bash (`AUTO_CD`, `CDABLE_VARS`, `CDPATH`).
- Repos con varios remotos / `gh repo set-default`.
- Programas definidos en la config de git (`core.fsmonitor`) de un repo no confiable al correr `gh repo view` en la ruta del comando.
- Reversión del fix (queda la evidencia del dev, 272/279); `test-plugin-manifest.sh` y `claude plugin validate --strict .` no corridos.
- Dos merges en un comando (solo se valida la primera ventana; preexistente).
- Audit de dependencias: no aplica.

---

## Ronda 2 — HEAD `98a8cab`, delta `8bfdb59..98a8cab` (2026-09-16)

- **Veredicto:** **CAMBIOS REQUERIDOS** — 5 HIGH bloqueantes, 2 HIGH legacy, 1 MEDIUM, 3 LOW. Transcrito por el orchestrator.
- **Método:** `gh` falso que imita al real (gana el último `-R`, luego `GH_REPO`, luego el remoto del cwd vía git, respeta `GIT_DIR`); cada caso contra el hook de HEAD, el de `8bfdb59` y el comando real en `/bin/zsh -f -c 'eval "$C"'` y `/bin/bash -c` (el Bash tool corre `zsh -c … eval`, visto con `ps`). `gh` real solo en lecturas.
- **Nota del orchestrator:** el prompt de esta ronda pidió contar también la evasión deliberada. `hooks/lib/guard-matching.sh:19-22` declara el modelo «errores honestos, no evasión adversarial». El conflicto se escala al usuario.

### Cierre de la ronda 1

Cerrados: los tres casos del HIGH #1 (`|`, `&`, `cd X extra;`); HIGH #2.1 (comillas y continuación), #2.2 (salto de línea), #2.3 (los 7 cambios de cwd), #2.4 sin comillas; el MEDIUM (`(cd …)`, `true && cd`, `pushd`, `{ …; }`); los LOW (ruta relativa, `cd;`/`cd&&`, «cinco» en `security-reviewer.md`); legacy `gh -R x pr merge` y `gh pr -R x merge`. Sin regresión en `--repo`/`-R` al final, merge sin `cd` y `cd` + `--repo`. `cd /abs;` y `cd /abs`⏎ ahora bloquean (sobre-bloqueo deliberado, header `:103-108`).

Abiertos: el header ahora afirma una allowlist que no existe (B1); `GH_REPO` literal bloquea pero se evade (B1); #2.4 con el segundo argumento comillado (B3).

**Regex `GH_PR_MERGE_RE`:** `-R` repetido — `gh` real usa el último (verificado con lecturas) y el hook también: alineado. `--repo` le gana a `GH_REPO` (verificado); el hook bloquea igual, conservador. Valores con dígitos alineados. Decoy `gh pr list --repo victima/otro && gh pr merge 45` alineado. Sin ReDoS: lineal, 976 KB en 0.43 s.

**Evidencia del dev confirmada:** 306/306; con el hook de `8bfdb59`, 278 verdes / 28 rojos; manifest 19/19; `validate --strict` pasa; shellcheck sin avisos nuevos. **La suite pasa con los 5 bloqueantes abiertos: ninguno tiene test.**

### Bloqueantes

- [ ] **B1 [HIGH] La allowlist del prefijo no existe** (`:640-647` es una blocklist de 7 palabras sobre el texto saneado; con `--repo` explícito no mira el prefijo). Verifican la sesión y mergean otro repo, en zsh y bash: `"cd"`, `'cd'`, `c\d`, `$'cd'`, `c""d`, `"pushd"` + ruta; `c=cd; $c /r/real && …`; `f() { c\d /r/real; }; f && …`; `. /tmp/x.sh && …`; `source /dev/stdin <<<'cd /r/real' && …`; `export GIT_DIR=/r/real/.git; gh pr merge 5` (el `gh` real respeta `GIT_DIR`); `export GH_REP""O=…`, `GH_REP\O`, `${x}O`, `typeset -x "GH_"REPO=…` (el chequeo de `:240` es grep literal); wrapper `gh() { … -R o/red; }; gh pr merge 5` — con `--repo o/green`, el hook verifica green y se mergea red. §5: header `:101-113`, `:537` y `README.md:34` dicen «cualquier otro prefijo bloquea», pero `echo hola && gh pr merge 5` pasa. Remediación: allowlist sobre el texto crudo, con o sin `--repo`.
- [ ] **B2 [HIGH, regresión] `[ \t]` en ERE de bash es {espacio, `\`, `t`}** (`:551`, `:613`). `cd t/<abs>/benign && gh pr merge 5` verifica benign y el shell hace `cd ./t/<abs>/benign`; con symlink preparado mergea red. En `8bfdb59` estaba alineado. `:613` acepta además `cd X t&& …`. Remediación: `[[:blank:]]` + test.
- [ ] **B3 [HIGH] `cd old new` de zsh con el segundo argumento comillado** — `cd /r/session "/r/real" && gh pr merge 5`: el saneo borra el argumento, verifica session y zsh mergea real.
- [ ] **B4 [HIGH] Segundo merge en otra línea no se detecta** (`:398-401`, `grep` por línea + `head -1`). `gh pr merge 45 --repo o/green`⏎`gh pr merge 45 -R o/red` mergea red#45; con `⏎gh pr merge 46` mergea session#46 sin verificar; variantes con `cd`/`pushd`. README y header (`:122-125`) prometen lo contrario.
- [ ] **B5 [HIGH] El valor de `--repo`/`-R` se trunca en el saneo** — `--repo o/re"d"`, `-R o/re"d"` intercalado, `--repo=o/re""d`, `-Ro/re'd'`, `--repo o/re\`⏎`d`: verifica `o/re`, `gh` actúa sobre `o/red` (`:471-514` tokeniza el saneado).

### Sugerencias

- [ ] **[HIGH legacy]** Invocaciones no interceptadas: `command gh`, `env gh`, `FOO=1 gh`, `\gh`, `"gh"`, `g\h`, ruta absoluta del binario, `zsh -c '…'`, también como segundo merge. `guard-matching.sh:19-22` lo acepta; decisión del usuario.
- [ ] **[HIGH legacy, línea reescrita `:412`]** Número de PR sin límite de palabra: `gh pr merge 1234-feature` / `45x` verifica #1234/#45 y `gh` lo toma como branch (verificado con lecturas).
- [ ] **[MEDIUM]** El hook no ve el entorno del shell (`.zshenv`, snapshot del Bash tool): `GH_REPO`/`GIT_DIR`/`gh()` escritos ahí desvían un merge limpio. No probado de punta a punta.
- [ ] **[LOW]** `export GH_HOST=h; gh pr merge 5 --repo o/green` pasa; `gh` apunta a `h`.
- [ ] **[LOW, docs]** `README.md:34` y `global/CLAUDE.md:158` prometen bloqueos con contraejemplos (B1, B4); `global/CLAUDE.md` omite la forma `cd <abs> && `.
- [ ] **[LOW, redacción]** `agents/qa-backend.md:45`: «… vive ahí — nunca la autorrevisión del autor» quedó sin sujeto.

### NO CUBIERTO

Merge real contra GitHub; cwd con que Claude Code lanza el hook frente al cwd guardado del Bash tool (el hook no usa el campo `cwd` del JSON); snapshot y `.zshenv` en sesión real; opciones de zsh (`AUTO_CD`, `CDPATH`, `CDABLE_VARS`); varios remotos / `gh repo set-default`; `GIT_CONFIG_*` con `gh` real; `GH_ENTERPRISE_TOKEN` y hosts Enterprise; `core.fsmonitor` en la ruta del `cd`; audit de dependencias (no aplica).

---

## Ronda 3 — HEAD `32ab443`, hook completo contra `dev` (2026-09-17)

- **Veredicto:** **APROBADO** — sin bloqueantes; 1 HIGH legacy (no bloquea), 1 MEDIUM sin verificar, 6 LOW. Transcrito por el orchestrator.
- **Modelo de amenaza aplicado:** D-04 (errores honestos, `guard-matching.sh:19-22`); invocaciones disfrazadas y entorno de arranque del shell fuera de alcance.
- **Método:** repos desechables + `gh` falso que registra llamadas, contra el hook de HEAD y el de `dev`; los no detectados, ejecutados en `/bin/zsh -f -c 'eval "$C"'` y `/bin/bash -c`; `gh` real solo en lecturas. El hook de HEAD está activo en la sesión (bloqueó `gh pr merge --help` del propio reviewer).

### Cierre de la ronda 2 — todo bloquea con 0 llamadas a `gh`

B1 (las 18 variantes, incluidos wrapper `gh()` con y sin `--repo` y `echo hola &&`); B2 (`cd t/<abs> &&`, `cd X t&&`); B3 (`cd /a "/b" &&`); B4 (segundo merge en otra línea, 3 variantes); B5 (las 5 variantes truncadas); número sin límite (`1234-feature`, `45x`, `05`, `+5`, `#5`); `GH_HOST` en comando y entorno; legacy `gh -R x pr merge` y `gh pr -R x merge`.

**Gramática:** ningún comando que la calce hace que `gh` actúe sobre otro repo, PR u host. Slugs raros (`-x/y`, `../..`) quedan alineados (el `gh` real también toma el argumento como valor); combinaciones `-m -s -r -d` y flags repetidos no-repo alineados; número enorme bloquea por GraphQL `null`. Bloquean host en el slug, `o/r/`, `-ms`, `--`, `#`, `\v`, `\f`, NBSP, ancho cero, `\r`. Locale sin diferencias en ASCII; bash 3.2 no toma `IFS` del entorno. NUL: bash lo descarta, pero `spawn` de Node y la herramienta Bash lo rechazan antes. 1 MB en 0.10–0.16 s, sin ReDoS.

**Detección sin ancla:** `GH_REP""O=x`, `FOO=1`, `"GH_REPO=o/red"`, `GH_REPO='o/red' … --repo o/green` bloquean (en `dev` pasaban). `command gh`, `env gh`, `\gh` y ruta absoluta ahora también bloquean. Solo pasan `"gh"`, `g\h`, `zsh -c` (fuera de alcance).

**Falsos positivos:** no bloquea ningún comando habitual — `git commit -m "…gh pr merge…"`, heredoc de commit, `gh pr view 5 --json state && echo merge`, `grep -rn 'gh pr merge'`, `rg`, `gh api …/merge`, `--json mergeable`, `--state merged`, `gh pr diff|view 5 | grep merge`. Bloquean `gh pr merge --help`, `git push # después gh pr merge 5`, `echo through pr merge` y `gh pr checks 5 --watch && gh pr merge 5` (intencional por D-04).

**Entorno:** `GH_REPO`/`GH_HOST` bloquean con y sin `--repo`; `GIT_DIR`/`GIT_WORK_TREE` bloquean sin `--repo`; `GH_REPO=` vacío pasa (el `gh` real lo ignora). Con `gh` real, `repo view` y `pr view` resuelven igual en 4 configuraciones de remotos y `GIT_CONFIG_*`. `GH_CONFIG_DIR`, `GH_ENTERPRISE_TOKEN`, `GITHUB_TOKEN`, `GIT_CONFIG_*` afectan igual a hook y merge.

**Regresión:** desde `# 1. Review decision` al final y el bloque `if [ -n "$EXPLICIT_REPO" ]`, idéntico a `dev`.

**Tests:** 305/305. Los borrados de ventana/balance/"gana el último" desaparecen con su mecanismo; el decoy `gh pr list --repo … && gh pr merge` queda cubierto por «cualquier prefijo bloquea»; sin reemplazo el del truncado del valor reflejado (verificado a mano, LOW 7).

### Veredicto
**APROBADO**

#### Bloqueantes
- Ninguno.

#### Sugerencias
- [ ] **[HIGH legacy, no bloquea] Merges que el saneo borra y el shell ejecuta** (`guard-matching.sh:97-99`): `echo x # don't`⏎`gh pr merge 5`⏎`# it's done`; `echo \'; gh pr merge 5; echo \'`; `echo $'it\'s' && gh pr merge 5 && echo 'x'`; `cat <<E"OF"`⏎`EOF`⏎`gh pr merge 5`⏎`E`. `continue` con 0 llamadas en HEAD y `dev`; zsh y bash mergean. El primero es error honesto plausible y no está en la lista de fuera de alcance. Además `gh pr -R o/a -R o/red merge 5` no se detecta (>2 tokens). Decidir: documentar o detectar también sobre el crudo.
- [ ] **[MEDIUM, sin verificar]** El cwd de la herramienta Bash persiste entre llamadas; sin `--repo` el hook resuelve con su propio cwd. Si difieren, `cd ../otro` y `gh pr merge N` en otra llamada repiten #75. Exigir `--repo` o usar `.cwd` del JSON tras verificar qué trae.
- [ ] **[LOW, §5 docs]** `README.md:34` y `global/CLAUDE.md:158` prometen «cualquier otro prefijo … o más de una línea bloquea» con contraejemplos; aclarar «cuando el hook reconoce la invocación». `README.md:34` perdió la mención de threads y checks.
- [ ] **[LOW, §5 header]** `:109-112` dice que `command gh`/`env gh`/`FOO=1 gh`/`\gh`/ruta absoluta no se reconocen (hoy bloquean); `:146-153` y `:170-174` describen el mecanismo anterior.
- [ ] **[LOW]** Mensaje de `:325` sugiere «usa --repo explícito y sin GH_HOST», pero con `GH_REPO` en entorno y `--repo` igual bloquea.
- [ ] **[LOW]** Falso positivo `gh pr merge --help` / `-h`.
- [ ] **[LOW, defensa en profundidad]** Bloquear caracteres de control distintos de `\t` en `.tool_input.command` (un NUL hace verificar un valor distinto del texto).
- [ ] **[LOW, tests]** Sin test del truncado del valor reflejado (200 KB → reason de 312 bytes, JSON válido) ni de `$(…)`/backtick como valor de `--repo` (bloquea, verificado a mano).

### NO CUBIERTO
Merge real contra GitHub; cwd del proceso del hook frente al persistido por la herramienta Bash y contenido del campo `cwd` del JSON; caracteres de control más allá del rechazo observado; `GH_CONFIG_DIR` y Enterprise con `gh` real; reversión de los tests nuevos; `test-plugin-manifest.sh` y `validate --strict`; snapshot/`.zshenv`/alias/funciones (fuera de alcance); audit de dependencias (no aplica).

---

## Ronda 4 — HEAD `e47a5da`, delta `32ab443..e47a5da` (2026-09-17)

- **Veredicto:** **APROBADO** — sin bloqueantes; 1 MEDIUM (fuera del modelo D-04) y 3 LOW. Transcrito por el orchestrator.
- **Mandato acotado por decisión del usuario:** solo si el delta abre un camino por el que un merge detectado pase mal verificado.
- **Método:** hook real con JSON armado y `gh` falso que registra llamadas, bajo `/bin/bash` 3.2.57. `test-hooks.sh`: 321/321. `guard-matching.sh` sin cambios en el delta.

### Seguridad

1. **Excepción `--help`/`-h`:** solo `gh pr merge --help` y `-h` exactos (con blancos extra) pasan con 0 llamadas. Bloquean con 0 llamadas: `--help 5`, `5 --help`, `-h 5`, `-h5`, `-hd`, `-dh`, `--help=false` (que sí mergearía: `gh pr view --help=false` corre normal), `--help=true`, `-h=false`, `--Help`, `---help`, `"--help"`, `-- --help`, `--help --`, `--help>x`, separadores, `$()`, backticks, `# comentario`, multilínea, continuación, NBSP, U+3000, ZWSP, U+0085 y guiones unicode. En gh 2.88.1 `pr merge` no tiene `-h` propio.
2. **Caracteres de control:** el patrón matchea exactamente `01-08 0b 0c 0e-1f 7f` (probados los 255 bytes). Los merges legítimos pasan el check y consultan `gh`; los comandos no-merge con ESC/DEL/UTF-8 siguen en `continue`. Va antes de la excepción de ayuda.
3. **Mensajes de entorno:** solo cambió el texto de dos `block`; las condiciones no. `GH_REPO`/`GH_HOST` bloquean con y sin `--repo`; `GIT_DIR`/`GIT_WORK_TREE` bloquean sin `--repo`.
4. **Header y docs:** lo que el header dice que bloquea, bloquea; lo que dice que evade, evade.

### Veredicto
**APROBADO**

#### Bloqueantes
- Ninguno.

#### Sugerencias (al issue de seguimiento, por decisión del usuario de no abrir más rondas)
- [ ] **[MEDIUM, fuera del modelo D-04]** `gh pr merge  --help` pasa con 0 llamadas (en `32ab443` bloqueaba): bash quita el NUL en `$(jq …)`. Preexistente en otra forma: `gh pr merge 5  --repo o/a` verifica `o/a#5`. Mitigado porque Node lanza `ERR_INVALID_ARG_VALUE` con NUL en argv. Arreglo de una línea: bloquear si `jq -e '.tool_input.command|contains(" ")'` antes de extraer; corregir el comentario de `:297`, que dice que el NUL es «el caso que sí importa» cuando ese check nunca lo ve.
- [ ] **[LOW, docs]** El header afirma que «un wrapper o una función `gh()` definidos en el MISMO comando TODOS bloquean» y que el código «bloquea MÁS de lo que este comentario admite, nunca menos», pero `w() { gh "$@"; }; w pr merge 5` y `m() { gh pr "$@"; }; m merge 5` pasan con 0 llamadas.
- [ ] **[LOW, docs]** `README.md:34` y `global/CLAUDE.md:158` no mencionan la excepción `--help`/`-h`; `global/CLAUDE.md` apunta a `hooks/pre-merge-check.sh` con ruta relativa al repo de la metodología, inexistente en un proyecto instalado.
- [ ] **[LOW, UX]** El mensaje de `GH_REPO`/`GH_HOST` dice que `--repo` no sirve y luego agrega `MERGE_FORM_HELP`, que recomienda usar `--repo`.

### NO CUBIERTO
Cómo el harness de Claude Code pasa el comando al shell y si su validación de caracteres de control incluye el NUL; `gh pr merge --help`/`-h` con `gh` real (inferido de `gh help pr merge` y `gh pr view -h`); el heredoc con delimitador comillado a medias del header (su variante `echo x # don't`⏎`gh pr merge 5` **bloquea** por multilínea, más estricto que lo que dice el header); aliases o funciones de comandos anteriores (fuera de alcance).
