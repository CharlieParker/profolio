# CI: how it fits together

Every pull request runs [`../workflows/ci.yml`](../workflows/ci.yml). This page explains the
files behind it, where each version pin lives, and how to run the same checks locally.

## The files

| Path | What it is |
| --- | --- |
| `.github/workflows/ci.yml` | The PR workflow: decides which jobs a PR needs, runs them, reports one result |
| `.github/scripts/validate-charts.sh` | Lints, renders and schema-checks every chart the way Argo CD deploys it |
| `.github/scripts/validate-argocd.sh` | yamllint, then schema-checks the Argo CD Applications against Argo's own CRD |
| `.github/scripts/load-versions.sh` | CI only: loads `versions.env` into the rest of a job |
| `.github/ci/versions.env` | Versions and checksums for tools CI downloads directly |
| `.github/ci/requirements.in` / `.txt` | Python tools for CI; the `.txt` is generated, with hashes |
| `.github/rulesets/protect-main.json` | Record of the branch protection on `main` |
| `.yamllint.yaml` | yamllint rules (repo root, where yamllint looks for it) |

Checks live in scripts rather than inline in the workflow so they can be run locally, exactly
as CI runs them.

## How a pull request is checked

1. `changes` looks at which files the PR touches and decides which jobs are needed.
2. The needed jobs run in parallel, each on a fresh runner. Jobs that aren't needed are skipped.
3. `ci-ok` fails if any job failed or was cancelled. It is the only required check, so a
   skipped job never blocks a merge.

Adding a job means three edits to `ci.yml`: a path filter in `changes`, the job, and an entry
in `ci-ok`'s `needs:`. The ruleset doesn't change.

## Where each pin lives

Everything CI uses is pinned to an exact version, and the pin is checked by a hash where one
exists. **Each pin lives where the tool that updates it can find it:**

| Pin | Kept current by | Lives in |
| --- | --- | --- |
| Actions (`uses:`) | Dependabot, `github-actions` ecosystem | the `uses:` line: `owner/repo@<commit sha> # vX.Y.Z` |
| Python tools | Dependabot, `pip` ecosystem | `requirements.txt`, generated from `requirements.in` |
| Downloaded binaries, CRDs, schemas | nobody: bump by hand | `versions.env` |

- **Actions** are pinned to a full commit SHA because tags can be moved; the trailing comment
  is the convention Dependabot reads and rewrites. `uses:` can't take variables, so these
  can't be centralised, and don't need to be.
- **Python tools** are installed with `pip install --require-hashes`, so every package,
  including dependencies, must match a recorded hash. To change a version, edit
  `requirements.in` and regenerate:

  ```sh
  uv pip compile --generate-hashes --python-version 3.12 .github/ci/requirements.in -o .github/ci/requirements.txt
  ```

- **`versions.env`** holds everything no bot tracks. Each download is checked against its
  sha256, so a changed file fails the build. Both the scripts (`source`) and CI (via
  `load-versions.sh`) read it, so it must stay plain `KEY=value` lines and `#` comments;
  `load-versions.sh` fails the job if it isn't.

## Run the checks locally

From anywhere in the repo, with `helm`, `kubeconform`, `yq` (mikefarah v4) and `uv` installed:

```sh
.github/scripts/validate-charts.sh
uv run --no-project --with-requirements .github/ci/requirements.txt -- .github/scripts/validate-argocd.sh
```

Versions come from `versions.env`; no environment variables needed. A local Helm that differs
from Argo CD's is fine for a quick check; CI uses Argo's.

## Upgrading Argo CD

The Argo CD block in `versions.env` moves together:

1. Set `ARGOCD_VERSION`, and `ARGOCD_CRD_SHA256` to the sha256 of
   `manifests/crds/application-crd.yaml` in the argo-cd repo at that tag.
2. Set `HELM_VERSION` to the Helm that release bundles (`hack/tool-versions.sh` at the same
   tag) and `HELM_SHA256` from `https://get.helm.sh/helm-v<version>-linux-amd64.tar.gz.sha256sum`.
3. Run both scripts locally, then open a PR.
