#!/usr/bin/env bash
# Reruns the whole spike: installs the packages, builds the TypeScript grammar,
# and runs both approaches over the fixture in every mode.
# Needs: Ruby with Bundler, Node with npm, a C compiler (cc), network access.
# Optional: NG_NUDGE_CLONE=/path/to/ng-nudge (with `npm ci` run in it) also
# regenerates expected/ng-nudge.json and checks it has not changed.
set -euo pipefail
cd "$(dirname "$0")"

# The fixture's one package under node_modules: copied in so the repository holds no node_modules.
rm -rf fixture/node_modules
mkdir -p fixture/node_modules/@acme
cp -R fixture/packages/acme-ui-base fixture/node_modules/@acme/ui-base

npm ci --ignore-scripts --no-audit --no-fund --silent

# Approach A needs the grammar as a shared library. The gem does not carry one.
case "$(uname -s)" in Darwin) ext=dylib ;; *) ext=so ;; esac
grammar=node_modules/tree-sitter-typescript/typescript
mkdir -p build
rm -f build/libtree-sitter-typescript.*
cc -shared -fPIC -O1 -I "$grammar/src" "$grammar/src/parser.c" "$grammar/src/scanner.c" -o "build/libtree-sitter-typescript.$ext"

export BUNDLE_PATH=vendor
bundle install --quiet

unexpected=0
# run NAME EXPECTED_EXIT ARGS...: EXPECTED_EXIT is 1 for a mode where a miss is the known result.
run() {
  local name=$1 want=$2; shift 2
  echo "== $name"
  local got=0
  "$@" || got=$?
  if [ "$got" -ne "$want" ]; then
    echo "UNEXPECTED: exit $got, expected $want"
    unexpected=1
  fi
}

run "A, ng-nudge's forms (c15 misses: a mixin's base needs types)" 1 bundle exec ruby check.rb a
run "A, ng-nudge's forms, mixin heuristic"                         0 bundle exec ruby check.rb a --mixin-heuristic
run "A, every Angular form (c15 misses)"                           1 bundle exec ruby check.rb a --strict
run "A, every Angular form, mixin heuristic"                       0 bundle exec ruby check.rb a --strict --mixin-heuristic
run "B, ng-nudge's forms"                                          0 ruby check.rb b
run "B, every Angular form"                                        0 ruby check.rb b --strict

if [ -n "${NG_NUDGE_CLONE:-}" ]; then
  echo "== ng-nudge's code on the fixture"
  node truth/dump.mjs "$NG_NUDGE_CLONE" fixture | diff - expected/ng-nudge.json && echo "expected/ng-nudge.json is current"
fi

exit $unexpected
