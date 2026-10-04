# Bootstrap: from nothing to a running Profolio

Everything this system needs that is **not** in the repository: settings, tokens, Secrets
and the one-off commands that create them. If you cloned this repo and wanted it running on
your own GitHub account and your own cluster, this is the list.

Running the app on a laptop needs none of this; that is in the
[README](../README.md#setup).

**This is a living document.** A pull request that adds or changes a secret, a token, a
GitHub setting or a manual step updates this file in the same pull request.

> **Status: not yet rehearsed end to end.** Every step below was carried out when the system
> was built, but one at a time over several weeks, and the charts were first installed with
> Helm and adopted by Argo CD afterwards, not in the Argo-first order of section 3. Running
> this page top to bottom against an empty cluster is an open task. Expect to correct it
> when that happens.

## 1. What lives outside the repo

### On GitHub

| Thing | What it is for | Created in | To rotate or recreate |
| --- | --- | --- | --- |
| Secret scanning and push protection | Rejects a push that contains a recognisable credential | 2.2 | n/a |
| Auto-merge, delete branch on merge | Lets the bump pull request merge itself and tidies its branch | 2.2 | n/a |
| Ruleset `protect-main` | Pull requests only, squash only, `ci-ok` required on an up-to-date branch | 2.3 | Change `.github/rulesets/protect-main.json` in a PR, then `PUT` it |
| GitHub App (`profolio-dev-bump` here) | The identity that opens the bump pull request | 2.4 | n/a |
| App private key | Lets the workflow act as the App. Secret `BUMP_APP_PRIVATE_KEY` in the `dev-bump` environment | 2.4 | Generate a new key on the App's page, `gh secret set` again, delete the old key there |
| App client ID | Tells the token action which App. Variable `BUMP_APP_CLIENT_ID` in `dev-bump`; not secret | 2.4 | n/a |
| Environment `dev-bump` | Holds the two values above; only runs on `main` may use it | 2.4 | n/a |
| GHCR packages `profolio-backend`, `profolio-frontend` | The images, private | 2.5 | n/a |
| Token with `read:packages` | Lets the cluster pull the private images; stored in the cluster as `ghcr-pull` | 3.2 | New token, recreate the Secret. Note its expiry date somewhere you will see it |
| Deploy key, read-only | Lets Argo CD read this repository | 3.4 | New key pair; replace it under the repo's deploy keys and in Argo CD |

### In the cluster

| Secret | Namespace | Keys | Used by | Created in |
| --- | --- | --- | --- | --- |
| `ghcr-pull` | `profolio-dev` | `.dockerconfigjson` | backend, frontend and the migrate Job, to pull images | 3.2 |
| `postgres-credentials` | `profolio-dev` | `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB`, `DATABASE_URL` | Postgres on first start; the backend | 3.2 |
| `keycloak-db-credentials` | `keycloak` | `password` | Keycloak, to reach its database | 3.2 |
| `keycloak-admin-credentials` | `keycloak` | `KC_BOOTSTRAP_ADMIN_USERNAME`, `KC_BOOTSTRAP_ADMIN_PASSWORD` | Keycloak's first start | 3.2 |
| Repository credential | `argocd` | managed by `argocd repo add` | Argo CD, to read this repo | 3.4 |
| `argocd-initial-admin-secret` | `argocd` | `password` | The first Argo CD login | made by the Argo CD chart |

Every one of these exists only in the cluster. A Kubernetes Secret is base64-encoded, not
encrypted: anyone with the cluster's admin kubeconfig can read them all. Nothing backs them
up either, so losing the cluster means recreating them from this page. Keeping them in Git
in encrypted form is planned; see section 5.

Two things in the cluster are not Secrets but are also made by hand: Keycloak's database
and role inside Postgres (3.5), and the seed data (3.6).

## 2. GitHub

Commands use the [`gh` CLI](https://cli.github.com/), run from a clone of the repo.

### 2.1 If this is your own copy: names to change

The owner's name is written into a few files. Search for `charlieparker` (any case):

- `charts/backend/values.yaml`, `charts/frontend/values.yaml`: `image.repository`
- `.github/workflows/deploy-dev.yml`: the `IMAGE` variable (must be lowercase)
- `argocd/root.yaml` and every file under `argocd/apps/`: `repoURL`
- `backend/app/routers/version.py`: `REPO_URL`, and the URL its test expects
- both `Dockerfile`s: the `org.opencontainers.image.source` label

`image.tag` and `image.digest` in `charts/*/values-dev.yaml` point at images in the original
owner's private registry. Leave them; step 2.5 replaces them with yours.

### 2.2 Repository settings

```sh
gh api --method PATCH repos/<owner>/profolio \
  -f 'security_and_analysis[secret_scanning][status]=enabled' \
  -f 'security_and_analysis[secret_scanning_push_protection][status]=enabled'
gh repo edit --enable-auto-merge --delete-branch-on-merge
```

### 2.3 Branch ruleset

```sh
gh api --method POST repos/<owner>/profolio/rulesets \
  --input .github/rulesets/protect-main.json
```

To change it later, edit the JSON in a pull request and apply it with
`gh api --method PUT repos/<owner>/profolio/rulesets/<id> --input <file>`. The file is a
record, not automation: nothing applies it for you.

The ruleset requires a check named `ci-ok` reported by GitHub Actions
(`integration_id` 15368). Until `ci.yml` has run on a pull request, that check shows as
"Expected".

### 2.4 The bump App and its environment

`deploy-dev.yml` opens a pull request after each build. It needs its own identity, because
a pull request opened with the workflow's built-in token does not start `ci.yml`.

1. **Create a GitHub App** (Settings → Developer settings → GitHub Apps → New):
   - any unique name, and any homepage URL;
   - Webhook: untick "Active";
   - Repository permissions: **Contents: Read and write**, **Pull requests: Read and
     write**. Leave everything else at "No access". Without the Workflows permission,
     GitHub rejects any push from the App that changes a workflow file;
   - installable "Only on this account".
2. **Install it** on this repository only (Install App → Only select repositories).
3. **Generate a private key** on the App's page. A `.pem` file downloads.
4. **Create the environment** `dev-bump` (repo Settings → Environments). Under "Deployment
   branches and tags" choose "Selected branches and tags" and add `main`. A repository-level
   secret can be read by a workflow on any branch; this one is released only to code that
   has already merged.
5. **Store the key and the client ID**, then delete the `.pem`:

   ```sh
   gh secret set BUMP_APP_PRIVATE_KEY --env dev-bump < <path-to-key>.pem
   gh variable set BUMP_APP_CLIENT_ID --env dev-bump --body "<client id from the App's page>"
   ```

The App's name is not written anywhere in the workflow; the job reads it from the token.

### 2.5 First images

```sh
gh workflow run deploy-dev.yml
```

A manual run builds both images, pushes them to GHCR tagged with the commit, and opens the
pull request that sets `image.tag` and `image.digest`. It merges itself once `ci-ok` passes.

Check each package afterwards (your profile → Packages): it should be private and linked to
this repository. If you pushed images by hand before the first run, link each package to
the repository yourself and give the repository **Write** under the package's "Manage
Actions access"; otherwise the workflow's push is refused.

## 3. Cluster

### 3.1 Before you start

- A Kubernetes cluster and an admin kubeconfig for it. This project runs on a single-node
  [k3s](https://k3s.io/); installing that is outside this repo.
- On your machine: `kubectl`, `helm`, the `argocd` CLI and `gh`. Versions that matter are in
  [`.github/ci/versions.env`](../.github/ci/versions.env) and
  [`argocd/values.yaml`](../argocd/values.yaml).

### 3.2 Namespaces and Secrets

Create these before Argo CD deploys anything, so the first pods find them.

```sh
kubectl create namespace profolio-dev
kubectl create namespace keycloak
```

`ghcr-pull` and `postgres-credentials`: the commands, and the rules the values must follow,
are in [`k8s/README.md`](../k8s/README.md#secrets). The token for `ghcr-pull` needs only
`read:packages`.

Keycloak's two, in its own namespace. Choose `<KEYCLOAK_DB_PASSWORD>` now; step 3.5 uses the
same value.

```sh
kubectl -n keycloak create secret generic keycloak-db-credentials \
  --from-literal=password='<KEYCLOAK_DB_PASSWORD>'
kubectl -n keycloak create secret generic keycloak-admin-credentials \
  --from-literal=KC_BOOTSTRAP_ADMIN_USERNAME=admin \
  --from-literal=KC_BOOTSTRAP_ADMIN_PASSWORD='<KEYCLOAK_ADMIN_PASSWORD>'
```

Never reuse the local-development credentials from `docker-compose.yml`. They are public.

### 3.3 Install Argo CD

```sh
helm repo add argo https://argoproj.github.io/argo-helm
helm install argocd argo/argo-cd --version 10.9.2 \
  -n argocd --create-namespace -f argocd/values.yaml
```

This is the one Helm release in the system. Everything else is deployed by Argo CD.

### 3.4 Give Argo CD the repository, then the root Application

```sh
# a key pair used only for this; the public half goes on the repo, read-only
ssh-keygen -t ed25519 -N "" -C argocd -f <path>/argocd-deploy-key
gh repo deploy-key add <path>/argocd-deploy-key.pub --title argocd

# log in to Argo CD through a port-forward (leave it running in another terminal)
kubectl -n argocd port-forward svc/argocd-server 8443:443
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d
argocd login localhost:8443 --username admin --insecure

# the private half goes to Argo CD, then delete the local copy
argocd repo add git@github.com:<owner>/profolio.git \
  --ssh-private-key-path <path>/argocd-deploy-key

kubectl apply -f argocd/root.yaml
```

`argocd/root.yaml` is the only manifest applied by hand. It points Argo CD at
`argocd/apps/`, and Argo CD creates the four Applications there and deploys their charts.

The backend runs its database migration before each sync. If its first sync fails because
Postgres was not ready yet, sync it again: `argocd app sync profolio-dev-backend`.

### 3.5 Keycloak's database

Keycloak shares the app's Postgres instance but has its own role and database, created once
by hand after `postgres-0` is Ready:

```sh
kubectl -n profolio-dev exec postgres-0 -- \
  psql -U <POSTGRES_USER> -d <POSTGRES_DB> -c \
  "CREATE ROLE keycloak WITH LOGIN PASSWORD '<KEYCLOAK_DB_PASSWORD>';"
kubectl -n profolio-dev exec postgres-0 -- \
  psql -U <POSTGRES_USER> -d <POSTGRES_DB> -c \
  "CREATE DATABASE keycloak OWNER keycloak;"
```

Keycloak restarts until this exists, then comes up by itself.

### 3.6 Seed data and a first look

Seeding is a manual, development-only step with synthetic data; see
[`k8s/README.md`](../k8s/README.md#seeding).

```sh
kubectl -n profolio-dev get pods,pvc,svc,jobs
kubectl -n keycloak get pods
kubectl -n profolio-dev port-forward svc/frontend 8080:80
```

Then open `http://localhost:8080`. `http://localhost:8080/api/version` reports the commit
the running backend image was built from.

## 4. The workflows, and what each one depends on

| Workflow | Runs on | Needs from this page |
| --- | --- | --- |
| `ci.yml` | every pull request | Nothing. It uses only the built-in token, read-only |
| `deploy-dev.yml`, `build` job | every merge to `main`; manual run | The GHCR packages accepting pushes from this repository (2.5) |
| `deploy-dev.yml`, `bump` job | after `build` | The App, the `dev-bump` environment and its two values (2.4); auto-merge (2.2); the ruleset (2.3) |

How the workflows work inside is in [`.github/ci/README.md`](../.github/ci/README.md).

## 5. Known gaps

- **This page has not been run from scratch.** See the status note at the top.
- **Secrets are created by hand and exist only in the cluster.** The planned fix is to keep
  them in Git in encrypted form, so that a rebuild needs one key and not this whole list.
- **No backups.** The database holds synthetic data only, so nothing irreplaceable is lost
  with the cluster. That changes the day real data goes in.
- **No ingress.** The app, Argo CD and Keycloak are reached with `kubectl port-forward`.
- **Argo CD uses its local admin account.** Single sign-on through Keycloak is planned.
- **Tokens expire.** The `read:packages` token behind `ghcr-pull` has an expiry date, and
  image pulls fail on a new node once it passes. Nothing warns you.
