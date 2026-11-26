#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT

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

rm -rf dist
(
  cd build
  mise x -- bundle install
  mise x -- bundle exec fledge --version
  mise x -- bundle exec fledge build ../app --out ../dist
)
ls -l dist
