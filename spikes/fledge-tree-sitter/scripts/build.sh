#!/usr/bin/env bash

# Build the app for the computer this runs on: compile the grammars, install
# the gems, run `fledge build`. Leaves the archive in dist/. Needs mise and
# a C compiler; mise installs Ruby 4.1.0-preview1 from mise.toml.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$here"

mise trust -q mise.toml
mise install
mise x -- ruby -v

mise x -- ruby scripts/grammars.rb

case "$(uname -s)" in
  MINGW*|MSYS*)
    # ruby_tree_sitter cannot build its own tree-sitter on Windows: build it
    # here and point the gem's build at it (see scripts/tree_sitter_core_windows.rb).
    BUNDLE_BUILD__RUBY_TREE_SITTER="$(mise x -- ruby scripts/tree_sitter_core_windows.rb | tail -1)"
    export BUNDLE_BUILD__RUBY_TREE_SITTER
    echo "BUNDLE_BUILD__RUBY_TREE_SITTER=$BUNDLE_BUILD__RUBY_TREE_SITTER"
    # Its C also needs two changes to compile and run there.
    mise x -- ruby scripts/windows_app.rb
    app=build/app-windows
    ;;
  *) app=app ;;
esac

rm -rf dist
(
  cd build
  mise x -- bundle install
  mise x -- bundle exec fledge --version
  mise x -- bundle exec fledge build "../$app" --out ../dist
)
ls -l dist
