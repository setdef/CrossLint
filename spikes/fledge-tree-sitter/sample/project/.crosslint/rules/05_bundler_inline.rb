# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT

# A rule file that asks Bundler to install its gem when it loads.
require "bundler/inline"

gemfile(true, quiet: true) do
  source "https://rubygems.org"
  gem "rainbow", "3.1.1"
end

TsSpike.rule("inline") { |_facts| [] }
