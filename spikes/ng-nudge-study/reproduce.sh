#!/usr/bin/env bash
# Runs ng-nudge against each fixture in fixtures/ and prints what it does.
#
# Usage: reproduce.sh NG_NUDGE_DIR [CASE...]
#
# NG_NUDGE_DIR is a clone of https://github.com/OverTheTopMarketing/ng-nudge
# at commit 10a722456daacca08f6425c5b74e5586183c654b, with `npm ci` run in it.
# Each case runs in a fresh temporary copy of its fixture, so the fixtures
# themselves never change. Each fixture's steps.sh lists the commands.
set -u

if [ $# -lt 1 ] || [ ! -f "$1/bin/ng-nudge" ]; then
  echo "usage: $0 NG_NUDGE_DIR [CASE...]" >&2
  exit 2
fi

NG_NUDGE_DIR=$(cd "$1" && pwd -P)
shift
HERE=$(cd "$(dirname "$0")" && pwd -P)

if [ $# -eq 0 ]; then
  set -- $(cd "$HERE/fixtures" && ls -d */ | tr -d /)
fi

# Runs ng-nudge in the current directory and prints its exit status.
nudge() {
  echo "\$ ng-nudge $*"
  node "$NG_NUDGE_DIR/bin/ng-nudge" "$@"
  echo "[exit $?]"
}

# Prints a command, then runs it.
show() {
  echo "\$ $*"
  "$@"
}

for case in "$@"; do
  work=$(cd "$(mktemp -d)" && pwd -P)
  cp -R "$HERE/fixtures/$case/." "$work/"
  mkdir -p "$work/node_modules/@overthetopmarketing"
  ln -s "$NG_NUDGE_DIR" "$work/node_modules/@overthetopmarketing/ng-nudge"
  # On Windows, Node prints the temporary folder's Windows form.
  native=$work
  if command -v cygpath > /dev/null 2>&1; then
    native=$(cygpath -w "$work" | sed 's#\\#\\\\#g')
  fi
  echo "=== $case"
  (
    cd "$work" || exit 1
    . ./steps.sh
  ) 2>&1 | sed -e "s#$work#\$PROJECT#g" -e "s#$native#\$PROJECT#g" \
    -e "s#$NG_NUDGE_DIR#\$NG_NUDGE#g" -e 's#(node:[0-9]*)#(node:PID)#'
  echo
  rm -rf "$work"
done
