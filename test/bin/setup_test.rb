# frozen_string_literal: true

require "test_helper"

# bin/setup, bin/pre-commit, and the pre-commit hook bin/setup installs, in
# a clone of their own that these tests make, with a mise of their own that
# records how it was called and stands in for the tools, the gems, and the
# gates.
class SetupTest < Minitest::Test
  BIN = File.expand_path("../../bin", __dir__)
  SCRIPTS = %w[setup pre-commit bundle-path].freeze
  GATES = "mise exec -- bundle exec rake"
  INSTALLED = "bin/setup: the pre-commit hook is installed: git commit runs the quality gates, and --no-verify skips them"

  def setup
    @base = Dir.mktmpdir("setup")
    @clone = File.join(@base, "clone")
    @tools = File.join(@base, "tools")
    @home = File.join(@base, "home")
    @log = File.join(@base, "log")
    @hook = File.join(@clone, ".git/hooks/pre-commit")
    FileUtils.mkdir_p([File.join(@clone, "bin"), @tools, @home])
    SCRIPTS.each { |script| FileUtils.cp(File.join(BIN, script), File.join(@clone, "bin", script)) }
    File.binwrite(File.join(@tools, "mise"), <<~MISE)
      #!/usr/bin/env bash
      echo "mise $* [BUNDLE_PATH=${BUNDLE_PATH-unset}] [GIT_DIR=${GIT_DIR-unset}]" >> "$FAKE_LOG"
      if [ "$*" = "exec -- bundle exec rake" ]; then exit "${FAKE_GATES_STATUS:-0}"; fi
    MISE
    File.chmod(0o755, File.join(@tools, "mise"))
    git("init", "-q")
  end

  def teardown
    FileUtils.remove_entry(@base)
  end

  def test_installs_the_tools_the_gems_and_the_fixtures_packages_in_that_order
    status, out, = run_setup

    assert_equal 0, status.exitstatus
    assert_equal ["mise trust -q mise.toml", "mise install", "mise exec -- bundle install", "mise exec -- bundle exec rake fixtures"], words
    assert_match(/^bin\/setup: done$/, out)
  end

  def test_puts_the_gems_in_a_folder_under_home_unless_bundle_path_is_set
    run_setup

    assert_equal [File.join(@home, ".cache/crosslint/bundle")], gem_folders

    File.truncate(@log, 0)
    run_setup("BUNDLE_PATH" => File.join(@base, "gems"))

    assert_equal [File.join(@base, "gems")], gem_folders
  end

  def test_installs_a_hook_that_runs_the_gates_before_each_commit_and_that_no_verify_skips
    run_setup
    File.truncate(@log, 0)

    assert_equal 0, commit("one").exitstatus
    assert_equal [GATES], words

    File.truncate(@log, 0)

    assert_equal 0, commit("two", "--no-verify").exitstatus
    assert_empty words
  end

  def test_refuses_a_commit_when_the_gates_fail
    run_setup

    assert_equal 1, commit("one", "FAKE_GATES_STATUS" => "1").exitstatus
    refute git("rev-parse", "--verify", "-q", "HEAD").last.success?
  end

  def test_runs_the_gates_with_the_same_gem_folder_and_none_of_gits_repository_variables
    _, _, status = Open3.capture3(env("GIT_DIR" => File.join(@clone, ".git")), "bash", File.join(@clone, "bin/pre-commit"), chdir: @clone)

    assert_predicate status, :success?
    assert_equal [GATES], words
    assert_equal [File.join(@home, ".cache/crosslint/bundle")], gem_folders
    assert_includes calls.first, "[GIT_DIR=unset]"
  end

  def test_leaves_a_pre_commit_hook_it_did_not_write_as_it_is_and_says_so
    File.binwrite(@hook, "#!/bin/sh\necho theirs >> \"$FAKE_LOG\"\n")
    File.chmod(0o755, @hook)

    status, out, = run_setup
    File.truncate(@log, 0)
    commit("one")

    assert_equal 0, status.exitstatus
    assert_includes out, "bin/setup: left .git/hooks/pre-commit as it is, since bin/setup didn't write it. To run the quality gates before each commit, make it run bin/pre-commit."
    assert_equal ["theirs"], words
  end

  def test_runs_again_with_nothing_to_change
    run_setup
    written = File.binread(@hook)

    status, out, = run_setup

    assert_equal 0, status.exitstatus
    assert_equal written, File.binread(@hook)
    assert_includes out, INSTALLED
  end

  def test_writes_a_hook_of_its_own_again_when_it_differs
    run_setup
    written = File.binread(@hook)
    File.binwrite(@hook, written.sub("runs the quality gates", "runs something else"))

    run_setup

    assert_equal written, File.binread(@hook)
  end

  def test_installs_no_hook_on_a_ci_runner
    status, out, = run_setup("CI" => "true")

    assert_equal 0, status.exitstatus
    assert_includes out, "bin/setup: CI is set, so no pre-commit hook"
    refute_path_exists @hook
  end

  def test_installs_no_hook_when_git_reads_its_hooks_from_a_folder_elsewhere
    git("config", "core.hooksPath", "../shared-hooks")

    status, out, = run_setup

    assert_equal 0, status.exitstatus
    assert_includes out, "bin/setup: core.hooksPath is ../shared-hooks, so Git reads hooks from there and not from this clone, and no pre-commit hook is installed. " \
      "To run the quality gates before each commit, make a pre-commit hook in that folder run bin/pre-commit."
    refute_path_exists @hook
  end

  def test_installs_no_hook_outside_a_git_clone
    FileUtils.rm_rf(File.join(@clone, ".git"))

    status, out, = run_setup("GIT_CEILING_DIRECTORIES" => @base)

    assert_equal 0, status.exitstatus
    assert_includes out, "bin/setup: this isn't a Git clone, so no pre-commit hook"
  end

  def test_stops_and_says_where_to_install_mise_when_there_is_none
    out, err, status = Open3.capture3(env("PATH" => @home), bash, File.join(@clone, "bin/setup"), chdir: @clone)

    assert_equal [1, ""], [status.exitstatus, out]
    assert_equal "bin/setup: mise isn't installed. Install it from https://mise.jdx.dev/installing-mise.html, and run bin/setup again.\n", err
    refute_path_exists @log
  end

  private

  def run_setup(extra = {})
    out, err, status = Open3.capture3(env(extra), "bash", File.join(@clone, "bin/setup"), chdir: @clone)
    [status, out, err]
  end

  def env(extra = {})
    {"HOME" => @home, "PATH" => [@tools, ENV.fetch("PATH")].join(File::PATH_SEPARATOR), "FAKE_LOG" => @log, "CI" => nil,
     "BUNDLE_PATH" => nil, "GIT_DIR" => nil, "GIT_INDEX_FILE" => nil, "GIT_WORK_TREE" => nil}.merge(extra)
  end

  def calls
    File.exist?(@log) ? File.readlines(@log, chomp: true) : []
  end

  # What the calls to mise were, without the settings each one logged.
  def words
    calls.map { |call| call.sub(/ \[BUNDLE_PATH.*/, "") }
  end

  def gem_folders
    # Git's bash on Windows writes C:/ as /c/.
    calls.map { |call| call[/\[BUNDLE_PATH=([^\]]*)\]/, 1].sub(%r{\A/([a-z])/}) { "#{$1.upcase}:/" } }.uniq
  end

  def git(*arguments, extra: {})
    out, err, status = Open3.capture3(env(extra), "git", *arguments, chdir: @clone)
    [out, err, status]
  end

  def commit(message, *options, **extra)
    git("commit", "--allow-empty", "-q", "-m", message, *options, extra: extra.transform_keys(&:to_s)).last
  end

  def bash
    ENV.fetch("PATH").split(File::PATH_SEPARATOR).flat_map { |folder| [File.join(folder, "bash"), File.join(folder, "bash.exe")] }.find { |path| File.file?(path) }
  end
end
