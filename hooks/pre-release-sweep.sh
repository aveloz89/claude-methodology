#!/bin/bash
# Bloquea PR a main si hay issues abiertos con label `latent-bug` y severidad
# CRÍTICO/CRITICAL que afecten archivos del diff. El agente latent-bugs-sweep
# crea esos issues; este hook verifica que no se mergeen archivos con bugs
# críticos pendientes.
#
# hooks.json filtra la invocación con "if": "Bash(gh *)" — optimización de
# latencia, no reemplaza la validación de abajo, que sigue mirando el
# comando completo.
#
# Contrato PreToolUse (auditoría best-practices): bloquear = stderr + exit
# 2, permitir = exit 0 sin stdout — igual que pre-push-guard.sh y pre-
# commit-guard.sh. Reemplaza el JSON {"decision":"block"}/{"continue":true}
# que este hook usaba antes.

# Fail-closed sin jq o sin gh (D-07, F4): antes este hook fallaba ABIERTO
# (exit 0) si faltaba cualquiera de los dos, dejando pasar un "gh pr create
# --base main" real sin evaluar los issues latent-bug del diff. Con "if":
# "Bash(gh *)" en hooks.json, el costo es bloquear un "gh …" cualquiera sin
# gh instalado — ese comando fallaría igual al ejecutarse.
if ! command -v jq >/dev/null 2>&1 || ! command -v gh >/dev/null 2>&1; then
  echo "BLOCKED: pre-release-sweep no operativo: falta jq o gh" >&2
  exit 2
fi

LIB="${0%/*}/lib/guard-matching.sh"
if [ ! -r "$LIB" ]; then
  echo "BLOCKED: pre-release-sweep no operativo: falta hooks/lib/guard-matching.sh" >&2
  exit 2
fi
# shellcheck source=lib/guard-matching.sh
source "$LIB"

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# NUL en el comando (#77 §3): ver guard_command_has_nul en guard-matching.sh
# para por qué se detecta sobre $INPUT y no sobre $COMMAND.
if guard_command_has_nul "$INPUT"; then
  echo "BLOCKED: pre-release-sweep: el comando trae un byte NUL" >&2
  exit 2
fi

SANITIZED_COMMAND=$(guard_sanitize "$COMMAND")

# Matching endurecido (D-07, #77, F): el match se sanea (spans quoted/
# heredoc) y se ancla a posición de comando en vez de exigir "gh pr create"
# al INICIO del string crudo — "cd . && gh pr create --base main" pasaba
# sin bloquear (F1). Acepta "--base main", "--base=main" y "-B main" (F2);
# el sufijo exige espacio/fin de string/separador de comando después de
# "main" para que "--base main-2" no matchee por un "\b" que solo mira el
# carácter siguiente (F3). Tolera "-R <owner/repo>"/"--repo <owner/repo>"
# entre "gh" y "pr" (F6, D-07): son formas honestas que gh acepta de
# verdad, y antes de F6 el ancla exigía "gh" seguido directo de "pr" — así
# que un "gh -R o/r pr create --base main" real pasaba sin que el hook
# evaluara los issues latent-bug del diff.
#
# Sufijo ampliado (review dual ronda 1, security MEDIUM, F5): el charset
# original (espacio/fin de string/";"/"&"/"|") no incluía ")", ">", "<" ni
# la comilla invertida — "--base main>/tmp/u" o "URL=$(gh pr create --base
# main)" pasaban sin bloquear porque "\b" solo mira el carácter siguiente a
# "main", nunca el separador real que sigue a la palabra completa.
#
# GH_REPO_OPT (ronda 2, security LOW): además de "-R <o/r>"/"--repo <o/r>"
# (con espacio, F6), tolera "--repo=<o/r>" (con "=") y "-R<o/r>"
# (clusterizado, sin espacio) — formas honestas que gh acepta de verdad.
# Se tolera tanto ANTES de "pr" como entre "pr" y "create" (gh también
# acepta "gh pr -R <o/r> create").
GH_REPO_OPT='(-R(\s+\S+|\S+)|--repo(=\S+|\s+\S+))'
GH_PR_CREATE_RE="${GUARD_ANCHOR}gh\s+(${GH_REPO_OPT}\s+)?pr\s+(${GH_REPO_OPT}\s+)?create\b"
BASE_MAIN_RE="${GH_PR_CREATE_RE}.*(--base[ =]main|-B\s+main)(\s|\$|[;&|)><\`])"

# Forma citada de "--base"/"-B" (ronda 2, security LOW, fail-open):
# guard_sanitize() borra el span quoted ENTERO (comillas incluidas), así
# que "--base \"main\"" queda como "--base " en SANITIZED_COMMAND — el
# "main" que BASE_MAIN_RE busca ya no está ahí, y "gh pr create --base
# \"main\"" pasaba sin bloquear. Mismo criterio que QUOTED_FORCE_PATTERN en
# block-force-push.sh: la invocación real de "gh ... pr create" se
# confirma sobre el SANEADO (ancla en posición de comando, nunca una
# mención dentro de un span borrado) y la forma citada se busca aparte
# sobre el comando SIN sanear, donde las comillas siguen ahí.
QUOTED_BASE_MAIN_RE="(--base[ =]|-B\s+)[\"']main[\"']"

if echo "$SANITIZED_COMMAND" | grep -qE "$BASE_MAIN_RE"; then
  :
elif echo "$SANITIZED_COMMAND" | grep -qE "$GH_PR_CREATE_RE" \
  && echo "$COMMAND" | grep -qE "$QUOTED_BASE_MAIN_RE"; then
  :
else
  exit 0
fi

# Limitación aceptada (D-07, F1, no se arregla): "cd <ruta> && gh pr create
# --base main" detecta el "gh pr create" real (match anclado, arriba) pero
# el "cd" no se resuelve — "git diff" de abajo sigue corriendo en el cwd DE
# LA SESIÓN, nunca en la ruta del "cd" del comando. Si la sesión ya está
# parada en el repo del PR (el caso normal), el diff es el correcto pese a
# todo; un "cd" a un repo DISTINTO evalúa el diff equivocado en vez de
# bloquear por no poder resolverlo — documentado, no un hueco no advertido.
# Detectar archivos cambiados vs main
CHANGED_FILES=$(git diff --name-only origin/main...HEAD 2>/dev/null)
if [ -z "$CHANGED_FILES" ]; then
  exit 0
fi

# Listar issues abiertos con label latent-bug
ISSUES_JSON=$(gh issue list --label latent-bug --state open --json number,title,body --limit 100 2>/dev/null)
if [ -z "$ISSUES_JSON" ] || [ "$ISSUES_JSON" = "[]" ]; then
  exit 0
fi

# Buscar issues que mencionen archivos del diff con severidad CRÍTICO/CRITICAL
BLOCKING=""
while IFS= read -r file; do
  [ -z "$file" ] && continue
  MATCH=$(echo "$ISSUES_JSON" | jq -r --arg f "$file" '
    .[]
    | select((.body | contains($f)) and (.body | test("CRÍTICO|CRITICAL"; "i")))
    | "  - #\(.number): \(.title)"
  ' 2>/dev/null)
  if [ -n "$MATCH" ]; then
    BLOCKING="${BLOCKING}\n${file}:\n${MATCH}\n"
  fi
done <<< "$CHANGED_FILES"

if [ -n "$BLOCKING" ]; then
  REASON=$(printf "Blocked: PR a main bloqueado por bugs latentes CRÍTICOS abiertos en archivos del diff:%b\nResuelve los issues (fix + cerrar) o re-ejecuta latent-bugs-sweep para confirmar el estado actual antes de mergear a main." "$BLOCKING")
  echo "$REASON" >&2
  exit 2
fi

exit 0
