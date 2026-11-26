#!/usr/bin/env bash
# Unpacks a release archive and runs `crosslint --version` and
# `crosslint --help` from it, with an empty folder as PATH, so that any
# Ruby installed on this computer is out of reach. Fails when either
# exits with a status other than 0, when --version doesn't print `crosslint`
# and the version in crosslint.usage.kdl, or when the first line of --help
# isn't the name and version there ("CrossLint 0.1.0").
#
#   smoke-archive.sh ARCHIVE
#
# Needs no Ruby and no mise.

set -eu

archive=${1:?usage: smoke-archive.sh ARCHIVE}
case "$archive" in /* | [A-Za-z]:*) ;; *) archive=$PWD/$archive ;; esac
[ -f "$archive" ] || { echo "smoke-archive.sh: no file $archive" >&2; exit 1; }

version=$("$(dirname "$0")/spec-version.sh")
name=$(sed -n 's/^name "\(.*\)"$/\1/p' "$(dirname "$0")/../../crosslint.usage.kdl")
case "$name" in
  "" | *'
'*) echo "smoke-archive.sh: crosslint.usage.kdl has no single top-level name line" >&2; exit 1 ;;
esac
work=$(mktemp -d "${TMPDIR:-/tmp}/crosslint-smoke.XXXXXX")
trap 'rm -rf "$work"' EXIT
mkdir "$work/unpacked" "$work/empty"

case "$archive" in
  *.tar.gz) tar -xzf "$archive" -C "$work/unpacked" ;;
  *.zip)
    powershell.exe -NoProfile -NonInteractive -Command \
      "Expand-Archive -LiteralPath '$(cygpath -w "$archive")' -DestinationPath '$(cygpath -w "$work/unpacked")'" ;;
  *) echo "smoke-archive.sh: $archive is neither .tar.gz nor .zip" >&2; exit 2 ;;
esac

program=
for candidate in "$work"/unpacked/*/crosslint "$work"/unpacked/*/crosslint.exe; do
  [ -f "$candidate" ] && program=$candidate
done
[ -n "$program" ] || { echo "smoke-archive.sh: no crosslint program in $archive" >&2; exit 1; }

# Runs the program with an empty PATH, printing what it prints.
run() {
  local output status=0
  output=$(env PATH="$work/empty" "$program" "$@" 2>&1) || status=$?
  if [ "$status" -ne 0 ]; then
    echo "smoke-archive.sh: crosslint $* exited with $status:" >&2
    echo "$output" >&2
    return 1
  fi
  printf '%s\n' "$output"
}

printed=$(run --version)
if [ "$printed" != "crosslint $version" ]; then
  echo "smoke-archive.sh: crosslint --version printed '$printed', expected 'crosslint $version'" >&2
  exit 1
fi
echo "crosslint --version: $printed"

run --help > "$work/help.txt"
first=$(head -n 1 "$work/help.txt")
if [ "$first" != "$name $version" ]; then
  echo "smoke-archive.sh: crosslint --help starts with '$first', expected '$name $version'" >&2
  exit 1
fi
echo "crosslint --help: $(wc -l < "$work/help.txt" | tr -d ' ') lines, starting with '$first'"
