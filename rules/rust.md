# Rust Review Rules

Reglas idiomáticas para revisar código Rust. El QA agent lee este archivo cuando el PR contiene archivos `.rs`.

## Ownership y borrowing

- **No `.clone()` innecesario** — Si clonas para satisfacer al borrow checker, probablemente hay una mejor estructura. Clone es válido cuando realmente necesitas una copia
- **Prefiere `&str` sobre `String` en parámetros** — Acepta borrows, retorna owned
- **Lifetimes explícitos solo cuando el compilador no puede inferir** — No anotes lifetimes innecesariamente
- **No `Rc`/`Arc` como primera opción** — Reestructura el ownership antes de recurrir a reference counting

## Error handling

- **`Result<T, E>` sobre `panic!`** — Panic es para bugs irrecuperables, no para errores esperados
- **No `.unwrap()` en código de producción** — Usa `?`, `.expect("razón")`, o pattern matching
- **Error types custom con `thiserror` o manual** — No `Box<dyn Error>` como catch-all en librerías
- **`anyhow` para aplicaciones, `thiserror` para librerías** — Distintos use cases
- **Propagación con `?`** — No matches manuales cuando solo propagas el error
- **`.expect("mensaje descriptivo")` sobre `.unwrap()`** — Cuando estás seguro de que no puede fallar, documenta por qué

## Patrones idiomáticos

- **Pattern matching exhaustivo** — Maneja todos los variants de un enum, no uses `_ =>` como catch-all a menos que sea intencional
- **`Option` sobre valores centinela** — No uses `-1`, `null`, `""` para "no hay valor"
- **Iteradores sobre loops manuales** — `.iter().map().filter().collect()` cuando es legible
- **`impl` methods sobre funciones sueltas** — Si opera sobre un tipo, debería ser un método
- **Derive traits comunes** — `#[derive(Debug, Clone, PartialEq)]` en structs de datos
- **`Default` trait** — Implementa `Default` para structs con valores sensatos por defecto
- **Builder pattern** para structs con muchos campos opcionales

## Tipos

- **Newtypes para domain modeling** — `struct UserId(u64)` sobre `u64` crudo
- **Enums para estados finitos** — No strings ni ints para representar estados
- **`From`/`Into` para conversiones** — No funciones sueltas `to_foo()`
- **Type aliases con `type` solo para simplificar tipos complejos** — No para esconder el tipo real

## Unsafe

- **No `unsafe` sin justificación documentada** — Cada bloque unsafe necesita un `// SAFETY:` comment explicando por qué es sound
- **Minimiza el scope de `unsafe`** — El bloque unsafe debe ser lo más pequeño posible
- **Wrappea unsafe en safe abstractions** — El caller no debería saber que hay unsafe debajo

## Concurrencia

- **`Send` y `Sync` bounds explícitos** cuando diseñas APIs concurrentes
- **`Mutex<T>` wrappea el dato, no el acceso** — El dato protegido va dentro del Mutex
- **No locks anidados** — Riesgo de deadlock. Si necesitas varios, define un orden consistente
- **`tokio`/`async-std` para async** — No threads manuales para I/O

## Testing

- **Tests en el mismo archivo con `#[cfg(test)]`** — Para unit tests
- **`tests/` directorio para integration tests** — Tests que usan la API pública
- **`assert_eq!` con mensajes** — `assert_eq!(got, want, "failed for input {}", input)`
- **Property-based testing con `proptest`** — Para funciones puras con muchos inputs posibles
- **No ignores tests** — `#[ignore]` necesita justificación

## Cargo y dependencias

- **`Cargo.lock` committeado en binarios** — No en librerías
- **Features para funcionalidad opcional** — No dependencias obligatorias para features que no todos usan
- **`clippy` sin warnings** — `cargo clippy -- -D warnings` debería pasar limpio

## Red flags

- `.unwrap()` en código de producción
- `.clone()` para satisfacer el borrow checker sin entender por qué
- `unsafe` sin `// SAFETY:` comment
- `#[allow(unused)]` o `#[allow(dead_code)]` sin justificación
- `String` en parámetros donde `&str` funciona
- `Box<dyn Error>` en librerías (usar error types específicos)
- Funciones de más de ~50 líneas
- Más de 3 niveles de nesting
- `todo!()` o `unimplemented!()` en código mergeado
