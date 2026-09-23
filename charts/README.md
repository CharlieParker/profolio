# charts — Helm charts for `profolio-dev` / `profolio-stage`

## What this directory is

The Helm pass that supersedes applying `../k8s/*.yaml` directly, per that directory's own
README. **`k8s/` is not deleted** — it stays as the applied, working reference; these
charts are a parallel, install-ready artifact. Adopting the *already-running* `postgres`
StatefulSet and its `data-postgres-0` PVC under Helm management, without data loss, is a
separate later step — see the postgres chart's own note below.

Four **separate small charts**, not one umbrella chart — Argo CD's app-of-apps (a later
pass) does the composing across them instead.

| Chart | Contents |
| --- | --- |
| `postgres/` | headless Service + StatefulSet with a 1Gi PVC per pod |
| `backend/` | backend Deployment + ClusterIP Service, plus `alembic upgrade head` as a `pre-install,pre-upgrade` hook Job |
| `frontend/` | frontend Deployment + ClusterIP Service + `BACKEND_URL` ConfigMap |
| `keycloak/` | Keycloak (codecentric's `keycloakx` chart), reusing the postgres chart's Postgres instance with its own logical database |

## The naming convention is load-bearing

Install each chart with a **release name equal to the chart name**:

```sh
helm install postgres  charts/postgres  -n profolio-dev -f charts/postgres/values.yaml -f charts/postgres/values-dev.yaml
helm install backend   charts/backend   -n profolio-dev -f charts/backend/values.yaml  -f charts/backend/values-dev.yaml
helm install frontend  charts/frontend  -n profolio-dev -f charts/frontend/values.yaml -f charts/frontend/values-dev.yaml
```

Helm's default fullname template collapses to just the release name when the release name
already contains the chart name — so these produce Service objects named exactly
`postgres`, `backend`, `frontend`, identical to today's raw manifests. That's why the
backend's `DATABASE_URL` (host `postgres`) and the frontend's `BACKEND_URL`
(`http://backend:8000`) needed no changes: they still resolve correctly. Installing under a
different release name would silently break both.

Swap `-f charts/*/values-dev.yaml` for `-f charts/*/values-stage.yaml` and `-n
profolio-dev` for `-n profolio-stage` to target stage. Both overlay files are currently
empty placeholders (see each chart's `values-dev.yaml` comment) — stage doesn't diverge
from dev yet, per Rung 3's scope.

## Secrets

Same rule as `../k8s/README.md`: nothing is committed, no value ever goes in git, every
Secret is created imperatively. `ghcr-pull` and `postgres-credentials` already exist in
`profolio-dev` from the raw-manifest pass and are reused as-is (see that README for their
create commands). Keycloak needs two more, in its own `keycloak` namespace:

| Secret | Namespace | Keys | Used for |
| --- | --- | --- | --- |
| `keycloak-db-credentials` | `keycloak` | `password` | Keycloak's Postgres role password |
| `keycloak-admin-credentials` | `keycloak` | `KC_BOOTSTRAP_ADMIN_USERNAME`, `KC_BOOTSTRAP_ADMIN_PASSWORD` | Keycloak's bootstrap admin login |

## Install order

**Before any of this:** if `profolio-dev` already has Postgres/backend/frontend running from
the raw-manifest pass, don't run `helm install` straight against it — Helm will reject
objects it doesn't already own. Back up the namespace's Secrets, delete and recreate
`profolio-dev`, restore the Secrets, then start at step 1 below. Exact commands and reasoning:
`docs/journal.md`, 2026-09-23.

```sh
# 0. one-time: fetch the keycloakx dependency chart
helm repo add codecentric https://codecentric.github.io/helm-charts
helm dependency build charts/keycloak

# 1. database
helm install postgres charts/postgres -n profolio-dev --create-namespace \
  -f charts/postgres/values.yaml -f charts/postgres/values-dev.yaml
kubectl -n profolio-dev rollout status sts/postgres

# 2. app (backend's pre-install hook runs `alembic upgrade head` automatically — no more
#    manual `kubectl delete job && kubectl apply` dance)
helm install backend charts/backend -n profolio-dev \
  -f charts/backend/values.yaml -f charts/backend/values-dev.yaml
helm install frontend charts/frontend -n profolio-dev \
  -f charts/frontend/values.yaml -f charts/frontend/values-dev.yaml
```

Rerunning migrations is now just `helm upgrade backend charts/backend -n profolio-dev -f ...`
— the hook's `before-hook-creation` delete policy handles the immutable-Job problem
automatically.

Keycloak is independent of the sequence above (own namespace, nothing in the app depends
on it yet), but its database step depends on `postgres` already being up:

```sh
kubectl create namespace keycloak

# One-time: create Keycloak's own Postgres role and database on the EXISTING postgres
# instance — a separate logical database, not a second Postgres, and not the app's own
# superuser role (keeps the isolation real, not just a naming convention).
kubectl -n profolio-dev exec -it postgres-0 -- \
  psql -U <POSTGRES_USER> -d <POSTGRES_DB> -c \
  "CREATE ROLE keycloak WITH LOGIN PASSWORD '<KEYCLOAK_DB_PASSWORD>';"
kubectl -n profolio-dev exec -it postgres-0 -- \
  psql -U <POSTGRES_USER> -d <POSTGRES_DB> -c \
  "CREATE DATABASE keycloak OWNER keycloak;"

kubectl -n keycloak create secret generic keycloak-db-credentials \
  --from-literal=password='<KEYCLOAK_DB_PASSWORD>'
kubectl -n keycloak create secret generic keycloak-admin-credentials \
  --from-literal=KC_BOOTSTRAP_ADMIN_USERNAME=admin \
  --from-literal=KC_BOOTSTRAP_ADMIN_PASSWORD='<KEYCLOAK_ADMIN_PASSWORD>'

helm install keycloak charts/keycloak -n keycloak \
  -f charts/keycloak/values.yaml -f charts/keycloak/values-dev.yaml
```

Only one Keycloak instance is ever installed, in the shared `keycloak` namespace,
regardless of `profolio-dev`/`profolio-stage` — see `charts/keycloak/values-dev.yaml`'s
comment for why.

## Checking it worked

```sh
kubectl -n profolio-dev get pods,pvc,svc,jobs
kubectl -n keycloak get pods,svc
```

The migrate Job should show `Completed`; `data-postgres-0` should be `Bound`; both
Deployments and the Keycloak StatefulSet should be `Running`/`Ready`.

## Known gaps, deliberately left for later

- **`profolio-dev` adoption question (Postgres, backend and frontend — not just
  Postgres) — resolved 2026-09-23: back up the namespace's Secrets, delete `profolio-dev`
  outright, recreate it, restore the Secrets, then `helm install` all three charts fresh.**
  Rejected per-resource Helm-adopt (annotating every StatefulSet/Deployment/Service/PVC with
  `meta.helm.sh/release-name`/`release-namespace` and the `app.kubernetes.io/managed-by: Helm`
  label) as three times the moving parts for data that's entirely synthetic anyway — see
  `docs/journal.md`, 2026-09-23, for the full reasoning and exact step order.
- **Bitnami's keycloak chart was considered and rejected** — it stopped shipping patched
  free Keycloak images/charts as of 2025-08-28 (the free `bitnamilegacy` path is frozen).
  `codecentric/keycloakx` was used instead — note the `x`: `codecentric/helm-charts` also
  has an older, deprecated `keycloak` chart (WildFly-based, matches pre-17 Keycloak); that
  one is NOT what's used here.
