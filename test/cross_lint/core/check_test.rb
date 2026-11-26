# frozen_string_literal: true

require "test_helper"

# Core::Check against the in-memory project-files adapter: every
# requirement of checking that isn't about Git, the filesystem, or how the
# report looks.
class CheckTest < Minitest::Test
  cover "CrossLint::Core::Check*"
  cover "CrossLint::Core::BuiltInRule*"
  cover "CrossLint::Core::Condition*"

  include CrossLint::Core

  ROOT = File.expand_path("/app")

  INVOICES = %w[currency invoice line_item pdf customer tax total discount payment].map { |name| "lib/invoices/#{name}.rb" }
  TESTED = %w[invoice line_item customer total discount payment].map { |name| "test/invoices/#{name}_test.rb" }

  def test_reports_each_artifact_whose_companion_is_missing
    result = check(project(tests_plugin), files: INVOICES + TESTED)

    assert_equal [
      ["lib/invoices/currency.rb", "no test file at test/invoices/currency_test.rb"],
      ["lib/invoices/pdf.rb", "no test file at test/invoices/pdf_test.rb"],
      ["lib/invoices/tax.rb", "no test file at test/invoices/tax_test.rb"]
    ], result.findings.map { |violation| [violation.artifact, violation.message] }
    assert_equal ["checked 9 ruby-file artifacts: 3 errors", true], [result.summary.line, result.failed]
  end

  def test_gives_each_violation_its_plugin_policy_artifact_role_and_severity
    violation = check(project(tests_plugin), files: ["lib/a.rb"]).findings.first

    assert_equal Violation.new(plugin: "tests", policy: "has-test", artifact: "lib/a.rb", role: "ruby-file",
      message: "no test file at test/a_test.rb", severity: :error, detail: nil), violation
  end

  def test_gives_an_artifact_and_its_violations_the_key_its_declaration_gives
    keyed = declaration("ruby-file", "lib/{path}.rb", "test" => "test/{path}_test.rb").with(key: PathPattern.new(source: "{path}"))
    plugin = plugin("tests", artifacts: [keyed, declaration("rake-file", "{path}.rake", "test" => "test/{path}_test.rb")],
      policies: [policy("has-test", rules: [rule]), policy("rake-has-test", rules: [rule], applies_to: "rake-file")])

    assert_equal [["lib/app/a.rb", "app/a"], ["tasks.rake", nil]], check(project(plugin), files: ["lib/app/a.rb", "tasks.rake"]).findings.map { [_1.artifact, _1.key] }
  end

  def test_passes_when_every_companion_exists
    result = check(project(tests_plugin), files: ["lib/a.rb", "lib/a/b.rb", "test/a_test.rb", "test/a/b_test.rb", "README.md"])

    assert_equal [[], "checked 2 ruby-file artifacts: no violations", false], [result.findings, result.summary.line, result.failed]
    assert_equal :normal, result.verbosity
  end

  def test_asks_whether_a_companion_exists_of_the_filesystem_not_of_git
    result = check(project(tests_plugin), files: ["lib/a.rb"], ignored: ["test/a_test.rb"])

    assert_empty result.findings
  end

  def test_reports_a_companion_that_exists_with_companion_absent
    plugin = tests_plugin(rules: [rule("companion-absent", companion: "test")])

    assert_equal [["lib/a.rb", "test file exists at test/a_test.rb"]],
      check(project(plugin), files: ["lib/a.rb", "test/a_test.rb", "lib/b.rb"]).findings.map { |violation| [violation.artifact, violation.message] }
  end

  def test_applies_a_policy_only_where_its_condition_holds
    files = ["lib/a.rb", "lib/b.rb", "lib/c.rb", "lib/d.rb", "sig/a.rbs", "sig/b.rbs", "doc/a.md", "doc/c.md"]
    has = ->(name) { Condition::CompanionExists.new(companion: name, line: 7) }
    cases = {
      has.call("signature") => ["lib/a.rb", "lib/b.rb"],
      Condition::Not.new(condition: has.call("signature"), line: 7) => ["lib/c.rb", "lib/d.rb"],
      Condition::All.new(conditions: [has.call("signature"), has.call("doc")], line: 7) => ["lib/a.rb"],
      Condition::Any.new(conditions: [has.call("signature"), has.call("doc")], line: 7) => ["lib/a.rb", "lib/b.rb", "lib/c.rb"]
    }
    cases.each do |condition, expected|
      plugin = plugin("tests", artifacts: [declaration("ruby-file", "lib/{path}.rb", "test" => "test/{path}_test.rb",
        "signature" => "sig/{path}.rbs", "doc" => "doc/{path}.md")], policies: [policy("has-test", rules: [rule], condition:)])

      assert_equal expected, check(project(plugin), files:).findings.map(&:artifact), condition.inspect
    end
  end

  def test_runs_every_rule_of_a_policy
    plugin = plugin("tests", artifacts: [declaration("ruby-file", "lib/{path}.rb", "test" => "test/{path}_test.rb", "signature" => "sig/{path}.rbs")],
      policies: [policy("complete", rules: [rule, rule(companion: "signature")])])

    assert_equal ["no signature file at sig/a.rbs", "no test file at test/a_test.rb"],
      check(project(plugin), files: ["lib/a.rb"]).findings.map(&:message)
  end

  def test_gives_a_violation_the_severity_of_its_rule_its_policy_or_the_configuration
    warning = tests_plugin(rules: [rule(severity: :warning)])
    severities = ->(plugin, settings = []) { check(project(plugin, policies: settings), files: ["lib/a.rb"]).findings.map(&:severity) }

    assert_equal [:error], severities.call(tests_plugin)
    assert_equal [:warning], severities.call(warning)
    assert_equal [:error], severities.call(warning, [setting("tests/has-test", severity: :error)])
    assert_equal [:warning], severities.call(tests_plugin, [setting("tests/has-test", severity: :warning)])
    assert_equal [:warning], severities.call(warning, [setting("tests/has-test", enabled: true)])
    assert_equal [:error], severities.call(tests_plugin, [setting("tests/other", severity: :warning)])
  end

  def test_runs_no_policy_the_configuration_disables
    result = check(project(tests_plugin, policies: [setting("tests/has-test", enabled: false)]), files: ["lib/a.rb"])

    assert_equal [[], "checked 0 artifacts: no violations", false], [result.findings, result.summary.line, result.failed]
  end

  def test_shows_warnings_by_default_and_fails_only_on_errors
    result = check(project(tests_plugin(rules: [rule(severity: :warning)])), files: ["lib/a.rb"])

    assert_equal [[:warning], "checked 1 ruby-file artifact: 1 warning", false],
      [result.findings.map(&:severity), result.summary.line, result.failed]
  end

  def test_hides_warnings_with_none
    result = check(project(mixed_plugin), files: ["lib/a.rb"], warnings: :none)

    assert_equal [["no test file at test/a_test.rb"], "checked 1 ruby-file artifact: 1 error", true],
      [result.findings.map(&:message), result.summary.line, result.failed]
    result = check(project(tests_plugin(rules: [rule(severity: :warning)])), files: ["lib/a.rb"], warnings: :none)

    assert_equal [[], "checked 1 ruby-file artifact: no errors", false], [result.findings, result.summary.line, result.failed]
  end

  def test_fails_on_a_warning_with_error
    result = check(project(tests_plugin(rules: [rule(severity: :warning)])), files: ["lib/a.rb"], warnings: :error)

    assert_equal [[:warning], true], [result.findings.map(&:severity), result.failed]
  end

  def test_takes_warnings_from_the_configuration_unless_the_command_line_gives_it
    plugin = tests_plugin(rules: [rule(severity: :warning)])

    assert check(project(plugin, warnings: :error), files: ["lib/a.rb"]).failed
    refute check(project(plugin, warnings: :error), files: ["lib/a.rb"], warnings: :all).failed
    assert_empty check(project(plugin, warnings: :none), files: ["lib/a.rb"]).findings
  end

  def test_reports_only_what_fails_the_check_when_quiet
    result = check(project(mixed_plugin), files: ["lib/a.rb"], verbosity: :quiet)

    assert_equal [["no test file at test/a_test.rb"], :quiet, true], [result.findings.map(&:message), result.verbosity, result.failed]
    assert_equal "checked 1 ruby-file artifact: 1 error, 1 warning", result.summary.line
    assert_equal 2, check(project(mixed_plugin), files: ["lib/a.rb"], verbosity: :quiet, warnings: :error).findings.size
  end

  def test_reports_nothing_when_silent
    result = check(project(mixed_plugin, unused: true), files: ["lib/a.rb"], verbosity: :silent, warnings: :error, all: true)

    assert_equal [[], [], :silent, true], [result.findings, result.notices, result.verbosity, result.failed]
  end

  def test_takes_the_verbosity_from_the_configuration_unless_the_command_line_gives_it
    assert_equal :quiet, check(project(tests_plugin, verbosity: :quiet), files: []).verbosity
    assert_equal :normal, check(project(tests_plugin, verbosity: :quiet), files: [], verbosity: :normal).verbosity
  end

  def test_lists_each_passing_artifact_with_all_in_order_among_the_violations
    result = check(project(tests_plugin), files: ["lib/c.rb", "lib/b.rb", "lib/a.rb", "test/a_test.rb", "test/c_test.rb"], all: true)

    assert_equal [["lib/a.rb", Artifact], ["lib/b.rb", Violation], ["lib/c.rb", Artifact]],
      result.findings.map { |finding| [finding.is_a?(Violation) ? finding.artifact : finding.path, finding.class] }
    assert_equal "checked 3 ruby-file artifacts: 1 error", result.summary.line
    assert_equal [Violation], check(project(tests_plugin), files: ["lib/a.rb", "lib/b.rb", "test/a_test.rb"], all: true,
      verbosity: :quiet).findings.map(&:class)
  end

  def test_lists_no_artifact_with_a_hidden_warning_as_passing
    result = check(project(tests_plugin(rules: [rule(severity: :warning)])), files: ["lib/a.rb"], all: true, warnings: :none)

    assert_empty result.findings
  end

  def test_lists_a_passing_artifact_with_its_companions_and_match
    artifact = check(project(tests_plugin), files: ["lib/a/b.rb", "test/a/b_test.rb"], all: true).findings.first

    assert_equal Artifact.new(plugin: "tests", role: "ruby-file", path: "lib/a/b.rb", match: {"path" => "a/b"},
      companions: [Companion.new(name: "test", path: "test/a/b_test.rb", exists: true)]), artifact
  end

  def test_sorts_findings_by_artifact_then_plugin_policy_and_message
    other = plugin("other", artifacts: [declaration("ruby-file", "lib/{path}.rb", "spec" => "spec/{path}_spec.rb")],
      policies: [policy("has-spec", rules: [rule(companion: "spec")]), policy("a-spec", rules: [rule(companion: "spec")])])
    result = check(project(tests_plugin, other), files: ["lib/b.rb", "lib/a.rb"])

    assert_equal [["lib/a.rb", "other", "a-spec"], ["lib/a.rb", "other", "has-spec"], ["lib/a.rb", "tests", "has-test"],
      ["lib/b.rb", "other", "a-spec"], ["lib/b.rb", "other", "has-spec"], ["lib/b.rb", "tests", "has-test"]],
      result.findings.map { |violation| [violation.artifact, violation.plugin, violation.policy] }
    assert_equal "checked 2 tests/ruby-file and 2 other/ruby-file artifacts: 6 errors", result.summary.line
  end

  def test_sorts_by_plugin_the_findings_of_policies_with_one_name
    other = plugin("other", artifacts: [], policies: [policy("has-test", applies_to: "tests/ruby-file", rules: [rule])])
    zed = plugin("zed", artifacts: [], policies: [policy("has-test", applies_to: "tests/ruby-file", rules: [rule])])

    assert_equal %w[other tests zed], check(project(tests_plugin, zed, other), files: ["lib/a.rb"]).findings.map(&:plugin)
  end

  def test_sorts_passing_artifacts_on_one_path_by_plugin_and_role_before_its_violations
    roles = %w[zed ruby-file alpha].map { |role| declaration(role, "lib/{path}.rb", "test" => "test/{path}_test.rb") }
    passing = plugin("tests", artifacts: roles, policies: roles.map { |role| policy("p-#{role.name}", applies_to: role.name, rules: [rule]) })
    spec = plugin("spec", artifacts: [declaration("ruby-file", "lib/{path}.rb", "spec" => "spec/{path}_spec.rb")],
      policies: [policy("has-spec", rules: [rule(companion: "spec")])])
    findings = check(project(passing, spec), files: ["lib/a.rb", "test/a_test.rb", "spec/a_spec.rb"], all: true).findings

    assert_equal [%w[spec ruby-file], %w[tests alpha], %w[tests ruby-file], %w[tests zed]], findings.map { |finding| [finding.plugin, finding.role] }
    mixed = plugin("tests", artifacts: [roles.first, declaration("ruby-file", "lib/{path}.rb", "signature" => "sig/{path}.rbs")],
      policies: [policy("p-zed", applies_to: "zed", rules: [rule]), policy("has-signature", rules: [rule(companion: "signature")])])
    findings = check(project(mixed), files: ["lib/a.rb", "test/a_test.rb"], all: true).findings

    assert_equal [[Artifact, "zed"], [Violation, "ruby-file"]], findings.map { |finding| [finding.class, finding.role] }
  end

  def test_applies_a_policy_to_another_plugins_artifact
    other = plugin("other", artifacts: [], policies: [policy("has-test", applies_to: "tests/ruby-file", rules: [rule])])
    result = check(project(tests_plugin(policies: []), other), files: ["lib/a.rb"])

    assert_equal [["other", "ruby-file"]], result.findings.map { |violation| [violation.plugin, violation.role] }
    assert_equal "checked 1 ruby-file artifact: 1 error", result.summary.line
  end

  def test_finds_a_file_two_artifacts_match_as_a_primary_file_of_each
    plugin = plugin("tests", artifacts: [declaration("ruby-file", "lib/{path}.rb", "test" => "test/{path}_test.rb"),
      declaration("library", "lib/{name}.rb", "test" => "spec/{name}_spec.rb")],
      policies: [policy("has-test", rules: [rule]), policy("has-spec", applies_to: "library", rules: [rule])])
    result = check(project(plugin), files: ["lib/a.rb", "lib/x/y.rb"])

    assert_equal [["lib/a.rb", "library"], ["lib/a.rb", "ruby-file"], ["lib/x/y.rb", "ruby-file"]],
      result.findings.map { |violation| [violation.artifact, violation.role] }
    assert_equal "checked 2 ruby-file and 1 library artifacts: 3 errors", result.summary.line
  end

  def test_counts_only_the_kinds_an_enabled_policy_applies_to
    plugin = plugin("tests", artifacts: [declaration("ruby-file", "lib/{path}.rb", "test" => "test/{path}_test.rb"),
      declaration("doc", "doc/{path}.md")], policies: [policy("has-test", rules: [rule])])

    assert_equal "checked 1 ruby-file artifact: 1 error", check(project(plugin), files: ["lib/a.rb", "doc/a.md"]).summary.line
  end

  def test_warns_of_a_files_pattern_that_matches_no_file
    plugin = plugin("tests", artifacts: [declaration("ruby-file", "lib/{path}.rb", "test" => "test/{path}_test.rb"),
      declaration("doc", "docs/{path}.md", line: 9)], policies: [policy("has-test", rules: [rule])])
    result = check(project(plugin), files: ["lib/a.rb", "test/a_test.rb"])

    assert_equal [Notice.new(file: ".config/tests/plugin.kdl", line: 9,
      message: %(no file matches "docs/{path}.md", the files of artifact "doc"))], result.notices
    refute result.failed
  end

  def test_warns_of_a_ruby_rule_no_policy_runs
    result = check(project(tests_plugin, unused: true), files: ["lib/a.rb", "test/a_test.rb"])

    assert_equal [Notice.new(file: ".config/tests/plugin.kdl", line: 3, message: %(no policy runs rule "unused", so CrossLint doesn't load it))],
      result.notices
  end

  def test_treats_its_own_warnings_as_warnings
    files = ["lib/a.rb", "test/a_test.rb"]
    plugin = project(tests_plugin, unused: true)

    assert_empty check(plugin, files:, warnings: :none).notices
    refute check(plugin, files:, warnings: :none).failed
    assert_empty check(plugin, files:, verbosity: :quiet).notices
    assert_empty check(plugin, files:, verbosity: :quiet, warnings: :all).notices
    assert_equal 1, check(plugin, files:, verbosity: :quiet, warnings: :error).notices.size
    assert check(plugin, files:, warnings: :error).failed
    refute check(project(tests_plugin), files:, warnings: :error).failed
  end

  def test_stops_at_a_root_outside_a_git_working_tree
    port = CrossLint::Adapters::MemoryProjectFiles.new
    assert_raises(Mistake) { Check.new(project_files: port, plugin_ruby: CrossLint::Adapters::MemoryPluginRuby.new, helpers: CrossLint::Adapters::MemoryHelpers.new, steps: {}).call(project(tests_plugin)) }
  end

  # A step that records what it sees and answers with what it is given.
  class ScriptedStep
    attr_reader :inputs

    def initialize(answer = nil, **result)
      @answer = answer || ->(_) { CrossLint::Core::StepResult.new(excused: [], violations: [], stale: [], notices: [], wrote: [], summary: []).with(**result) }
      @inputs = []
    end

    def policies = ["has-debt"]

    def check_settings(_settings, _file) = nil

    def call(input)
      @inputs << input
      @answer.call(input)
    end
  end

  def stepped(name = "debt", flags: [])
    manifest = Manifest.new(file: "#{name}/plugin.kdl", artifacts: [], policies: [], rules: [], helpers: [],
      step_policies: [StepPolicy.new(name: "has-debt", line: 1)], flags: flags.map { |flag| FlagDeclaration.new(name: flag, line: 2) },
      steps: [StepDeclaration.new(name: "track-debt", line: 3)])
    Plugin.new(name:, folder: "#{ROOT}/#{name}", manifest:, listing: ListedPlugin.new(name:, ref: nil, settings: [], line: 1))
  end

  def stale(artifact) = Stale.new(plugin: "tests", policy: "has-test", artifact:, file: "debt.tsv", line: 2, message: "is stale")

  def debt_violation(severity = :error)
    Violation.new(plugin: "debt", policy: "has-debt", artifact: "debt.tsv", role: "debt-file", message: "line 2", severity:, detail: "2")
  end

  def test_runs_each_step_on_every_violation_whatever_warnings_hides
    step = ScriptedStep.new
    files = ["lib/a.rb", "lib/b.rb"]
    check(project(mixed_plugin, stepped), files:, warnings: :none, steps: {"track-debt" => step})
    input = step.inputs.fetch(0)

    assert_equal [4, "debt", [], []], [input.violations.size, input.plugin.name, input.faulted, input.flags]
    assert_equal ROOT, input.project.root
  end

  def test_leaves_out_what_a_step_excuses_and_reports_what_it_adds
    excuse = ->(input) { StepResult.new(excused: input.violations.take(1), violations: [debt_violation(:warning)], stale: [], notices: [], wrote: [], summary: ["1 accepted as debt"]) }
    result = check(project(tests_plugin, stepped), files: ["lib/a.rb", "lib/b.rb", "test/b_test.rb", "lib/c.rb"], steps: {"track-debt" => ScriptedStep.new(excuse)})

    assert_equal [["debt.tsv", "line 2"], ["lib/c.rb", "no test file at test/c_test.rb"]], result.findings.map { |each| [each.artifact, each.message] }
    assert_equal ["checked 3 ruby-file artifacts: 1 error, 1 warning, 1 accepted as debt", true], [result.summary.line, result.failed]
    excused = check(project(tests_plugin, stepped), files: ["lib/a.rb", "lib/b.rb", "test/b_test.rb"], all: true, steps: {"track-debt" => ScriptedStep.new(excuse)})

    assert_equal [["lib/a.rb", Artifact], ["lib/b.rb", Artifact], ["debt.tsv", Violation]].sort, excused.findings.map { |each| [each.is_a?(Artifact) ? each.path : each.artifact, each.class] }.sort
    refute excused.failed
  end

  def test_drops_what_a_step_adds_of_a_policy_the_configuration_disables
    step = ScriptedStep.new(violations: [debt_violation])
    result = check(project(stepped, policies: [setting("debt/has-debt", enabled: false)]), files: [], steps: {"track-debt" => step})

    assert_equal [[], false], [result.findings, result.failed]
  end

  def test_fails_at_a_stale_entry_and_reports_it_among_the_findings_even_when_quiet
    step = ScriptedStep.new(stale: [stale("lib/b.rb")])
    result = check(project(tests_plugin, stepped), files: ["lib/a.rb", "lib/c.rb"], verbosity: :quiet, steps: {"track-debt" => step})

    assert_equal ["lib/a.rb", "lib/b.rb", "lib/c.rb"], result.findings.map(&:artifact)
    assert_equal [true, 1], [result.failed, result.summary.stale]
    assert_empty check(project(stepped), files: [], verbosity: :silent, steps: {"track-debt" => step}).findings
  end

  def test_reports_a_steps_warnings_only_at_the_normal_verbosity_and_never_fails_on_them
    notice = Notice.new(file: "debt.tsv", line: 3, message: "coarse")
    step = ScriptedStep.new(notices: [notice])
    results = [{}, {verbosity: :quiet}, {warnings: :none}, {warnings: :error}].map { |options| check(project(stepped), files: [], steps: {"track-debt" => step}, **options) }

    assert_equal [[notice], [], [], [notice]], results.map(&:notices)
    assert_equal [false] * 4, results.map(&:failed)
  end

  def test_passes_a_check_that_wrote_and_says_what_it_wrote_unless_silent
    step = ScriptedStep.new(wrote: ["wrote debt.tsv"], violations: [debt_violation], stale: [stale("lib/a.rb")])
    result = check(project(stepped), files: [], steps: {"track-debt" => step})

    assert_equal [false, ["wrote debt.tsv"]], [result.failed, result.wrote]
    assert_empty check(project(stepped), files: [], verbosity: :silent, steps: {"track-debt" => step}).wrote
  end

  def test_gives_each_step_only_the_flags_its_plugin_takes
    step = ScriptedStep.new
    check(project(stepped(flags: ["update-debt"]), stepped("other")), files: [], flags: ["update-debt"], steps: {"track-debt" => step})

    assert_equal [["debt", ["update-debt"]], ["other", []]], step.inputs.map { |input| [input.plugin.name, input.flags] }
  end

  def test_runs_no_step_of_a_plugin_that_stopped_and_tells_the_others_which_stopped
    step = ScriptedStep.new
    broken = tests_plugin(rules: [rule("boom")], ruby: ["boom"]).then do |plugin|
      plugin.with(manifest: plugin.manifest.with(step_policies: [StepPolicy.new(name: "has-debt", line: 1)], steps: [StepDeclaration.new(name: "track-debt", line: 3)]))
    end
    ruby = {"#{ROOT}/.config/tests/rules/boom.rb" => ->(_namespace) { raise "boom" }}
    result = check(project(broken, stepped), files: ["lib/a.rb"], ruby:, steps: {"track-debt" => step})

    assert_equal [["debt"], [["tests"]], ["tests"]], [step.inputs.map { |input| input.plugin.name }, step.inputs.map(&:faulted), result.faults.map(&:plugin)]
  end

  def test_fails_at_a_stale_entry_alone
    step = ScriptedStep.new(stale: [stale("lib/a.rb")], summary: ["0 accepted as debt"])
    result = check(project(stepped, stepped("other")), files: [], steps: {"track-debt" => step})

    assert_equal [true, ["0 accepted as debt", "0 accepted as debt"]], [result.failed, result.summary.steps]
  end

  def test_drops_only_what_a_step_adds_of_the_policy_the_configuration_disables
    kept = debt_violation.with(policy: "kept")
    policies = [setting("debt/kept", severity: :error), setting("debt/has-debt", enabled: false), setting("other/kept", enabled: false)]
    result = check(project(stepped, policies:), files: [], steps: {"track-debt" => ScriptedStep.new(violations: [debt_violation, kept])})

    assert_equal [kept], result.findings
  end

  def test_gives_each_step_the_flags_its_plugin_takes_among_others
    step = ScriptedStep.new
    check(project(stepped(flags: ["x", "update-debt"]), stepped("other", flags: ["x"])), files: [], flags: ["update-debt", "x"],
      steps: {"track-debt" => step})

    assert_equal [["debt", ["update-debt", "x"]], ["other", ["x"]]], step.inputs.map { |input| [input.plugin.name, input.flags] }
    mistake = assert_raises(Mistake) { check(project(stepped("other", flags: ["x"]), stepped(flags: ["y"])), files: [], flags: ["y", "nope"]) }

    assert_equal "lists no plugin that takes --nope", mistake.message
  end

  def test_stops_at_a_flag_no_listed_plugin_takes
    mistake = assert_raises(Mistake) { check(project(stepped), files: [], flags: ["update-debt"]) }

    assert_equal [".config/crosslint/config.kdl", "lists no plugin that takes --update-debt"], [mistake.location, mistake.message]
  end

  private

  def check(project, files:, ignored: [], steps: {}, ruby: {}, **options)
    port = CrossLint::Adapters::MemoryProjectFiles.new({ROOT => files}, ignored: {ROOT => ignored})
    Check.new(project_files: port, plugin_ruby: CrossLint::Adapters::MemoryPluginRuby.new(ruby), helpers: CrossLint::Adapters::MemoryHelpers.new, steps:)
      .call(project, **options)
  end

  def declaration(name, files, line: 1, **companions)
    ArtifactDeclaration.new(name:, files: PathPattern.new(source: files), line:,
      companions: companions.map { |companion, pattern| CompanionDeclaration.new(name: companion, pattern: PathPattern.new(source: pattern), line: line + 1) })
  end

  def rule(name = "companion-exists", companion: "test", severity: nil, line: 6)
    arguments = BuiltInRule.named(name) ? {"companion" => companion} : {}
    PolicyRule.new(name:, arguments:, severity:, line:)
  end

  def policy(name, rules:, applies_to: "ruby-file", condition: nil)
    Policy.new(name:, applies_to: AppliesTo.new(artifact: applies_to, line: 6), condition:, rules:, line: 5)
  end

  def plugin(name, artifacts:, policies:, ruby: [])
    rules = ruby.map { |rule| RuleDeclaration.new(name: rule, ruby: "rules/#{rule}.rb", line: 3) }
    manifest = Manifest.new(file: ".config/#{name}/plugin.kdl", artifacts:, policies:, rules:, helpers: [])
    Plugin.new(name:, folder: "#{ROOT}/.config/#{name}", listing: ListedPlugin.new(name: "./.config/#{name}", ref: nil, settings: [], line: 1),
      manifest:)
  end

  def tests_plugin(rules: [rule], policies: nil, ruby: [])
    plugin("tests", artifacts: [declaration("ruby-file", "lib/{path}.rb", "test" => "test/{path}_test.rb")],
      policies: policies || [policy("has-test", rules:)], ruby:)
  end

  def mixed_plugin
    plugin("tests", artifacts: [declaration("ruby-file", "lib/{path}.rb", "test" => "test/{path}_test.rb", "signature" => "sig/{path}.rbs")],
      policies: [policy("has-test", rules: [rule]), policy("has-signature", rules: [rule(companion: "signature", severity: :warning)])])
  end

  def setting(name, enabled: nil, severity: nil) = PolicySetting.new(name:, enabled:, severity:, line: 4)

  def project(*plugins, policies: [], warnings: nil, verbosity: nil, unused: false)
    if unused
      first = plugins.first
      rules = [RuleDeclaration.new(name: "unused", ruby: "unused.rb", line: 3)]
      plugins = [first.with(manifest: first.manifest.with(rules:))] + plugins.drop(1)
    end
    configuration = Configuration.new(file: ".config/crosslint/config.kdl", plugins: plugins.map(&:listing), policies:, warnings:, verbosity:)
    Project.new(root: ROOT, configuration:, plugins:)
  end
end
