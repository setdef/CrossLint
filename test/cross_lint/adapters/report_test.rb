# frozen_string_literal: true

require "test_helper"
require "json"

# What writes a test of a report adapter shares: the streams it writes
# to, and a result to write.
module ReportTestHelper
  include CrossLint::Core

  def setup
    @out = StringIO.new
    @err = StringIO.new
  end

  def own_lines = @err.string.lines(chomp: true).map { |line| line.delete_prefix("crosslint: ") }

  def notices = own_lines.filter_map { |line| line.match(/\A(.+):(\d+): warning: (.*)\z/)&.captures&.then { |file, line, message| [file, line.to_i, message] } }

  def summary_line = own_lines.grep(/\Achecked /).first

  def violation_of(path, message, severity = :error, plugin: "tests", detail: nil)
    Violation.new(plugin:, policy: "has-test", artifact: path, role: "ruby-file", message:, severity:, detail:)
  end

  def result_of(findings, verbosity: :normal, notices: [])
    summary = Summary.new(kinds: [["ruby-file", 9]], errors: 1, warnings: 1, warnings_shown: true)
    CheckResult.new(notices:, findings:, summary:, verbosity:, failed: true)
  end
end

class TextReportTest < Minitest::Test
  cover "CrossLint::Adapters::TextReport*"

  include CrossLint::Testing::ReportContract
  include ReportTestHelper

  def report_port = CrossLint::Adapters::TextReport.new(out: @out, err: @err)

  def reported
    findings = @out.string.lines(chomp: true).map do |line|
      path, rest = line.split(": ", 2)
      warning = rest.delete_prefix!("warning: ")
      message, plugin, policy = rest.match(/\A(.*) \(([^\/]+)\/(.+)\)\z/).captures
      [path, message, plugin, policy, warning ? :warning : :error]
    end
    {findings:, notices:, summary: summary_line}
  end

  def test_writes_each_finding_on_a_line_of_standard_output
    report_port.write(result_of([violation_of("lib/a.rb", "no test file at test/a_test.rb"), violation_of("lib/b.rb", "no sig", :warning)]))

    assert_equal "lib/a.rb: no test file at test/a_test.rb (tests/has-test)\nlib/b.rb: warning: no sig (tests/has-test)\n", @out.string
    assert_equal "crosslint: checked 9 ruby-file artifacts: 1 error, 1 warning\n", @err.string
  end

  def test_writes_each_notice_then_the_summary_on_standard_error
    report_port.write(result_of([], notices: [Notice.new(file: "p.kdl", line: 2, message: "no file matches")]))

    assert_equal "crosslint: p.kdl:2: warning: no file matches\ncrosslint: checked 9 ruby-file artifacts: 1 error, 1 warning\n", @err.string
  end

  def test_writes_a_passing_artifact_with_its_role
    artifact = Artifact.new(plugin: "tests", role: "ruby-file", path: "lib/a.rb", match: {"path" => "a"}, companions: [])
    report_port.write(result_of([artifact]))

    assert_equal "lib/a.rb: ruby-file passes\n", @out.string
  end

  def test_colors_only_the_message_by_its_severity
    CrossLint::Adapters::TextReport.new(out: @out, err: @err, color: true)
      .write(result_of([violation_of("lib/a.rb", "no test"), violation_of("lib/b.rb", "no sig", :warning)]))

    assert_equal "lib/a.rb: \e[31mno test\e[0m (tests/has-test)\nlib/b.rb: \e[33mwarning: no sig\e[0m (tests/has-test)\n", @out.string
    assert_equal "crosslint: checked 9 ruby-file artifacts: 1 error, 1 warning\n", @err.string
  end

  def test_writes_only_ascii
    artifact = Artifact.new(plugin: "tests", role: "ruby-file", path: "lib/é.rb", match: {}, companions: [])
    report_port.write(result_of([violation_of("lib/café.rb", "no tést"), artifact], notices: [Notice.new(file: "ü.kdl", line: 1, message: "ö")]))

    assert_equal "lib/caf?.rb: no t?st (tests/has-test)\nlib/?.rb: ruby-file passes\n", @out.string
    assert_equal "crosslint: ?.kdl:1: warning: ?\n", @err.string.lines.first
  end

  def test_writes_a_byte_that_isnt_utf_8_as_a_question_mark
    report_port.write(result_of([violation_of("lib/a\xFF.rb".dup.force_encoding("UTF-8"), "no test")]))

    assert_equal "lib/a?.rb: no test (tests/has-test)\n", @out.string
  end
end

class JSONReportTest < Minitest::Test
  cover "CrossLint::Adapters::JSONReport*"

  include CrossLint::Testing::ReportContract
  include ReportTestHelper

  def report_port = CrossLint::Adapters::JSONReport.new(out: @out, err: @err)

  def reported
    object = @out.string.empty? ? {"findings" => []} : JSON.parse(@out.string)
    findings = object.fetch("findings").map do |finding|
      [finding.fetch("path"), finding.fetch("message"), finding.fetch("plugin"), finding.fetch("policy"), finding.fetch("severity").to_sym]
    end
    {findings:, notices:, summary: summary_line}
  end

  def test_writes_one_object_with_its_keys_in_order
    report_port.write(result_of([violation_of("lib/a.rb", "no test"), violation_of("lib/b.rb", "x", :warning, detail: "y")]))

    assert_equal <<~JSON.delete("\n") + "\n", @out.string
      {"findings":[{"path":"lib/a.rb","message":"no test","plugin":"tests","policy":"has-test","artifact":"lib/a.rb","role":"ruby-file","severity":"error","detail":null},
      {"path":"lib/b.rb","message":"x","plugin":"tests","policy":"has-test","artifact":"lib/b.rb","role":"ruby-file","severity":"warning","detail":"y"}],
      "summary":{"artifacts":9,"errors":1,"warnings":1}}
    JSON
    assert_equal "crosslint: checked 9 ruby-file artifacts: 1 error, 1 warning\n", @err.string
  end

  def test_writes_the_object_with_no_summary_line_when_quiet
    report_port.write(result_of([], verbosity: :quiet))

    assert_equal [%({"findings":[],"summary":{"artifacts":9,"errors":1,"warnings":1}}\n), ""], [@out.string, @err.string]
  end

  def test_leaves_passing_artifacts_out
    artifact = Artifact.new(plugin: "tests", role: "ruby-file", path: "lib/a.rb", match: {}, companions: [])
    report_port.write(result_of([artifact]))

    assert_equal [], JSON.parse(@out.string).fetch("findings")
  end

  def test_writes_no_object_when_silent
    report_port.write(result_of([], verbosity: :silent))

    assert_equal ["", ""], [@out.string, @err.string]
  end

  def test_escapes_what_isnt_ascii
    report_port.write(result_of([violation_of("lib/café.rb", "no test")]))

    assert_includes @out.string, %("path":"lib/caf\\u00e9.rb")
  end
end

class MemoryReportTest < Minitest::Test
  cover "CrossLint::Adapters::MemoryReport*"

  include CrossLint::Testing::ReportContract
  include ReportTestHelper

  def report_port = @port = CrossLint::Adapters::MemoryReport.new

  def reported
    results = @port.results.reject { |result| result.verbosity == :silent }
    findings = results.flat_map(&:violations).map do |violation|
      [violation.artifact, violation.message, violation.plugin, violation.policy, violation.severity]
    end
    notices = results.flat_map(&:notices).map { |notice| [notice.file, notice.line, notice.message] }
    summary = results.find { |result| result.verbosity == :normal }&.summary&.line
    {findings:, notices:, summary:}
  end

  def test_holds_every_result_written_in_order
    port = report_port
    first = result_of([])
    second = result_of([], verbosity: :quiet)
    port.write(first)
    port.write(second)

    assert_equal [first, second], port.results
  end
end
