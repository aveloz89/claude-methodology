# Architecture

Decisiones arquitectónicas recurrentes del proyecto. El `architect` lee este archivo al inicio de cada diseño para mantener consistencia, y lo actualiza al final con decisiones nuevas.

A diferencia de `DESIGN.md` (que vive solo durante una feature), este archivo persiste y acumula decisiones de **alcance recurrente**: stack, patrones, librerías canónicas, convenciones.

## Qué va aquí

- Arquitectura elegida y justificación (Monolito | Modular | Clean | Hexagonal | Microservicios)
- Patrones adoptados (repository, service layer, ports/adapters, etc.)
- Stack confirmado: librerías canónicas para validación, ORM, HTTP client, logging, cache, queue, testing
- Convenciones de nombres y estructura de directorios
- Boundaries entre módulos / bounded contexts

## Qué NO va aquí

- Detalles de la feature actual (eso vive en `DESIGN.md`)
- Decisiones específicas a un PR
- Notas de implementación

## Formato de entrada

```markdown
### [YYYY-MM-DD] Título de la decisión

**Contexto:** qué situación llevó a esta decisión.

**Decisión:** qué se eligió.

**Justificación:** por qué (alternativas evaluadas, tradeoffs).

**Implicación:** qué cambia para futuros diseños / qué patrones se siguen.
```

---

## Decisiones

(Las entradas se agregan aquí, la más reciente arriba)
