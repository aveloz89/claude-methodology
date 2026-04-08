# Self-Reflection Rules

Proceso de auto-revisión que los agentes dev ejecutan ANTES de hacer commit. El objetivo es detectar y corregir violaciones idiomáticas antes de que lleguen al QA, reduciendo ciclos de review.

## Cuándo ejecutar

Después de la verificación final (tests, coverage, build) y ANTES del commit. El código ya funciona — ahora se revisa que sea idiomático y limpio.

## Proceso

### 1. Identificar el lenguaje y cargar las rules

- Python → leer `rules/python.md`
- TypeScript/JavaScript → leer `rules/typescript.md`
- Si el PR tiene ambos lenguajes, revisar contra ambos archivos

### 2. Revisar el diff completo

Ejecutar `git diff --cached` (o `git diff` si aún no está staged) y revisar CADA archivo modificado contra las rules del lenguaje correspondiente.

### 3. Checklist de revisión

Para cada archivo modificado, verificar:

#### Generales (todos los lenguajes)
- [ ] No hay strings mágicos repetidos (deberían ser constantes/enums)
- [ ] No hay funciones de más de ~50 líneas
- [ ] No hay más de 3 niveles de nesting
- [ ] No hay `console.log` / `print()` en código de producción
- [ ] No hay comentarios obvios o redundantes
- [ ] Error handling es específico (no catch-all genéricos)

#### Python (si aplica)
- [ ] Type hints en funciones públicas
- [ ] No mutable defaults (`list`, `dict`, `set` como default)
- [ ] Patrones pythónicos (`enumerate`, `zip`, f-strings, `pathlib`, context managers)
- [ ] No bare `except:` ni `except Exception:` en lógica de negocio
- [ ] No `import *`

#### TypeScript (si aplica)
- [ ] No `any` — usar tipos concretos o `unknown`
- [ ] No non-null assertions (`!`) sin justificación
- [ ] `import type` para imports de solo tipos
- [ ] No floating promises (todo Promise con `await`, `.then()`, o `void`)
- [ ] `??` en vez de `||` para defaults

### 4. Corregir violaciones encontradas

- Corregir cada violación directamente
- Re-ejecutar tests para confirmar que las correcciones no rompen nada
- Si una corrección es controversial (ej: cambiaría la lógica), NO la hagas y documéntala para el QA

### 5. Documentar en el commit

Si se corrigieron violaciones durante self-reflection, mencionarlo brevemente en el commit message:

```
Implement user authentication endpoint

- Add POST /auth/login with JWT token generation
- Add input validation with Pydantic models
- Self-reflection: fix mutable default in token config, add type hints to helper functions
```

## Qué NO es self-reflection

- **No es QA** — no busca edge cases ni lógica de negocio incorrecta
- **No es security review** — no busca vulnerabilidades OWASP
- **No es refactoring** — no reorganiza código ni cambia arquitectura
- Es exclusivamente una revisión idiomática contra las rules del proyecto
