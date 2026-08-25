---
paths:
  - "**/*.sh"
  - "**/*.bash"
---

# Bash Review Rules

Reglas idiomáticas para revisar shell. El agente `qa-backend` lee este archivo cuando el PR contiene archivos `.sh` o `.bash`.

Buena parte del shell de este sistema son **hooks que deciden si un comando se ejecuta**. Ahí un error no produce un bug: produce un guard que deja pasar lo que debía bloquear. Por eso la sección de fail-closed va primero.

## Guards: fail-closed por defecto

- **Si no podés verificar, bloqueá.** Un guard que no logra consultar lo que necesita —falta un binario, la API no responde, el parseo devuelve vacío— bloquea con su razón, nunca pasa en silencio. "No pude verificar" y "está todo bien" no son el mismo estado
- **Declará las dependencias al inicio** con `command -v <bin> > /dev/null 2>&1 || bloquear`. Un `grep` o un `jq` ausente que se descubre a mitad del script ya dejó pasar medio camino
- **Degradar es una decisión, no un accidente.** Si un paso opcional falla y el script sigue, el comentario tiene que decir por qué esa dirección es la segura. Si no podés escribir esa frase, la dirección probablemente no es segura
- **Nunca devuelvas la cadena vacía como resultado degradado** de una función cuyo valor se compara o se grepea: el match no encuentra nada y el guard pasa. Devolvé el input sin procesar, que produce falsos positivos en vez de falsos permisos

## Quoting y expansión

- **Comillas siempre** — `"$var"`, `"$@"`, `"${arr[@]}"`. Sin comillas, bash re-parsea el valor: word splitting y glob expansion sobre datos que no controlás
- **`"$@"` nunca `$*`** para reenviar argumentos
- **Arrays para comandos, no strings.** `cmd=(npm test -w "$ws"); "${cmd[@]}"` — así un nombre con `;` o backticks viaja como un único argv y no se reinterpreta. Un comando armado como string y ejecutado con `eval` o sin comillas es inyección esperando el input correcto
- **Nada de `eval` ni `sh -c` con datos** que vengan de archivos, de `git`, de una API o del usuario
- **`${var:?mensaje}`** para exigir que una variable esté seteada, en vez de fallar tres líneas después con un path vacío

## Errores y estado de salida

- **`set -euo pipefail`** en scripts que ejecutan trabajo. **No** en hooks que deben decidir y responder siempre: ahí un `set -e` mata el script antes de que emita su veredicto, y el harness recibe silencio en vez de un bloqueo
- **Capturá `$?` en la línea inmediatamente siguiente** a lo que querés medir. Cualquier comando en medio —incluido un `echo`— lo pisa. Y `local var=$(cmd)` enmascara el status con el del propio `local`: declarar y asignar en líneas separadas
- **El exit code de un pipeline es el del último comando.** Si te importa el del primero, usá `pipefail` o `PIPESTATUS`
- **Ojo con los exit codes invertidos**: `grep -q` sale 1 cuando no encuentra, que suele ser el caso *bueno*. Encadenar eso con `&&` o bajo `set -e` produce falsos rojos. El idioma `grep -cv <patrón>` con comparación de conteo es más legible cuando lo que importa es "no debe haber ninguno"

## Portabilidad

- **macOS no es GNU.** `sed -i` pide argumento, `ps -o etimes=` no existe, `timeout` no viene instalado, `date -d` es otra cosa. Si el script corre en la máquina de alguien, verificá los flags **ahí**, no en la documentación de coreutils
- **Preferí lo que existe en ambos**: `ps -o etime=`, `perl -e 'alarm'` en vez de `timeout`, `mktemp -d` sin plantilla
- **Resolvé rutas sin binarios externos** cuando podés: `"${0%/*}"` es el idioma para dirname cuando `$0` trae al menos un `/`

## Procesos y limpieza

- **Matar un subshell no mata a sus hijos.** `kill -9 "$pid"` sobre el shell que lanzó un pipe deja al hijo huérfano corriendo. Usá `pkill -P "$pid"` o el grupo de procesos
- **Acotá en tiempo todo lo que pueda no terminar** —un regex sobre input no confiable, una espera de red—: `perl -e 'BEGIN{alarm N}'` o un watchdog explícito. Un proceso colgado en un hook cuelga la sesión entera
- **Limpiá lo que creás**: `trap 'rm -rf "$tmp"' EXIT` para directorios temporales, `git worktree remove` para worktrees

## Regex

- **Nada de cuantificadores anidados sobre texto solapado.** `(?:(?!X).*\n?)*` con `.` matcheando newline es backtracking exponencial: consume línea por línea con `[^\n]*\n` para que cada iteración avance exactamente un salto y no haya ambigüedad
- **Preferí no-greedy cuando la semántica es "hasta el primero"** — un delimitador de cierre, un terminador de bloque. Greedy se estira hasta el último y se traga lo que hay en medio
- **Probá el regex contra la realidad que va a parsear**, no contra el caso feliz que tenías en mente

## Testing

- **Los tests de shell corren binarios reales en directorios temporales**, no mocks: `mktemp -d`, fixtures escritos ahí, y aserciones sobre efectos observables (exit code, archivos marcador) en vez de sobre internals
- **Fixture con heredoc: delimitador entre comillas** (`<<'EOF'`) salvo que quieras expansión. Sin comillas, `$(...)` y `$var` del cuerpo se evalúan al escribir el archivo
- **Un test que verifica un fix debe romperse si revertís el fix** — ver el corolario del principio 5 en `implementation-principles.md`

## Red flags

- Un guard que sale 0 por un camino que no verificó nada
- `eval`, `sh -c` o variables sin comillas en la línea que ejecuta el trabajo
- `$?` leído lejos de lo que mide
- `set -e` en un hook que tiene que responder siempre
- Un flag de GNU en un script que corre en macOS
- Un comentario que afirma una garantía absoluta ("ningún modo de falla…", "el único caso es…"): se escribe como inventario de lo verificado, no como absoluto
