# C# Review Rules

Reglas idiomáticas para revisar código C#. El QA agent lee este archivo cuando el PR contiene archivos `.cs`.

## Nombres y convenciones

- **PascalCase para públicos** — Clases, métodos, propiedades, eventos
- **camelCase para locales y parámetros** — `userName`, `itemCount`
- **`_camelCase` para campos privados** — `_userRepository`, `_logger`
- **`I` prefix para interfaces** — `IUserRepository`, `ILogger`
- **`Async` suffix en métodos async** — `GetUserAsync()`, `SaveChangesAsync()`
- **No abreviaciones** — `GetUser` no `GetUsr`, `repository` no `repo` (excepto convenciones conocidas como `id`, `db`)

## Null safety

- **Nullable reference types habilitados** — `<Nullable>enable</Nullable>` en el `.csproj`
- **No `!` (null-forgiving operator) sin justificación** — Maneja el null explícitamente
- **`?.` y `??` sobre null checks manuales** — `user?.Name ?? "Unknown"` sobre `if (user != null)`
- **No retornes `null` de colecciones** — Retorna colección vacía (`Array.Empty<T>()`, `Enumerable.Empty<T>()`)
- **Pattern matching para null checks** — `if (user is not null)` sobre `if (user != null)`

## Patrones idiomáticos

- **`using` declarations (C# 8+)** — `using var stream = File.OpenRead(path);` sobre bloques `using () { }`
- **String interpolation** — `$"Hello {name}"` sobre `string.Format` o concatenación
- **Pattern matching** — `switch` expressions, `is` patterns, property patterns
- **Records para DTOs** — `record UserDto(string Name, string Email);` para objetos inmutables de datos
- **`init` properties** — Para propiedades que solo se setean en construcción
- **Primary constructors (C# 12)** si el proyecto lo soporta
- **Collection expressions (C# 12)** — `[1, 2, 3]` sobre `new[] { 1, 2, 3 }` si el proyecto lo soporta

## Async/Await

- **No `async void`** — Solo válido en event handlers. Siempre `async Task` o `async Task<T>`
- **No `.Result` ni `.Wait()`** — Deadlock risk. Usa `await` siempre
- **`ConfigureAwait(false)` en librerías** — No en código de aplicación (ASP.NET Core no tiene SynchronizationContext)
- **`CancellationToken` como último parámetro** — En todo método async que pueda ser cancelado
- **No `Task.Run()` innecesario** — No wrappees métodos sync en `Task.Run` para simular async
- **`ValueTask` sobre `Task`** cuando el resultado suele estar disponible síncronamente

## LINQ

- **Method syntax sobre query syntax** — `.Where().Select()` sobre `from x in y where ...`
- **No LINQ en hot paths** — LINQ tiene overhead de allocations. En código performance-critical, usa loops
- **`.Any()` sobre `.Count() > 0`** — Más eficiente y claro
- **No multiple enumeration** — Si necesitas enumerar un `IEnumerable` más de una vez, materializa con `.ToList()`

## Dependency Injection

- **Constructor injection** — No service locator pattern (`IServiceProvider.GetService<T>()` directo)
- **Interfaces para servicios** — `IUserService` inyectado, no `UserService` concreto
- **Scoped para DB contexts** — `AddScoped<DbContext>()`, no Singleton ni Transient
- **No lógica en constructores** — Solo asignación de dependencias

## Error handling

- **No bare `catch`** — Siempre especifica el tipo de excepción
- **No `catch (Exception ex) { }` vacío** — Log o throw, nunca silenciar
- **`throw;` sobre `throw ex;`** — Preserva el stack trace
- **Excepciones custom para dominio** — `UserNotFoundException` sobre `InvalidOperationException`
- **No excepciones para control de flujo** — Usa Result pattern o return codes para errores esperados

## Testing

- **xUnit o NUnit como framework** — Consistente con lo que ya usa el proyecto
- **Arrange-Act-Assert** — Estructura clara en cada test
- **Mocks con interfaces** — `Mock<IUserRepository>` (Moq) o `Substitute.For<IUserRepository>()` (NSubstitute)
- **`[Theory]` con `[InlineData]`** para variaciones — No copiar tests con inputs distintos
- **FluentAssertions** — `result.Should().Be(expected)` para assertions legibles
- **No tests de implementación** — Testea comportamiento, no internals

## ASP.NET Core (si aplica)

- **No lógica en controllers** — Controllers reciben request, llaman al service, retornan response
- **`IActionResult` o typed results** — `ActionResult<UserDto>` para endpoints tipados
- **Model validation con Data Annotations o FluentValidation** — No validación manual en controllers
- **Middleware para cross-cutting concerns** — Auth, logging, error handling
- **Status codes explícitos** — `CreatedAtAction()`, `NoContent()`, `NotFound()`

## Entity Framework Core (si aplica)

- **No queries en views/controllers** — Las queries van en repositories o services
- **`.Include()` explícito** — No lazy loading implícito
- **Migraciones revisables** — Verificar que no hay data loss
- **`AsNoTracking()` para queries de lectura** — Mejora performance cuando no vas a modificar

## Red flags

- `async void` fuera de event handlers
- `.Result` o `.Wait()` en código async
- `catch (Exception) { }` vacío
- `throw ex;` en vez de `throw;`
- `#pragma warning disable` sin justificación
- `dynamic` sin justificación
- `object` como tipo de parámetro donde un tipo concreto funcionaría
- Funciones de más de ~50 líneas
- Más de 3 niveles de nesting
- Strings mágicos repetidos (usar `const` o `enum`)
