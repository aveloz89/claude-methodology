---
name: new-project
description: Scaffold de proyecto nuevo con gitflow, GitHub Actions CI/CD, CLAUDE.md y estructura estándar.
user-invocable: true
allowed-tools: Read, Write, Edit, Bash, Glob, Grep
argument-hint: "<nombre-proyecto> <stack>"
---

# Crear Nuevo Proyecto

Crea un proyecto nuevo con toda la infraestructura configurada.

## Argumentos

- `$1` — Nombre del proyecto
- `$2` — Stack (node-react, node-vue, python-react, node-next, node-nuxt, python-fastapi, etc.)

Si no se proporcionan argumentos, pregunta al usuario.

## Pasos

### 1. Crear estructura base

```
$1/
├── .claude/
│   ├── settings.json
│   └── agents/          (vacío, para agentes específicos del proyecto)
├── .github/
│   └── workflows/
│       ├── ci.yml
│       └── security.yml
├── docker/
│   ├── frontend.Dockerfile
│   └── backend.Dockerfile
├── docker-compose.yml
├── .dockerignore
├── .gitignore
├── CLAUDE.md
└── README.md
```

### 2. Inicializar Git con Gitflow

```bash
cd $1
git init
git checkout -b main
git checkout -b dev
```

### 3. Generar CLAUDE.md

Crea un CLAUDE.md con:
- Nombre del proyecto y stack
- Estructura de directorios
- Comandos: dev, test, lint, build
- Convenciones de código (basadas en el stack)
- Reglas de gitflow: main (producción), dev (desarrollo), feature/* (features), hotfix/* (fixes urgentes)

### 4. Generar GitHub Actions

> **Presupuesto de CI** (ver la skill `pr-workflow`, regla 5): los repos privados tienen minutos contados. Todo workflow lleva `concurrency` con `cancel-in-progress`, `timeout-minutes` por job, cache de dependencias y runners `ubuntu-latest` (macOS cuesta 10×).

**ci.yml** — Trigger en push a dev y PRs a main/dev:
- Checkout → Setup runtime (con cache de deps) → Install → Lint → Tests
- `timeout-minutes: 10` por job (ajustar si el proyecto lo justifica)

```yaml
concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true
```

**security.yml** — Trigger en PRs a main + schedule semanal (`cron`) sobre dev. **NUNCA en push/PRs a dev**:
- Semgrep CE scan
- Dependency audit (npm audit / pip audit)
- CodeQL si el stack lo amerita (es el job más caro — solo pre-release + schedule)
- **El run por `schedule` debe hacer checkout con `ref: dev` explícito** — los crons corren sobre el default branch (`main`); sin ese `ref`, el scan semanal escanea la rama equivocada y la ventana de exposición de `dev` queda sin cubrir silenciosamente

### 5. Generar .gitignore

Basado en el stack elegido. Siempre incluir:
```
.env
.env.*
node_modules/
__pycache__/
*.pyc
.DS_Store
dist/
build/
coverage/
```

### 6. Scaffold del stack

Según `$2`, inicializa el proyecto con el tooling apropiado:
- **node-***: `npm init`, tsconfig si TypeScript, ESLint, Prettier
- **python-***: `pyproject.toml`, ruff o flake8, pytest

### 7. Generar Docker

Genera los archivos de Docker basándose en el stack elegido (`$2`):

**docker-compose.yml** — Define los servicios del proyecto:
- Servicio de **frontend** (nombre: `frontend`) — expone el puerto del dev server (ej: 3000, 5173)
- Servicio de **backend** (nombre: `backend`) — expone el puerto del API (ej: 8080, 3001)
- Servicio de **DB** si aplica (postgres, mongo, etc.) — con volume persistente
- Red compartida entre servicios
- Variables de entorno vía `.env` (usar `env_file`)
- Volumes para montar código fuente (desarrollo con hot reload)

**docker/frontend.Dockerfile** — Multi-stage:
- Stage `dev`: imagen base del runtime, instala deps, monta código, corre dev server
- Stage `prod`: build estático + nginx (o similar)

**docker/backend.Dockerfile** — Multi-stage:
- Stage `dev`: imagen base del runtime, instala deps, monta código, corre con watch/reload
- Stage `prod`: build optimizado

**.dockerignore** — Basado en el stack:
```
node_modules/
__pycache__/
.git/
.env
dist/
build/
coverage/
.DS_Store
```

**Criterios:**
- Target `dev` por defecto en docker-compose (para desarrollo local)
- Los Dockerfiles deben tener tanto `dev` como `prod` stages
- Usar versiones específicas de imágenes base (no `latest`)
- Siempre incluir healthchecks en los servicios

### 8. Commit inicial

```bash
git add -A
git commit -m "Initial project setup with CI/CD, Docker and gitflow"
```

### 9. Crear repo en GitHub y push

```bash
gh repo create $1 --public --source=. --push
git push -u origin dev
```

Pregunta al usuario si quiere el repo público o privado antes de crearlo.

### 10. Configurar branch protection

```bash
gh api repos/{owner}/$1/branches/main/protection -X PUT -f ...
gh api repos/{owner}/$1/branches/dev/protection -X PUT -f ...
```

- **`main`**: PR obligatorio + **branch up to date estricto** (`strict: true`) + `required_status_checks.contexts` enumerando **por nombre TODOS los jobs de `ci.yml` Y de `security.yml`**. Es el gate de release. **Crítico:** un workflow que corre en el PR pero cuyo job no está listado en `contexts` es informativo, no bloqueante — sin esto, un CRITICAL de CodeQL no impediría el merge a `main`.
- **`dev`**: `strict: false` (sin up-to-date — mergear un PR no invalida los demás en cola ni fuerza re-runs de CI, ver la skill `pr-workflow`, regla 5.6) + `contexts` con **SOLO los jobs de `ci.yml`**. **NUNCA listar jobs de `security.yml` en `dev`**: no corren en PRs a `dev`, y un context requerido que nunca reporta deja el merge colgado esperando indefinidamente.
