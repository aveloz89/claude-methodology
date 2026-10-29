# Code Sweep Common

Texto común al workflow `workflows/code-sweep.js` y al agente de respaldo `agents/code-sweep.md`. Acá viven una sola vez los patrones, los umbrales, el schema de hallazgo, el criterio de refutación y el formato de reporte. Todo es de solo lectura: nadie que use este rulebook modifica código.

## 1. Patrones por stack (modo `bugs`)

Detecta el stack primero: `find . -type f \( -name "*.ts" -o -name "*.tsx" -o -name "*.py" -o -name "*.go" -o -name "*.rs" -o -name "*.cs" \) | head -20`. Salta los lenguajes ausentes.

| Stack | Patrones (grep/find concreto) |
|---|---|
| TypeScript/JS | Headers HTTP incondicionales en wrappers fetch/axios (`grep -rn "headers:" --include="*.ts"`); `useEffect` con fetch sin `AbortController`; non-null assertions arriesgadas (`grep -rnE "\.env\.\w+!|params\.\w+!" --include="*.ts" -r src/`); handlers async sin `.catch()` (`grep -rnE "onClick=\{.*async" --include="*.tsx" -r src/`); `catch {}`/`catch { alert(...) }` vacíos (`grep -rnE "catch\s*\{\s*\}" -r src/`) |
| Python | Mutable default arguments (`grep -rnE "def \w+\(.*=(\[\]|\{\})" --include="*.py" -r .`); `except:`/`except Exception: pass` (`grep -rnE "except(:|\s+Exception:)" --include="*.py" -r .`); `asyncio.run()` anidado; `subprocess`/`os.system` con string y `shell=True` (`grep -rnE "shell=True" --include="*.py" -r .`) |
| Go | Errores ignorados con `_` (`grep -rnE ", _ := \w+\(" --include="*.go" -r .`); `defer` dentro de loops (`grep -rnB2 "defer " --include="*.go" -r . \| grep -B2 "for "`); goroutines sin `context.Context`; acceso a maps/slices sin mutex entre goroutines |
| Rust | `.unwrap()`/`.expect()` fuera de tests (`grep -rnE "\.(unwrap|expect)\(" --include="*.rs" -r src/`); `panic!()` en libraries; `.lock().unwrap()` sin manejo de poisoning |
| C# | `async void` fuera de event handlers (`grep -rnE "async void" --include="*.cs" -r .`); `.Result`/`.Wait()` sobre `Task` (`grep -rnE "\.Result\b|\.Wait\(\)" --include="*.cs" -r .`); `IDisposable` sin `using` (`grep -rnE "new (DbContext|FileStream|HttpClient)" --include="*.cs" -r .`) |

Para cada match, lee el contexto y verifica que es real antes de reportarlo: un falso positivo no cuenta. Si un patrón además es una vulnerabilidad de seguridad (p. ej. shell injection), anótalo en `description` para que `security-reviewer` lo priorice.

## 2. Umbrales (modo `smells`)

| Severidad | Función LoC | Nesting | Archivo LoC |
|---|---|---|---|
| **Crítico** | > 200 | > 5 | > 800 |
| **Moderado** | 100–200 | 4–5 | 500–800 |
| **Menor** | 50–100 | 4 | 300–500 |

Ajustes: Go suma 50% al umbral de archivo, Rust suma 30% (convención de módulos grandes).

- **Duplicación**: solo con **3+ ocurrencias con la misma forma** (regla de 3, no DRY prematuro).
- **God files**: `grep -rn "from '<archivo>'" --include="*.ts" -r src/ | wc -l`; más de ~30 imports es candidato.
- **Nombres crípticos, responsabilidades mezcladas**: severidad por juicio, según cuánto frena el desarrollo.
- **Dead code = candidato a revisión humana, nunca se borra por suite verde.** Puede ser API pública, usado por reflexión o referenciado solo desde tests. Repórtalo; no lo elimines ni lo sugieras como fix automático.
- **Coverage / refactor seguro**: el workflow no mide coverage. Si el repo ya trae un reporte de coverage, cítalo en la descripción; un archivo con coverage < 50% no es seguro de refactorizar sin tests de caracterización primero.
- Mapeo a la severidad del schema: Crítico → `CRITICO`, Moderado → `MEDIO`, Menor → `BAJO`.

## 3. Schema de hallazgo

Contrato entre las fases `audit`, `verify` y `consolidate`:

```json
{"id":"CS-001","mode":"bugs","severity":"CRITICO|ALTO|MEDIO|BAJO","pattern":"<nombre del patrón de este rulebook>",
 "file":"ruta/relativa","line":42,"snippet":"...","description":"...","manifestation":"cómo se manifestaría",
 "verdict":"confirmed|refuted|unverified","evidence":"qué se intentó para refutarlo","issue":null}
```

En modo `smells` el auditor puede añadir el campo opcional `"refactor":"<una línea con el refactor sugerido>"`; en `bugs` no existe.

- `pattern`: nombre del patrón del rulebook, solo letras, dígitos, espacio y `_ . - / ( ) { } : ,`.
- `id` determinista: se asigna ordenando por `file`, `line`, `pattern`; nunca aleatorio.
- El auditor deja `verdict: "unverified"` y `evidence: ""`; el verificador fija ambos.
- `issue` es `null` hasta que el consolidador crea o encuentra un issue.

## 4. Criterio de refutación (verificación adversarial)

El verificador es una instancia distinta de la que auditó y su mandato es **refutar** cada hallazgo: construir el input o el camino de ejecución que demuestra que no es bug (o smell). Lee el contexto real, no solo el snippet: guards upstream, validación previa, código inalcanzable, fixtures de test.

- `refuted`: encontró el guard, el camino imposible o el input que lo desmiente, y lo escribe en `evidence`.
- `confirmed`: intentó refutarlo con al menos un camino concreto, no pudo, y describe cuál probó.
- `unverified`: no pudo construir el input ni leer lo necesario, o el resultado es ambiguo. Nunca se promueve a `confirmed` por default.

La evidencia de un issue previo es una hipótesis, no una conclusión: repetir el experimento que el issue cita confirma su mismo error si lo tenía. Si no logras ejercitar la rama con un input nuevo, repórtalo `unverified`.

## 5. Formato de reporte

**Modo `bugs`:**

```markdown
## Code Sweep (bugs) — <fecha>
### Resumen
- Stack: <lenguajes> · Path: <path o "todo el repo">
- Hallazgos: CRÍTICO <N> (issues: #X) · ALTO <N> (issues: #Y) · MEDIO <N> · BAJO <N>
- Refutados en verificación: <N> · No verificados: <N>
### Hallazgos
#### <patrón> — `path:línea` [SEVERIDAD] [confirmado|no verificado]
Snippet, descripción, cómo se manifestaría, issue creado (o "issue existente #N").
### Bloqueante para pre-release (solo si recibiste lista de diff o el token pre-release)
[SÍ/NO] — BLOQUEANTE PRE-RELEASE si hay hallazgo CRÍTICO confirmado.
### NO CUBIERTO
- Lo que no se pudo auditar o verificar (p. ej. este rulebook ausente, chunks sin respuesta).
```

**Modo `smells`:**

```markdown
## Code Sweep (smells) — <fecha>
### Resumen
- Archivos escaneados: X (lo informa el workflow) · Smells: X (críticos X, moderados X, menores X)
- Coverage: no medido por el workflow
- Refutados en verificación: <N> · No verificados: <N>
### Smells detectados
#### `archivo:línea` — <tipo> (<métrica>) [SEVERIDAD]
Problema, impacto y, si el hallazgo trae el campo "refactor", el refactor sugerido.
### NO CUBIERTO
```

Los refutados solo aparecen como conteo en el resumen. La sección `NO CUBIERTO` es fail-visible: nada que no se pudo cubrir se omite en silencio.
