#!/bin/bash
# Helper compartido por los guards que interceptan comandos Bash
# (pre-merge-check.sh, block-admin-merge.sh, pre-commit-guard.sh) — ver
# issue #47. Antes de matchear el comando vigilado de cada guard, se sanean
# los spans quoted ('...'/"...") y los cuerpos de heredoc: son contenido
# literal (ej. un mensaje de commit) que puede mencionar la frase vigilada
# sin ser una invocación real. El match además se ancla a posición de
# comando (inicio de string/línea, o justo después de &&, ||, ;, |, $() —
# no al string completo — para no perder invocaciones reales dentro de
# comandos compuestos en una sola línea.
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
# |, $().
# shellcheck disable=SC2034 # se usa en los guards que sourcean este archivo
GUARD_ANCHOR='(^|&&|\|\||;|\||\$\()\s*'

# guard_sanitize: recibe el comando crudo como $1 y devuelve por stdout el
# texto saneado (sin spans quoted ni cuerpos de heredoc).
#
# Si perl no está disponible, se devuelve el comando sin sanear (fallback
# al comportamiento que block-admin-merge.sh y pre-commit-guard.sh tenían
# antes de este helper, que nunca dependió de perl). Es la dirección
# segura para un guard: sin perl hay más falsos positivos posibles (texto
# quoted que menciona la frase vigilada), pero nunca un falso negativo
# silencioso por dependencia ausente — evita reintroducir en estos dos
# guards el mismo fail-open de #50.
guard_sanitize() {
  if command -v perl > /dev/null 2>&1; then
    printf '%s' "$1" | perl -0777 -pe '
      s/<<-?[\x27"]?(\w+)[\x27"]?[^\n]*\n(?:(?!^[ \t]*\1$).*\n?)*[ \t]*\1(?:\n|$)/\n/gsm;
      s/\x27[^\x27]*\x27/ /g;
      s/"(?:[^"\\]|\\.)*"/ /g;
    '
  else
    printf '%s' "$1"
  fi
}
