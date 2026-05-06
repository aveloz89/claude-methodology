---
paths:
  - "**/*.go"
---

# Go Review Rules

Reglas idiomáticas para revisar código Go. El agente `qa-backend` lee este archivo cuando el PR contiene archivos `.go`.

## Nombres y convenciones

- **Nombres cortos y concisos** — `srv` no `server`, `ctx` no `context`, `err` no `error`. Go idiomático prefiere nombres cortos en scope corto
- **No prefijos de tipo** — `User` no `UserStruct`, `Reader` no `IReader`
- **Interfaces de un método terminan en `-er`** — `Reader`, `Writer`, `Closer`, `Stringer`
- **Acrónimos en mayúsculas** — `HTTPServer`, `userID`, `xmlParser` (no `HttpServer`, `userId`)
- **Paquetes en singular y lowercase** — `user` no `users`, no `userPackage`, no `user_service`
- **No stuttering** — `user.User` está bien, `user.UserService` no (debería ser `user.Service`)

## Error handling

- **No ignores errores** — `result, _ := doSomething()` necesita justificación explícita
- **Errors are values** — Retorna `error` como último valor, no uses panic para control de flujo
- **Wrap errors con contexto** — `fmt.Errorf("fetching user %d: %w", id, err)` no `return err` a secas
- **Errors custom con `errors.New` o tipos propios** — Para errores de dominio que necesitan ser matcheados
- **`errors.Is()` y `errors.As()`** sobre comparación directa — Para unwrapping de errors wrapeados
- **No `panic` en librerías** — Solo en `main` o en situaciones verdaderamente irrecuperables

## Patrones idiomáticos

- **Accept interfaces, return structs** — Parámetros como interfaces, retornos como tipos concretos
- **No interfaces prematuras** — Solo crea una interface cuando tienes 2+ implementaciones o necesitas mock en tests
- **Comma-ok pattern** — `val, ok := myMap[key]` siempre, no `val := myMap[key]` directamente
- **Early returns** — Maneja el error primero, happy path sin nesting
- **`defer` para cleanup** — Files, locks, conexiones. Pero cuidado con `defer` en loops
- **No `init()`** — Excepto para register de drivers. Inicialización explícita es mejor
- **Zero values útiles** — Diseña structs que funcionen con sus zero values cuando sea posible

## Goroutines y concurrencia

- **No lances goroutines sin forma de pararlas** — Siempre usa `context.Context` o un channel de done
- **`sync.WaitGroup` para fan-out/fan-in** — No sleep para esperar goroutines
- **Channels para comunicación, mutexes para estado** — "Don't communicate by sharing memory; share memory by communicating"
- **No goroutine leaks** — Toda goroutine debe tener un exit path claro
- **`context.Context` como primer parámetro** — `func DoWork(ctx context.Context, ...) error`
- **`select` con `ctx.Done()`** — Para goroutines que esperan en channels

## Structs y tipos

- **No getters/setters innecesarios** — Campos exportados están bien si son parte de la API pública
- **Constructores como `New<Type>()`** — `NewServer(addr string) *Server`
- **Embedding sobre herencia** — Usa embedding para composición, no para simular herencia OOP
- **No `interface{}` / `any` innecesario** — Usa generics (Go 1.18+) cuando aplique

## Testing

- **Table-driven tests** — `tests := []struct{ name string; input X; want Y }` con `t.Run()`
- **`testdata/` para fixtures** — Archivos de test en el directorio `testdata/`
- **No mocks excesivos** — Prefiere interfaces pequeñas que sean fáciles de implementar en tests
- **`t.Helper()` en funciones auxiliares de test** — Para que los errores apunten al caller
- **`t.Parallel()` cuando sea seguro** — Para acelerar tests independientes
- **Subtests con `t.Run()`** — Para agrupar casos relacionados

## Módulos y dependencias

- **`go.sum` committeado** — Siempre va al repo
- **No dependencias innecesarias** — La stdlib de Go es muy completa, no importes un paquete para algo que puedes hacer en 5 líneas
- **`internal/` para código privado** — Lo que no debe ser importado por otros módulos

## Red flags

- `panic()` fuera de main o tests
- Error ignorado sin comentario (`_ = doSomething()`)
- `interface{}` / `any` donde generics o un tipo concreto funcionarían
- `time.Sleep()` para sincronización (usa channels o WaitGroup)
- Goroutine sin exit path (goroutine leak)
- `go func()` sin recover en boundaries de la app
- Package-level mutable state (variables globales mutables)
- `init()` con side effects
- Funciones de más de ~50 líneas
- Más de 3 niveles de nesting
