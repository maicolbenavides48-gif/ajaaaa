# Project memory

## Product intent & audience

- Web application with authentication (login view) and multiple additional views.
- Backend powered by Supabase; database managed via migrations.
- User-facing app requiring styled, functional UI across several screens.

## Brand personality & voice

- Not yet inferred from available context.

## Visual design & UX direction

- Styling via Tailwind CSS + PostCSS.
- UI includes icons and multiple views (login + others).
- Global styles in `index.css`, imported through `main.tsx`.
- Tailwind `content` paths must scan `./src/**/*.{js,ts,jsx,tsx}` and `./index.html` (project was reorganized into `./src/`).

## Decisions, constraints & rationale

- **Folder reorganization**: all source files moved under `./src/` (components, context, etc.); root-level Tailwind content paths caused styles to stop rendering.
- **Tailwind fix**: update `tailwind.config.js` content array to `['./index.html', './src/**/*.{js,ts,jsx,tsx}']`.
- **Supabase scope**: create **only** the `users` table (migration + basic RLS policies); no other tables yet.
- **Entry point**: `main.tsx`; framework is Vite + React.
- App must run without errors after fixes.

## Open questions & assumptions

- Tailwind version (v3 vs v4) not confirmed — affects config format.
- Supabase project credentials/URL and migration tooling details unknown.
- `users` table schema not yet defined (columns, constraints, relationships).
- Full list of views beyond login is unknown.
- No `.bolt/prompt` file present; no explicit global instructions to reference.