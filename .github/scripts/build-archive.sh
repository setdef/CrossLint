#!/usr/bin/env bash
# Builds the app with Fledge on this computer and packs it as
# OUTPUT_DIR/crosslint-VERSION-PLATFORM.tar.gz, or .zip on Windows.
#
#   build-archive.sh PLATFORM OUTPUT_DIR
#
# PLATFORM is macos-aarch64, linux-x86_64, or windows-x86_64. Run it from a
# fresh checkout, with the Ruby and tools mise.toml pins on PATH: Fledge
# packs the whole project folder, so a folder that ran the tests would
# carry coverage/ into the archive. The bundle goes outside the checkout
# for the same reason, unless BUNDLE_PATH says where.

set -eu

platform=${1:?usage: build-archive.sh PLATFORM OUTPUT_DIR}
output=${2:?usage: build-archive.sh PLATFORM OUTPUT_DIR}
case "$platform" in
  macos-aarch64 | linux-x86_64) extension=tar.gz ;;
  windows-x86_64) extension=zip ;;
  *) echo "build-archive.sh: unknown platform $platform" >&2; exit 2 ;;
esac

root=$(cd "$(dirname "$0")/../.." && pwd)
version=$("$root/.github/scripts/spec-version.sh")
cd "$root"

if [ -e coverage ] || [ -e build/dist ]; then
  echo "build-archive.sh: coverage/ or build/dist exists in $root; build from a fresh checkout" >&2
  exit 1
fi

export BUNDLE_WITHOUT=${BUNDLE_WITHOUT:-check}
export BUNDLE_PATH=${BUNDLE_PATH:-${TMPDIR:-/tmp}/crosslint-bundle}
bundle install
bundle exec rake build

set -- build/dist/*."$extension"
if [ "$#" -ne 1 ] || [ ! -f "$1" ]; then
  echo "build-archive.sh: expected one build/dist/*.$extension, found: $*" >&2
  exit 1
fi

mkdir -p "$output"
name="crosslint-$version-$platform.$extension"
cp "$1" "$output/$name"
echo "build-archive.sh: wrote $output/$name"
