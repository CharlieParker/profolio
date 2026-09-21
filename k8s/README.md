# k8s — raw manifests for `profolio-dev`

## What this directory is

A deliberate, **transitional** raw-manifest pass. The point is to write a
`volumeClaimTemplates` StatefulSet, a headless Service and per-Deployment
`imagePullSecrets` by hand once, so the abstractions Helm generates later aren't opaque.
It is not a long-term deployment mechanism: the Helm chart under `/charts` (next pass)
supersedes applying from here directly, though these files may seed its templates.

Every manifest sets `namespace: profolio-dev` explicitly. The namespace itself is already
provisioned and is not created here. Target cluster context: `beelink`.

| File | Contents |
| --- | --- |
| `postgres-statefulset.yaml` | headless Service + StatefulSet with a 1Gi PVC per pod |
| `backend-deployment.yaml` | backend Deployment (probe `/health`) + ClusterIP Service |
| `backend-migrate-job.yaml` | `alembic upgrade head` Job (reuses the backend image) |
| `frontend-configmap.yaml` | `BACKEND_URL` for the nginx templating |
| `frontend-deployment.yaml` | frontend Deployment (probe `GET /`) + ClusterIP Service |

## Secrets

Neither Secret is committed, and no value ever goes in git. Both are created imperatively
in the namespace. Between them, these are every Secret `profolio-dev` needs.

| Secret | Type | Keys | Used for |
| --- | --- | --- | --- |
| `ghcr-pull` | `kubernetes.io/dockerconfigjson` | `.dockerconfigjson` | pulling the private GHCR backend/frontend images (the migrate Job reuses the backend image) |
| `postgres-credentials` | `Opaque` | `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB`, `DATABASE_URL` | Postgres init, and app-to-DB auth |

`ghcr-pull` (already exists; command to recreate it). The PAT needs only `read:packages`:

```sh
kubectl --context beelink -n profolio-dev create secret docker-registry ghcr-pull \
  --docker-server=ghcr.io \
  --docker-username=<GITHUB_USERNAME> \
  --docker-password=<READ_PACKAGES_PAT>
```

`postgres-credentials`. `DATABASE_URL` must be consistent with the other three keys, and
`<PASSWORD>` must be URL-safe (or percent-encoded in the URL, but not in
`POSTGRES_PASSWORD`). The host is the headless Service name `postgres`:

```sh
kubectl --context beelink -n profolio-dev create secret generic postgres-credentials \
  --from-literal=POSTGRES_USER=<USER> \
  --from-literal=POSTGRES_PASSWORD=<PASSWORD> \
  --from-literal=POSTGRES_DB=<DB> \
  --from-literal=DATABASE_URL='postgresql+psycopg://<USER>:<PASSWORD>@postgres:5432/<DB>'
```

Note that Postgres only reads `POSTGRES_*` on first init of an empty volume. Changing the
Secret later does not change the password of an existing database.

## Apply order

```sh
# 1. secrets (above), then the database
kubectl --context beelink apply -f k8s/postgres-statefulset.yaml
kubectl --context beelink -n profolio-dev rollout status sts/postgres

# 2. schema
kubectl --context beelink apply -f k8s/backend-migrate-job.yaml
kubectl --context beelink -n profolio-dev logs job/backend-migrate

# 3. app
kubectl --context beelink apply -f k8s/backend-deployment.yaml \
  -f k8s/frontend-configmap.yaml -f k8s/frontend-deployment.yaml
```

Rerunning migrations: a Job's spec is immutable, so delete it first
(`kubectl -n profolio-dev delete job backend-migrate`), then apply again. `alembic upgrade head`
is idempotent, so this is safe.

## Seeding

`backend/seed.py` is a manual, dev-only step, run by hand once against a port-forwarded
Postgres (`kubectl -n profolio-dev port-forward sts/postgres 5432:5432`, then run it locally
with `DATABASE_URL` pointing at `localhost`). It is not in any image and not part of the
deploy path. Synthetic data only.

## Checking it worked

```sh
kubectl --context beelink -n profolio-dev get pods,pvc,svc
kubectl --context beelink -n profolio-dev port-forward svc/frontend 8080:80
```

`data-postgres-0` should be `Bound`, and `describe pod` on backend/frontend should show
the image pulled without pull errors.
