# CLAUDE.md — Profolio

Profolio is a small portfolio-analysis app used as a vehicle for platform-engineering
practice: containerised, deployed to a single-node k3s cluster with Helm, managed by Argo CD
(GitOps), and — next — built and shipped by a GitHub Actions pipeline. The app is
deliberately modest; the platform around it is the point.

**This repo is public.** Personal context and the wider practice plan live in a private
`CLAUDE.md` in the parent directory, which Claude Code loads automatically. Keep this file to
what anyone working on the repo would need. Never add personal details about the author —
employer, role, background — here or anywhere else in the repo: code, docs, commit messages
or PR text.

## Working agreement

- **Propose before doing.** Use plan mode for anything nontrivial — a schema change, a new
  endpoint shape, a new workflow — before writing files.
- **AI-generated code is fine. AI-run commands are not, by default.** Propose the command and
  a short explanation; Charlie runs it himself and pastes back results. This is deliberate —
  it's how he's building CLI fluency — and holds even when the code itself came from you.
- **No attribution.** Never add `Co-Authored-By: Claude` or similar trailers to commits or PR
  descriptions. Enforced two ways: `.claude/settings.json`'s `attribution` block (stops it
  being written) and the `commit-msg` hook in `.githooks/` (catches it if it slips through).
- **Branch → PR → CI → squash merge.** `main` is being put behind a ruleset as part of the
  CI/CD work below. Once that lands, no direct commits to `main`.

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
e.g. "Invest" and "Stocks ISA") and does portfolio analysis on them: current holdings,
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

## Current focus — CI/CD pipeline

One code change flowing end to end: PR → CI (`ci.yml`: per-component path filtering inside
the workflow, single required `ci-ok` aggregator check) → SHA-tagged image pushed on merge
(`deploy-dev.yml`) → CI commits the tag bump to `charts/*/values-dev.yaml` via a GitHub App
token → Argo syncs. Security scanners (Trivy, Checkov, Syft SBOM, gitleaks) follow as a
second pass. Then OIDC via Keycloak as the first feature through the pipeline.
PDF import, price history and broader tests come after.
