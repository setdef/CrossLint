# frozen_string_literal: true

source "https://rubygems.org"

# CrossLint's gems, from cross_lint.gemspec.
gemspec

# On Windows, CrossLint puts each helper in a job object through fiddle,
# which Ruby 4.1 has as a bundled gem rather than in its standard
# library. A gemspec can't ask for a gem on one platform alone.
gem "fiddle", "~> 1.1", platforms: :windows

# For contributors only. The Fledge build leaves these groups out of the
# app (Rakefile, build), and Fledge has a separate bundle, in build/, so
# the app doesn't carry it.
group :development do
  gem "rake", "~> 13.4"
end

group :test do
  gem "minitest", "~> 6.1"
  # Mutation testing, which is free for open-source projects
  # (.mutant.yml, usage).
  gem "mutant-minitest", "~> 0.17.1"
  gem "simplecov", "~> 0.22"
  # rdoc, which mutant needs, needs erb, and Ruby 4.1.0-preview1's erb is
  # a version no gem server has, so its lockfile entry could have no
  # checksum.
  gem "erb", "~> 6.0.7"
  # rbs validate, and RBS's runtime type checker (rake test:rbs).
  gem "rbs", "~> 4.2"
end

# The checks that only CI's Linux job runs, so the macOS and Windows jobs,
# which run the tests, leave this group out (BUNDLE_WITHOUT). Steep needs
# ffi, which has no build for Ruby 4.1 and compiles on install.
group :check do
  # Steep checks lib/ against sig/ (rake steep).
  gem "steep", "~> 2.1"
  # Standard checks the style of the Ruby files (rake standard).
  gem "standard", "~> 1.54"
end
