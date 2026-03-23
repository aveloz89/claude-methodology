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

**ci.yml** — Trigger en push a dev y PRs a main/dev:
- Checkout → Setup runtime → Install deps → Lint → Tests

**security.yml** — Trigger en PRs a main:
- Semgrep CE scan
- Dependency audit (npm audit / pip audit)

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

### 7. Commit inicial

```bash
git add -A
git commit -m "Initial project setup with CI/CD and gitflow"
```

### 8. Crear repo en GitHub y push

```bash
gh repo create $1 --public --source=. --push
git push -u origin dev
```

Pregunta al usuario si quiere el repo público o privado antes de crearlo.

### 9. Configurar branch protection

```bash
gh api repos/{owner}/$1/branches/main/protection -X PUT -f ...
```

Requiere: PR para merge a main, status checks pasados.
