# CI: how it fits together

Two workflows live here. Every pull request runs [`../workflows/ci.yml`](../workflows/ci.yml),
which checks the change. Every merge to `main` runs
[`../workflows/deploy-dev.yml`](../workflows/deploy-dev.yml), which builds the images and
points the dev environment at them. This page explains the files behind both, where each
version pin lives, what isn't pinned, and how to run the same checks locally.

It lives in `.github/ci/` rather than `.github/` on purpose: GitHub shows a
`.github/README.md` on the repository's front page in place of the one at the root.

## The files

| Path | What it is |
| --- | --- |
| `.github/workflows/ci.yml` | The PR workflow: decides which jobs a PR needs, runs them, reports one result |
| `.github/workflows/deploy-dev.yml` | The merge workflow: builds and pushes the changed images, then opens the pull request that deploys them to dev |
| `.github/scripts/validate-charts.sh` | Lints, renders and schema-checks every chart the way Argo CD deploys it |
| `.github/scripts/validate-argocd.sh` | yamllint, then schema-checks the Argo CD Applications against Argo's own CRD |
| `.github/scripts/lint-workflows.sh` | actionlint over the workflows, shellcheck over the CI scripts and git hooks |
| `.github/scripts/lint-dockerfiles.sh` | hadolint over every Dockerfile git tracks |
| `.github/scripts/bump-values.sh` | Writes an image's tag and digest into its chart's `values-dev.yaml`, unless the digest is already the pinned one |
| `.github/scripts/load-versions.sh` | CI only: loads `versions.env` into the rest of a job |
| `.github/ci/versions.env` | Versions and checksums for tools CI downloads directly |
| `.github/ci/requirements.in` / `.txt` | Python tools for CI; the `.txt` is generated, with hashes |
| `.github/rulesets/protect-main.json` | Record of the branch protection on `main` |
| `.yamllint.yaml` | yamllint rules (repo root, where yamllint looks for it) |
| `.shellcheckrc` | shellcheck settings: follow `source`d files, resolve `source=` hints from the script's directory |

Checks live in scripts rather than inline in the workflow so they can be run locally, exactly
as CI runs them.

## How a pull request is checked

1. `changes` looks at which files the PR touches and decides which jobs are needed.
2. The needed jobs run in parallel, each on a fresh runner. Jobs that aren't needed are skipped.
3. `ci-ok` fails if any job failed or was cancelled. It is the only required check, so a
   skipped job never blocks a merge.

Adding a job means three edits to `ci.yml`: a path filter in `changes`, the job, and an entry
in `ci-ok`'s `needs:`. The ruleset doesn't change.

## How a merge reaches dev

1. `changes` works out which images the merged commit affects. A commit that touches
   neither `backend/`, `frontend/` nor the workflow itself builds nothing, and the run ends.
2. `build` builds each affected image and pushes it to GHCR, tagged with the full commit SHA.
3. `bump` asks the registry for each new image's digest and writes tag and digest into
   `charts/<image>/values-dev.yaml`. An image whose digest hasn't changed is left alone.
4. If anything changed, `bump` opens a pull request as the `profolio-dev-bump` GitHub App
   and turns on auto-merge. `ci.yml` checks it like any other pull request, and GitHub
   merges it once `ci-ok` passes. The App cannot bypass the ruleset.
5. Argo CD sees the new commit on `main` and rolls the image out.

The bump pull request only touches `charts/`, so its own merge stops at step 1: that is
what keeps the workflow from triggering itself in a loop.

The App may write contents and pull requests in this repository and nothing else; without
the Workflows permission, GitHub rejects any push from it that changes a workflow file. Its
private key is a secret in the `dev-bump` environment, which only runs on `main` can use.

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

## What isn't pinned

"Everything is pinned" has limits, and these are the known ones:

- **The runner image.** Jobs run on `ubuntu-24.04`, which names an image GitHub rebuilds
  about weekly. The basics every job leans on come from it unpinned: `bash`, `git`, `curl`,
  `tar`, `sha256sum`, `python3` and the Docker engine.
- **`gh`, the GitHub CLI**, in `deploy-dev.yml`'s `bump` job. It opens the pull request,
  turns on auto-merge and waits for the merge, using whatever version the runner image has.
  This is the one tool whose behaviour a job depends on that is taken from the image. It
  only calls GitHub's own API, and a change in it would show up as a failed `bump` job
  rather than a wrong deployment.
- **`docker buildx imagetools`**, in the same job, reads a digest from the registry using
  the runner's Docker. `bump-values.sh` checks the answer looks like a digest before using it.

## Run the checks locally

From anywhere in the repo, with `helm`, `kubeconform`, `yq` (mikefarah v4), `uv`,
`actionlint`, `shellcheck` and `hadolint` installed:

```sh
.github/scripts/validate-charts.sh
uv run --no-project --with-requirements .github/ci/requirements.txt -- .github/scripts/validate-argocd.sh
.github/scripts/lint-workflows.sh
.github/scripts/lint-dockerfiles.sh
```

Install the versions in `versions.env`: the linters add rules between releases, and yq
decides which charts get rendered. The lint scripts and `validate-charts.sh` warn if yours
differ. `lint-workflows.sh` refuses to run without shellcheck, because
actionlint would otherwise skip checking `run:` blocks without saying so.

Versions come from `versions.env`; no environment variables needed. A local Helm that differs
from Argo CD's is fine for a quick check; CI uses Argo's.

## Upgrading Argo CD

The Argo CD block in `versions.env` moves together:

1. Set `ARGOCD_VERSION`, and `ARGOCD_CRD_SHA256` to the sha256 of
   `manifests/crds/application-crd.yaml` in the argo-cd repo at that tag.
2. Set `HELM_VERSION` to the Helm that release bundles (`hack/tool-versions.sh` at the same
   tag) and `HELM_SHA256` from `https://get.helm.sh/helm-v<version>-linux-amd64.tar.gz.sha256sum`.
3. Run both scripts locally, then open a PR.
