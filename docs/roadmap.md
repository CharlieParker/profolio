# Roadmap

What is planned, and roughly in what order. These are intentions, not commitments, and the
order changes as the app does. What already exists is described in the
[README](../README.md); this page is for what doesn't yet.

The platform (cluster, charts, GitOps, pipeline) is in place: a merged pull request reaches
the dev environment with no manual step. From here the app leads, and platform work is
pulled in when a feature needs it.

## Next

1. **Ingress.** Reach the app by name on the local network, so nothing needs
   `kubectl port-forward`.
2. **Allocation chart.** How the portfolio splits by holding and by account. The first
   feature with something to look at, built on the synthetic data already there.
3. **A public demo on synthetic data.** The app reachable from the internet through an
   outbound tunnel. No login is needed while the data is synthetic. Once login exists, the
   same portfolio becomes a built-in demo user's data: visitors who aren't signed in see
   it, read-only, and anything that writes requires login.
4. **The basic pipeline gates.** Dependabot; an image build and a vulnerability scan on
   every pull request (nothing builds a Dockerfile on a pull request today); a secrets scan.

## Features

- **Version footer.** The frontend and backend commits shown in the UI, from `/api/version`.
- **Price data.** Prices fetched on a schedule and stored, giving each holding a history.
- **Value over time.** A chart of portfolio value, once there is price history.
- **Portfolio theory.** Risk and return per holding and for the whole, and the efficient
  frontier. Needs price history.
- **Portfolio-weighted news.** Stories ranked by how much of the portfolio they touch: the
  combined weight of the holdings a story mentions, adjusted for how recent it is. Shown as
  a headline cloud or treemap, where a story about a large holding is displayed larger.
- **Broker import.** Holdings pulled from a broker's API, or from its export file, in place
  of seed data. This brings real data, so it waits for login.
- **Tests against a real database.** Backend tests running against Postgres in CI.

## Platform

- **Login.** Keycloak is deployed but nothing uses it. Planned: single sign-on for Argo CD,
  login in the app, then each user seeing only their own accounts. Platform users and app
  users kept in separate realms.
- **HTTPS** on the app's hostnames.
- **Secrets in Git, encrypted,** so a rebuild needs one key and not a list of commands. The
  tool is undecided.
- **A rehearsal of [`bootstrap.md`](bootstrap.md)** against an empty cluster, including
  backup and restore.
- **More pipeline gates:** a software bill of materials, signed build attestations,
  infrastructure and workflow scanners.
- **Observability:** metrics, logs, dashboards and alerts, once there is traffic to observe.
- **Infrastructure as code** for the cluster-level pieces that are installed by hand today.
- **Chores:** pin the Postgres image by digest; delete the old `:latest` image tags; a
  summary table from `ci-ok`; a scheduled check of external links (CI checks only the links
  between files in the repo); a Markdown linter.

## Constraints that shape the order

- **No real financial data without login.** Everything before login runs on synthetic data.
- **The cluster is on a home network.** GitHub cannot call into it, so Argo CD polls, and
  anything public goes out through a tunnel.
