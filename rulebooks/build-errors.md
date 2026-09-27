# Build Errors

Conocimiento para resolver un error de build, compilación o dependencias. Lo usa el mismo dev que produjo el error (`backend-dev` o `frontend-dev`) — el error nace en el contexto de qué cambió y por qué, y ese contexto ya lo tiene quien lo produjo. Se aplica también cuando el usuario pide ayuda directa con un build roto en su branch: la sesión delega en `backend-dev` o `frontend-dev` con este rulebook, no hay agente aparte que invocar.

## Clasificar el error antes de tocar nada

No todo lo que llega como "el build falla" es un error de build. Clasifica primero:

| Tipo de error | Es de build | Acción |
|---|---|---|
| Type error (TypeScript, mypy) | sí | arreglar el tipo correctamente |
| Module not found / Cannot resolve | sí | arreglar import / instalar dep / corregir config |
| Versión incompatible / peer dependency | sí | escalar si es major, aplicar si es minor/patch |
| Dockerfile syntax / build context | sí | arreglar |
| Lint error de formato (espacios, comillas) | sí | correr autofix y commitear |
| Error en CI por env var faltante | sí | agregar en `.env.example` o config de CI |
| Test fallando con assertion error | no | bug de código o de test — sigue en tu lote, no cambia de dueño |
| Test fallando con timeout / flakiness | no | problema de test, mismo dueño |
| Lint error que requiere cambiar lógica | no | decisión de código, mismo dueño |
| Runtime error en producción/staging | no | bug de lógica, mismo dueño |
| Error en CI por servicio externo caído | no | reportar al usuario, no es de build |

Si el error cae en la columna "no", el fix sigue siendo tuyo (sos el dev del lote) pero ya no es un problema de build: aplica el flujo normal de tu agente, no este rulebook.

## Causa raíz

1. Lee el error completo (stack trace, logs) e identifica qué falla (archivo, línea, módulo), qué tipo es y cuándo empezó (`git diff dev...HEAD`, `git log --oneline -10`).
2. Investiga según el tipo:
   - **Tipos/módulos**: ¿el import/export es correcto? ¿los tipos son compatibles con la firma esperada? ¿la dep existe con la versión correcta? ¿la config del build tool está bien?
   - **Dependencias**: `pnpm ls <dep>` / `npm ls <dep>`, `pip show <dep>`, `go list -m all | grep <dep>`.
   - **Docker**: `docker compose logs --tail=50 <servicio>`, `docker compose config`, `docker compose build --no-cache <servicio> 2>&1 | tail -30`.
   - **Local vs CI**: versión de Node/Python/Go del workflow vs local, env vars que falten en uno u otro, cache corrupto (`actions/cache` con keys viejas).

## Fix mínimo

Aplica el cambio mínimo para que el build pase. Si involucra una dependencia, usa la tabla de abajo. Si agrega o cambia config, documenta la razón en el commit.

Verifica que el build pasa (`pnpm tsc --noEmit && pnpm build` / `python -m mypy . && python -m build` / `go build ./...` / `cargo check && cargo build` / `dotnet build` / `docker compose build <servicio>`, según el stack) y que los tests que pasaban antes siguen pasando — no que todos los tests pasen: algunos pueden estar fallando por bugs no relacionados, eso no cambia con este fix.

Si tu fix hace pasar el error pero introduce uno nuevo: no acumules fixes sobre fixes. Revierte (`git checkout <archivo>` o `git reset --soft HEAD~1`), vuelve a investigar la causa raíz — la hipótesis anterior probablemente era incorrecta — y aplica un fix distinto.

## Dependencias: criterio

| Cambio | Acción |
|---|---|
| Patch update (`1.2.3 → 1.2.4`) | aplicar, documentar en el commit |
| Minor update (`1.2.0 → 1.3.0`) | aplicar, documentar en el commit |
| Major update (`1.x → 2.x`) | escalar al architect o al usuario |
| Agregar dependencia nueva al proyecto | escalar al architect o al usuario |
| Remover dependencia que ya no se usa | escalar al architect (puede tener consumers ocultos) |
| Mover dep entre `dependencies` y `devDependencies` | aplicar, documentar |
| Downgrade de versión | escalar (puede reintroducir un CVE conocido) |
| Regenerar lockfile sin cambiar versiones | aplicar si es la causa del error |

Al escalar, reporta: qué cambio propones (de qué versión a qué versión, o qué dependencia agregar), por qué resolvería el build, y qué riesgo trae (breaking changes conocidos, CVE, incompatibilidad).

## En vez de → hacé

| En vez de | Hacé |
|---|---|
| `@ts-ignore`, `@ts-expect-error`, `# type: ignore`, `#[allow(...)]` para silenciar un type/lint error | arreglar el tipo o el código |
| `any` / `cast(Type, value)` sin validación para esquivar un type error | tipar correctamente |
| borrar un test que falla | arreglar el código o el test; si es un bug real, avisar al dueño del dominio |
| tocar `.gitignore` para esconder un archivo problemático | resolver la causa del archivo problemático |
| desactivar una regla de lint para evitar el error | arreglar el código que la viola |
| downgrade del runtime (Node, Python, Go, .NET) para esquivar el error | si la versión actual rompe el build, es decisión del architect actualizar el código o pinear el runtime |
| aflojar `strict`/`mypy`/`clippy` (`strict: false`, `--no-strict-features`) | esas reglas existen por algo; arreglar el código que no las cumple |
| refactorizar código no relacionado mientras arreglás el build | fix quirúrgico solamente — el refactor va en su propio PR |
| "limpiar" imports no usados que no son la causa del error | dejarlos; si son la causa, sí se tocan |
| agregar features o cambiar comportamiento de paso | eso no es un fix de build |

## Escalar antes de aplicar el fix

- Major version update de una dependencia → architect o usuario (decisión de stack).
- Dependencia nueva que no estaba en el proyecto → architect o usuario.
- Downgrade de una dependencia con CVE conocido → security-reviewer, no aplicar sin revisión.
- El fix implica cambiar una decisión arquitectónica (cambiar de ORM, de build tool) → architect.

## Commit y verificación

```bash
git add <archivos-cambiados>
git commit -m "build: <descripción del fix en imperativo>"
```

Ejemplos: `build: corregir tipo de retorno de getUserById`, `build: actualizar zod a 3.22.4 por incompatibilidad con TS 5.4`, `build(docker): agregar libssl-dev a imagen de Python`, `build(ci): pinear setup-node a v4`.

No pusheas fuera de las excepciones ya definidas en `dev-common.md` — el commit del fix se comporta como cualquier otro commit de tu lote.

## Tres intentos

Si después de tres intentos de fix el build sigue fallando, no sigas iterando a ciegas:

1. No uses `git reset --hard` (el hook `block-hard-reset.sh` lo bloquea). Alternativas seguras: `git reset --soft <commit-antes-de-tus-intentos>` + `git checkout -- .` o `git stash`; o `git revert <rango>` si preferís no reescribir historia.
2. Reporta al orchestrator qué intentaste y por qué no funcionó.
3. Sugiere a quién escalar: architect si requiere decisión de stack, al dueño del dominio si requiere conocimiento específico, al usuario si es ambiguo.

No dejes el branch a medio camino con fixes parciales — es peor que el estado original.
