# CLAUDE.md — Profolio

Profolio is a small portfolio-analysis app used as a vehicle for platform-engineering
practice: containerised, deployed to a single-node k3s cluster with Helm, managed by Argo CD
(GitOps), and built and shipped by a GitHub Actions pipeline. The app is deliberately
modest; the platform around it is the point.

**This repo is public.** Keep this file, and everything else committed, to what anyone
working on the code would need. Never add personal details about the author — employer,
role, background — anywhere in the repo: code, docs, commit messages or PR text.

## Working agreement

- **Propose before doing.** Use plan mode for anything nontrivial — a schema change, a new
  endpoint shape, a new workflow — before writing files.
- **AI-generated code is fine. AI-run commands are not, by default.** Propose the command with
  a short explanation; the maintainer runs it and pastes back the results. This holds even
  when the code itself came from you.
- **No attribution.** Never add `Co-Authored-By: Claude` or similar trailers to commits or PR
  descriptions. Enforced two ways: `.claude/settings.json`'s `attribution` block (stops it
  being written) and the `commit-msg` hook in `.githooks/` (catches it if it slips through).
- **Branch → PR → CI → squash merge.** `main` is behind a ruleset
  (`.github/rulesets/protect-main.json`): no direct commits, squash merges only, and one
  required check, `ci-ok`, on a branch that is up to date with `main`.

## Stack

FastAPI (Python) backend, React + TypeScript frontend (Vite), Tailwind + shadcn/ui (copied-in
components) with TanStack Table for tables. Postgres + SQLAlchemy + Alembic. Monorepo:
`/backend`, `/frontend`, `/charts` (Helm), `/argocd` (Argo CD Applications), with
`/terraform` to come later.

**Local dev:** `docker-compose.yml` wires Postgres, backend and frontend together,
`pg_isready`-gated so the backend doesn't race Postgres on startup — `docker compose up -d
postgres` then `docker compose up --build`. For active coding, backend (`uv run uvicorn
--reload`) and frontend (`pnpm dev`) run natively with hot reload against just Postgres. The
Compose credentials are local-dev defaults only — no other environment may reuse them.

## Domain — portfolio analyser

Parses the user's own brokerage holdings (instrument, ISIN, quantity, price, per account —
e.g. a general investment account and an ISA) and does portfolio analysis on them: current holdings,
pricing history, eventually a portfolio-weighted newsfeed.

**Hard rule: no real financial data in this repo, ever.** Not in seed data, not in test
fixtures, not in a sample PDF, not in a README screenshot. Real holdings stay local
(gitignored) and untested-against-in-CI. Everything committed uses synthetic data.

## Deployment — settled shape, don't re-derive

- **Cluster:** single-node k3s. Namespaces `profolio-dev` / `profolio-stage` (stage not yet
  in use), plus a shared `keycloak` namespace.
- **Charts:** four small charts under `charts/` (postgres, backend, frontend, keycloak via
  codecentric's `keycloakx`), base `values.yaml` + per-environment overlays. Release name
  must equal chart name — see `charts/README.md`.
- **Argo CD owns the releases** via the app-of-apps in `argocd/` (`root.yaml` applied by hand
  as the bootstrap exception), automated sync with prune + self-heal. Deploy by merging to
  `main`; never `helm upgrade`/`helm uninstall`. `helm install` is bootstrap/DR only.
- **Migrations** run as a Helm `pre-install,pre-upgrade` hook, which Argo runs as `PreSync`
  on every sync.
- **Images:** private GHCR packages, pulled via the `ghcr-pull` Secret (a
  `read:packages`-scoped PAT) referenced per-Deployment.
- **Secrets are imperative** — created with `kubectl`, never committed. `k8s/README.md` and
  `charts/README.md` have the commands with placeholders only.
- `k8s/` holds the original raw manifests, kept as a reference; superseded by the charts.
- Redis is deliberately deferred until a real feature needs it.

## Pipeline — settled shape, don't re-derive

A merged pull request is the only route to dev, with no manual step after the merge:

- **PR → CI** (`ci.yml`): per-component path filtering inside the workflow, and a single
  required `ci-ok` aggregator check.
- **Merge → images** (`deploy-dev.yml`): each image whose code changed is built and pushed
  to GHCR, tagged with the full commit SHA.
- **Images → dev:** the same workflow's `bump` job opens a pull request as the
  `profolio-dev-bump` GitHub App, setting `image.tag` and `image.digest` in
  `charts/*/values-dev.yaml`. Auto-merge lands it once `ci-ok` passes, and Argo syncs. An
  image whose digest hasn't changed is left alone. Those two fields are normally the
  bot's to set, not a feature PR's.
- **Which code is running:** `GET /api/version` on the backend reports the commit its
  image was built from, with a link.

`.github/ci/README.md` explains the files, where each version pin lives and what isn't
pinned.

## Current focus

Small test PRs for the pipeline's untried cases: a bot PR that falls behind `main`, a bot
PR whose checks fail, a frontend-only change. Then OIDC via Keycloak as the first feature
through the pipeline, and security scanners (Trivy, Checkov, Syft SBOM, gitleaks) as a
second pass on it. PDF import, price history and broader tests come after.
