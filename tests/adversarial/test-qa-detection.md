# QA Detection Test Fixtures

Código deliberadamente malo que los QA agents DEBEN detectar. Usar estos fixtures para validar que `qa-frontend` y `qa-backend` están funcionando correctamente.

## Cómo usar

1. Crear un PR con uno o más de estos fixtures
2. Invocar al QA agent correspondiente según la capa del fixture:
   - Fixtures 1, 2, 3 (Python) → `qa-backend`
   - Fixture 4 (TypeScript) → `qa-frontend` si el archivo está bajo `components/`, `pages/`, `app/`, etc.; `qa-backend` si está bajo `services/`, `api/`, `server/`, etc.
3. Verificar que detecta TODOS los problemas listados
4. Si no detecta alguno, ajustar el prompt del agente correspondiente

---

## Fixture 1: Stubs y TODOs

El QA DEBE detectar y reportar como bloqueante.

```python
# file: services/user_service.py

def create_user(data: dict) -> dict:
    # TODO: implement validation
    pass

def get_user(user_id: int):
    raise NotImplementedError("coming soon")

def delete_user(user_id: int) -> bool:
    # FIXME: actually delete from database
    return True
```

**Expected QA findings:**
- `pass` as implementation (stub)
- `NotImplementedError` placeholder
- `FIXME` comment with no real implementation
- Missing type hints on `get_user`
- `dict` input/output instead of Pydantic models

## Fixture 2: Tests skippeados sin justificación

```python
# file: tests/test_user_service.py
import pytest

@pytest.mark.skip
def test_create_user():
    assert create_user({"name": "test"}) is not None

@pytest.mark.skip(reason="")
def test_delete_user():
    assert delete_user(1) is True

# Este está bien — tiene justificación
@pytest.mark.skip(reason="Depends on external API, tracked in JIRA-123")
def test_external_integration():
    pass
```

**Expected QA findings:**
- `test_create_user` skippeado sin razón
- `test_delete_user` skippeado con razón vacía
- `test_external_integration` aceptable (tiene justificación con issue reference)

## Fixture 3: Red flags Python

```python
# file: services/data_processor.py
import os
from utils import *

def process(d, l=[]):
    if len(l) == 0:
        l = d
    for i in range(len(l)):
        x = l[i]
        if x == None:
            try:
                result = os.system("echo " + str(x))
            except:
                pass
        else:
            if x == True:
                if isinstance(x, str):
                    print("processing: " + x)
                    result = x.upper()
    return l
```

**Expected QA findings:**
- `import *`
- Mutable default `l=[]`
- `len(l) == 0` instead of `if not l:`
- `range(len(l))` instead of `enumerate(l)`
- Single-letter variables (`d`, `l`, `x`, `i`)
- `== None` instead of `is None`
- `os.system()` with string concatenation (command injection)
- Bare `except: pass`
- `== True` instead of `is True`
- 4 levels of nesting
- `print()` in production code
- No type hints
- Missing docstring on public function

## Fixture 4: Red flags TypeScript

```typescript
// file: services/userService.ts
import { User } from './types'

export async function getUsers() {
  const response = fetch('/api/users')
  const data: any = response.json()
  return data
}

export function processUser(user: any) {
  const name = user!.name
  const role = user.role || ''

  // eslint-disable-next-line
  console.log('processing user', name)

  if (user.active) {
    if (user.role === 'admin') {
      if (user.permissions) {
        if (user.permissions.includes('write')) {
          return { ...user, canWrite: true }
        }
      }
    }
  }

  return user
}
```

**Expected QA findings:**
- `async` function without `await` on fetch (floating promise)
- `any` type used twice
- Non-null assertion (`!`) on `user!.name`
- `||` instead of `??` for default value
- `eslint-disable` without justification
- `console.log` in production code
- 4 levels of nesting
- Missing return type annotations
- `import type` should be used for `User` (if only used as type)
