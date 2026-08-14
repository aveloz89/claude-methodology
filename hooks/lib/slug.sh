#!/bin/bash
# repo_slug(): slug determinístico de un path de repo, para nombrar
# directorios/archivos de artefactos bajo ~/.claude/methodology/ sin
# colisiones entre repos.
#
# Reemplaza la convención vieja (tr '/' '-'), que no es inyectiva: rutas
# distintas como /a/b-c y /a-b/c colapsaban al mismo string y dos repos
# podían pisarse snapshots/markers entre sí. Ver ARCHITECTURE.md.
#
# Uso: sourcear este archivo y llamar a `repo_slug <toplevel-path>`.
# Imprime el slug por stdout; retorna 1 si no hay ninguna herramienta de
# hash disponible en PATH — el caller decide qué hacer (los hooks que usan
# este lib son observabilidad no-bloqueante: ante el fallo, no-op limpio).
#
# Formato: <basename saneado>-<hash8>
#   basename saneado: basename del toplevel, filtrado a una allowlist
#     alfanumérica + guion/guion bajo (A-Za-z0-9_-); si queda vacío, "repo".
#   hash8: primeros 8 hex chars de un hash del path completo del toplevel,
#     leído por stdin (printf '%s', nunca un archivo temporal).
#
# Cadena de fallback de herramienta de hash — la consistencia importa por
# máquina a lo largo del tiempo, no entre máquinas (los artefactos viven en
# $HOME): shasum -a 256 (macOS siempre, Linux con perl) → sha256sum (GNU) →
# md5 -q (BSD, último recurso: no es cripto, pero para diferenciar paths 8
# hex chars dan la misma protección práctica) → md5sum (GNU).
_slug_hash8() {
  local hex=""
  if command -v shasum > /dev/null 2>&1; then
    hex=$(printf '%s' "$1" | shasum -a 256 | cut -d' ' -f1)
  elif command -v sha256sum > /dev/null 2>&1; then
    hex=$(printf '%s' "$1" | sha256sum | cut -d' ' -f1)
  elif command -v md5 > /dev/null 2>&1; then
    hex=$(printf '%s' "$1" | md5 -q)
  elif command -v md5sum > /dev/null 2>&1; then
    hex=$(printf '%s' "$1" | md5sum | cut -d' ' -f1)
  else
    return 1
  fi
  printf '%s' "${hex:0:8}"
}

repo_slug() {
  local toplevel="$1" base hash8
  base=$(basename "$toplevel" | tr -cd 'A-Za-z0-9_-')
  [ -n "$base" ] || base="repo"
  hash8=$(_slug_hash8 "$toplevel") || return 1
  printf '%s-%s' "$base" "$hash8"
}
