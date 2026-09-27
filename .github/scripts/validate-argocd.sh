#!/usr/bin/env bash
# Lint and schema-validate the Argo CD manifests under argocd/.
#   1. yamllint (config in .yamllint.yaml) over everything in argocd/.
#   2. kubeconform over the Application manifests, against a JSON Schema generated
#      from Argo CD's own Application CRD at the version the cluster runs.
#
# Needs yamllint and PyYAML (.github/ci/requirements.txt), python3, kubeconform, curl.
# Versions come from .github/ci/versions.env. Locally, run it with the Python tools:
#   uv run --no-project --with-requirements .github/ci/requirements.txt -- .github/scripts/validate-argocd.sh
set -euo pipefail
shopt -s globstar nullglob
cd "$(dirname "$0")/../.." # repo root, wherever this is run from

# shellcheck source=.github/ci/versions.env
source .github/ci/versions.env

: "${ARGOCD_VERSION:?missing from .github/ci/versions.env}"
: "${ARGOCD_CRD_SHA256:?missing from .github/ci/versions.env}"
: "${KUBECONFORM_VERSION:?missing from .github/ci/versions.env}"
: "${OPENAPI2JSONSCHEMA_SHA256:?missing from .github/ci/versions.env}"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

echo "::group::yamllint"
yamllint --strict argocd/
echo "::endgroup::"

# The CRD and the converter are fetched by tag, then checked against a pinned
# sha256 - so a moved tag fails the build instead of changing what we validate.
echo "::group::Application schema from Argo CD v${ARGOCD_VERSION}'s CRD"
curl -fsSLo "$work/application-crd.yaml" \
  "https://raw.githubusercontent.com/argoproj/argo-cd/v${ARGOCD_VERSION}/manifests/crds/application-crd.yaml"
echo "${ARGOCD_CRD_SHA256}  $work/application-crd.yaml" | sha256sum -c -
curl -fsSLo "$work/openapi2jsonschema.py" \
  "https://raw.githubusercontent.com/yannh/kubeconform/v${KUBECONFORM_VERSION}/scripts/openapi2jsonschema.py"
echo "${OPENAPI2JSONSCHEMA_SHA256}  $work/openapi2jsonschema.py" | sha256sum -c -
mkdir "$work/schemas"
# DENY_ROOT_ADDITIONAL_PROPERTIES also rejects unknown top-level keys (`specs:`),
# which the converter otherwise lets through. FILENAME_FORMAT must match the
# -schema-location template below.
(
  cd "$work/schemas"
  DENY_ROOT_ADDITIONAL_PROPERTIES=1 FILENAME_FORMAT='{kind}_{version}' \
    python3 "$work/openapi2jsonschema.py" "$work/application-crd.yaml"
)
echo "::endgroup::"

# Only the generated Argo CD schema is offered - no Kubernetes core schemas - so
# anything other than an Application under argocd/apps/ fails as "missing schema".
# argocd/values.yaml is Helm values for the argo-cd chart, not a manifest.
echo "::group::kubeconform"
kubeconform -strict -summary \
  -schema-location "$work/schemas/{{ .ResourceKind }}_{{ .ResourceAPIVersion }}.json" \
  argocd/root.yaml argocd/apps/**/*.yaml
echo "::endgroup::"
