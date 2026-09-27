#!/usr/bin/env bash
# Load .github/ci/versions.env into the rest of a GitHub Actions job, via $GITHUB_ENV.
# Locally there's nothing to load: the validate-*.sh scripts source the file themselves.
#
# versions.env is read both by bash and by Actions, so first check every line is
# something both read the same way: a # comment, a blank line, or KEY=value with no
# spaces, quotes or trailing comment.
set -euo pipefail
cd "$(dirname "$0")/../.."

file=.github/ci/versions.env
if bad=$(grep -nvE '^(#.*)?$|^[A-Z][A-Z0-9_]*=[A-Za-z0-9._/-]+$' "$file"); then
  echo "::error file=$file::not a comment or a plain KEY=value line: $bad"
  exit 1
fi
grep -E '^[A-Z]' "$file" >> "${GITHUB_ENV:?GITHUB_ENV is unset - this script is for GitHub Actions}"
