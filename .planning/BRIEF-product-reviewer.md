## Brief: product-reviewer

### Objetivo
Sumar un "par de ojos" de producto que cuestione si una feature vale la pena y deje claro qué esperamos obtener de ella, con criterios de aceptación medibles. El usuario suele llegar con ideas vagas. Tiene que ser liviano, sin volver más complicado el flujo.

### Alcance
- Incluye:
  - Subagente nuevo `agents/product-reviewer.md`: modelo opus (degradable a sonnet), de solo lectura, con contexto limpio.
  - Invocación en el flujo: después de que el orchestrator cierra el brainstorming y escribe `BRIEF.md`, y antes de `ui-ux` y del architect.
  - Activación: solo en proyectos cuyo `CLAUDE.md` declare que es un producto con usuarios reales (una línea, p. ej. `Tipo: producto con usuarios`), y solo en features nuevas. No corre en bug fixes ni cambios técnicos (las mismas condiciones que permiten saltar el brainstorming).
  - `/new-project` pregunta el tipo de proyecto y escribe esa línea.
  - Integración en la skill `orchestrator` (fase y tabla de equipo), el runbook, el README, el marketplace y los tests (lint de frontmatter y referencias).
- NO incluye:
  - Roadmap, backlog, priorización de issues ni PRD largo.
  - Verificación al final del PR contra los criterios de aceptación (descartado; ver abajo).
  - Cambios al brainstorming del orchestrator: sigue igual.

### Usuarios y permisos
Lo invoca el orchestrator. El reporte vuelve al orchestrator, que se lo presenta al usuario. El subagente no habla con el usuario ni edita archivos.

### Flujo principal
1. El orchestrator hace el brainstorming con el usuario y escribe `BRIEF.md`, como hoy.
2. Si el proyecto es un producto con usuarios y la tarea es una feature nueva, invoca `product-reviewer` con el `BRIEF.md` y, si hace falta contexto del producto, el README.
3. `product-reviewer` devuelve un reporte corto:
   - **¿Vale la pena?** Un veredicto entre seguir, reducir alcance y repensar, con 2-3 razones.
   - **Qué esperamos obtener:** el resultado para el usuario en una frase y cómo sabremos que funcionó (métrica o señal observable).
   - **Criterios de aceptación medibles:** los del brief reescritos para que se puedan verificar, más los que falten.
4. El orchestrator le presenta el reporte al usuario con `AskUserQuestion`: incorporar todo, elegir qué incorporar o seguir sin cambios.
5. Lo aceptado se escribe en `BRIEF.md` (secciones nuevas "Resultado esperado" y "Criterios de aceptación"), que usan el architect y QA.

### Reglas de negocio
- **No bloquea nunca.** Aunque el veredicto sea "repensar", decide el usuario.
- Reporte corto: el objetivo es no complicar.
- Proyecto sin la línea de tipo en su `CLAUDE.md` → no corre, y el orchestrator no pregunta.

### Edge cases discutidos
- Repos de tooling o metodología (como este): no tienen la línea, así que nunca se activa.
- Bug fix o cambio técnico en un producto: se salta.
- Opus rate-limited: degradar a sonnet es aceptable.

### Decisiones tomadas
- [D-01] (usuario) No sustituye el brainstorming: funciona como filtro de "vale la pena" y de qué esperamos obtener.
- [D-02] (usuario) No bloquea.
- [D-03] (usuario) Solo en productos con usuarios reales, no en repos como este.
- [D-04] (usuario) Propuesta aprobada: subagente entre el brief y el architect, activado por una línea en el `CLAUDE.md` del proyecto.
- [D-05] (usuario) Siempre preguntar antes que suponer. Si al agente le falta algo que cambia su veredicto, devuelve solo preguntas; el orchestrator se las pasa al usuario y reanuda al agente con las respuestas.

### Descartado explícitamente
- **Skill que entrevista al usuario:** el brainstorming ya cumple esa función. Lo que falta es la mirada independiente, que solo da un contexto limpio.
- **Revisión al final del PR** contra los criterios: una invocación más por feature; el usuario prefiere no complicar.
- **Preguntar en cada brainstorming** si pasar por el PM: se prefirió la activación por configuración.
- Roadmap, backlog y PRD.
