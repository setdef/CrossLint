# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT

# csv is a bundled gem of Ruby 4.x: part of the runtime, not in the app's lockfile.
require "csv"

TsSpike.rule("csv") { |_facts| [] }
