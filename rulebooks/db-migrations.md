# DB Migrations

Conocimiento para el lote de DB cuando el trabajo califica como **complejo**. Lo usa `backend-dev`: no hay agente aparte — el schema nace en el mismo contexto de `DESIGN.md` y del schema actual que el lote siguiente va a consumir, así que separarlo en otro agente solo obligaría a reconstruir ese contexto. El orden ("el lote db-complejo va primero, el siguiente consume el schema sin modificarlo") lo garantiza el plan de lotes del `architect`, no un agente distinto.

## Cuándo un lote es db-complejo

El `architect` marca un lote como `db-complejo` en el plan cuando el trabajo de DB incluye alguno de estos puntos. El resto lo trata como cualquier lote de `backend-dev` (ver "Cuándo un lote es DB complejo" en `rulebooks/orchestrator-runbook.md`):

- Migraciones con backfill de datos (script de transformación)
- Cambio de tipo de columna con datos existentes (`varchar → text`, `int → bigint`, JSON → columnas tipadas)
- Particionamiento o sharding
- Migración de datos entre tablas (split/merge)
- Estrategia zero-downtime (expand-contract)
- Optimización de queries lentas (EXPLAIN, índices compuestos, materialización)
- Constraints nuevos sobre datos existentes (`NOT NULL` en columna con NULLs)
- Migraciones que afecten >1M de filas en producción
- Schema con relaciones complejas, herencia, polimorfismo, requisitos de performance específicos

Si al implementar un lote que no fue marcado `db-complejo` te encuentras con alguno de estos puntos, no sigas: escala al orchestrator para que el `architect` reordene el plan (puede necesitar mover la migración a su propio lote, antes de los que consumen el schema).

## División de schemas con el architect

En una feature hay dos tipos de schemas:

- Schema de validación (Zod, Pydantic, structs con tags) — contrato HTTP, valida input, genera tipos compartidos. Lo escribe el `architect`.
- Schema de DB (Drizzle, Prisma, SQLAlchemy models, migraciones SQL) — tablas, columnas, FK, índices, relaciones. Lo escribes tú en el path canónico del proyecto, en el lote `db-complejo`.

El lote que consume tu schema importa ambos: el de validación para sus endpoints, el de DB para sus queries. Si el schema de validación del `architect` no refleja una restricción real de DB (ej: declaró `string` pero la DB tiene `varchar(50)` con CHECK), escala al orchestrator para que el `architect` lo alinee — no corrijas el schema de validación tú.

## Principios de migración

1. Migraciones reversibles siempre: toda migración tiene `up` y `down`. Si genuinamente no es reversible (ej: drop de columna con datos no recuperables), documenta la justificación en el commit y agrega un paso de backup previo.
2. Idempotencia donde aplique: `CREATE TABLE IF NOT EXISTS`, `CREATE INDEX IF NOT EXISTS`, `ON CONFLICT DO NOTHING/UPDATE`. Una migración idempotente puede volver a correr sin romper.
3. Transacciones para migraciones de múltiples writes: `BEGIN; ... COMMIT;` envolvente, salvo que la migración use operaciones que no soportan transacción (ej: `CREATE INDEX CONCURRENTLY` en Postgres); en ese caso, documéntalo.
4. Índices con propósito: uno por cada query frecuente conocida o anticipada por el diseño. Nada de índices "por si acaso": ocupan espacio y ralentizan los writes.
5. Data integrity a nivel DB: FK con `ON DELETE` explícito (CASCADE/RESTRICT/SET NULL según el caso), `NOT NULL` cuando aplique, `UNIQUE` para invariantes de negocio, `CHECK` para reglas que la app no debe violar.
6. No tocas `docker-compose.yml`: documenta los requisitos del servicio de DB en `DESIGN.md` (versión de engine, extensiones, env vars, healthcheck, volumes); el lote de infraestructura los aplica.
7. Normalización pragmática: 3NF por defecto, desnormaliza solo con justificación de performance documentada en `ARCHITECTURE.md` (ver "Actualizar `.planning/ARCHITECTURE.md`" abajo).
8. Desviación de índice: si el `architect` propuso un índice simple pero la query real necesita un índice compuesto o parcial, ajústalo y documenta la razón en `ARCHITECTURE.md`.
9. Nunca corras la migración contra producción desde el lote: el lote termina en la DB de test/CI; aplicarla en producción es responsabilidad del pipeline de deploy del proyecto, no tuya.
10. Nunca pongas secrets ni credenciales en migraciones ni seeds: usa env vars o el mecanismo de secrets del proyecto — un valor hardcodeado queda en el historial de git para siempre.

## Expand-contract (zero-downtime)

Para cambios que rompen compatibilidad en producción (renombrar/borrar columna, cambiar tipo) sin downtime:

1. Expand: agrega la columna/tabla nueva sin tocar la vieja. Deploy.
2. Migrate: backfilla y hace doble escritura (o el código lee de la nueva, escribe en ambas) hasta que todo el tráfico use el path nuevo.
3. Contract: una vez verificado que nada lee la columna vieja, otro lote la elimina.

No colapses las tres fases en una migración: cada una es un despliegue verificable por separado.

## EXPLAIN y queries optimizadas

Antes de declarar una query optimizada, corre `EXPLAIN` (o `EXPLAIN ANALYZE`) contra un dataset representativo y verifica que usa el índice esperado, no un full scan. Documenta el plan de query resultante en el commit cuando el cambio es justamente agregar o cambiar un índice — es la evidencia de que resolvió el problema, no una afirmación sin verificar.

## Testing de DB y coverage

Qué se testea, con coverage:

- Migraciones up/down/up: aplicar, revertir, re-aplicar. El estado final debe ser equivalente al inicial tras el down, y al post-up tras el up. Obligatorio salvo migración declarada no reversible.
- Constraints: insertar datos que violen FK/UNIQUE/NOT NULL/CHECK debe fallar con el error esperado; datos válidos deben pasar.
- Cascadas: `ON DELETE CASCADE` borra los hijos; `RESTRICT` falla si hay hijos. Verifica el comportamiento declarado.
- Queries optimizadas: con datasets sintéticos (ej: 10K filas), verifica con `EXPLAIN` que el plan usa el índice y que el tiempo queda bajo un umbral razonable.
- Backfill: con dataset de prueba que cubra los casos límite (NULLs, valores extremos, datos malformados preexistentes), verifica que produce el resultado esperado.

Qué NO se testea con coverage: migraciones triviales sin transformación (`CREATE TABLE` simple sin backfill), seeds de desarrollo, definiciones puras de schema sin lógica.

Coverage mínimo: 80% de branches sobre archivos del diff con lógica de migración o transformación. Definiciones puras de schema y migraciones triviales quedan fuera del cálculo (alineado con `CLAUDE.md` raíz).

Mocks: no mockees la DB. Los tests corren contra una DB de test real (Postgres en Docker, SQLite en memoria si el proyecto lo soporta). Si el proyecto no tiene DB de test configurada, escala al orchestrator antes de improvisar mocks.

## Idiomática SQL (migraciones SQL puras, sin ORM)

- Sintaxis válida según el dialecto del proyecto (PostgreSQL, MySQL, SQLite).
- Idempotencia: `CREATE TABLE IF NOT EXISTS`, `CREATE INDEX IF NOT EXISTS`, `CREATE OR REPLACE FUNCTION`, `INSERT ... ON CONFLICT`.
- Transacción envolvente en migraciones que tocan más de una tabla o hacen múltiples writes.
- Down migration o estrategia de rollback documentada.
- Naming explícito de constraints (`CONSTRAINT fk_orders_user_id`), para poder dropearlos individualmente después.
- `CONCURRENTLY` para crear índices en tablas grandes en producción (Postgres); no se puede usar dentro de una transacción.

Si encuentras un patrón antiguo en el codebase (índices sin naming explícito, migraciones sin transacción) y tu cambio no lo toca, no lo arregles — es scope del agente `refactor` o un PR aparte.

## Documentar para el lote siguiente

En la sección de `DESIGN.md` de tu lote, deja explícito para el lote que va a consumir tu schema:

- Path al schema generado/modificado.
- Cambios en interfaces que ya se consumían.
- Índices nuevos que cambian el query plan esperado.
- Requisitos de `docker-compose.yml` que aplicará el lote de infraestructura (versión de engine, extensiones como `pg_trgm`/`uuid-ossp`/`pgvector`, env vars, healthcheck, volumes).

## Actualizar `.planning/ARCHITECTURE.md` (sección DB)

Después de un lote `db-complejo`, actualiza la sección DB de `ARCHITECTURE.md` con decisiones que aplican a futuras features (no a la actual): stack confirmado (engine + versión, ORM, migration tool), extensiones instaladas, convenciones de naming, patrones adoptados (soft vs hard delete, timestamps automáticos, UUIDs vs serials), decisiones de partitioning/sharding/replicación, estrategias zero-downtime adoptadas. El resto del archivo lo mantiene el `architect`; toca solo la sección DB.

Lo que NO va ahí (es específico de la feature actual, vive en `DESIGN.md`): tablas concretas creadas en este PR, la migración específica, índices puntuales.

## Estado de la DB de test en HANDOFF

Si el budget se agota a mitad de una migración (schema cambiado pero backfill sin terminar), el fallback de budget agotado de `rulebooks/dev-common.md` aplica igual, con un dato extra en `.planning/HANDOFF.md`: el estado exacto de la DB de test.

```
Estado de DB de test: <up | down | intermedio: descripción>
```

Sin ese dato, la siguiente invocación puede aplicar una migración sobre un estado que no es el que asume, y corromper el branch.
