#!/usr/bin/env bash
# Lint every Dockerfile tracked by git with hadolint. The list comes from git rather than
# being written out, so a new Dockerfile is linted without touching CI.
#
# hadolint's default rules and failure threshold (info): any finding fails. To accept one,
# put `# hadolint ignore=DLxxxx` on the line above it, with a comment saying why.
#
# Needs hadolint (version in .github/ci/versions.env) and git. A different local version
# still runs, with a warning.
set -euo pipefail
cd "$(dirname "$0")/../.." # repo root, wherever this is run from

# shellcheck source=../ci/versions.env
source .github/ci/versions.env
: "${HADOLINT_VERSION:?missing from .github/ci/versions.env}"

have=$(hadolint --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1)
if [[ $have != "$HADOLINT_VERSION" ]]; then
  echo "warning: hadolint $have here, CI pins $HADOLINT_VERSION" >&2
fi

# A failing git inside < <(...) doesn't trip set -e, so an empty list is treated as an
# error below rather than as "nothing to lint".
mapfile -t dockerfiles < <(git ls-files -- '*Dockerfile')
if ((${#dockerfiles[@]} == 0)); then
  echo "no Dockerfiles found - is this a git checkout?" >&2
  exit 1
fi

printf '%s\n' "${dockerfiles[@]}"
hadolint "${dockerfiles[@]}"
