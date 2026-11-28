# frozen_string_literal: true

# Every line and branch of lib/ and of each built-in plugin's Ruby must run
# in the tests.
require "minitest/autorun"
require "simplecov"

SimpleCov.start do
  root File.expand_path("..", __dir__)
  enable_coverage :branch
  track_files "{lib,plugins}/**/*.rb"
  # A plugin's tests are counted no more than test/ is.
  add_filter %r{\A/(test|tasks|vendor)/}
  add_filter %r{\A/plugins/[^/]+/test/}
  # A helper's process tree is a job object on Windows and a process
  # group elsewhere, and each system runs only its own.
  add_filter(RbConfig::CONFIG.fetch("host_os").match?(/mswin|mingw/) ? "lib/cross_lint/adapters/process_group.rb" : "lib/cross_lint/adapters/job_object.rb")
  # One process runs every test, so there is nothing to merge. SimpleCov
  # would merge in the result of any run in the same folder within the
  # last ten minutes, such as one of a few tests, or of other code, and
  # that run's branches, at lines that have since moved, would count as
  # branches no test reached.
  use_merging false
  minimum_coverage line: 100, branch: 100
end
# Minitest 6 loads no plugin it isn't asked to, SimpleCov's included,
# so this does what that plugin would: it checks the coverage once the
# tests have run, and not when Ruby exits, which can come first.
SimpleCov.external_at_exit = true
Minitest.after_run { SimpleCov.at_exit_behavior }

require "fileutils"
require "open3"
require "securerandom"
require "stringio"
require "tmpdir"

# CrossLint keeps what it fetches in the user's cache, and Git reads the
# user's home folder. A test gives its own folder to every port it makes,
# and these point the ones it doesn't, and every program a test starts,
# at folders that go with the run, so that a mistake in CrossLint reads and
# writes nowhere in the user's home. Git's
# settings for the tests are in one file, which is all of Git's
# configuration: no system file, and no file in the home folder.
SANDBOX = Dir.mktmpdir("crosslint-sandbox")
SANDBOX_HOME = File.join(SANDBOX, "home")
CACHE = File.join(SANDBOX, "cache")
FileUtils.mkdir_p([SANDBOX_HOME, CACHE])
File.binwrite(File.join(SANDBOX, "gitconfig"), "[user]\n\tname = Test\n\temail = test@example.com\n[commit]\n\tgpgsign = false\n[tag]\n\tgpgsign = false\n" \
  "[core]\n\tautocrlf = false\n[init]\n\tdefaultBranch = main\n")
ENV["HOME"] = ENV["USERPROFILE"] = SANDBOX_HOME
ENV["XDG_CACHE_HOME"] = ENV["LOCALAPPDATA"] = CACHE
ENV["GIT_CONFIG_GLOBAL"] = File.join(SANDBOX, "gitconfig")
ENV["GIT_CONFIG_NOSYSTEM"] = "1"
Minitest.after_run { FileUtils.rm_rf(SANDBOX) }

require "cross_lint"
require "cross_lint/testing"
require_relative "crosslint_ruby"

# The tests name what each covers, with `cover "CrossLint::App*"`, a
# declaration that mutation testing used and that nothing reads now.
class Minitest::Test
  def self.cover(*) = nil
end

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
  def file_url(path) = "file://#{'/' unless path.start_with?('/')}#{path}"

  # A Git repository in `folder` that has `files`, a hash of paths and
  # text, in one commit on the branch main, with `tags` on that commit.
  # Its file URL.
  def repository_at(folder, files, tags: [])
    files.each { |path, text| write(folder, path, text) }
    [%w[init -q -b main], %w[add -A], %w[commit -q -m one], *tags.map { |tag| ["tag", tag] }].each do |arguments|
      _, error, status = Open3.capture3("git", *arguments, chdir: folder)
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

  # The one code block of `language` in a documentation page that
  # `containing` matches, found by what it holds and not by where it
  # sits, so that adding or moving an example breaks no test. Fails
  # when the page has none, or more than one, to say which.
  def doc_block(page, language, containing)
    found = doc_blocks(page, language).grep(containing)

    assert_equal 1, found.size, "#{page} should have one #{language} block matching #{containing.inspect}, and has #{found.size}"
    found.first
  end
end

Minitest::Test.include(TestHelper)
