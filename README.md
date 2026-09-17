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
| Local stack | Docker Compose | Postgres + backend + frontend, one command up/down — dev convenience, not Kubernetes |

## Configuration

`DATABASE_URL` (backend) and `VITE_API_URL` (frontend) are already read from `.env`, each
with a `localhost` default — the standard pattern, and enough for one deployment target
(this laptop). CORS in `backend/app/main.py` uses an `allow_origin_regex` matching any
`localhost`/`127.0.0.1` port, covering every local dev surface (native Vite, containerized
nginx) without hand-enumerating each one. Real per-environment config — an actual
non-localhost origin — still doesn't exist, deliberately: that's a Rung 3 problem, once
there's a real hostname to configure for.

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
cp backend/.env.example backend/.env
docker compose up -d postgres   # starts just Postgres, from the root compose file
cd backend
uv sync                         # installs dependencies into .venv
uv run alembic upgrade head     # creates the accounts/holdings tables
uv run python seed.py           # loads synthetic seed data
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

## Containers

Multi-stage `Dockerfile`s exist for both apps (`backend/Dockerfile`, `frontend/Dockerfile`)
— non-root, pinned base images (tag + digest), small final images.

### Run the full stack

```sh
docker compose up -d postgres
cd backend && uv run alembic upgrade head && uv run python seed.py && cd ..
docker compose up --build
```

- `docker compose up -d postgres` — starts just Postgres, from the root compose file
  (fresh volume, empty schema)
- `alembic upgrade head` / `seed.py` — one-off bootstrap against that fresh DB, over its
  published `localhost:5432`; not part of what the backend image ships (`seed.py` isn't
  even copied in — dev tooling, not runtime code)
- `docker compose up --build` — builds/rebuilds both app images and starts all three
  together in this terminal, logs interleaved and prefixed by service name. `Ctrl+C`
  stops all three at once

Compose gives the backend `DATABASE_URL=...@postgres:5432/...` — Postgres by its Compose
service name, not the `localhost` default in `backend/.env` (only correct for `uvicorn`
running natively). Postgres's `pg_isready` healthcheck plus `depends_on: condition:
service_healthy` stops the backend racing ahead of a Postgres that isn't accepting
connections yet — a standard Compose gotcha, not specific to this app.

### Run an image standalone

Useful for checking image size or the non-root user, without the full stack:

```sh
docker build -t profolio-backend backend/
docker build -t profolio-frontend frontend/

docker run --rm profolio-backend id
docker run --rm profolio-frontend id
```

Standalone, the backend still needs a real path to Postgres:

```sh
docker run --rm -p 8000:8000 \
  --add-host=host.docker.internal:host-gateway \
  -e DATABASE_URL=postgresql+psycopg://profolio:profolio@host.docker.internal:5432/profolio \
  profolio-backend
```

- `host.docker.internal` — Docker's name for "the host machine", from inside a container
- `--add-host=...:host-gateway` — makes that name resolve on plain Docker Engine (e.g.
  WSL2); Docker Desktop wires it up automatically

Frontend `http://localhost:8080` calls the backend at whatever `VITE_API_URL` was baked
into the bundle at build time (`.env`'s default, `http://localhost:8000`) — both
containers publish their ports to the host, so the browser reaches the backend directly;
the two containers don't need to see each other.

### Notes

- **Compose wiring was a later addition, not the original plan.** Rung 2 initially kept
  Compose out entirely, to save "make services talk to each other" for Rung 3's Helm/k3s
  work. Manually smoke-testing each image standalone (the host-networking override above,
  a CORS-per-port mismatch) surfaced real friction and had already taught the underlying
  lesson — a container's `localhost` isn't the host — before Compose entered the picture.
  Compose's bridge network and service-name DNS are different enough from Kubernetes
  Services/Ingress that having one doesn't dry-run the other.
- **Before rebuilding the frontend image, run `pnpm build` locally first.** `pnpm dev`
  never type-checks (Vite's dev server uses esbuild, not `tsc`) — `pnpm build` runs
  `tsc -b && vite build`, which does. Treat that as the real gate.
- **Bumping a base image:** resolve the digest before editing `FROM` —
  `docker pull <image>:<tag>` then
  `` docker inspect --format='{{index .RepoDigests 0}}' <image>:<tag> ``.

## CI

None yet, deliberately — this pass is about the app existing and running locally. Direct
commits to `main` are fine until CI exists; once it does, this switches to branch → PR → CI
→ merge, the same flow as the private `beelink-platform` repo.
