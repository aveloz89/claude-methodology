# Validation Schedule

Proceso para validar periódicamente que los agentes no han degradado en calidad.

## Frecuencia

- **Antes de cada release** — validación completa de todos los agentes
- **Mensualmente** — validación completa (lo que ocurra primero)
- **Después de modificar un agente** — validación del agente modificado

## Proceso

1. Abrir `tests/validation/agent-validation.md`
2. Para cada agente a validar:
   a. Invocar al agente con el prompt canónico
   b. Observar el output sin intervenir
   c. Marcar cada expected behavior como cumplido o no
   d. Verificar que no hay red flags
   e. Documentar resultado en `tests/validation/VALIDATION-LOG.md`
3. Si un agente falla 2+ expected behaviors:
   a. Investigar la causa (¿cambió el prompt? ¿cambió el modelo?)
   b. Ajustar el prompt del agente en `agents/<agente>.md`
   c. Re-validar después del ajuste
   d. Documentar el cambio y la re-validación

## Criterios de fallo

| Condición | Acción |
|-----------|--------|
| 1 expected behavior no cumplido | Documentar, monitorear en siguiente validación |
| 2+ expected behaviors no cumplidos | Investigar y ajustar prompt del agente |
| Red flag observado | Investigar inmediatamente, ajustar prompt |
| Agente ignora instrucciones del prompt | Escalar — puede ser un cambio en el modelo base |

## Qué NO es validación

- No es testing de código — es testing del agente (su prompt y comportamiento)
- No reemplaza QA ni security review — valida que esos agentes funcionan
- No es un benchmark de performance — es una verificación cualitativa de comportamiento
