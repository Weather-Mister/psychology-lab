# Psychology Lab development rules

## Source of truth
This GitHub repository is the source of truth for Psychology Lab development.

## Architecture
- `public/`: browser frontend deployed by GitHub Pages.
- `supabase/migrations/`: Psychology database schema and RPC history.
- Live Supabase project: `statistics-r-lab` (`ibkirlsqpzmhuwssdcjj`).
- Profile sync uses the Supabase REST RPC endpoints `psychology_profile_load` and `psychology_profile_save`.
- Browser code uses only the Supabase publishable key. Never put a secret/service-role key in `public/`.
- The RPC sets `app.psychology_profile_username` for the transaction; RLS restricts SELECT/INSERT/UPDATE to that username. Unscoped browser-role table reads return no rows.

## Preservation invariant
Do not redesign, reset, re-seed, or silently change the site. Preserve the current UI, course content, notes, flashcards, matching, quizzes, usernames, profile state, revisions, and stored database rows unless the user explicitly asks for a change.

## Frontend development
Edit files in `public/`. Asset URLs must remain GitHub Pages-compatible (relative paths, not repository-root `/` paths).

## Backend development
For backend changes:
1. Record database/RPC changes under `supabase/migrations/`.
2. Apply changes to Supabase project `ibkirlsqpzmhuwssdcjj`.
3. Keep Psychology data accessible only through the username-scoped RLS/RPC pattern.
4. Never recreate or clear the existing Psychology profile table for ordinary development.
5. Treat migrations as additive and data-preserving.

## Deployment
`.github/workflows/pages.yml` deploys `public/` to GitHub Pages on pushes to `main`.
