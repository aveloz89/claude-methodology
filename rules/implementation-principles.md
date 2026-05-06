# Implementation Principles

Principios de disciplina que los agentes dev aplican DURANTE la implementación. Complementan TDD y self-reflection:

- **TDD** asegura que el código funciona
- **Self-reflection** asegura que el código es idiomático
- **Implementation principles** aseguran que el scope es correcto

## Cuándo aplican

Durante toda la implementación — desde que el dev recibe el brief hasta que abre el PR. Los QA agents también validan estos principios al revisar el diff.

## Principios

### 1. YAGNI estricto

Implementar exactamente lo que el brief pide. Nada más.

**No agregar:**
- Features no pedidas ("aprovecho que estoy aquí y agrego X")
- Validaciones para casos que no pueden ocurrir — confiar en código interno; validar solo en boundaries (input de usuario, APIs externas)
- Error handling defensivo "por si acaso"
- Abstracciones especulativas (helpers, factories, interfaces) — esperar a 3 ocurrencias antes de abstraer
- Flexibilidad no solicitada (parámetros opcionales, configurabilidad, feature flags) — agregar solo cuando exista el caso de uso real
- Comentarios explicativos de QUÉ hace el código (los nombres ya lo dicen) — solo POR QUÉ cuando sea no obvio

**Self-check antes de commitear:**
> "¿Un senior llamaría a esto sobre-ingeniería?"

Si la respuesta es "tal vez", borra y vuelve a lo mínimo.

### 2. Cambios quirúrgicos

Tocar solo lo que el brief requiere. El diff debe ser mínimo y trazable.

**No hacer:**
- Refactorizar código no relacionado dentro de un PR de feature (renames, reorganización, cleanup colateral)
- Cambiar el estilo de código existente para que coincida con tu preferencia — coincidir con el estilo del archivo
- Tocar archivos solo para "limpiar" — usar el agente `refactor` por separado, en su propio PR
- Mover código de un archivo a otro a menos que el brief lo pida

**Regla de oro:** cada línea del diff debe poder trazarse a una línea específica del brief. Si no puede, sale del PR.

**Excepción legítima:** si una refactorización es necesaria para implementar la feature correctamente, está dentro del scope. Documentarlo en la descripción del PR.

### 3. Asumir explícito

Si el brief tiene ambigüedad, preguntar al orchestrator antes de implementar. No adivinar.

**Cuándo preguntar:**
- El brief permite múltiples interpretaciones razonables
- Una decisión técnica afectaría contratos/APIs definidos por el architect
- El comportamiento esperado en un edge case no está claro
- Una librería/dependencia nueva sería necesaria

**Cómo preguntar:**
1. Pausar la implementación
2. Listar las interpretaciones posibles
3. Pedir confirmación explícita al orchestrator
4. Continuar solo cuando haya respuesta

**Cuándo NO preguntar:**
- Decisiones puramente idiomáticas que cubren las `rules/` del lenguaje
- Detalles de implementación que no afectan contratos ni comportamiento observable

## Cómo se valida

- **Devs:** auto-aplicar durante implementación; mencionar en commit message si hubo decisión ambigua resuelta
- **QA agents:** revisar el diff buscando violaciones (scope creep, abstracciones especulativas, error handling defensivo, refactor colateral)
- **Security reviewer:** fuera de su scope — estos principios no son su responsabilidad

## Qué NO son estos principios

- **No reemplazan TDD** — el código sigue necesitando tests primero
- **No reemplazan self-reflection** — el código sigue necesitando ser idiomático
- **No prohíben refactoring** — solo lo separan en su propio scope/PR
