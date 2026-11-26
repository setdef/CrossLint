# frozen_string_literal: true

# Every line and branch of lib/ must run in the tests. Under mutant, which
# loads the tests once for every mutation it tries, coverage is left off.
require "minitest/autorun"

unless defined?(Mutant)
  require "simplecov"
  SimpleCov.start do
    root File.expand_path("..", __dir__)
    enable_coverage :branch
    track_files "lib/**/*.rb"
    # A plugin's Ruby loads anew into each check, which starts its
    # coverage again each time, so only lib/ is counted.
    add_filter %r{\A/(test|tasks|vendor|plugins)/}
    # A helper's process tree is a job object on Windows and a process
    # group elsewhere, and each system runs only its own.
    add_filter(RbConfig::CONFIG.fetch("host_os").match?(/mswin|mingw/) ? "lib/cross_lint/adapters/process_group.rb" : "lib/cross_lint/adapters/job_object.rb")
    minimum_coverage line: 100, branch: 100
  end
  # Minitest 6 loads no plugin it isn't asked to, SimpleCov's included,
  # so this does what that plugin would: it checks the coverage once the
  # tests have run, and not when Ruby exits, which can come first.
  SimpleCov.external_at_exit = true
  Minitest.after_run { SimpleCov.at_exit_behavior }
end

require "mutant/minitest/coverage"
require "fileutils"
require "stringio"
require "tmpdir"

# CrossLint keeps what it fetches in the user's cache. A test gives its
# own folder to every port it makes, and these point the ones it doesn't
# at a folder that goes with the run, so that a mistake in CrossLint, or a
# mutation of it, writes nowhere in the user's cache.
CACHE = Dir.mktmpdir("crosslint-cache")
ENV["XDG_CACHE_HOME"] = ENV["LOCALAPPDATA"] = CACHE
Minitest.after_run { FileUtils.rm_rf(CACHE) }

require "cross_lint"
require "cross_lint/testing"

module TestHelper
  ROOT = File.expand_path("..", __dir__)

  def fixture_spec = CrossLint::UsageSpec.load(File.join(__dir__, "fixtures", "tool.usage.kdl"))

  def shipped_spec = CrossLint::UsageSpec.load

  def write(base, path, text)
    full = File.join(base, path)
    FileUtils.mkdir_p(File.dirname(full))
    File.binwrite(full, text)
    full
  end

  # The code blocks of `language` in a documentation page, so a test
  # fails when the page and CrossLint disagree.
  def doc_blocks(page, language)
    File.read(File.join(ROOT, page)).scan(/^```#{language}\n(.*?)^```$/m).flatten
  end
end

Minitest::Test.include(TestHelper)
