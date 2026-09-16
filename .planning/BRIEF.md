# Brief: el hook de merge resuelve el repo por el cwd de la sesión, y la fila del DoD (2026-09-16)

> Branch `fix/hook-merge-repo-y-fila-dod` sobre `dev` @ `1c2a77f` (después del merge del PR #75). Son los dos follow-ups que el usuario aprobó al cerrar ese PR. Fase anterior archivada en `BRIEF-regla-verificacion-visual.md`.

## Objetivo

1. Que `hooks/pre-merge-check.sh` verifique el PR **del repo que se está mergeando**, no el del cwd de la sesión.
2. Agregar a la tabla del paso 4 del DoD anti-drift la fila del PR #75.

## Incidente que lo origina (verificado, 2026-09-16)

Al mergear el PR #75 de **este** repo desde una sesión cuyo cwd es `easy-quotes`, el hook bloqueó con «Hay 1 CI check(s) fallando». No había ninguno: este repo no tiene `.github/`, `gh pr checks 75` responde «no checks reported» y el rollup viene vacío.

Lo que pasó: el `cd` de un comando de Bash no cambia el cwd de la sesión, así que `REPO=$(gh repo view …)` (`hooks/pre-merge-check.sh:409`) resolvió `aveloz89/easy-quotes` y el hook consultó **easy-quotes#75** — un PR de julio, mergeado, cuyo check `ci` figura en rojo. Es el mismo modo de falla que el hook de pre-commit ya tiene documentado con worktrees: el hook no ve el árbol real del comando.

Salida usada, sin bypass: `gh pr merge 75 --repo aveloz89/claude-methodology …`. El hook ya honra `--repo` explícito (`:389`, `:407`) y ahí verificó lo correcto.

## Alcance

- **Incluye:**
  1. `hooks/pre-merge-check.sh`: resolver el repo de forma que corresponda al comando. Dos caminos aceptables, el dev elige con evidencia:
     - parsear un `cd <ruta>` inicial en el comando y resolver `gh repo view` con ese cwd;
     - o bloquear pidiendo `--repo` explícito cuando el comando trae un `cd` a un repo distinto del de la sesión.
     En cualquier caso, **fail-closed**: si no se puede determinar el repo con certeza, bloquea y lo dice, como ya hace el resto del hook.
  2. Tests en `tests/adversarial/test-hooks.sh` que cubran el caso del incidente: comando con `cd` a otro repo y número de PR que existe en los dos.
  3. `rulebooks/orchestrator-runbook.md`, tabla del paso 4 del DoD anti-drift: la fila del PR #75.
- **NO incluye:** tocar los demás hooks, ni la lógica de checks/threads/reviews del propio `pre-merge-check.sh` más allá de la resolución del repo.

## Decisiones

- [D-01] El hook se endurece, no se documenta y ya (decisión del usuario). Documentar la limitación dejaba el bloqueo falso en pie, y un bloqueo falso entrena a pedir bypass, que es justo lo que este hook existe para evitar.
- [D-02] La fila del PR #75 dice lo que pasó: **dos** violaciones de su propia regla en el mismo PR —una afirmación sin verificar en el handoff del orchestrator y una exigencia incumplible en el primer borrador—, las dos encontradas por la pasada externa, no por la autorrevisión.

## Verificación esperada

- El caso del incidente reproducido: con el hook nuevo, un `gh pr merge <N>` precedido de `cd` a otro repo verifica el PR correcto; sin `--repo` y sin poder determinarlo, bloquea explicando.
- `tests/adversarial/test-hooks.sh` en verde, con los casos nuevos rojos al revertir el fix.
- `claude plugin validate --strict .` en verde (se toca un hook registrado en `hooks/hooks.json`; revisar la paridad que exige `tests/adversarial/test-plugin-manifest.sh`).
- DoD anti-drift del propio repo aplicado al cambio.
