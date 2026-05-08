# Implementation Principles

Principios de disciplina que los agentes dev aplican DURANTE la implementación. Complementan TDD y self-reflection:

- **TDD** asegura que el código funciona
- **Self-reflection** asegura que el código es idiomático
- **Implementation principles** aseguran que el scope es correcto

## Cuándo aplican

Durante toda la implementación — desde que el dev recibe el brief hasta que abre el PR. Los QA agents también validan estos principios al revisar el diff.

## Brief vs principios

**El brief manda en decisiones de scope y features**: si el brief pide algo que parece "innecesario" desde YAGNI (un feature flag para un solo caso, configurabilidad sin segundo caso de uso, una abstracción específica), el dev lo implementa sin push back. El brief refleja contexto que el dev no tiene.

**Los principios mandan en decisiones de calidad de código**: stubs, TODOs, error handling silencioso, validación faltante en boundaries, comentarios mentirosos. Aquí el brief no puede override. Si el brief explícitamente pide violarlos ("deja un TODO aquí"), el dev lo escala al orchestrator antes de implementar.

## Principios

### 1. YAGNI estricto

Implementar exactamente lo que el brief pide. Nada más.

**No agregar:**
- Features no pedidas ("aprovecho que estoy aquí y agrego X")
- Validaciones para casos que no pueden ocurrir — confiar en código interno; validar solo en boundaries (ver definición abajo)
- Error handling defensivo "por si acaso"
- Abstracciones especulativas (helpers, factories, interfaces) — esperar a 3 ocurrencias **con la misma forma** antes de abstraer. Tres funciones que casualmente se parecen pero pueden divergir no son DRY, son acoplamiento accidental.
- Flexibilidad no solicitada (parámetros opcionales, configurabilidad, feature flags) — agregar solo cuando exista el caso de uso real **o el brief lo pida explícitamente**
- Comentarios de QUÉ hace el código (los nombres ya lo dicen). **Excepción:** código intrínsecamente denso — regex complejos, fórmulas matemáticas, workarounds documentados con link al issue/bug upstream.

**Qué cuenta como "boundary" para validación:**
- Input HTTP de usuario (body, query params, headers)
- Respuestas de APIs externas / servicios de terceros
- Lectura de archivos, env vars, configuración
- Resultados de queries a DB en el punto de deserialización
- Mensajes recibidos de colas, webhooks, eventos externos

**Qué NO cuenta como boundary** (no validar aquí):
- Llamadas entre funciones del mismo módulo
- Llamadas entre módulos del mismo servicio que comparten tipos
- Datos que ya pasaron por un boundary y están tipados

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
- El brief pide algo que choca con un principio de calidad (ver "Brief vs principios")

**Cómo preguntar:**
1. Pausar la implementación
2. Listar las interpretaciones posibles (con pros/cons si ayuda)
3. Pedir confirmación explícita al orchestrator
4. Continuar solo cuando haya respuesta

**Cuándo NO preguntar (decidir solo):**
- Decisiones puramente idiomáticas que cubren las `rules/` del lenguaje
- Detalles de implementación interna que no afectan contratos, comportamiento observable, ni performance medible. **Nota:** la duda entre "implementación abstracta vs directa" se resuelve por YAGNI (siempre directa hasta tener 3 ocurrencias **a menos que el brief pida abstracción explícitamente**), no preguntando.

### 4. No stubs ni TODOs en código mergeado

Todo lo que entra al PR debe estar terminado. Código placeholder es bloqueante para merge.

**No dejar:**
- `// TODO`, `// FIXME`, `// HACK` sin issue/ticket asociado
- Funciones que retornan `null` / valor vacío "para llenar después"
- Endpoints que devuelven 501 Not Implemented
- Tests con `xit` / `it.skip` / `pytest.mark.skip` sin razón documentada y ticket
- Mocks "temporales" en código de producción
- Datos hardcodeados con comentario "cambiar antes de prod"

**Lo que SÍ debe estar (no cuenta como scope creep ni especulativo):**
- Logs estructurados en boundaries y en paths de error (con `logger.info`, `pino`, `structlog`, etc. — **no `console.log` ni `print()`**, esos los bloquea self-reflection)
- Error handling explícito de fallos esperados (network, DB, validación de input). Defensivo "por si acaso" sigue prohibido por YAGNI; explícito de fallos reales es scope siempre.

**Excepciones permitidas (con condiciones):**
- `TODO` con link a issue específico, cuando la dependencia es externa al PR actual (ej: feature toggle pendiente de aprobar en otra capa). Formato: `// TODO(#123): descripción breve`
- Tests skipeados con razón explícita Y ticket: `it.skip('flaky por CI lento, ver #456', ...)`

**Self-check antes de commitear:**
> "¿Si este PR mergeara y nunca volviera a tocarse, todo seguiría funcionando correctamente en producción?"

Si la respuesta es "no" o "depende", el PR no está listo.

## Cómo se valida

**Devs (auto-aplicación durante implementación):**
- Aplicar los 4 principios al escribir código, no al final
- Correr los self-checks antes de cada commit

**Devs (al abrir PR):**
- Si hubo decisión ambigua resuelta con orchestrator durante el PR, mencionarla en la descripción del PR o en commit message. Formato libre, basta con que quede rastro de qué se decidió y por qué.

**QA agents:**
- Revisar el diff buscando violaciones: scope creep, abstracciones especulativas, error handling defensivo, refactor colateral, stubs/TODOs sin ticket, validación faltante en boundaries.

**Security reviewer:**
- Reportar violaciones **solo cuando tienen implicación de seguridad**: catch silencioso que oculta errores, validación faltante en boundary que recibe input de usuario, secrets hardcodeados disfrazados de "TODO cambiar antes de prod", logs ausentes en flujos de auth/pago. El resto queda en scope de QA.

## Qué NO son estos principios

- **No reemplazan TDD** — el código sigue necesitando tests primero
- **No reemplazan self-reflection** — el código sigue necesitando ser idiomático
- **No prohíben refactoring** — solo lo separan en su propio scope/PR
- **No override del brief en decisiones de scope** — ver sección "Brief vs principios" arriba
