---
name: refactor-scan
description: Escanea el codebase en busca de code smells y deuda técnica. Genera un reporte priorizado y permite refactorizar lo que elijas.
user-invocable: true
allowed-tools: Read, Grep, Glob, Bash, Agent(refactor)
argument-hint: "[directorio o archivo específico]"
---

# Refactor Scan

Escanea el codebase (o un directorio/archivo específico) en busca de código difícil de mantener.

## Argumentos

- `$1` (opcional) — Directorio o archivo a escanear. Si no se proporciona, escanea `src/` (o el directorio principal del proyecto detectado desde CLAUDE.md)

## Flujo

### 1. Determinar alcance

Si se proporcionó `$1`, escanea solo eso. Si no:
- Lee CLAUDE.md para detectar la estructura del proyecto
- Escanea el directorio de código fuente principal (src/, app/, lib/, etc.)
- Excluye: node_modules, dist, build, coverage, .next, __pycache__, migrations

### 2. Invocar al agente refactor en modo scan

Invoca al agente `refactor` con la instrucción de escanear el alcance definido. Pásale:
- El directorio o archivos a escanear
- Que ejecute en **modo scan** (solo detección, no modifique nada)

### 3. Presentar el reporte al usuario

Muestra el reporte del agente. Pregunta al usuario:

> "¿Quieres que refactorice algo de lo encontrado? Dime cuál(es) o dime 'todos los críticos'."

### 4. Ejecutar refactors (si el usuario elige)

Si el usuario elige uno o más items:
1. Invoca al agente `refactor` en **modo refactor** con los items seleccionados
2. El agente crea branch `refactor/...`, refactoriza, corre tests, crea PR
3. Reporta el link del PR al usuario
