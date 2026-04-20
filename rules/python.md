# Python Review Rules

Reglas idiomáticas para revisar código Python. El agente `qa-backend` lee este archivo cuando el PR contiene archivos `.py`.

## Tipos y type hints

- **Type hints en funciones públicas** — Parámetros y retorno deben estar tipados
- **No `Any` innecesario** — Usa tipos concretos, `Union`, `Optional`, generics
- **`Optional[X]` solo si `None` es un valor válido** — No como atajo para "no sé el tipo"
- **Usa `|` syntax (3.10+)** si el proyecto lo soporta: `str | None` en vez de `Optional[str]`

## Patrones pythónicos

- **No `len(lista) == 0`** — Usa `if not lista:`
- **No `== True` / `== False` / `== None`** — Usa `is True`, `is False`, `is None`
- **List/dict comprehensions sobre loops** cuando son legibles (una línea). Si necesitas más de una línea, usa un loop
- **`enumerate()` sobre `range(len())`** para iterar con índice
- **`zip()` para iterar dos listas en paralelo**
- **`pathlib.Path` sobre `os.path`** para manipulación de rutas
- **f-strings sobre `.format()` y `%`** para string formatting
- **Context managers (`with`)** para archivos, locks, conexiones DB

## Mutable defaults (trampa clásica)

```python
# MAL — el default mutable se comparte entre llamadas
def add_item(item, items=[]):
    items.append(item)
    return items

# BIEN
def add_item(item, items=None):
    if items is None:
        items = []
    items.append(item)
    return items
```

Buscar activamente este anti-pattern en funciones con defaults `list`, `dict`, `set`.

## Async

- **No mezclar sync y async** — Si una función es async, sus callers deben ser async también. No usar `asyncio.run()` dentro de código async
- **No `await` en loops** si se puede paralelizar con `asyncio.gather()`
- **Async context managers** (`async with`) para recursos async (DB connections, HTTP sessions)

## Error handling

- **No bare `except:`** — Siempre especifica el tipo de excepción
- **No `except Exception:`** como catch-all en lógica de negocio — es válido solo en boundaries (handlers, workers)
- **No silenciar excepciones** — `except SomeError: pass` necesita justificación
- **Excepciones custom sobre genéricas** — `raise UserNotFoundError()` sobre `raise ValueError("user not found")`

## Imports

- **No `import *`** — Importa lo que necesitas explícitamente
- **Orden de imports** — stdlib → third party → local (isort/ruff se encargan, pero verificar)
- **No imports circulares** — Si necesitas un type hint circular, usa `from __future__ import annotations` o `TYPE_CHECKING`

## FastAPI / Pydantic (si aplica)

- **Pydantic models para request/response** — No uses dicts crudos
- **Validadores en el model, no en el endpoint** — La validación vive en Pydantic
- **Dependency injection** — Usa `Depends()` para DB sessions, auth, etc. No importes directamente
- **Status codes explícitos** — `status_code=201` para creación, `status_code=204` para delete, etc.
- **No lógica de negocio en endpoints** — El endpoint recibe, valida, llama al service, retorna

## Django (si aplica)

- **No queries en templates** — Si ves `{{ object.related_set.all }}` en un template, debería estar en la view con `select_related`/`prefetch_related`
- **No lógica en views** — Las views orquestan, la lógica va en models o services
- **Migraciones** — Verificar que las migraciones son reversibles y no tienen data loss

## Testing

- **Fixtures sobre setup repetido** — Usa `@pytest.fixture` para datos de test reutilizables
- **`pytest.raises` para excepciones** — No try/except en tests
- **No hardcodear paths** — Usa `tmp_path` fixture para archivos temporales
- **Parametrize para variaciones** — `@pytest.mark.parametrize` en vez de copiar tests con inputs distintos

## Red flags

- `# type: ignore` sin justificación
- `print()` en código de producción (usa `logging`)
- Variables de una letra fuera de comprehensions y loops cortos
- Funciones de más de ~40 líneas
- Más de 3 niveles de nesting
- Strings mágicos repetidos (deberían ser constantes o enums)
- `os.system()` o `subprocess.call()` con strings (inyección de comandos) — usar `subprocess.run()` con lista de args
