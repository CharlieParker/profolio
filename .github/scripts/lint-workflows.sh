#!/usr/bin/env bash
# Lint the CI's own code:
#   1. actionlint over .github/workflows/ (it finds the files itself). If shellcheck is
#      on PATH, actionlint also runs it over every `run:` block; if not, it silently
#      skips that, so this script refuses to run without it.
#   2. shellcheck over the scripts CI and the git hooks run. Settings: .shellcheckrc.
#
# Needs actionlint and shellcheck, at the versions in .github/ci/versions.env. A different
# local version still runs, with a warning: newer linters add rules, so results can differ.
set -euo pipefail
shopt -s nullglob
cd "$(dirname "$0")/../.." # repo root, wherever this is run from

# shellcheck source=../ci/versions.env
source .github/ci/versions.env
: "${ACTIONLINT_VERSION:?missing from .github/ci/versions.env}"
: "${SHELLCHECK_VERSION:?missing from .github/ci/versions.env}"

if ! command -v shellcheck >/dev/null; then
  echo "shellcheck is not on PATH; actionlint would silently skip checking run: blocks" >&2
  exit 1
fi

have=$(actionlint -version | head -n1)
if [[ $have != "$ACTIONLINT_VERSION" ]]; then
  echo "warning: actionlint $have here, CI pins $ACTIONLINT_VERSION" >&2
fi
have=$(shellcheck --version | sed -n 's/^version: //p')
if [[ $have != "$SHELLCHECK_VERSION" ]]; then
  echo "warning: shellcheck $have here, CI pins $SHELLCHECK_VERSION" >&2
fi

echo "::group::actionlint"
actionlint
echo "::endgroup::"

scripts=(.github/scripts/*.sh .githooks/*)
echo "::group::shellcheck"
printf '%s\n' "${scripts[@]}"
shellcheck "${scripts[@]}"
echo "::endgroup::"
