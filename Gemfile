# frozen_string_literal: true

source "https://rubygems.org"

# CrossLint's gems, from crosslint.gemspec.
gemspec

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
end
