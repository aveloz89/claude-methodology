# STATE

El estado mutable (fase, lotes, progreso) vive en `state.json`.

## Estado actual

- **Feature:** guard-sanitize-redos — arreglar el ReDoS de `guard_sanitize()`, que colgaba indefinidamente cada llamada Bash con un heredoc patológico y quemaba tres núcleos por comando
- **Última actualización:** 2026-08-25

## Decisiones

- [D-01] Es fix a `dev`, no hotfix a `main`: `hooks/lib/guard-matching.sh` es posterior al PR #46 y no existe en `main`. El bug solo afecta a quien corre `dev` — que hoy es el autor, vía el symlink del dev-loop.
- [D-02] `pre-merge-check.sh` entró al scope declarado del lote, que era solo `guard-matching.sh` + tests: la rama nueva de fallback es la que vuelve alcanzable el camino donde ese guard extrae el número de PR de texto crudo. Mismo criterio que en el PR #59 con el check 4 — un PR cierra las ventanas que él mismo abre.
- [D-03] La sugerencia de QA sobre el `perl` huérfano se subió a **obligatoria**. Es el fallo que la sesión llevaba horas apagando a mano, y quedaría escondido justo en el test que existe para atrapar la regresión.
- [D-04] El bloqueante de la ronda 2 lo verificó el **orchestrator**, no el agente: qa-backend no se relanzó en la ronda 3 porque el criterio era objetivo y reproducible (borrar el `pkill` tiene que poner un test en rojo). Queda registrado que la re-verificación no fue de un reviewer independiente.
- [D-05] El LOW de `grep` ausente del check de dependencias de `pre-merge-check.sh` se difiere a otro PR, por recomendación explícita del propio security-reviewer: extiende un fail-open preexistente en vez de crear uno nuevo.
- [D-06] Docs (Fase 2.5) saltada con razón: ni el README ni ninguna doc describen el sanitizador. Su documentación son los comentarios inline del propio archivo, actualizados por el dev en `1996c73`.
- [D-07] El dev ignoró, en las tres invocaciones, un system-reminder que le pedía usar heredocs y `sed` en comandos Bash. Criterio correcto: contradecía la restricción de seguridad del brief con el ReDoS activo, y habría metido al agente justo en la trampa.

## Blockers

- ninguno
