# Psychology Lab

GitHub is the source of truth for the Psychology Lab.

- `public/` — static frontend deployed to GitHub Pages
- `supabase/migrations/` — Psychology profile database and RPC backend
- Supabase project: `statistics-r-lab` (`ibkirlsqpzmhuwssdcjj`)

The browser uses the Supabase REST RPC endpoints `psychology_profile_load` and `psychology_profile_save` with a browser-safe publishable key. The RPC sets the requested username for the transaction, and RLS limits table access to that username. Unscoped browser queries see no Psychology profile rows.

The Psychology profile data was migrated from Hatchable without resetting usernames, notes, progress, flashcards, matching state, quiz state, revisions, or timestamps.

Frontend: https://weather-mister.github.io/psychology-lab/
