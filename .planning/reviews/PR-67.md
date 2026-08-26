# Review dual pre-push — refactor/dead-guards-pnpm-dirs (Fase 2.6)

**Branch:** refactor/dead-guards-pnpm-dirs · **Base:** dev · **Fecha:** 2026-08-26 · Cierra el issue #62 · Presupuesto: ~5 min/reviewer, tres rondas

## El issue estaba medio equivocado, y lo escribí yo

El #62 pedía borrar dos guards de `_workspace_scope_pnpm_dirs` con el argumento de que el chequeo final `[ -z "$rels" ] && return 1` los atrapa igual. La evidencia adjunta era de qa-backend, del review del PR #58: removió cada uno por separado y la suite quedó en 176/176.

**La premisa era falsa para uno de los dos.** `jq` emite salida a medida que la produce: si el error aparece en el elemento N, los N−1 anteriores ya salieron. `rels` queda **no vacío pero truncado**, el chequeo final no dispara, y `_WS_DIRS` se puebla incompleto con `rc=0`.

## Los dos reviewers lo encontraron por separado, con disparadores distintos

**security-reviewer** — elemento sin `.path`, `.path` no-string, o JSON válido con basura después. Reproducido end-to-end con pnpm 10.32.1 real sobre un monorepo con workspaces anidados:

```
old (dev):  rc=1 → fail-closed, corre la suite completa
new:        rc=0 → _WS_DIRS=(app), faltan app/sub y otro
            → APP_RAN=SI  SUB_RAN=NO
```

El commit pasa habiendo corrido menos tests que el fallback, en silencio. Contradice el invariante que el propio archivo declara en su header.

**qa-backend** — JSON válido seguido de texto extra en el mismo stdout, que es como corepack y npm ensucian una salida `--json`. No hace falta un pnpm roto.

## Por qué la evidencia original no lo vio

El único fixture de JSON malo del corpus (`{not valid json`) rompe en el **primer** carácter, así que `jq` no emite nada parcial y `rels` sale vacío con o sin el guard. Los 176/176 de entonces y los 217/217 del agente `refactor` no distinguían las dos ramas.

**El agente verificó de buena fe —tres experimentos reales, números reales— pero contra un corpus ciego a la rama que importaba.** Eso no confirma la afirmación: confirma que el corpus calla. Es la distinción que deja este PR.

## Lo que terminó entrando

| | |
|---|---|
| `[ -z "$list_json" ] && return 1` | **Borrado.** Los dos reviewers lo confirmaron muerto: con `list_json` vacío, `jq` sale `rc=0` sin salida y el chequeo final lo atrapa |
| `\|\| return 1` del pipeline | **Conservado**, con cuatro líneas de comentario explicando el mecanismo no obvio |
| Test del guard | JSON válido + contenido extra en stdout |
| Test del filtro | Elemento sin campo `path` |

## Los dos fixtures no son redundantes, y qa-backend explicó por qué

Fallan por **mecanismos distintos**. El del guard depende de un error del *reader* top-level de `jq` —contenido extra después del array—, que ocurre sin importar cómo esté escrito el filtro. El del filtro depende de un error de *evaluación*.

Verificación de dos pasos, exigida antes de aceptar el fixture nuevo:

| Experimento | Test del guard | Test del filtro |
|---|---|---|
| Guard quitado | rojo | rojo |
| Guard puesto, filtro suavizado a `.path? // empty` | **verde** | **rojo** |

El segundo es el que prueba que el fixture nuevo aporta algo: si alguien "endurece" el filtro para tolerar entradas sin `path`, el guard deja de tener error que atrapar y el bug original vuelve por otra puerta. Sin ese test, nadie lo vería.

qa-backend confirmó además que el fixture es black-box —solo mira el `rc` de la función— así que cubre también variantes como envolver el pipeline en `try ... catch empty`.

## Cierre

Veredictos limpios en la última ronda de cada reviewer. Suite de 217 a **219**. El issue #62 quedó corregido con un comentario que documenta el alcance real y por qué la evidencia original no alcanzaba — no se editó el cuerpo original, para que quede el rastro.

**Saldo del refactor:** el archivo quedó con menos código y más protección que antes de abrirlo. Lo contrario de lo que el issue pedía.
