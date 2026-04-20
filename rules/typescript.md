# TypeScript Review Rules

Reglas idiomáticas para revisar código TypeScript/JavaScript. Lo lee `qa-frontend` para archivos en rutas de UI (`components/`, `pages/`, `app/`, `hooks/`, etc.) y `qa-backend` para archivos en rutas de servidor (`api/`, `services/`, `controllers/`, `routes/`, etc.). Las reglas de React dentro de este archivo solo aplican al review de `qa-frontend`.

## Tipos

- **No `any`** — Usa tipos concretos, generics, o `unknown` si no sabes el tipo. `any` desactiva el type checker
- **No type assertions innecesarias** (`as Type`) — Prefiere type guards (`if ('key' in obj)`, `instanceof`, discriminated unions)
- **Usa `as const`** para literales que no deben mutar (ej: arrays de opciones, objetos de config)
- **No `!` (non-null assertion)** — Maneja el caso `null`/`undefined` explícitamente
- **Prefiere `unknown` sobre `any`** en catches: `catch (error: unknown)`
- **Interfaces para objetos, types para unions/intersecciones** — Mantén consistencia con lo que ya use el proyecto

## Imports y exports

- **No imports circulares** — Si A importa B y B importa A, hay un problema de diseño
- **No re-exports innecesarios** — Un barrel file (`index.ts`) está bien, pero no hagas cadenas de re-exports
- **Imports de tipos con `import type`** — Evita importar tipos como valores (`import type { User } from ...`)

## Async

- **No `async` sin `await`** — Si la función no tiene `await`, no necesita ser `async`
- **No floating promises** — Todo `Promise` debe tener `await`, `.then()`, o `void` explícito
- **No `Promise` constructor innecesario** — Si ya tienes una función async, no la wrappees en `new Promise()`
- **Error handling en async** — `try/catch` o `.catch()`. Nunca dejes un promise sin manejo de error en boundaries

## React (si aplica)

- **No lógica de negocio en componentes** — Solo renderizado, estado de UI y llamadas a API
- **Keys estables en listas** — Usa IDs, no índices del array (salvo listas estáticas)
- **No estado derivado** — Si puedes calcularlo del estado existente, no lo guardes en otro `useState`
- **useEffect solo para sincronización con sistemas externos** — No para derivar estado ni para "reaccionar" a cambios
- **Dependencias completas en hooks** — No ignores warnings del exhaustive-deps lint rule
- **Memoización justificada** — `useMemo`/`useCallback` solo cuando hay un problema de performance medido, no preventivamente

## Patrones

- **Prefiere `Map`/`Set` sobre objetos planos** cuando las keys son dinámicas
- **Prefiere `??` (nullish coalescing) sobre `||`** para defaults — `||` trata `0`, `""`, `false` como falsy
- **Prefiere optional chaining (`?.`)** sobre checks manuales de null
- **No mutar argumentos** — Retorna nuevos objetos/arrays en vez de modificar los que recibes
- **Enums: prefiere `as const` objects** sobre `enum` — los enums de TS tienen comportamientos inesperados en runtime

## Testing

- **No `test.skip` sin justificación** — Si un test está skippeado, debe tener un comentario con issue/razón
- **No snapshots para lógica** — Snapshots son para UI estática, no para validar comportamiento
- **Mocks tipados** — Usa `vi.fn<>()` o `jest.fn<>()` con tipos, no mocks sin tipar
- **No testees implementación** — Testea comportamiento (qué retorna, qué efecto tiene), no cómo lo hace internamente

## Red flags

- `// eslint-disable` o `// @ts-ignore` sin justificación
- `console.log` en código de producción (solo permitido en logger dedicado)
- Strings mágicos repetidos (deberían ser constantes o enums)
- Funciones de más de ~50 líneas (señal de que hace demasiado)
- Más de 3 niveles de nesting (refactorear con early returns o extraer funciones)
