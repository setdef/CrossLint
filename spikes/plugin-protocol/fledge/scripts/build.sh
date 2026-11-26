#!/usr/bin/env bash

# Build the host (../host/crosslint.rb) into a Fledge console app for the
# computer this runs on. Leaves the archive in dist/. Needs mise; mise installs
# Ruby 4.1.0-preview1 from mise.toml (RubyInstaller's head build on Windows).
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$here"

mise trust -q mise.toml
mise install
mise x -- ruby -v

# Fledge runs app/main.rb. The host is the program, so the build copies it there.
cp ../host/crosslint.rb app/main.rb
cp ../host/debt.rb app/debt.rb
(cd app && mise x -- bundle lock)

rm -rf dist
(
  cd build
  mise x -- bundle install
  mise x -- bundle exec fledge --version
  mise x -- bundle exec fledge build ../app --out ../dist
)
ls -l dist
