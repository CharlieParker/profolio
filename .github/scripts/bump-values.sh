#!/usr/bin/env bash
# Point dev at the images built from one commit. For each image named, look up the digest
# its <sha> tag has in the registry and write tag + digest into
# charts/<image>/values-dev.yaml. An image whose digest is already the pinned one is left
# alone, tag included: the bytes are the same, and a tag-only change would still restart
# its pods.
#
# It only edits files. Committing, pushing and opening the PR are the workflow's job, so
# this is safe to run locally: `git diff` shows the result, `git restore charts/` undoes it.
#
# Usage:  .github/scripts/bump-values.sh <full commit sha> <image>...
#   e.g.  .github/scripts/bump-values.sh "$(git rev-parse HEAD)" backend frontend
#
# Needs yq (mikefarah v4, at the version in .github/ci/versions.env; a different local
# version still runs, with a warning) and docker buildx, logged in to the registry with
# read access to the packages.
set -euo pipefail
cd "$(dirname "$0")/../.." # repo root, wherever this is run from

# shellcheck source=../ci/versions.env
source .github/ci/versions.env
: "${YQ_VERSION:?missing from .github/ci/versions.env}"

yq_version=$(yq --version 2>&1 || true)
if [[ $yq_version != *mikefarah* ]]; then
  echo "::error::needs mikefarah's yq (v4, Go); found: ${yq_version:-nothing}"
  exit 1
fi
if [[ $yq_version != *" v${YQ_VERSION}" ]]; then
  echo "warning: $yq_version here, CI pins $YQ_VERSION" >&2
fi

if (($# < 2)); then
  echo "usage: $0 <full commit sha> <image>..." >&2
  exit 1
fi
sha=$1
shift
if [[ ! $sha =~ ^[0-9a-f]{40}$ ]]; then
  echo "::error::not a full 40-character commit sha: $sha"
  exit 1
fi

changed=()
for image in "$@"; do
  values=charts/$image/values-dev.yaml
  if [[ ! $image =~ ^[a-z0-9-]+$ || ! -f $values ]]; then
    echo "::error::no $values - '$image' is not a chart with a dev overlay"
    exit 1
  fi

  # The chart knows where its image lives, so the name is written in one place.
  repository=$(yq '.image.repository' "charts/$image/values.yaml")
  if [[ $repository == null ]]; then
    echo "::error::charts/$image/values.yaml has no image.repository"
    exit 1
  fi
  ref="$repository:$sha"

  # Ask the registry rather than the build job: it is what the cluster will pull from, and
  # a tag that isn't there fails here instead of in a pod. `.Manifest` is the descriptor
  # the tag points at; its digest is what a pull of this tag would resolve to.
  new=$(docker buildx imagetools inspect "$ref" --format '{{json .Manifest}}' | yq -p json '.digest')
  if [[ ! $new =~ ^sha256:[0-9a-f]{64}$ ]]; then
    echo "::error::unexpected digest for $ref: $new"
    exit 1
  fi

  current=$(yq '.image.digest' "$values")
  if [[ $new == "$current" ]]; then
    echo "$image: $ref is the digest already pinned - left alone"
    continue
  fi

  # strenv() passes the values in as strings, so nothing in them is read as yq syntax.
  TAG=$sha DIGEST=$new yq -i '.image.tag = strenv(TAG) | .image.digest = strenv(DIGEST)' "$values"
  echo "$image: $current -> $new (tag $sha)"
  changed+=("$image")
done

# For the workflow: the images that moved, space-separated. Empty means nothing to commit.
if [[ -n ${GITHUB_OUTPUT:-} ]]; then
  echo "changed=${changed[*]}" >> "$GITHUB_OUTPUT"
fi
