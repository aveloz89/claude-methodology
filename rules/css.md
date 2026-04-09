# CSS Review Rules

Reglas idiomáticas para revisar código CSS. El QA agent lee este archivo cuando el PR contiene archivos `.css`, `.scss`, `.sass`, `.less`, o archivos con estilos inline/módulos CSS.

## Especificidad y selectores

- **No `!important`** — Si lo necesitas, probablemente hay un problema de especificidad que deberías resolver. Excepciones: utilities de override intencional, overrides de terceros
- **No IDs para estilos** — `#header` tiene especificidad demasiado alta. Usa clases
- **No selectores anidados profundos** — `.header .nav .list .item .link` es frágil. Máximo 3 niveles
- **No selectores de tag solos** — `div { }` o `p { }` afecta todo el documento. Califica con una clase
- **BEM o la convención del proyecto** — Consistencia sobre preferencia personal
- **No selectores acoplados al DOM** — `.sidebar > div > ul > li` se rompe si cambia el markup

## Layout

- **Flexbox o Grid sobre floats** — Floats son legacy para layout
- **No `position: absolute` para layout general** — Solo para overlays, tooltips, dropdowns
- **`gap` sobre margins en flex/grid** — Más limpio y mantenible
- **No alturas fijas** — `height: 500px` se rompe con contenido dinámico. Usa `min-height` si necesitas
- **`rem`/`em` sobre `px` para tipografía** — Respeta la configuración del usuario
- **`%` o viewport units para layout responsive** — No anchos fijos en px para contenedores

## Responsive

- **Mobile-first** — Media queries con `min-width`, no `max-width`
- **No breakpoints mágicos** — Usa los breakpoints del design system o defínelos como variables
- **No ocultar contenido con `display: none` por responsive** — Si no es necesario en mobile, probablemente tampoco en desktop. Si es necesario, usa una estrategia mejor que ocultar

## Variables y tokens

- **CSS custom properties para valores repetidos** — `var(--color-primary)` sobre `#3b82f6` repetido
- **No magic numbers** — `margin-top: 37px` necesita un comentario o ser un token
- **Consistencia en spacing** — Usa una escala (4px, 8px, 16px, 24px, 32px, 48px, 64px) no valores arbitrarios
- **Colores como variables** — Nunca hex/rgb hardcodeado repetido

## Animaciones

- **`transform` y `opacity` para animaciones** — Son las propiedades que el GPU acelera. No animes `width`, `height`, `top`, `left`
- **`prefers-reduced-motion`** — Respeta usuarios que desactivan animaciones
  ```css
  @media (prefers-reduced-motion: reduce) {
    * { animation: none !important; transition: none !important; }
  }
  ```
- **No animaciones que distraigan** — Si parpadea, rota o se mueve constantemente, probablemente sobra

## Dark mode (si aplica)

- **`prefers-color-scheme`** — Soporte nativo con media query
- **Variables semánticas** — `--color-bg`, `--color-text`, no `--white`, `--black`
- **Testea contraste en ambos modos**

## Accesibilidad

- **Focus styles visibles** — Nunca `outline: none` sin alternativa (`:focus-visible` + custom style)
- **Contraste suficiente** — WCAG AA: 4.5:1 texto normal, 3:1 texto grande
- **No `display: none` para accesibilidad** — Usa `sr-only` (visually hidden) si quieres ocultar visualmente pero mantener para screen readers
- **Touch targets mínimo 44x44px** — Para botones y links en mobile

## Red flags

- `!important` (revisar si hay forma de evitarlo)
- Selectores con ID (`#header`)
- Selectores de más de 3 niveles de anidación
- `float` para layout (usar flexbox/grid)
- Alturas fijas en contenedores de contenido dinámico
- `px` en font-size (usar `rem`)
- Colores hex hardcodeados repetidos (deberían ser variables)
- `z-index: 9999` (señal de z-index war — definir una escala)
- `outline: none` sin `:focus-visible` alternativo
- Magic numbers sin comentario
- Vendor prefixes manuales (usar autoprefixer)
