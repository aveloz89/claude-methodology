# Review dual pre-push — feature/close-process-gaps (Fase 2.6)

**Branch:** feature/close-process-gaps · **Base:** dev · **Fecha:** 2026-08-26 · **Diez rondas de review**

## Qué cierra

Los dos pendientes de proceso que habían quedado en cola, más lo que apareció al escribirlos:

1. **Paso 4 del DoD anti-drift** — si el PR introduce una regla, releé el diff aplicándola.
2. **Instrucción al agente `refactor`** — la evidencia adjunta a un issue es hipótesis, no hecho.
3. **Enforcement del paso 4** — el reviewer aplica la regla al diff, en vez de auditar que el autor la releyó.
4. **Regla del árbol quieto** — mientras haya un reviewer corriendo, el árbol no se mueve.
5. **Paso 3 extendido** — enunciar una vez y remitir vale también para afirmaciones sobre incidentes pasados.

## Diez rondas, y el patrón que las explica

Cada ronda encontró que el PR violaba alguna de las reglas que estaba escribiendo. Pero el patrón real, visible recién al final, es más específico: **las reglas se sostuvieron; lo que falló fue la prosa de respaldo.**

| Ronda | Qué encontró |
|---|---|
| 1 | La cláusula de enforcement no era ejecutable en Fase 2.6: pedía verificar un artefacto en superficies que no existen cuando el QA corre |
| 1 | La instrucción al `refactor` vivía en Modo Scan, que por contrato no modifica nada; el borrado ocurre en Modo Refactor |
| 2 | Una cita falsa dentro del paso que exige verificar: el descriptor del absoluto es del #64, no del #65 |
| 3 | La cláusula fail-closed no cubría el caso que la motivó — el input corre, da verde, y nunca llega a la rama |
| 3 | "Las cuatro las atrapó un reviewer" era falso para el #65, donde lo encontraron los dos |
| 4 | La tercera salida afirmaba que un verde prueba que el input no llega: falso para un guard redundante, que es el ejemplo que la propia frase citaba |
| 5 | Una oración huérfana del artefacto eliminado, sin antecedente, contradiciendo al párrafo doce palabras antes |
| 6 | El conteo de actores del caso #62: dos corrieron la prueba ciega, no tres. El tercero —quien escribió el issue— no corrió nada |
| 7 | Tres conteos sin respaldo: "tres experimentos entre los dos", "pasó tres veces en #65, #66 y #67" (el #67 fue otro PR), y la referencia cruzada rota por mi propia renumeración |

De las nueve entradas, **seis son conteos, citas o atribuciones parafraseadas de memoria**. Ninguna es un error en la regla.

## El diagnóstico final lo dio qa-backend, y es mejor que el mío

Yo propuse "escribir menos narrativa justificativa". Su corrección:

> El problema no es la cantidad de prosa sino **reconstruir incidentes pasados en vez de remitir** a donde ya están escritos. Si la línea remitiera a `LEARNINGS.md`, esta ronda no habría tenido nada que verificar en ese párrafo, porque no habría nada parafraseado que pudiera divergir de la fuente.

O sea: **el paso 3 que este mismo corpus ya tenía —enunciar una vez, remitir— aplicaba al caso que más fallaba, y nadie lo estaba usando ahí.** El último commit lo extiende explícitamente a las afirmaciones sobre incidentes pasados, y reemplaza la narración de la línea 161 por una remisión.

## Veredictos

**security-reviewer** — bloqueó en las rondas 1, 2, 3 y 5; **aprobó en la 6**. Su aporte más valioso no fue un hallazgo sino una respuesta de alcance que le pedí explícitamente: identificó que la cláusula de enforcement tenía dos problemas estructurales —el hallazgo caía sobre el dev cuando la falla era del orchestrator, y el artefacto era autodeclarado— y recomendó separar eso de la iteración de redacción. Esa observación llevó a la decisión del usuario que reescribió el enforcement entero.

**qa-backend** — bloqueó en las rondas 1, 6 y 7; **aprobó en la última**. Encontró el defecto del conteo de actores aplicando la regla que el diff introduce, que es literalmente para lo que existe. Y marcó tres veces que el árbol se movía bajo sus pies, lo que produjo la quinta regla de este PR.

## Un defecto lo encontré yo

El cierre de la sección decía "Este paso no es opcional ni cosmético", en singular: escrito cuando el DoD tenía dos pasos, quedó leyéndose como si solo el último fuera obligatorio al agregar el tercero y el cuarto. Lo encontré aplicando el paso 4 a mi propio diff — el primero de este PR que no vino de un reviewer, y la única evidencia de que el paso hace lo que dice.

## Sobre el último commit

Aplica la sugerencia de qa-backend y no se re-revisó. La razón: **reduce superficie de afirmación en vez de agregarla** — reemplaza prosa parafraseada por punteros a los registros. Queda dicho acá para que la decisión sea auditable y no un olvido.
