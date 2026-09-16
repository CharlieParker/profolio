# Profolio

Portfolio analyser: parses brokerage holdings (instrument, ISIN, quantity, price, per
account) and does portfolio analysis on them. No real financial data in this repo, ever —
everything committed uses synthetic data.

## Layout

Monorepo, flat at the repo root:

```
backend/     FastAPI + SQLAlchemy + Alembic — the API
frontend/    React + TypeScript (Vite) — the UI
```

No shared root-level JS/Python workspace tooling (no Nx/Turborepo/pnpm workspaces) — two
apps in different languages with nothing shared between them yet doesn't earn one. `/charts`
(Helm) and `/terraform` land later as siblings, once the rungs that need them arrive.

## Toolchain

| | Choice | Why |
|---|---|---|
| Backend | [uv](https://docs.astral.sh/uv/) | One tool for venv + dependencies + lockfile (`uv.lock`), fast installs |
| Frontend | pnpm (via corepack) | Faster and stricter than npm; corepack ships with modern Node, no extra global install |
| Frontend build | Vite + React + TypeScript | The modern default (CRA is deprecated); what shadcn/ui's setup assumes |
| Frontend CSS | Tailwind v4 (`@tailwindcss/vite`) | CSS-first config (`@theme` in `src/index.css`, no `tailwind.config.ts`) — what shadcn's CLI v4 sets up by default |
| Frontend UI | [shadcn/ui](https://ui.shadcn.com/) + [TanStack Table](https://tanstack.com/table) | Generic, React-transparent components, chosen over `@royalnavy/react-component-library` — its Storybook leans on GOV.UK-pattern institutional chrome, the wrong look for a personal app |
| Local Postgres | Docker Compose | Reproducible, one command up/down — dev convenience, not Kubernetes |

## Configuration

`DATABASE_URL` (backend) and `VITE_API_URL` (frontend) are already read from `.env`, each
with a `localhost` default — the standard pattern, and enough for one deployment target
(this laptop). Still hardcoded, deliberately, until there's a second target to parameterize
for: CORS origins in `backend/app/main.py`.

**Gotcha for later, not solved now:** Vite bakes `VITE_*` values into the JS bundle at
*build* time, not container start. The usual "inject env vars into the running container"
pattern that works for the backend does nothing here — a per-environment image, or an
entrypoint script writing a small `env.js` the app reads instead, will be needed once this
is containerised (Rung 3).

## Setup

### Git hooks

This repo ships a `commit-msg` hook that rejects commits carrying AI attribution trailers
(`Co-Authored-By: Claude`, `Generated with/by Claude`), backing up the `attribution` block
in `.claude/settings.json`. `core.hooksPath` is local git config, so it isn't set
automatically on a fresh clone — wire it up once per clone:

```sh
chmod +x .githooks/commit-msg
git config core.hooksPath .githooks
```

### Backend

```sh
cd backend
cp .env.example .env
docker compose up -d          # starts Postgres
uv sync                       # installs dependencies into .venv
uv run alembic upgrade head   # creates the accounts/holdings tables
uv run python seed.py         # loads synthetic seed data
uv run uvicorn app.main:app --reload
```

API is then up at `http://localhost:8000` — try `GET /accounts/1/holdings` and
`GET /accounts/summary`.

### Frontend

```sh
cd frontend
cp .env.example .env
corepack enable
pnpm install
pnpm dlx shadcn@latest init
pnpm dlx shadcn@latest add table
pnpm dev
```

`shadcn init` writes `components.json` and the real Tailwind v4 theme into `src/index.css`
(accept the prompt to overwrite it — the checked-in version is just a bare `@import`).
`shadcn add table` regenerates `src/components/ui/table.tsx` from the actual registry rather
than the hand-copied version this pass started with (accept that overwrite too). Once
`components.json` exists, `pnpm dlx shadcn@latest add <component>` works cleanly for whatever
Pass 1 still needs.

UI is then up at `http://localhost:5173`, reading from the backend above.

## CI

None yet, deliberately — this pass is about the app existing and running locally. Direct
commits to `main` are fine until CI exists; once it does, this switches to branch → PR → CI
→ merge, the same flow as the private `beelink-platform` repo.
