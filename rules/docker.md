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
---

# Docker Review Rules

Reglas idiomáticas para Dockerfiles y archivos de compose. Las leen `backend-dev` al implementar cambios de infraestructura y `qa-backend` al revisar el diff. El `architect` toma decisiones de alto nivel (qué servicio, qué propósito, qué variables de entorno) y delega los detalles de implementación a estas reglas.

## Imágenes base

- **Pinear versiones** — Usar tags específicos (`node:20.11-alpine`, `python:3.12-slim`), nunca `latest`. `latest` rompe builds reproducibles
- **Preferir variantes minimales** — `alpine`, `slim`, `distroless` cuando sea posible, salvo que el runtime requiera glibc o features de Debian
- **No cambiar la imagen base sin razón documentada** — Pasar de `node:20` a `node:22` es breaking; mencionar explícitamente en el PR

## Multi-stage builds

- **Separar build de runtime** en imágenes de producción — La imagen final no debe contener compilador, dev dependencies ni herramientas de build
- **Nombrar stages con `AS <nombre>`** (`AS builder`, `AS runtime`) para claridad y trazabilidad
- **`COPY --from=<stage>`** explícito, copiar solo lo necesario (no `COPY --from=builder /app /app`)

## Seguridad

- **`USER nonroot` en producción** — Crear un usuario sin privilegios y usarlo antes del `CMD`/`ENTRYPOINT`. Nunca correr como root en runtime
  - Node: `USER node` (ya viene en la imagen oficial)
  - Python/Go/otros: crear con `RUN adduser` o `useradd`
- **`COPY --chown=<user>:<group>`** para mantener ownership correcto
- **No hardcodear secrets** — Nada de `ENV API_KEY=...`, ni copiar `.env` a la imagen. Pasar por `--secret`, env vars del runtime, o secret managers
- **No instalar herramientas de debug en producción** — `curl`, `wget`, `bash` solo en imagen de desarrollo
- **`apt-get`/`apk` con `--no-install-recommends`** y limpiar caches (`rm -rf /var/lib/apt/lists/*`) en la misma capa

## Optimización de capas

- **`COPY package*.json ./` antes que `COPY . .`** — Para que `npm install` se cachee si solo cambia código de aplicación
- **Order matters** — Las capas que cambian menos van primero (deps), las que cambian más al final (código)
- **Combinar `RUN` relacionados con `&&`** — Reduce capas y permite limpieza en la misma operación
- **`.dockerignore` siempre presente** — Excluir `node_modules`, `.git`, `.env`, `dist/`, `coverage/`, `__pycache__/`, archivos de IDE. Builds más rápidos y evita filtrar secrets

## Compose (`docker-compose.yml`)

- **Solo exponer puertos necesarios** — `expose:` para comunicación interna entre servicios; `ports:` solo cuando el host necesita acceso
- **`depends_on` con `condition: service_healthy`** cuando hay dependencias de arranque (DB lista antes que API). `service_started` no garantiza que esté listo
- **`healthcheck:` en cada servicio crítico** — DB, API, queue. Sin healthcheck, `depends_on` está adivinando
- **`restart: unless-stopped`** en producción — `always` puede crear loops si el servicio falla al arrancar
- **`volumes:` con propósito explícito**:
  - Bind mounts (`./src:/app/src`) → código en desarrollo (hot reload)
  - Named volumes (`db-data:/var/lib/postgresql/data`) → datos persistentes
  - tmpfs → temporales en memoria
- **No `network_mode: host`** salvo razón estricta — pierde el aislamiento de red

## Hot reload en desarrollo

El compose de desarrollo debe permitir editar código sin rebuild. Por lenguaje:

- **Node/TypeScript** — `tsx --watch`, `nodemon`, `vite dev` (HMR), `next dev`
- **Python** — `uvicorn --reload`, `flask --debug`, `watchfiles`
- **Go** — `air`, `reflex`, `CompileDaemon`
- **Rust** — `cargo watch -x run`
- **Otros** — documentar cómo se reinicia el servicio

Patrón típico:

```yaml
services:
  api:
    build: .
    volumes:
      - ./src:/app/src      # bind mount para código fuente
      - /app/node_modules   # volumen anónimo para no pisar deps del container
    command: npm run dev    # script con watch mode
```

Si el servicio no soporta hot reload, documentarlo en el README o comentario del compose para que el dev sepa que cada cambio requiere `docker compose restart <servicio>` o rebuild.

## Variables de entorno

- **Toda variable nueva va a `.env.example`** con valor de ejemplo (no en `.env`, que está gitignored)
- **No defaults hardcodeados de secrets** — `DATABASE_PASSWORD: ${DB_PASS}` sin default; si falta, que falle al arrancar
- **Validar requeridas al arranque** — El servicio falla rápido si falta una env var crítica, no espera al primer request

## Builds reproducibles

- **Copiar lockfiles** — `package-lock.json`, `pnpm-lock.yaml`, `poetry.lock`, `go.sum`, `Cargo.lock`. Bloquea versiones exactas
- **`npm ci` sobre `npm install`** en builds — `ci` requiere lockfile y falla si hay drift
- **`--frozen-lockfile` o equivalente** del package manager

## Anti-patrones comunes

- **`FROM node` sin tag** — pinear siempre la versión
- **`COPY . .` antes de `COPY package*.json ./ && npm install`** — invalida cache de deps en cada build
- **Correr el container como `root` en producción** — riesgo de escalada si hay un RCE
- **`ENV NODE_ENV=development`** en imagen de producción — algunas libs cambian comportamiento (Express deshabilita view cache, etc.)
- **`RUN npm install -g <tool>` para herramientas de dev en imagen de producción** — bloat sin razón
- **Dejar `.git`, `node_modules`, archivos de IDE en la imagen final** — usar `.dockerignore`
- **Múltiples `ENV` separados** cuando se pueden combinar — más capas innecesarias
- **Healthcheck que solo verifica que el proceso corre** (`pgrep node`) — debe verificar que el servicio responde (`curl -f localhost/health`)
