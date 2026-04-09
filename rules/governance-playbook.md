# Governance Playbook

Decision trees para escenarios de fallo. El orchestrator consulta este documento cuando algo sale mal durante el flujo de trabajo.

---

## 1. QA encuentra stubs/TODOs

```
QA reporta stub/TODO
  → BLOQUEANTE — PR no se puede mergear
  → Orchestrator asigna fix al dev original
  → Dev corrige en el MISMO branch del PR
  → Re-review de QA
  → Si persisten stubs → repetir hasta que estén todos resueltos
```

**No hay excepciones.** Código placeholder nunca se mergea.

## 2. Security encuentra vulnerabilidad

```
Security reporta vulnerabilidad
  ├─ Critical/High → BLOQUEANTE
  │   → Dev corrige en el MISMO branch del PR
  │   → Re-review de security
  │   → No se mergea hasta que security apruebe
  │
  └─ Medium/Low → NO BLOQUEANTE (con condiciones)
      → Se puede mergear SI:
        1. Se crea un issue con el hallazgo
        2. El issue se asigna al sprint actual o siguiente
        3. Security lo acepta como follow-up
      → Si security NO acepta → se trata como bloqueante
```

## 3. Coverage < 80%

```
QA reporta coverage < 80%
  → BLOQUEANTE — PR no se puede mergear
  → Dev agrega tests en el MISMO branch
  → Re-ejecuta coverage
  → Re-review de QA
  → Repetir hasta coverage ≥ 80%
```

## 4. Hook falla silenciosamente

```
Sospecha de que un hook no se ejecutó
  → Verificar en settings.json que el hook está configurado
  → Ejecutar el hook manualmente para confirmar que funciona:
      bash hooks/<nombre-del-hook>.sh
  → Si el hook tiene bug:
      → Arreglar en un hotfix branch
      → Testear manualmente
      → PR a main
  → Si el hook no estaba configurado:
      → Agregar a settings.json
      → Verificar con un test manual
  → Revisar si algún PR pasó sin la protección del hook:
      → Si sí, revisar esos PRs manualmente
```

## 5. PR mergeado con issues

```
Se descubre un problema en código ya mergeado
  ├─ Es un bug de seguridad (critical/high)
  │   → Hotfix inmediato:
  │     git checkout main && git checkout -b hotfix/fix-descripcion
  │   → Fix + test + PR a main
  │   → Después de merge, integrar a dev
  │
  ├─ Es un bug funcional
  │   → Evaluar severidad con el usuario
  │   → Si afecta producción → hotfix (igual que seguridad)
  │   → Si no es urgente → feature branch normal desde dev
  │
  └─ Es deuda técnica / code smell
      → Crear issue para tracking
      → Resolver en el próximo ciclo de refactoring
      → NO hacer hotfix por deuda técnica
```

## 6. Agente produce output degradado

```
Output del agente es de baja calidad / incorrecto / incompleto
  → Paso 1: Re-ejecutar el agente con el mismo prompt
     → Si mejora → fue un outlier nondeterminístico, continuar
  → Paso 2: Si persiste, revisar el prompt del agente
     → ¿Cambió el contexto que recibe?
     → ¿El archivo del agente fue modificado recientemente?
     → git log agents/<agente>.md para ver cambios
  → Paso 3: Si el prompt está correcto, hacer review manual
     → El orchestrator o el usuario revisan el output directamente
     → Documentar el problema en .planning/LEARNINGS.md
  → Paso 4: Si es un patrón recurrente
     → Ajustar el prompt del agente
     → Agregar el caso como test de validación (tests/validation/)
```

## 7. Conflicto entre security y QA

```
Security y QA tienen opiniones contradictorias
  ├─ Es un tema de seguridad
  │   → Security tiene la última palabra
  │   → QA documenta su concern como issue
  │
  ├─ Es un tema de funcionalidad
  │   → QA tiene la última palabra
  │   → Security documenta su concern como issue
  │
  └─ Es ambiguo / no está claro quién decide
      → Escalar al usuario para decisión
      → Documentar la decisión en .planning/STATE.md
```

## 8. Build falla después de merge

```
Build falla en main o dev después de merge
  → NO revertir automáticamente sin avisar al usuario
  → Paso 1: Invocar build-resolver para diagnóstico
  → Paso 2: Si el fix es trivial (< 5 min)
     → Hotfix en el mismo branch
  → Paso 3: Si el fix es complejo
     → Revertir el merge: git revert <merge-commit>
     → Crear nuevo feature branch para arreglar
     → PR con el fix + el código original corregido
```

## 9. Contexto agotado durante implementación

```
El context-monitor avisa que el contexto está en 25% (critical)
  → Paso 1: Crear HANDOFF.md con estado actual
  → Paso 2: Commit/push de todo el trabajo en progreso
  → Paso 3: Informar al usuario que debe iniciar nueva sesión
  → Paso 4: En la nueva sesión, leer HANDOFF.md y retomar
```
