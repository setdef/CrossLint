#!/usr/bin/env bash
# Prints the version in crosslint.usage.kdl, which is the version of every
# release archive.

set -eu

root=$(cd "$(dirname "$0")/../.." && pwd)
version=$(sed -n 's/^version "\(.*\)"$/\1/p' "$root/crosslint.usage.kdl")
case "$version" in
  "" | *'
'*) echo "spec-version.sh: crosslint.usage.kdl has no single top-level version line" >&2; exit 1 ;;
esac
echo "$version"
