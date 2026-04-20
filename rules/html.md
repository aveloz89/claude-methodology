# HTML Review Rules

Reglas idiomáticas para revisar código HTML. El agente `qa-frontend` lee este archivo cuando el PR contiene archivos `.html`, `.htm`, o templates con markup (`.jsx`, `.tsx`, `.vue`, `.svelte`, `.razor`).

## Semántica

- **HTML semántico sobre `div`/`span` genéricos** — Usa `header`, `nav`, `main`, `section`, `article`, `aside`, `footer`
- **`<button>` para acciones, `<a>` para navegación** — No `<div onClick>` ni `<a href="#" onClick>`
- **`<ul>`/`<ol>` para listas** — No `div` con items sueltos
- **`<table>` solo para datos tabulares** — No para layout
- **`<form>` wrappea campos de formulario** — Con `action` o `onSubmit`, no campos sueltos
- **Headings en orden jerárquico** — `h1` → `h2` → `h3`, no saltar niveles
- **Un solo `<h1>` por página** — El título principal

## Accesibilidad (a11y)

- **`alt` en todas las `<img>`** — Descriptivo para contenido, vacío (`alt=""`) para decorativas
- **Labels en inputs** — `<label for="email">` o `<label>` wrapeando el input. No inputs sin label
- **`aria-label` cuando no hay texto visible** — Botones con solo ícono necesitan `aria-label`
- **Roles explícitos solo cuando el elemento semántico no existe** — No `<nav role="navigation">` (redundante)
- **Contraste de color suficiente** — WCAG AA mínimo (4.5:1 texto, 3:1 texto grande)
- **Focus visible** — No `outline: none` sin alternativa. El focus ring es necesario para navegación por teclado
- **`tabindex` con cuidado** — `tabindex="0"` para hacer focusable, `-1` para programático. Nunca `tabindex > 0`
- **Skip navigation link** — `<a href="#main-content" class="skip-link">` para usuarios de screen reader

## Formularios

- **Inputs con `type` correcto** — `email`, `tel`, `url`, `number`, `date`, etc. Activa teclado correcto en mobile
- **`required` para campos obligatorios** — Validación nativa del browser
- **`autocomplete` attributes** — `autocomplete="email"`, `autocomplete="current-password"`, etc.
- **`<fieldset>` + `<legend>` para grupos de campos** — Radio buttons, checkboxes relacionados
- **Mensajes de error asociados** — `aria-describedby` apuntando al mensaje de error

## Performance

- **`loading="lazy"` en imágenes below the fold** — No lazy-load la imagen hero
- **`<picture>` con `srcset` para responsive images** — Sirve tamaños apropiados
- **`defer` o `async` en scripts** — No scripts bloqueantes en el `<head>` sin razón
- **No inline styles masivos** — Si son más de 2-3 propiedades, usa una clase CSS
- **`<link rel="preload">` para recursos críticos** — Fonts, CSS above the fold

## SEO básico

- **`<title>` único por página**
- **`<meta name="description">` presente**
- **`<html lang="es">` (o el idioma correcto)** — Necesario para screen readers y SEO
- **URLs semánticas** — `/productos/zapatos` no `/page?id=42`

## Red flags

- `<div>` con `onClick` en vez de `<button>` o `<a>`
- Imágenes sin `alt`
- Inputs sin `<label>` asociado
- `<table>` usado para layout
- Headings fuera de orden (`h1` → `h3` sin `h2`)
- `tabindex` positivo (> 0)
- Inline styles extensos
- `<br>` para spacing (usar CSS margin/padding)
- `<b>` / `<i>` para semántica (usar `<strong>` / `<em>`)
- `target="_blank"` sin `rel="noopener noreferrer"`
