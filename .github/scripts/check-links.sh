#!/usr/bin/env bash
# Check the links between files in this repo with lychee. In every Markdown file git
# tracks, a link to another file must point at a file that exists, and a link to a heading
# (`#anchor`, in the same file or another Markdown file) at a heading that exists.
#
# External URLs are NOT checked: lychee runs offline and skips them, so a dead https://
# link passes. Checking those is listed in docs/roadmap.md.
#
# The file list comes from git rather than from pointing lychee at the directory, which
# would skip hidden directories (.github/ci/README.md) and pick up untracked files.
#
# Needs lychee (version in .github/ci/versions.env) and git. A different local version
# still runs, with a warning.
set -euo pipefail
cd "$(dirname "$0")/../.." # repo root, wherever this is run from

# shellcheck source=../ci/versions.env
source .github/ci/versions.env
: "${LYCHEE_VERSION:?missing from .github/ci/versions.env}"

have=$(lychee --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1)
if [[ $have != "$LYCHEE_VERSION" ]]; then
  echo "warning: lychee $have here, CI pins $LYCHEE_VERSION" >&2
fi

# A failing git inside < <(...) doesn't trip set -e, so an empty list is treated as an
# error below rather than as "nothing to check".
mapfile -t files < <(git ls-files -- '*.md')
if ((${#files[@]} == 0)); then
  echo "no Markdown files found - is this a git checkout?" >&2
  exit 1
fi

printf '%s\n' "${files[@]}"
echo "Checking links between files in this repo only. External URLs are skipped, not checked."

# --offline             local files only; external URLs are reported as "Excluded"
# --include-fragments   also check the #anchor part of a link against the target's headings
# --root-dir            resolve links that start with / from the repo root, as GitHub does
# --no-progress, --mode plain   no progress bar or colour codes in CI logs
lychee --offline --include-fragments --root-dir "$PWD" --no-progress --mode plain -- "${files[@]}"
