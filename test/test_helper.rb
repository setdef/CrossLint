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
require "open3"
require "securerandom"
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

  # The file URL of the folder `path`.
  def file_url(path) = "file://#{"/" unless path.start_with?("/")}#{path}"

  # A Git repository in `folder` that has `files`, a hash of paths and
  # text, in one commit on the branch main, with `tags` on that commit.
  # Its file URL.
  def repository_at(folder, files, tags: [])
    files.each { |path, text| write(folder, path, text) }
    settings = %w[-c user.name=Test -c user.email=test@example.com -c commit.gpgsign=false -c tag.gpgsign=false]
    [%w[init -q -b main], %w[add -A], %w[commit -q -m one], *tags.map { |tag| ["tag", tag] }].each do |arguments|
      _, error, status = Open3.capture3("git", *settings, *arguments, chdir: folder)
      raise error unless status.success?
    end
    file_url(folder)
  end

  # Runs the block with a Git setting, in a home folder that goes with
  # the block, that sends the https URL `url` to `origin`, a file URL, so
  # that what asks for `url` reaches no network.
  def rewriting(url, origin)
    Dir.mktmpdir("crosslint-home") do |home|
      File.binwrite(File.join(home, ".gitconfig"), %([url "#{origin}"]\n\tinsteadOf = #{url}\n))
      names = %w[HOME USERPROFILE]
      saved = ENV.values_at(*names)
      names.each { |name| ENV[name] = home }
      begin
        yield
      ensure
        names.zip(saved) { |name, value| ENV[name] = value }
      end
    end
  end

  # The code blocks of `language` in a documentation page, so a test
  # fails when the page and CrossLint disagree.
  def doc_blocks(page, language)
    File.read(File.join(ROOT, page)).scan(/^```#{language}\n(.*?)^```$/m).flatten
  end
end

Minitest::Test.include(TestHelper)
