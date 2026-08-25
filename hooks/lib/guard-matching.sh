#!/bin/bash
# Helper compartido por los guards que interceptan comandos Bash
# (pre-merge-check.sh, block-admin-merge.sh, pre-commit-guard.sh) — ver
# issue #47. Antes de matchear el comando vigilado de cada guard, se sanean
# los spans quoted ('...'/"...") y los cuerpos de heredoc: son contenido
# literal (ej. un mensaje de commit) que puede mencionar la frase vigilada
# sin ser una invocación real. El match además se ancla a posición de
# comando (inicio de string/línea, o justo después de &&, ||, ;, |, $(,
# backtick, "(", "{", &) — no al string completo — para no perder
# invocaciones reales dentro de comandos compuestos en una sola línea.
#
# Uso: sourcear este archivo y usar guard_sanitize junto con la constante
# GUARD_ANCHOR (fragmento de regex ERE) al armar el patrón del comando
# vigilado:
#
#   SANITIZED=$(guard_sanitize "$COMMAND")
#   if echo "$SANITIZED" | grep -qE "${GUARD_ANCHOR}gh\s+pr\s+merge\b"; then ...
#
# Limitación aceptada: es saneo heurístico de texto, no un parser de shell
# real — un wrapper como bash -c "..." no se detecta porque el comando real
# queda dentro de una string que este helper sanitiza. Aceptable: los guards
# protegen errores honestos del orchestrator, no evasión adversarial.

# Fragmento de regex ERE que ancla el match a posición de comando: inicio
# de string/línea, o justo después de un separador de comandos (&&, ||, ;,
# |, $(, backtick, "(", "{", &).
# shellcheck disable=SC2034 # se usa en los guards que sourcean este archivo
GUARD_ANCHOR='(^|&&|\|\||;|\||\$\(|`|\(|\{|&)\s*'

# guard_sanitize: recibe el comando crudo como $1 y devuelve por stdout el
# texto saneado (sin spans quoted ni cuerpos de heredoc).
#
# Si perl no está disponible, se devuelve el comando sin sanear (fallback
# al comportamiento que block-admin-merge.sh y pre-commit-guard.sh tenían
# antes de este helper, que nunca dependió de perl). Es la dirección
# segura para un guard: sin perl hay más falsos positivos posibles (texto
# quoted que menciona la frase vigilada), pero nunca un falso negativo
# silencioso por dependencia ausente — evita reintroducir en estos dos
# guards el mismo fail-open de #50. Se anuncia por stderr para que el modo
# degradado sea visible en vez de un fallback silencioso.
guard_sanitize() {
  if command -v perl > /dev/null 2>&1; then
    # Orden importa: primero unir continuaciones de línea (backslash-
    # newline) — un comando real partido en dos líneas (ej. "gh pr merge 5
    # \" + "  --admin") no debe evadir el match por quedar partido antes de
    # que corra cualquier otra regla. Los spans single-quoted y double-quoted
    # se sanean en UNA sola pasada con alternancia (no dos reglas
    # secuenciales): el span que abre primero consume el texto hasta su
    # propio cierre, sin importar qué tipo de comilla sea — así es como el
    # shell realmente parsea. Una secuencia de dos reglas separadas rompe
    # esto en ambas direcciones: sanear "..." antes que '...' hace que dos
    # apóstrofes en spans double-quoted DISTINTOS (ej. "it's fine" ...
    # "that's all") se emparejen entre sí; sanear '...' antes que "..." hace
    # lo mismo con comillas dobles sueltas dentro de spans single-quoted
    # DISTINTOS (ej. 'quote the " char' ... 'end " here'). Ambos casos se
    # tragan el comando real de en medio como si fuera contenido quoted.
    # La regla de heredocs consume el cuerpo línea por línea con
    # "(?:(?!^[ \t]*\1[ \t]*$)[^\n]*\n)*?" — dos propiedades DISTINTAS,
    # cada una resolviendo un problema distinto de la versión anterior
    # (".*\n?", con /s, "." matchea salto de línea):
    #
    #   1. [^\n] en vez de "." elimina la AMBIGÜEDAD DE PARTICIÓN: cada
    #      iteración avanza exactamente un salto de línea, sin poder
    #      solaparse con el "\n" que la cierra, así que el motor nunca
    #      tiene más de una forma de repartir el texto entre iteraciones.
    #      Es lo que garantiza TERMINACIÓN en tiempo lineal — sin esto,
    #      ".*\n?" dejaba que cada iteración consumiera un número variable
    #      de líneas, y sin terminador real el motor probaba todas las
    #      formas de partir el texto: backtracking catastrófico (con 8
    #      líneas de relleno sin cerrar, >3s; crece sin cota visible).
    #   2. El cuantificador no-greedy ("*?" en vez de "*") elige CUÁL
    #      terminador cierra el heredoc cuando hay más de uno disponible
    #      con el mismo nombre de delimitador: el PRIMERO, igual que bash
    #      de verdad. La versión greedy elegía el ÚLTIMO — dos heredocs
    #      bien formados con el mismo delimitador (ambos "<<EOF") y un
    #      comando real en el medio hacían que el greedy se tragara TODO
    #      lo de en medio (incluido el comando real y el terminador
    #      legítimo del primer heredoc) en un solo span reemplazado por un
    #      salto de línea — un fail-open real y explotable sin necesidad
    #      de colgar nada (ver test [security] en test-hooks.sh). Esto es
    #      independiente de la propiedad 1: un futuro refactor podría
    #      volver a poner "*" greedy creyendo que solo afecta performance,
    #      sin tocar [^\n], y reintroduciría la evasión sin reintroducir
    #      el ReDoS.
    local sanitized status
    sanitized=$(printf '%s' "$1" | perl -0777 -pe '
      BEGIN { alarm 2 }
      s/\\\n\s*/ /g;
      s/<<-?[\x27"]?(\w+)[\x27"]?[^\n]*\n(?:(?!^[ \t]*\1[ \t]*$)[^\n]*\n)*?[ \t]*\1(?:\n|$)/\n/gsm;
      s/\x27[^\x27]*\x27|"(?:[^"\\]|\\.)*"/ /g;
    ')
    status=$?
    # Red de seguridad para cualquier patológico futuro no anticipado por
    # el fix de arriba: si perl no vuelve a tiempo, alarm(2) lo mata (sin
    # $SIG{ALRM} instalado, la señal termina el proceso — perl sale con
    # 128+14). Si perl falla por cualquier motivo (timeout o error), NO se
    # puede devolver su stdout (vacío o parcial): eso equivaldría a sanear
    # todo el comando a la nada, y el grep de cada guard nunca matchearía
    # nada — fail-open silencioso. Se cae al mismo fallback que "perl no
    # disponible": comando sin sanear (más falsos positivos, la dirección
    # segura), avisado por stderr.
    if [ "$status" -ne 0 ]; then
      echo "guard-matching: saneo abortado (perl salió con estado $status, posible timeout), matching sin saneo (posibles falsos positivos)" >&2
      printf '%s' "$1"
    else
      printf '%s' "$sanitized"
    fi
  else
    echo "guard-matching: perl no disponible, matching sin saneo (posibles falsos positivos)" >&2
    printf '%s' "$1"
  fi
}
