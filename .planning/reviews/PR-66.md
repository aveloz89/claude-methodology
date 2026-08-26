# Review dual pre-push — feature/state-facts-once (Fase 2.6)

**Branch:** feature/state-facts-once · **Base:** dev · **Fecha:** 2026-08-26 · Presupuesto: ~6 min/reviewer

## Origen

En el PR #65 arreglé una contradicción del runbook en un lugar y la dejé viva en otro, a 400 líneas. Las dos frases decidían lo mismo —¿se escribe en `.planning/` después del merge?— **sin compartir una palabra**: "commit propio posterior a la integración" contra "push directo a un branch protegido". El grep del DoD anti-drift cruza términos, no decisiones.

La raíz no era la redacción: era que **el mismo hecho estaba enunciado dos veces**. El usuario eligió el fix estructural entre tres opciones: enunciar una vez y remitir.

## La auditoría primero, el cambio después

Antes de escribir nada, `qa-backend` auditó las 1900 líneas del corpus normativo buscando hechos enunciados en más de un lugar. El resultado acotó el trabajo: **5 casos, 2 ya divergidos**, y el resto del corpus ya usa el patrón correcto —resumen más puntero— con más disciplina de la esperada. No era sistémico.

| # | Hecho | Estado |
|---|---|---|
| 1 | Cuántas excepciones hay a "el dev no pushea" | **Divergido**: `agent-budget` decía "la única situación"; `dev-common` y `pr-workflow`, "dos excepciones" |
| 2 | Qué ofrece la regla de 3 | **Divergido**: dos copias en el mismo runbook a 325 líneas, una con dos opciones y otra con tres |
| 3 | Qué dispara `last_batch=true` | Coincidían, pero dos de las tres copias estaban en el núcleo que se carga siempre |
| 4 | Cómo se pausa | `governance` §9 re-enumeraba los pasos y omitía actualizar `STATE.md` |
| 5 | Qué cuenta como intento de fix de CI | Enunciado una sola vez, pero en el núcleo en vez del runbook |

## Veredictos

**security-reviewer — APROBADO** (1 MEDIUM, 1 LOW, ambos aplicados).

Su MEDIUM fue el más instructivo: **tres líneas debajo de mi fix, en el mismo archivo, sobrevivía la enunciación vieja.** La línea 69 pasó a decir "una de las dos excepciones" y la 72 seguía diciendo "El paso 4 es **la** excepción explícita", en singular definido. La misma clase de drift que este PR elimina, colada en el archivo que este PR modifica.

Su LOW fue sobre la regla misma: el guardrail llegaba dos párrafos después del imperativo, así que quien leyera la primera frase y actuara podía dejar un puntero pelado. Ahora la condición viaja con la instrucción.

Verificó además las tres preguntas de costo que le puse: ninguna remisión debilita un gate, y la del matiz de CI deja el límite **más estricto**, no más débil — lo que bajó al runbook es la cláusula que afloja el conteo, así que quien no abra el runbook escala antes.

**qa-backend — APROBADO** sin bloqueantes.

Verificó cada remisión desde la posición del lector en el momento de urgencia. La de `governance` §9 **mejora** el caso viejo: remite a "Pause / Resume", que vive en `global/CLAUDE.md` y por lo tanto ya está cargado cuando el aviso de contexto dispara — la versión anterior tenía los cuatro pasos completos pero dentro de un rulebook que no se autocarga.

Su sugerencia aplicada: **la regla contra la duplicación tenía duplicación adentro**. El guardrail y el párrafo "Lo que SÍ es correcto" decían lo mismo desde dos ángulos.

## Dos observaciones de proceso, ambas sobre mí

1. **El diff creció mientras qa-backend revisaba.** Apliqué los fixes de security a mitad de su pasada, y casi reporta como bloqueante algo que ese commit ya había cerrado. Es el mismo error de coordinación del PR #65 —lanzar review sobre un árbol que alguien está editando—, con el autor cambiado: ahí era un dev, acá era yo.
2. **La contradicción residual se coló en el propio PR que introduce el paso 3 del DoD**, y la atrapó security, no mi autorrevisión. El DoD nuevo necesita más de una pasada para autoaplicarse con fidelidad.

## Cierre

Veredictos limpios. Los 5 casos de la auditoría cerrados, la regla escrita en el DoD anti-drift, y el DoD del propio cambio corrido antes de pedir review: "dos excepciones" coincide en los cinco lugares, la regla de 3 remite, y los homónimos —la regla de 3 de `refactor.md` y los reintentos del architect— son hechos distintos, correctamente no conflatados.
