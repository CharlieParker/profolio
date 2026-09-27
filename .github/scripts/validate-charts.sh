#!/usr/bin/env bash
# Lint, render and schema-validate every chart the way Argo CD deploys it.
# The list of charts comes from the Argo CD Applications under argocd/apps/,
# so a new chart is picked up by adding its Application - nothing to edit here.
#
# Needs helm (the version Argo CD bundles), kubeconform and yq (mikefarah v4).
# In CI, yq is the copy pre-installed on the runner image and is NOT pinned: it
# moves when GitHub updates ubuntu-24.04 (weekly-ish). The expressions below use
# only long-stable yq v4 features, so a minor bump shouldn't matter; if an image
# update ever breaks this, pin yq with a checksum-verified download like helm.
# Locally, the Python `yq` (a jq wrapper) is a different tool and won't work.
#
# Versions come from .github/ci/versions.env. Run:  .github/scripts/validate-charts.sh
set -euo pipefail
shopt -s globstar nullglob
cd "$(dirname "$0")/../.." # repo root, wherever this is run from

# shellcheck source=.github/ci/versions.env
source .github/ci/versions.env

: "${KUBE_VERSION:?missing from .github/ci/versions.env}"
: "${SCHEMA_REF:?missing from .github/ci/versions.env}"
schema="https://raw.githubusercontent.com/yannh/kubernetes-json-schema/${SCHEMA_REF}/{{ .NormalizedKubernetesVersion }}-standalone{{ .StrictSuffix }}/{{ .ResourceKind }}{{ .KindSuffix }}.json"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

apps=(argocd/apps/**/*.yaml)
if [ "${#apps[@]}" -eq 0 ]; then
  echo "::error::no Application manifests found under argocd/apps/"
  exit 1
fi

# 1. Fail on Application options this script doesn't reproduce, rather than
#    quietly validating something different from what Argo renders.
unsupported=$(yq -N 'select(.kind == "Application" and (.spec.sources or .spec.source.helm.values or .spec.source.helm.valuesObject or .spec.source.helm.parameters or .spec.source.helm.fileParameters)) | filename' "${apps[@]}")
if [ -n "$unsupported" ]; then
  echo "::error::these Applications use a source or Helm option this script doesn't mirror - extend it: $unsupported"
  exit 1
fi

# 2. One tab-separated line per chart-backed Application:
#    chart path, release name (Argo defaults it to the Application name), namespace, value files.
yq -N 'select(.kind == "Application" and (.spec.source.path // "" | test("^charts/")))
  | [.spec.source.path,
     .spec.source.helm.releaseName // .metadata.name,
     .spec.destination.namespace,
     (.spec.source.helm.valueFiles // [] | join(","))]
  | @tsv' "${apps[@]}" > "$work/charts.tsv"

# 3. Every chart must be deployed by at least one Application.
orphans=0
for chart_yaml in charts/*/Chart.yaml; do
  dir=${chart_yaml%/Chart.yaml}
  if ! cut -f1 "$work/charts.tsv" | grep -qxF "$dir"; then
    echo "::error::$dir has no Argo CD Application under argocd/apps/"
    orphans=1
  fi
done
[ "$orphans" -eq 0 ]

# 4. Fetch subchart dependencies at the versions and digests in each Chart.lock.
#    helm needs every http(s) repository added first; oci:// needs no repo.
for lock in charts/*/Chart.lock; do
  while read -r repo; do
    case "$repo" in
      http://* | https://*)
        helm repo add "dep-$(printf '%s' "$repo" | sha256sum | cut -c1-8)" "$repo" >/dev/null
        ;;
    esac
  done < <(yq '.dependencies[].repository' "$lock" | sort -u)
  helm dependency build "${lock%/Chart.lock}"
done

# 5. Lint, render and validate each Application's chart. fd 3 keeps the loop's
#    input separate from stdin, so nothing inside the loop can swallow the list.
while IFS=$'\t' read -r path release ns files <&3; do
  args=("$path" --kube-version "$KUBE_VERSION")
  IFS=, read -ra value_files <<< "$files"
  for f in "${value_files[@]}"; do
    args+=(-f "$path/$f")
  done
  echo "::group::$release ($path -> $ns)"
  helm lint --strict "${args[@]}"
  helm template "$release" "${args[@]}" --namespace "$ns" \
    | kubeconform -strict -summary -kubernetes-version "$KUBE_VERSION" -schema-location "$schema"
  echo "::endgroup::"
done 3< "$work/charts.tsv"
