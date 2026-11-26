#!/usr/bin/env bash
# Refuses a release unless the tag is exactly `v` plus the version in
# crosslint.usage.kdl, and that version is three plain integers starting
# with 0 and a dot, with no prerelease form and no build metadata.
#
#   check-release-tag.sh TAG

set -eu

tag=${1:?usage: check-release-tag.sh TAG}
version=$("$(dirname "$0")/spec-version.sh")

if ! [[ "$version" =~ ^0\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
  echo "check-release-tag.sh: version '$version' in crosslint.usage.kdl is not 0.X.Y with plain integers" >&2
  exit 1
fi
if [ "$tag" != "v$version" ]; then
  echo "check-release-tag.sh: tag '$tag' is not 'v$version', the version in crosslint.usage.kdl" >&2
  exit 1
fi
echo "check-release-tag.sh: $tag matches crosslint.usage.kdl"
