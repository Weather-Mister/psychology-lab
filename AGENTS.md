# Psychology Lab development rules

## Source of truth
This GitHub repository is the source of truth for Psychology Lab development.

## Architecture
- `public/`: browser frontend. GitHub Pages deploys this directory.
- `api/`: source for the live Hatchable API functions.
- `migrations/`: source for the existing Hatchable PostgreSQL schema.
- Live backend project: `proj_1ATf1esEBZNh` (`psychology-lab`).
- Live backend URL: `https://psychology-lab.hatchable.site/api`.

## Migration invariant
The move to GitHub must not redesign, reset, re-seed, or silently change the site. Preserve the current UI, course content, notes, flashcards, matching, quizzes, usernames, profile state, revisions, and stored database rows unless the user explicitly asks for a change.

## Frontend development
Edit files in `public/`. Asset URLs must remain GitHub Pages-compatible (relative paths, not repository-root `/` paths). `public/app.js` must use the Hatchable API URL when `window.__HATCHABLE__` is absent.

## Backend development
For backend changes:
1. Edit the matching source under `api/` or `migrations/` in this repository.
2. Apply the same backend code change to Hatchable project `proj_1ATf1esEBZNh`.
3. Deploy Hatchable.
4. Never recreate or clear the existing database for ordinary development.
5. Treat migrations as additive and data-preserving.

## Deployment
`.github/workflows/pages.yml` deploys `public/` to GitHub Pages on pushes to `main`.

GitHub repository settings must have Pages > Build and deployment > Source set to **GitHub Actions**.

Because the frontend is cross-origin from the backend, the Hatchable project must be publicly reachable and the API must keep the GitHub Pages CORS allowance for `https://weather-mister.github.io`.
