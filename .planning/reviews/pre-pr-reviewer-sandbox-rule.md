# Review dual pre-push: reviewer-sandbox-rule

- **Branch:** `feature/reviewer-sandbox-rule` · **Base:** `dev` · **Fecha:** 2026-09-26

## Pre-review del orchestrator: HEAD `3fc8832`

- El comentario de `extract_section` citaba `reviewer_sandbox_files()`, una función que no existe. Se quitó en `23a97be`.
- Los asserts de contenido buscaban en todo el archivo, y `NO CUBIERTO` ya estaba en los prompts de QA, así que pasaban sin la regla. Se acotaron a la sección extraída en `23a97be`. El dev verificó en una copia temporal que borrar la frase rompe el assert (174/176).

## Ronda 1: HEAD `23a97be`

**Veredicto consolidado:** APROBADO, sin bloqueantes.

### security-reviewer (opus): APROBADO
- **[MEDIUM]** La lista de escrituras parecía cerrada: dejaba afuera `sed -i`, `git checkout --`/`restore`, `git apply` y `mv`, y no advertía que `git stash` es compartido entre worktrees. → aplicado en `6e0260a`.
- **[MEDIUM]** La regla se esquivaba cambiando de flag (`acceptEdits`, `--allowedTools`, otros agentes CLI). Se reformuló como invariante: el proceso hijo no tiene más permisos que el reviewer. → aplicado en `6e0260a`.
- **[LOW]** No decía que el worktree va fuera del repo ni que se quita al terminar. → aplicado en `6e0260a`.
- **[LOW]** Los asserts estaban acoplados al texto. → actualizados en `d67f267`.
- Sensibilidad verificada en un worktree desechable: alterar la sección en un solo archivo hace fallar tanto la identidad como el contenido.

### qa-backend: APROBADO
- Se verificó por ejecución en worktrees desechables: el RED en `fbc7d56` (159/176), la divergencia entre agentes y el número que declaró el dev (174/176). En todas las corridas se cumple Total = Pass + Fail.
- **Sugerencia:** a `security-reviewer.md` le faltaba un lugar para NO CUBIERTO en el formato de reporte. → aplicado en `a6a9d18`.
- **Sugerencia:** `state.json` estaba desactualizado. → reconciliado en el merge `9d1c901`.
- **Nota:** `extract_section` compara el encabezado por igualdad exacta. No se aplicó: hoy no es un riesgo, y el fallo que produciría sería visible.

## Ronda 2 (security, sobre el delta `23a97be..a6a9d18`)

**security-reviewer: APROBADO.** Los 4 findings quedaron resueltos. Aparecieron 2 LOW nuevos:
- La regla había quitado la opción del directorio temporal para archivos auxiliares, y la etiqueta del assert quedó desalineada. → aplicado en `8d24ee9`.
- Faltaba `### NO CUBIERTO` en el formato de re-review. → aplicado en `ca529e7` (RED) y `03593c9`.

Estos dos LOW cambian una línea cada uno y los cubre el test (187/187), así que no se relanzó a security. Después se integró `dev` (PR #83) en `9d1c901`, con conflictos solo en `.planning/` y en bloques de test adyacentes. Suites después del merge: 189/107/358.

`docs` se saltó (D-03 en `STATE.md`).

## Pendiente de verificación manual (NO CUBIERTO de los reviewers)

- No se sabe si el harness bloquea `claude -p --permission-mode acceptEdits` o `--allowedTools` cuando lo lanza un subagente de solo lectura. Para verificarlo, el usuario lo corre a mano desde un subagente.

## Cierre

**Veredicto final:** APROBADO. HEAD `03593c9` + merge de dev.
