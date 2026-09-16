# Security review pre-push: `docs/regla-verificacion-visual`

> Transcrito por el orchestrator desde la respuesta del `security-reviewer`, que no tiene herramienta de escritura. El contenido es del agente; el formato está condensado.

- **Branch:** `docs/regla-verificacion-visual` · **Base:** `dev` (merge-base `0df5c64`) · **HEAD ronda 1:** `d1671c7` · **Fecha:** 2026-09-16
- **Veredicto ronda 1: CAMBIOS REQUERIDOS** (1 bloqueante, fix de una línea). Sin hallazgos de seguridad en sentido clásico: el diff no tiene código, dependencias, CI ni superficie de ejecución.

### Seguridad — ronda 1

**Higiene, verificada y no deducida:** barrido de patrones de secrets sobre los tres archivos normativos y el `BRIEF.md` → cero. Rutas absolutas de máquina en líneas agregadas → cero (usan `~/.claude/rules/...`, convención del repo, 26 usos en `agents/`). URLs externas → cero. La única línea que implica ejecutar algo (`agents/ui-ux.md:281`, script efímero de Playwright) ya existía: la frase agregada cambia el estándar de evidencia, no el permiso.

**§5 no se debilita.** La viñeta nueva (`rules/implementation-principles.md:147`) es aditiva, entra en «Qué exige, en concreto», arriba del corolario rojo→verde y de las condiciones de la excepción, y no toca ninguno. Las excepciones siguen redactadas contra el corolario, así que no abren vía para declarar verificado lo visual sin evidencia: sube el piso probatorio.

**El diff pasa su propia regla.** Sus dos afirmaciones fácticas traen evidencia ejecutada: `document.fonts.check()` puede devolver `true` sin ejercer el camino (`PR-269.md`, cerrado con CDP `getPlatformFontsForNode` y conteo de peticiones) y `.clients-page__table td { color }` anulaba el contraste en tres tablas (`PR-270.md`, con la especificidad 0,1,1 vs 0,1,0).

#### Bloqueante (ronda 1)

**`agents/qa-frontend.md:80`, con su espejo en el template `:288` — sube el estándar de evidencia sin nombrar quién la produce.** Verificado sobre el prompt completo: `qa-frontend` nunca recibe un stack corriendo (su handoff son diff, lista de archivos y design system; `grep` de `stack corriendo|URL del stack|localhost|dev server` en su prompt y en el runbook → cero), su flujo de 11 pasos no tiene navegador, y §5 le prohíbe tocar el árbol. Con contraste como criterio **bloqueante**, el único método disponible —leer el token— queda declarado insuficiente sin reemplazo alcanzable: quedan tres salidas, todas peores que el estado previo (sello de goma, bloqueo falso, o levantar Playwright en pleno review). Que es descuido de redacción y no diseño lo prueba `:89`, dos secciones más abajo, que resuelve el caso idéntico bien: «ante duda, **exige** el valor computado».

**Remediación:** alinear `:80` con el patrón de `:89` (exigir la evidencia al `frontend-dev`, en voz activa) y admitir en `:288` el tercer estado que el sistema ya tiene (`implementation-principles.md:185`, *no verificable*, no bloqueante).

#### Sugerencias (ronda 1)

- **[LOW]** `agents/frontend-dev.md:48` no fue reconciliado: su lista de mínimos no incluye contraste, así que el reviewer exigiría evidencia que al productor nunca se le pidió.
- **[LOW]** `agents/ui-ux.md:292` usa `implementation-principles.md` a secas; los otros 26 usos de `agents/` usan la ruta completa.
- **[LOW]** `agents/ui-ux.md:292` leído aislado exige contraste computado aunque el audit corra solo por código; el escape existe en `:281`, en otra viñeta.
- **[LOW]** El criterio queda enunciado dos veces dentro de `ui-ux.md` (`:281` y `:292`); D-01 lo sanciona, pero estira «enunciar una vez, remitir el resto».

### NO CUBIERTO — ronda 1

- `claude plugin validate --strict .`, `tests/adversarial/` y `tests/validation/`: no corridos (queda para qa-backend; el BRIEF declara los tests no aplicables a este diff).
- Audit de dependencias, CI, headers, Docker y OWASP: sin superficie.
- Comportamiento efectivo de los prompts: no observable desde el diff. El bloqueante se argumenta sobre lo que el prompt habilita y exige, no sobre conducta medida.
- `.planning/*`: revisado solo por higiene e intención.

**Nota del reviewer sobre el veredicto:** no hay vulnerabilidad; «CAMBIOS REQUERIDOS» es por integridad de gate, y se salda con media línea más el estado extra del checklist. El criterio de §5 está bien construido y bien respaldado.

---

## Ronda 2 — delta d1671c7..6c7c388 (2026-09-16)

> Transcrito por el orchestrator desde la respuesta del agente. Delta: 5 archivos, 8 líneas, todas prosa.

### Seguridad

1. **Bloqueante de ronda 1 — RESUELTO.** `agents/qa-frontend.md:80` pasó a voz activa y nombra al productor («exige al `frontend-dev` el valor computado… como evidencia»), el patrón que ya usaba `:89`. El camino ahora es alcanzable: el dev produce, el reviewer exige. `:288` admite el tercer estado, así que «no llegó evidencia» no se resuelve como `OK` silencioso.
2. **LOW-1 — RESUELTO.** `agents/frontend-dev.md:48` suma contraste a los mínimos con el valor computado como evidencia y cierra con «`qa-frontend` valida esto en review y exige esa evidencia»: el lazo queda explícito en las dos puntas.
3. **LOW-2 y LOW-3 — RESUELTOS.** `agents/ui-ux.md:292` con la ruta completa y remitiendo al paso 3, cuyo escape («sin stack, el audit por código es válido; decláralo como limitación») el reviewer verificó que existe. `:229` ganó la evidencia; `:258` quedó intacto y es lo correcto: es un umbral de especificación, no una afirmación sobre un render observado.
4. **El cross-reference nuevo no debilita ningún gate.** Comparado contra `dev`: las líneas de `rules/css.md:59,64` y `rules/html.md:32` no tenían estándar de evidencia y el delta solo **agrega** qué cierra la prueba. Nada removido, ningún «→ bloqueante» degradado en los 5 archivos.
5. **Higiene limpia:** sin secrets, sin rutas absolutas de máquina (solo `~/.claude/rules/...`), sin URLs ni comandos nuevos, sin nada que saque a un agente de su sandbox.

### Veredicto

**APROBADO**

#### Bloqueantes
Ninguno.

#### Sugerencias (las tres, aplicadas en `d1f6d36` sin re-review: son prosa)
- **[LOW]** La evidencia de contraste no tiene canal declarado en el reporte del productor: `agents/frontend-dev.md:156-166` no la nombra, así que la entrega depende de que el dev se acuerde.
- **[LOW]** `NO VERIFICABLE` en `qa-frontend.md:288` no significa lo mismo que en `implementation-principles.md:185`, donde está reservado a dos causas nombradas y la evidencia ausente **sí** bloquea. El repo ya pagó esa erosión (`.planning/reviews/PR-61.md:35`).
- **[LOW]** `rules/css.md:59,64` y `rules/html.md:32` usan voz impersonal en archivos con dos audiencias; el patrón de `:80`/`:89` los haría inequívocos en aislamiento.

### NO CUBIERTO — ronda 2
- No corrió `claude plugin validate --strict .`: toma el `passed` del dev como no verificado por él.
- No releyó el diff de ronda 1; solo los dos anclajes que el delta cita.
- No descartó del todo un consumidor aguas abajo que asuma dos estados en el checklist (grep sin hallazgos, pero sin leer completos el runbook ni la skill `review-pr`).
- La eficacia práctica de la regla solo se verá en el primer PR de frontend que la ejerza.
