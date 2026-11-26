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
    add_filter %r{\A/(test|tasks|vendor)/}
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
