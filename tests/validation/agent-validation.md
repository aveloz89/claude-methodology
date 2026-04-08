# Agent Validation Prompts

Prompts canónicos para validar que cada agente se comporta correctamente. Los agentes son nondeterminísticos — no se valida output exacto, sino comportamientos esperados.

## Cómo usar

1. Invocar al agente con el prompt canónico
2. Verificar que el output cumple TODOS los "Expected behaviors"
3. Verificar que NO exhibe ningún "Red flag"
4. Documentar resultado en `VALIDATION-LOG.md`
5. Si falla 2+ expected behaviors → investigar y ajustar el prompt del agente

---

## Orchestrator

**Prompt canónico:**
> "Quiero agregar una feature de notificaciones por email cuando un usuario recibe un mensaje nuevo."

**Expected behaviors:**
- [ ] Inicia brainstorming — hace preguntas antes de diseñar
- [ ] Pregunta sobre alcance (¿todos los mensajes o solo ciertos tipos?)
- [ ] Pregunta sobre usuarios/roles
- [ ] NO invoca al architect sin hacer preguntas primero
- [ ] NO empieza a implementar directamente
- [ ] Sugiere persistir estado en .planning/

**Red flags:**
- Salta directo al diseño sin preguntar
- Invoca a un dev antes de tener diseño
- Genera código él mismo

---

## Backend Dev

**Prompt canónico:**
> "Implementa un endpoint POST /api/notifications que reciba { userId: string, message: string, type: 'email' | 'push' } y lo guarde en la tabla notifications. El architect ya definió el schema en .planning/DESIGN.md. Trabaja en el branch feature/notifications."

**Expected behaviors:**
- [ ] Lee CLAUDE.md primero
- [ ] Verifica/crea el branch correcto
- [ ] Busca schemas del architect antes de implementar
- [ ] Sigue TDD: escribe test primero, verifica que falla, luego implementa
- [ ] Usa type hints (Python) o tipos (TypeScript) en la implementación
- [ ] Ejecuta tests con coverage
- [ ] Verifica que el build compila
- [ ] Ejecuta self-reflection contra rules del lenguaje
- [ ] No deja stubs ni TODOs

**Red flags:**
- Implementa sin leer el diseño del architect
- Escribe código de producción antes del test
- Hace commit sin verificar coverage
- Trabaja en main o dev directamente
- Deja `pass`, `NotImplementedError`, o `TODO` en el código

---

## Frontend Dev

**Prompt canónico:**
> "Implementa la página de notificaciones que muestre una lista de notificaciones del usuario. Usa el endpoint GET /api/notifications. El design system está en design-system/myapp/MASTER.md. Trabaja en el branch feature/notifications."

**Expected behaviors:**
- [ ] Lee CLAUDE.md primero
- [ ] Busca el design system antes de elegir estilos
- [ ] Busca schemas/contratos del architect
- [ ] Sigue TDD para componentes
- [ ] No pone lógica de negocio en el componente
- [ ] Maneja estados de loading y error
- [ ] Ejecuta self-reflection contra rules/typescript.md
- [ ] Verifica build y coverage

**Red flags:**
- Elige colores/fonts sin consultar el design system
- Pone lógica de negocio en el componente (cálculos, permisos, validaciones complejas)
- No maneja estados de loading/error
- Implementa sin tests

---

## QA Agent

**Prompt canónico:**
> Revisar un PR que contenga los fixtures de `tests/adversarial/test-qa-detection.md` (Fixture 3: Red flags Python).

**Expected behaviors:**
- [ ] Detecta `import *`
- [ ] Detecta mutable default `l=[]`
- [ ] Detecta `len(l) == 0`
- [ ] Detecta `== None` y `== True`
- [ ] Detecta bare `except: pass`
- [ ] Detecta `os.system()` con string concatenation
- [ ] Detecta `print()` en producción
- [ ] Reporta coverage issues si aplica
- [ ] Marca el PR como "CAMBIOS REQUERIDOS"

**Red flags:**
- Aprueba el PR
- No detecta el mutable default (es el bug más sutil)
- No detecta la inyección de comandos
- Reporta falsos positivos que no son reales

---

## Security Reviewer

**Prompt canónico:**
> Revisar un PR que contenga los fixtures de `tests/adversarial/test-security-detection.md` (Fixture 1: SQL Injection + Fixture 3: Secrets).

**Expected behaviors:**
- [ ] Detecta SQL injection por f-string
- [ ] Detecta SQL injection por concatenación
- [ ] Detecta hardcoded database credentials
- [ ] Detecta hardcoded API key
- [ ] Detecta hardcoded JWT secret
- [ ] Detecta hardcoded AWS secret key
- [ ] Recomienda parameterized queries
- [ ] Recomienda variables de entorno o secrets manager
- [ ] Clasifica severidad (critical/high para injection, high para secrets)

**Red flags:**
- No detecta SQL injection
- No detecta secrets hardcodeados
- Clasifica SQL injection como "low" severity
- Aprueba el PR con vulnerabilidades presentes
