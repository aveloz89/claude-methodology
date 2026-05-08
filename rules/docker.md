---
paths:
  - "**/Dockerfile"
  - "**/Dockerfile.*"
  - "**/*.Dockerfile"
  - "**/docker-compose.yml"
  - "**/docker-compose.*.yml"
  - "**/compose.yml"
  - "**/compose.*.yml"
  - "**/.dockerignore"
agents:
  - backend-dev
  - frontend-dev
  - qa-backend
  - qa-frontend
---

# Docker Review Rules

Reglas idiomáticas para Dockerfiles y archivos de compose. Las leen `backend-dev` / `frontend-dev` al implementar cambios de infraestructura y `qa-backend` / `qa-frontend` al revisar el diff.

## Responsabilidades por agente

- **`architect`** — decide **qué** servicios existen, **qué** env vars existen y para qué, y escribe `.env.example` con placeholders. No escribe Dockerfiles ni compose.
- **`backend-dev` / `frontend-dev`** — implementan Dockerfiles y modifican compose siguiendo estas reglas. Agregan al compose las env vars que el architect ya declaró en `.env.example`.
- **`qa-backend` / `qa-frontend`** — validan que los Dockerfiles y compose del diff cumplan estas reglas.

## Imágenes base

- **Pinear versiones** — Usar tags específicos (`node:22-alpine`, `python:3.12-slim`), nunca `latest`. `latest` rompe builds reproducibles.
- **Preferir variantes minimales** — `alpine`, `slim`, `distroless` cuando sea posible, salvo que el runtime requiera glibc o features de Debian.
- **No cambiar la imagen base sin razón documentada** — Pasar de `node:22` a `node:24` es breaking; mencionar explícitamente en el PR.

## Multi-stage builds

- **Separar build de runtime** en imágenes de producción — La imagen final no debe contener compilador, dev dependencies ni herramientas de build.
- **Nombrar stages con `AS <nombre>`** (`AS builder`, `AS runtime`) para claridad y trazabilidad.
- **`COPY --from=<stage>`** explícito, copiar solo lo necesario (no `COPY --from=builder /app /app`).

## Seguridad

- **`USER nonroot` en producción** — Crear un usuario sin privilegios y usarlo antes del `CMD`/`ENTRYPOINT`. Nunca correr como root en runtime.
  - Node: `USER node` (ya viene en la imagen oficial).
  - Python/Go/otros: crear con `RUN adduser --disabled-password --gecos "" --uid 1001 appuser`.
  - Excepción: contenedores de **dev** pueden necesitar root para hot reload con bind mounts en Linux (problema de UID mismatch). Documentar con comentario.
- **`COPY --chown=<user>:<group>`** para mantener ownership correcto al copiar al stage final.
- **No hardcodear secrets** — Nada de `ENV API_KEY=...`, ni copiar `.env` a la imagen. Pasar por `--secret`, env vars del runtime, o secret managers.
- **No instalar herramientas de debug en producción** — `curl`, `wget`, `bash` solo en imagen de desarrollo. (Para healthchecks, ver sección "Healthchecks" abajo — hay alternativas que no requieren `wget`/`curl`.)
- **`apt-get`/`apk` con `--no-install-recommends`** y limpiar caches (`rm -rf /var/lib/apt/lists/*`) en la misma capa.

## Optimización de capas

- **`COPY package*.json ./` antes que `COPY . .`** — Para que `npm install` se cachee si solo cambia código de aplicación.
- **Order matters** — Las capas que cambian menos van primero (deps), las que cambian más al final (código).
- **Combinar `RUN` relacionados con `&&`** — Reduce capas y permite limpieza en la misma operación.
- **`.dockerignore` siempre presente** — Excluir `node_modules`, `.git`, `.env`, `dist/`, `coverage/`, `__pycache__/`, archivos de IDE. Builds más rápidos y evita filtrar secrets.

## Compose (`docker-compose.yml`)

- **No incluir el campo `version:`** — Está obsoleto en Docker Compose v2 (genera warning `the attribute 'version' is obsolete`). Omitirlo directamente. Templates viejos lo siguen incluyendo; eliminarlo si aparece.
- **Solo exponer puertos necesarios** — `expose:` para comunicación interna entre servicios; `ports:` solo cuando el host necesita acceso (reverse proxy, debug local de DB).
- **`depends_on` con `condition: service_healthy`** cuando hay dependencias de arranque (DB lista antes que API). `service_started` no garantiza que esté listo.
- **`restart: unless-stopped`** en producción — `always` puede crear loops si el servicio falla al arrancar.
- **`volumes:` con propósito explícito**:
  - Bind mounts (`./src:/app/src`) → código en desarrollo (hot reload).
  - Named volumes (`db-data:/var/lib/postgresql/data`) → datos persistentes.
  - tmpfs → temporales en memoria.
- **`network_mode: host` solo en casos legítimos** — agentes de monitoreo que necesitan ver la red del host (Prometheus node_exporter, Datadog/NewRelic agents), VPN, mDNS/Bonjour. NO usarlo "para ahorrar config de puertos" — pierde el aislamiento de red.

## Healthchecks

Cada servicio crítico (API, DB, queue, cache) debe tener healthcheck. Sin healthcheck, `depends_on: condition: service_healthy` no funciona.

**Que verifique respuesta real, no solo proceso vivo.** `pgrep node` no sirve — el proceso puede estar corriendo pero el servicio caído.

**Por defecto, usar el runtime del lenguaje** (sin instalar `wget`/`curl` solo para healthcheck — choca con la regla "no debug tools en prod"):

```yaml
services:
  api:
    healthcheck:
      # Node 18+: fetch global disponible
      test: ["CMD", "node", "-e", "fetch('http://localhost:3000/health').then(r => process.exit(r.ok ? 0 : 1))"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 10s
  api-python:
    healthcheck:
      test: ["CMD", "python", "-c", "import urllib.request; urllib.request.urlopen('http://localhost:8000/health')"]
      interval: 30s
      timeout: 5s
      retries: 3
  db:
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U $${POSTGRES_USER}"]
      interval: 10s
      timeout: 3s
      retries: 5
```

**Alternativa:** si el runtime no permite hacer requests fácilmente, instalar **solo** `wget` (~500KB) y usarlo:

```yaml
test: ["CMD", "wget", "--spider", "-q", "http://localhost:3000/health"]
```

## Hot reload en desarrollo

El compose de desarrollo debe permitir editar código sin rebuild. Por lenguaje:

| Lenguaje / Framework | Comando recomendado |
|---|---|
| Node + TypeScript | `tsx watch src/main.ts`, `nodemon --exec tsx src/main.ts` |
| Node + JS plano | `node --watch src/main.js` (Node 20+), `nodemon` |
| Vite (frontend) | `vite dev` (HMR built-in) |
| Next.js | `next dev` (HMR built-in) |
| Python + FastAPI | `uvicorn app.main:app --reload --host 0.0.0.0` |
| Python + Flask | `flask --app app run --debug --host 0.0.0.0` |
| Python + Django | `python manage.py runserver 0.0.0.0:8000` |
| Go | `air` (requiere `.air.toml`) |
| Rust | `cargo watch -x run` |
| .NET | `dotnet watch run` |

Patrón típico:

```yaml
services:
  api:
    build: .
    volumes:
      - ./src:/app/src      # bind mount para código fuente
      - /app/node_modules   # volumen anónimo: evita que el host pise deps del container
    command: pnpm dev       # script con watch mode internamente
```

Si el servicio no soporta hot reload, documentarlo en el README o comentario del compose para que el dev sepa que cada cambio requiere `docker compose restart <servicio>` o rebuild.

## Logging

Servicios deben loggear a **stdout/stderr**, no a archivos dentro del container. Docker captura stdout y lo expone vía `docker logs` o el driver de logging configurado.

```javascript
// Mal — archivos dentro del container se pierden al recrearlo
fs.appendFileSync('/app/logs/app.log', message)

// Bien — logger estructurado escribe a stdout, Docker lo captura
logger.info({ event: 'request', path: req.path })
```

Usar la librería del stack (Pino en Node, structlog en Python, zap en Go, slog en Go 1.21+) configurada con output a stdout. **No usar `console.log`/`print()` directos** — `rules/self-reflection.md` los bloquea como debug residual; el logger estructurado es lo que va a stdout.

## Variables de entorno

- **Toda variable nueva va a `.env.example`** con valor de ejemplo o placeholder explicativo (no en `.env`, que está gitignored). Esto lo escribe el architect; el dev solo agrega referencia en el compose.
- **No defaults hardcodeados de secrets** — `DATABASE_PASSWORD: ${DB_PASS}` sin default; si falta, que falle al arrancar.
- **Validar requeridas al arranque** — El servicio falla rápido si falta una env var crítica, no espera al primer request.
- **Convenciones de nombre** — Mayúsculas con guion bajo (`DATABASE_URL`, no `databaseUrl`). URLs completas con esquema (`postgres://...`) mejor que piezas separadas.

## Builds reproducibles

- **Copiar lockfiles** — `package-lock.json`, `pnpm-lock.yaml`, `poetry.lock`, `go.sum`, `Cargo.lock`. Bloquea versiones exactas.
- **`npm ci` sobre `npm install`** en builds — `ci` requiere lockfile y falla si hay drift.
- **`--frozen-lockfile` o equivalente** del package manager (`pnpm install --frozen-lockfile`, `yarn install --frozen-lockfile`).

## Resource limits en producción

Servicios deben tener límites de memoria y CPU declarados en producción. La sintaxis depende del orquestador:

**`docker compose up` standalone (compose v2 sin Swarm)** — usar `mem_limit` / `cpus:` directos:

```yaml
services:
  api:
    mem_limit: 512m
    mem_reservation: 256m
    cpus: '1.0'
```

**Swarm / `docker stack deploy` / Kubernetes con converters** — usar el bloque `deploy:`:

```yaml
services:
  api:
    deploy:
      resources:
        limits:
          cpus: '1.0'
          memory: 512M
        reservations:
          memory: 256M
```

**Footgun común:** poner `deploy:` en un compose que se levanta con `docker compose up` standalone no produce error — los límites se ignoran silenciosamente. Si el deploy es standalone, asegurar que la sintaxis es la primera.

Razón: previene que un servicio con leak consuma todo el host. En desarrollo es opcional (límites bajos generan OOM molestos durante debug).

## Anti-patrones comunes

- **`FROM node` sin tag** — pinear siempre la versión.
- **`COPY . .` antes de `COPY package*.json ./ && npm install`** — invalida cache de deps en cada build.
- **Correr el container como `root` en producción** — riesgo de escalada si hay un RCE.
- **`ENV NODE_ENV=development`** en imagen de producción — algunas libs cambian comportamiento (Express deshabilita view cache, etc.).
- **`RUN npm install -g <tool>` para herramientas de dev en imagen de producción** — bloat sin razón.
- **Dejar `.git`, `node_modules`, archivos de IDE en la imagen final** — usar `.dockerignore`.
- **Múltiples `ENV` separados** cuando se pueden combinar — más capas innecesarias.
- **Healthcheck que solo verifica que el proceso corre** (`pgrep node`) — debe verificar que el servicio responde (`wget --spider /health` o equivalente con runtime nativo).
- **Incluir `version: "3.8"` en compose** — obsoleto en Docker Compose v2, omitir el campo.
- **`chmod 777` para "arreglar permisos"** — síntoma de USER mal configurado, no fix.
- **Imágenes >1GB sin justificación** — casi siempre indica que faltó multi-stage o variante slim.
