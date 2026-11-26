#!/usr/bin/env bash
# Clones ng-nudge at the commit this study read, and installs its packages.
#
# Usage: fetch-ng-nudge.sh DIR
#
# Needs git, Node.js 18 or later, and npm.
set -eu

if [ $# -ne 1 ]; then
  echo "usage: $0 DIR" >&2
  exit 2
fi

git clone -q https://github.com/OverTheTopMarketing/ng-nudge "$1"
git -C "$1" checkout -q 10a722456daacca08f6425c5b74e5586183c654b
(cd "$1" && npm ci --ignore-scripts --no-audit --no-fund)
