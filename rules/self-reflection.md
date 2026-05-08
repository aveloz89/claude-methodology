# Self-Reflection Rules

Proceso de auto-revisión que los agentes dev ejecutan ANTES de hacer commit. El objetivo es detectar y corregir violaciones idiomáticas antes de que lleguen al QA, reduciendo ciclos de review.

## Cuándo ejecutar

Después de la verificación final (tests, coverage, build) y ANTES del commit. El código ya funciona — ahora se revisa que sea idiomático y limpio según las `rules/` del lenguaje.

## Fuente única de verdad

**Las reglas idiomáticas viven en `rules/<lenguaje>.md`, no en este archivo.** Este documento define el *proceso* de revisión. Las reglas concretas (estilo, patrones, anti-patrones, métricas) se cargan desde el archivo de rules correspondiente al lenguaje del archivo modificado.

Si una regla aparece duplicada entre este documento y `rules/`, la versión en `rules/` gana.

## Proceso

### 1. Mapear archivos del diff a sus rules

Ejecutar `git diff --cached --name-only` (o sin `--cached` si nada está staged) y, para cada archivo modificado, identificar el `rules/<lenguaje>.md` correspondiente según extensión (la tabla está en el `CLAUDE.md` raíz, sección Stack).

Si una extensión no tiene archivo de rules, el archivo se revisa solo contra principios generales del proyecto (`implementation-principles.md`) y se omite la revisión idiomática.

### 2. Cargar las rules necesarias

Cargar **una vez** cada archivo de rules que vaya a usarse. No recargar entre archivos del mismo lenguaje.

Si el PR es grande (>15 archivos modificados o >2 lenguajes distintos), revisar agrupando por lenguaje en lugar de archivo por archivo, para reducir cambios de contexto.

### 3. Revisar el diff

Para cada archivo modificado, revisar **solo las líneas del diff** contra las rules cargadas. No revisar el archivo completo — eso es scope del agente `refactor`, no de self-reflection.

Excepción: si una línea del diff modifica una función, revisar la función completa (porque el cambio puede haber roto la coherencia interna). **Tope:** si la función pasa de ~50 líneas, mantener la revisión a las líneas del diff y reportar el resto como issue legacy si hay violaciones visibles — no expandir el scope al revisar funciones largas heredadas.

### 4. Clasificar cada violación encontrada

Para cada violación, decidir su categoría:

| Categoría | Definición | Acción |
|-----------|------------|--------|
| **In-scope, trivial** | Fix mecánico (rename, ajuste a patrón idiomático equivalente, formato), no cambia lógica ni decisiones de diseño | Arreglar directamente, re-correr tests |
| **In-scope, controvertida** | Violación en código del diff pero el fix cambiaría comportamiento o requiere decisión de diseño | NO arreglar. Crear issue (ver paso 6) |
| **Legacy** | Violación en código que ya existía antes del PR (no tocado por el diff, pero visible al revisar el archivo) | NO arreglar (cambios quirúrgicos manda). Crear issue (ver paso 6) |

### 5. Aplicar correcciones in-scope triviales

- Arreglar cada violación trivial directamente.
- Re-ejecutar tests para confirmar que las correcciones no rompen nada.
- Si una corrección rompe tests, revertir y reclasificar como **in-scope controvertida** (paso 6).

### 6. Crear issues para violaciones no resueltas

Tanto las **controvertidas** como las **legacy** generan un issue en el backlog. Esto evita que se pierdan y le da trabajo concreto al agente `refactor`.

**Formato del issue (libre, pero con estos campos mínimos):**

- **Título:** `[self-reflection] <descripción corta>`
- **Etiqueta:** `legacy-violation` (si es legacy) o `controversial-fix` (si es in-scope controvertida)
- **Cuerpo:**
  - Archivo y línea(s) afectadas
  - Regla violada (referencia a `rules/<lenguaje>.md` o sección)
  - Por qué no se arregló en este PR (cambia lógica / requiere discusión / fuera de scope / etc.)
  - PR de origen (link)

**Cómo crearlo:** `gh issue create` en **el repo del PR actual** (los devs tienen permiso para correr `gh issue`).

**Si las labels no existen en el repo:** crearlas la primera vez con `gh label create legacy-violation` y `gh label create controversial-fix`. Si no se quieren crear las labels, se omiten y la categoría se indica en el título del issue (`[self-reflection][legacy] ...` o `[self-reflection][controversial] ...`).

**Fallback si `gh issue create` falla:** anotarlo en la descripción del PR bajo una sección `## Self-reflection — pendientes` para que no se pierda. Crear el issue después manualmente.

### 7. Documentar en el commit

Si se aplicaron correcciones triviales (paso 5), mencionarlo en el commit message. Formato libre, suficiente con que quede rastro:

```
auth: agregar endpoint POST /auth/login

- Generación de JWT con expiración configurable
- Validación de input con Pydantic
- Self-reflection: corregir mutable default en config, agregar type hints
```

Si solo se crearon issues (no hubo correcciones aplicadas), no es necesario mencionarlo en el commit — basta con los issues creados.

## Qué NO es self-reflection

- **No es QA** — no busca edge cases, lógica de negocio incorrecta, ni tests faltantes
- **No es security review** — no busca vulnerabilidades OWASP
- **No es refactoring** — no reorganiza código, no cambia arquitectura, no toca código fuera del diff
- **No reemplaza implementation-principles** — esos se aplican durante la implementación, no al final
- **No tiene reglas propias** — todas las reglas idiomáticas viven en `rules/<lenguaje>.md`

Es exclusivamente: *"¿el código del diff cumple las rules idiomáticas del proyecto, y si no, lo arreglo o lo escalo a issue?"*
