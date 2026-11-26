# frozen_string_literal: true

require "test_helper"

# .github/scripts/check-ci-passed.sh, with a gh of these tests' own that
# prints the lines a test gives it, as `gh run list --jq` would, and
# records how it was called.
class CheckCiPassedTest < Minitest::Test
  SCRIPT = File.expand_path("../../.github/scripts/check-ci-passed.sh", __dir__)
  COMMIT = "0123456789abcdef0123456789abcdef01234567"

  def setup
    @folder = Dir.mktmpdir("check-ci-passed")
    File.binwrite(File.join(@folder, "gh"), %(#!/usr/bin/env bash\necho "$@" > "$FAKE_GH_CALL"\nprintf '%s' "$FAKE_GH_OUTPUT"\nexit "$FAKE_GH_STATUS"\n))
    File.chmod(0o755, File.join(@folder, "gh"))
  end

  def teardown
    FileUtils.remove_entry(@folder)
  end

  def test_passes_when_a_run_of_ci_completed_with_success
    status, out, err = run_script("completed failure\ncompleted success\n")

    assert_equal [0, "check-ci-passed.sh: CI passed for #{COMMIT}\n", ""], [status.exitstatus, out, err]
  end

  def test_asks_gh_for_the_status_and_conclusion_of_each_run_of_ci_on_the_commit
    run_script("completed success\n")

    assert_equal %(run list --commit #{COMMIT} --workflow CI --json status,conclusion --jq .[] | "\\(.status) \\(.conclusion)"\n),
      File.read(File.join(@folder, "call"))
  end

  def test_refuses_a_commit_with_no_run_of_ci
    status, _, err = run_script("")

    assert_equal [1, "check-ci-passed.sh: CI has no run that completed with success for commit #{COMMIT}; found: no run of CI\n"], [status.exitstatus, err]
  end

  def test_refuses_a_commit_whose_runs_are_going_failed_or_were_canceled
    status, _, err = run_script("in_progress \ncompleted failure\ncompleted cancelled\n")

    assert_equal [1, "check-ci-passed.sh: CI has no run that completed with success for commit #{COMMIT}; " \
      "found: status in_progress, conclusion none yet; status completed, conclusion failure; status completed, conclusion cancelled\n"], [status.exitstatus, err]
  end

  def test_refuses_a_commit_whose_only_success_has_not_completed
    status, = run_script("in_progress success\n")

    assert_equal 1, status.exitstatus
  end

  def test_refuses_a_commit_when_gh_fails
    status, out, err = run_script("", gh_status: 1)

    assert_equal [1, "", "check-ci-passed.sh: gh couldn't list the runs of CI for commit #{COMMIT}\n"], [status.exitstatus, out, err]
  end

  private

  def run_script(output, gh_status: 0)
    env = {"PATH" => [@folder, ENV.fetch("PATH")].join(File::PATH_SEPARATOR), "FAKE_GH_OUTPUT" => output, "FAKE_GH_STATUS" => gh_status.to_s,
           "FAKE_GH_CALL" => File.join(@folder, "call")}
    out, err, status = Open3.capture3(env, "bash", SCRIPT, COMMIT)
    [status, out, err]
  end
end
