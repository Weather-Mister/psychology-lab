# Psychology Lab development rules

## Source of truth
This GitHub repository is the source of truth for Psychology Lab development.

## Architecture
- `public/`: browser frontend deployed by GitHub Pages.
- `supabase/functions/psychology-profile/`: live profile load/save API source.
- `supabase/migrations/`: Psychology database schema and RPC history.
- Live Supabase project: `statistics-r-lab` (`ibkirlsqpzmhuwssdcjj`).
- Live Edge Function: `psychology-profile`.

## Preservation invariant
Do not redesign, reset, re-seed, or silently change the site. Preserve the current UI, course content, notes, flashcards, matching, quizzes, usernames, profile state, revisions, and stored database rows unless the user explicitly asks for a change.

## Frontend development
Edit files in `public/`. Asset URLs must remain GitHub Pages-compatible (relative paths, not repository-root `/` paths). Profile sync must use the Supabase `psychology-profile` Edge Function.

## Backend development
For backend changes:
1. Edit the matching source under `supabase/functions/` or `supabase/migrations/` in this repository.
2. Apply database changes to Supabase project `ibkirlsqpzmhuwssdcjj`.
3. Deploy the `psychology-profile` Edge Function when its source changes.
4. Never recreate or clear the existing Psychology profile table for ordinary development.
5. Treat migrations as additive and data-preserving.

## Deployment
`.github/workflows/pages.yml` deploys `public/` to GitHub Pages on pushes to `main`.
