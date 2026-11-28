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

  def faults = own_lines.filter_map { |line| line.match(/\Afault in plugin (\S+): rule (\S+)(?: on (\S+))? (.*)\z/)&.captures }

  def notices = own_lines.filter_map { |line| line.match(/\A(.+):(\d+): warning: (.*)\z/)&.captures&.then { |file, line, message| [file, line.to_i, message] } }

  def summary_line = own_lines.grep(/\Achecked /).first

  def wrote = own_lines.grep(/\Awrote /)

  def violation_of(path, message, severity = :error, plugin: "tests", detail: nil)
    Violation.new(plugin:, policy: "has-test", artifact: path, role: "ruby-file", message:, severity:, detail:)
  end

  def result_of(findings, verbosity: :normal, notices: [], faults: [])
    summary = Summary.new(kinds: [["ruby-file", 9]], faults: 0, errors: 1, warnings: 1, warnings_shown: true)
    CheckResult.new(notices:, findings:, summary:, verbosity:, failed: true, faults:)
  end

  def fault_of(trace: ["rules/a.rb:3:in 'check'"])
    Fault.new(plugin: "tests", rule: "names-class", artifact: "lib/a.rb", message: "raised RuntimeError: boom", trace:)
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
    paid_off, findings = findings.partition { |_, message| message == "is paid off" }
    {findings:, notices:, faults:, paid_off: paid_off.map { |finding| finding.take(4) }, wrote:, summary: summary_line}
  end

  def test_writes_each_fault_after_the_findings_and_says_how_to_see_its_trace
    report_port.write(result_of([violation_of("lib/b.rb", "no test")], faults: [fault_of, fault_of(trace: [])]))

    assert_equal ["fault in plugin tests: rule names-class on lib/a.rb raised RuntimeError: boom"] * 2 +
      ["run it again with --debug to see where each fault was raised", "checked 9 ruby-file artifacts: 1 error, 1 warning"], own_lines
  end

  # Standard error on a terminal.
  class Terminal < StringIO
    def tty? = true
  end

  def test_says_what_a_check_is_checking_only_on_a_terminal
    kinds = [["component", 3], ["pipe", 0], ["service", 1]]
    terminal = Terminal.new
    CrossLint::Adapters::TextReport.new(out: @out, err: terminal).start(kinds)
    report_port.start(kinds)

    assert_equal ["crosslint: checking 3 component and 1 service artifacts\n", "", ""], [terminal.string, @err.string, @out.string]
  end

  def test_writes_each_faults_trace_with_debug
    CrossLint::Adapters::TextReport.new(out: @out, err: @err, debug: true).write(result_of([], verbosity: :quiet, faults: [fault_of]))

    assert_equal "crosslint: fault in plugin tests: rule names-class on lib/a.rb raised RuntimeError: boom\n" \
      "crosslint:   from rules/a.rb:3:in 'check'\n", @err.string
  end

  def test_writes_only_the_faults_when_silent
    report_port.write(result_of([], verbosity: :silent, faults: [fault_of]))

    assert_equal "crosslint: fault in plugin tests: rule names-class on lib/a.rb raised RuntimeError: boom\n", @err.string
  end

  def test_writes_each_line_of_a_faults_message_as_a_line_of_its_own
    report_port.write(result_of([], verbosity: :silent, faults: [fault_of.with(message: "called helper h, which wrote:\none\ntwo")]))

    assert_equal "crosslint: fault in plugin tests: rule names-class on lib/a.rb called helper h, which wrote:\ncrosslint: one\ncrosslint: two\n",
      @err.string
  end

  def test_says_nothing_of_traces_for_faults_that_have_none
    report_port.write(result_of([], verbosity: :quiet, faults: [fault_of(trace: [])]))

    assert_equal ["fault in plugin tests: rule names-class on lib/a.rb raised RuntimeError: boom"], own_lines
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
    artifact = Artifact.new(plugin: "tests", role: "ruby-file", path: "lib/a.rb", match: {"path" => "a"}, pieces: [])
    report_port.write(result_of([artifact]))

    assert_equal "lib/a.rb: ruby-file passes\n", @out.string
  end

  def test_writes_an_artifacts_name_after_its_path_when_the_two_differ
    named = Violation.new(plugin: "tests", policy: "has-test", artifact: "app/a", path: "lib/app/a.rb", role: "ruby-file", message: "no test",
      severity: :error, detail: nil)
    artifact = Artifact.new(plugin: "tests", role: "ruby-file", path: "lib/app/b.rb", name: "app/b", match: {}, pieces: [])
    report_port.write(result_of([named, artifact]))

    assert_equal "lib/app/a.rb: app/a: no test (tests/has-test)\nlib/app/b.rb: app/b: ruby-file passes\n", @out.string
  end

  def test_writes_the_line_of_an_artifact_a_regex_found
    route = Violation.new(plugin: "routes", policy: "has-action", artifact: "get /cart", path: "config/routes.rb", line: 2, role: "route",
      message: "no action in app/controllers/carts_controller.rb", severity: :error, detail: nil)
    passing = Artifact.new(plugin: "routes", role: "route", path: "config/routes.rb", name: "get /", line: 4, match: {}, pieces: [])
    report_port.write(result_of([route, passing]))

    assert_equal "config/routes.rb:2: get /cart: no action in app/controllers/carts_controller.rb (routes/has-action)\n" \
                 "config/routes.rb:4: get /: route passes\n", @out.string
  end

  def test_colors_only_the_message_by_its_severity
    CrossLint::Adapters::TextReport.new(out: @out, err: @err, color: true)
      .write(result_of([violation_of("lib/a.rb", "no test"), violation_of("lib/b.rb", "no sig", :warning)]))

    assert_equal "lib/a.rb: \e[31mno test\e[0m (tests/has-test)\nlib/b.rb: \e[33mwarning: no sig\e[0m (tests/has-test)\n", @out.string
    assert_equal "crosslint: checked 9 ruby-file artifacts: 1 error, 1 warning\n", @err.string
  end

  def test_writes_a_path_and_other_text_from_the_project_as_they_are
    artifact = Artifact.new(plugin: "tests", role: "ruby-file", path: "lib/é.rb", match: {}, pieces: [])
    report_port.write(result_of([violation_of("lib/café.rb", "no tést"), artifact], notices: [Notice.new(file: "ü.kdl", line: 1, message: "ö")]))

    assert_equal "lib/café.rb: no tést (tests/has-test)\nlib/é.rb: ruby-file passes\n", @out.string
    assert_equal "crosslint: ü.kdl:1: warning: ö\n", @err.string.lines.first
    assert_equal [Encoding::UTF_8, Encoding::UTF_8], [@out.string.encoding, @err.string.encoding]
  end

  def test_writes_only_ascii_of_its_own_words
    report_port.write(result_of([violation_of("lib/a.rb", "no test")], notices: [Notice.new(file: "p.kdl", line: 1, message: "x")]))

    assert_predicate @out.string + @err.string, :ascii_only?
  end

  # A stream that holds its lines until it is flushed, as Ruby holds
  # standard output to a pipe, into a log both streams share.
  class Held
    def initialize(log)
      @log = log
      @held = []
    end

    def puts(line) = @held << line

    def flush = @log.concat(@held.slice!(0..))

    def write(text) = puts(text)

    def tty? = false
  end

  # A stream that writes each line at once, as standard error does.
  class Unheld < Held
    def puts(line) = @log << line
  end

  def test_writes_out_the_findings_before_the_summary
    log = []
    CrossLint::Adapters::TextReport.new(out: Held.new(log), err: Unheld.new(log)).write(result_of([violation_of("lib/a.rb", "no test")]))

    assert_equal ["lib/a.rb: no test (tests/has-test)", "crosslint: checked 9 ruby-file artifacts: 1 error, 1 warning"], log
  end

  def test_writes_the_bytes_of_a_path_that_isnt_utf_8_as_they_are
    path = "lib/a\xFF.rb".dup.force_encoding("UTF-8")
    report_port.write(result_of([violation_of(path, "no test")], notices: [Notice.new(file: path, line: 1, message: "x")]))

    assert_equal "lib/a\xFF.rb: no test (tests/has-test)\n".b, @out.string.b
    assert_equal "crosslint: lib/a\xFF.rb:1: warning: x\n".b, @err.string.lines.first.b
  end
end

class JSONReportTest < Minitest::Test
  cover "CrossLint::Adapters::JSONReport*"

  include CrossLint::Testing::ReportContract
  include ReportTestHelper

  def report_port = CrossLint::Adapters::JSONReport.new(out: @out, err: @err, crosslint: "1.4.0")

  def reported
    object = @out.string.empty? ? {"findings" => []} : JSON.parse(@out.string)
    findings = object.fetch("findings").map do |finding|
      [finding.fetch("path"), finding.fetch("message"), finding.fetch("plugin"), finding.fetch("policy"), finding.fetch("severity").to_sym]
    end
    paid_off = object.fetch("paid_off", []).map { |each| [each.fetch("artifact"), each.fetch("message"), each.fetch("plugin"), each.fetch("policy")] }
    {findings:, notices:, faults:, paid_off:, wrote:, summary: summary_line}
  end

  def test_writes_one_object_with_its_keys_in_order
    report_port.write(result_of([violation_of("lib/a.rb", "no test"), violation_of("lib/b.rb", "x", :warning, detail: "y")]))

    assert_equal <<~JSON.delete("\n") + "\n", @out.string
      {"crosslint_version":"1.4.0","findings":[{"path":"lib/a.rb","message":"no test","plugin":"tests","policy":"has-test","artifact":"lib/a.rb","role":"ruby-file","severity":"error","detail":null,"line":null},
      {"path":"lib/b.rb","message":"x","plugin":"tests","policy":"has-test","artifact":"lib/b.rb","role":"ruby-file","severity":"warning","detail":"y","line":null}],
      "paid_off":[],"summary":{"artifacts":9,"errors":1,"warnings":1,"paid_off":0}}
    JSON
    assert_equal "crosslint: checked 9 ruby-file artifacts: 1 error, 1 warning\n", @err.string
  end

  def test_writes_a_violations_primary_piece_as_its_path_and_its_name_as_its_artifact
    named = Violation.new(plugin: "tests", policy: "has-test", artifact: "app/a", path: "lib/app/a.rb", role: "ruby-file", message: "no test",
      severity: :error, detail: nil)
    report_port.write(result_of([named]))

    assert_equal [["lib/app/a.rb", "app/a", nil]], JSON.parse(@out.string).fetch("findings").map { [it.fetch("path"), it.fetch("artifact"), it.fetch("line")] }
  end

  def test_writes_each_paid_off_entry_with_its_keys_in_order
    paid_off = PaidOffEntry.new(plugin: "tests", policy: "has-test", artifact: "lib/a.rb", file: "debt.tsv", line: 2, message: "is paid off")
    report_port.write(result_of([paid_off]))

    assert_equal %({"crosslint_version":"1.4.0","findings":[],"paid_off":[{"file":"debt.tsv","line":2,"plugin":"tests","policy":"has-test","artifact":"lib/a.rb",) +
      %("message":"is paid off"}],"summary":{"artifacts":9,"errors":1,"warnings":1,"paid_off":0}}\n), @out.string
  end

  def test_writes_the_object_with_no_summary_line_when_quiet
    report_port.write(result_of([], verbosity: :quiet))

    assert_equal [%({"crosslint_version":"1.4.0","findings":[],"paid_off":[],"summary":{"artifacts":9,"errors":1,"warnings":1,"paid_off":0}}\n), ""], [@out.string, @err.string]
  end

  def test_leaves_passing_artifacts_out
    artifact = Artifact.new(plugin: "tests", role: "ruby-file", path: "lib/a.rb", match: {}, pieces: [])
    report_port.write(result_of([artifact]))

    assert_equal [], JSON.parse(@out.string).fetch("findings")
  end

  def test_writes_no_object_when_silent
    report_port.write(result_of([], verbosity: :silent))

    assert_equal ["", ""], [@out.string, @err.string]
  end

  def test_writes_only_the_faults_when_silent
    fault = Fault.new(plugin: "tests", rule: "r", artifact: nil, message: "requires rainbow", trace: ["a.rb:1"])
    report_port.write(result_of([], verbosity: :silent, faults: [fault]))

    assert_equal ["", "crosslint: fault in plugin tests: rule r requires rainbow\n"], [@out.string, @err.string]
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
    faults = @port.results.flat_map(&:faults).map { |fault| [fault.plugin, fault.rule, fault.artifact, fault.message] }
    summary = results.find { |result| result.verbosity == :normal }&.summary&.line
    paid_off = results.flat_map(&:paid_off).map { |each| [each.artifact, each.message, each.plugin, each.policy] }
    {findings:, notices:, faults:, paid_off:, wrote: results.flat_map(&:wrote), summary:}
  end

  def test_holds_every_result_written_in_order
    port = report_port
    first = result_of([])
    second = result_of([], verbosity: :quiet)
    port.write(first)
    port.write(second)

    assert_equal [first, second], port.results
  end

  def test_holds_the_counts_of_every_start_in_order
    port = report_port
    port.start([["ruby-file", 2]])
    port.start([["doc", 1]])

    assert_equal [[[["ruby-file", 2]], [["doc", 1]]], []], [port.starts, port.results]
  end
end
