# PR Workflow

Reglas de proceso para crear, reviewear y mergear pull requests. Aplican a TODOS los proyectos.

## 1. Una fase = un PR separado

Cada fase de implementación (refactor, feature nueva, bugfix, doc audit) debe ir en su propio branch + PR. No acumular múltiples fases en un solo branch.

**Por qué:** PRs incrementales son más fáciles de reviewear, revertir y trazar. Un mega-PR con 5 cambios distintos toma 10× más tiempo de review y si algo se rompe es imposible bisectar.

**Cómo aplicar:**
- Al iniciar nueva fase: crear `feature/<descripción-corta>` desde la base correcta (típicamente `dev`)
- Implementar la fase completa con TDD + self-reflection
- Abrir PR al terminar
- NO empezar la siguiente fase en el mismo branch — esperar merge primero

**Excepción legítima:** un refactor pequeño necesario para implementar la feature correctamente está dentro del scope. Documentarlo en el PR body.

## 2. Review obligatorio antes de mergear

Después de crear cada PR, lanzar **security-reviewer + qa** (qa-frontend y/o qa-backend según lo que toque) **en paralelo automáticamente, sin pedir confirmación al usuario**.

**Cuándo lanzar:**
- En el mismo turn donde creo el PR, lanzo los agents en paralelo (single message, multiple Agent calls)
- Si el siguiente paso natural es rebuildear dev (Docker, etc.), lanzar el rebuild en paralelo con los reviewers — son independientes
- Reportar findings al usuario después

**Si hay blockers:**
- Fixearlos en el MISMO branch/PR (no abrir uno nuevo)
- Re-correr el agent relevante para validar el fix
- Continuar solo cuando todo verde

**Sugerencias no bloqueantes: aplicarlas en el mismo PR antes de pedir merge.**
Cuando un reviewer marca sugerencias (no bloqueantes) que son baratas, sin riesgo y trazables al scope del PR, aplicarlas en el MISMO branch antes de informar "PR listo para tu review" — no diferirlas ni solo anotarlas. Las que cambien comportamiento, requieran decisión de diseño, o sean scope de otra fase, NO se aplican: se anotan como issue o handoff en `.planning/STATE.md`. Después de aplicar, re-correr solo el reviewer que las marcó (o los tests si es cambio menor).

**Por qué:** el patrón "aplicar sugerencias en el mismo PR" apareció en 4 PRs consecutivos como decisión manual del usuario. Formalizarlo evita el ida-y-vuelta de pedir permiso para cada mejora obvia. El usuario sigue siendo el checkpoint del **merge** (regla 3), no de cada pulido.

### Verificación E2E real obligatoria en PRs de frontend

Antes de aprobar el merge de un PR que toca UI (componentes, páginas, flujos de usuario), **ejecutar el flujo real en un navegador contra el backend levantado** — no basta con tests unitarios ni con verificación por `curl`.

**Por qué es obligatorio:** los tests de frontend mockean `fetch` y corren en jsdom, que NO renderiza CSS, NO aplica `@media`/`@page`, NO ejecuta las reglas nativas de `<dialog>`/top-layer, y NO negocia `Content-Type` real con el servidor. La "verificación en vivo por `curl`" ejercita la API pero nunca la UI. En una sola fase (catálogos) se escaparon a review 3 bugs que ningún test veía: un modal que no cerraba en desktop (CSS sin scope a `[open]`), archivado completamente roto (`Content-Type: application/json` en POST sin body → Fastify lo rechazaba), y un falso positivo de test que afirmaba renderizar un botón que en el DOM real no estaba.

**Cómo aplicar:**
- **Preferente:** invocar `e2e-runner` sobre el flujo del PR (crea/corre tests Playwright contra los servicios en Docker). Bloqueante si falla.
- **Mínimo:** manejar el flujo en un navegador real (extensión de browser o Playwright manual) contra `docker compose up` — ejercitar happy path + las mutaciones (crear, editar, archivar/deshacer) y confirmar en el DOM real, no solo en screenshot.
- **Distinguir bug de código vs bundle stale:** si algo no se ve/comporta como el código fuente dice, reiniciar el contenedor de frontend (HMR + service worker de PWA pueden servir módulos viejos tras muchos pushes) y re-verificar ANTES de escalar al dev. No mandar a "arreglar" código correcto.
- Restaurar datos de seed (`db:seed`) si la verificación ensució el entorno de dev.

**Qué NO requiere E2E real:** PRs sin superficie de UI (backend puro, migraciones, docs, config). Ahí basta con tests + la verificación en vivo por `curl`/API que ya hacen los devs.

### Checklist obligatorio para security-reviewer

El security-reviewer DEBE verificar estos puntos además de OWASP Top 10:

1. **Rate limiting** — Toda ruta de mutación (POST/PATCH/PUT/DELETE) debe tener `config: { rateLimit }` explícito. Si no, es bloqueante.
2. **Shell injection** — Si hay `execSync`/`exec` con interpolación de strings, flag como bloqueante. Usar `execFileSync` con array de args.
3. **Prototype pollution** — En lookups con `obj[key]`, verificar `Object.hasOwn()`.
4. **Reflected input** — Mensajes de error no deben incluir input del usuario sin sanitizar.

**Por qué este checklist:** CodeQL atrapó missing rate limiting en rutas que el security-reviewer no detectó porque solo buscaba XSS/injection/auth, no infraestructura.

## 3. NUNCA mergear sin aprobación explícita del usuario

Aunque CI esté verde y los reviewers aprueben sin blockers, **no ejecutar `gh pr merge` hasta que el usuario diga "mergea" o equivalente**.

**Por qué:** el usuario quiere ser el checkpoint final. Cada merge es una decisión que afecta la rama destino — debe ser explícita, no inferida del estado de CI/reviews.

**Cómo aplicar:**
- Cuando CI pasa y reviewers aprueban, informar al usuario "PR listo para tu review" + link
- Esperar respuesta explícita antes de mergear
- Si el usuario dice "mergea X y Y", validar uno a la vez (cada merge invalida los otros PRs por branch protection)

## 4. NUNCA mergear con CI en rojo

Si algún CI workflow falla (lint, test, security scan, codeql, semgrep, dependency-audit), NO mergear — aunque el finding parezca preexistente o un falso positivo.

**Por qué:** un blocker es un blocker. Mergear con CI rojo argumentando "es preexistente" rompe el contrato del status check y normaliza fallos. Si es falso positivo legítimo, agregar la supresión correspondiente y esperar que CI pase.

**Cómo aplicar:**
1. Verificar que TODOS los workflows pasaron antes de `gh pr merge`
2. Si alguno falla, arreglarlo primero — no usar `--admin` para saltarlo
3. Falso positivo → suprimir formalmente + re-correr CI
4. Solo después de todo verde, mergear (con aprobación del usuario per regla 3)

## Trade-offs aceptados

- **PRs pequeños generan más reviews.** Vale la pena: cada review es rápido (~5 min) y atrapa errores antes de que el usuario los vea.
- **Auto-merge no se usa.** Branch protection requires up-to-date branches; cada merge invalida los demás. Loop manual de `update-branch + CI wait + merge` por PR.
- **El usuario es el checkpoint final.** Significa fricción mínima entre "listo" y "merged", pero garantiza que nada se mergea sin su mirada.
