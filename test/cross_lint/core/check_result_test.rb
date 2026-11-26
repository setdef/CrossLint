# frozen_string_literal: true

require "test_helper"

class CheckResultTest < Minitest::Test
  cover "CrossLint::Core::Summary*"
  cover "CrossLint::Core::CheckResult*"
  cover "CrossLint::Core::Artifact*"
  cover "CrossLint::Core::Companion*"
  cover "CrossLint::Core::Spelling*"

  include CrossLint::Core

  def test_says_how_many_artifacts_of_each_kind_it_checked
    assert_equal "checked 9 ruby-file artifacts: 3 errors", summary([["ruby-file", 9]], errors: 3).line
    assert_equal "checked 1 ruby-file artifact: 1 error", summary([["ruby-file", 1]], errors: 1).line
    assert_equal "checked 0 ruby-file artifacts: no violations", summary([["ruby-file", 0]]).line
    assert_equal "checked 0 artifacts: no violations", summary([]).line
    assert_equal "checked 1 ruby-file and 1 adr artifacts: 2 warnings", summary([["ruby-file", 1], ["adr", 1]], warnings: 2).line
    assert_equal "checked 2 a, 0 b, and 1 c artifacts: 1 error, 1 warning", summary([["a", 2], ["b", 0], ["c", 1]], errors: 1, warnings: 1).line
  end

  def test_says_no_errors_when_warnings_are_hidden
    assert_equal "checked 2 ruby-file artifacts: no errors", summary([["ruby-file", 2]], warnings_shown: false).line
  end

  def test_counts_the_artifacts_of_every_kind
    assert_equal [3, 0], [summary([["a", 2], ["b", 1]]).artifacts, summary([]).artifacts]
  end

  def test_lists_the_violations_among_the_findings
    companion = Companion.new(name: "test", path: "test/a_test.rb", exists: true)
    artifact = Artifact.new(plugin: "tests", role: "ruby-file", path: "lib/a.rb", match: {"path" => "a"}, companions: [companion])
    violation = Violation.new(plugin: "tests", policy: "p", artifact: "lib/b.rb", role: "ruby-file", message: "m", severity: :error, detail: nil)
    result = CheckResult.new(notices: [], findings: [artifact, violation], summary: summary([]), verbosity: :normal, failed: true, faults: [])

    assert_equal [violation], result.violations
  end

  def test_counts_faults_before_errors_and_warnings
    assert_equal ["checked 1 a artifact: 1 fault", "checked 1 a artifact: 2 faults, 1 error"],
      [summary([["a", 1]], faults: 1).line, summary([["a", 1]], faults: 2, errors: 1, warnings_shown: false).line]
  end

  def test_finds_an_artifacts_companion_by_name
    companion = Companion.new(name: "test", path: "test/a_test.rb", exists: true)
    artifact = Artifact.new(plugin: "tests", role: "ruby-file", path: "lib/a.rb", match: {}, companions: [companion])

    assert_equal [companion, true], [artifact.companion("test"), artifact.companion("test").exist?]
    assert_equal %(artifact "ruby-file" has no companion "spec"), assert_raises(KeyError) { artifact.companion("spec") }.message
  end

  def test_joins_words_with_the_conjunction_it_is_given
    assert_equal ["a", "a and b", "a, b, and c", "a, b, or c"],
      [Spelling.list(["a"], "and"), Spelling.list(%w[a b], "and"), Spelling.list(%w[a b c], "and"), Spelling.list(%w[a b c])]
  end

  private

  def summary(kinds, faults: 0, errors: 0, warnings: 0, warnings_shown: true) = Summary.new(kinds:, faults:, errors:, warnings:, warnings_shown:)
end
