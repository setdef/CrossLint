# frozen_string_literal: true

require "test_helper"

# Rules written in Ruby, run by Core::Check through the in-memory
# plugin-Ruby port: what docs/design/plugins.md requires of Ruby rules,
# except what only files on disk show (FilePluginRubyTest).
class RubyRuleTest < Minitest::Test
  cover "CrossLint::Core::RubyRule*"
  cover "CrossLint::Core::Fault*"
  cover "CrossLint::Core::Check*"
  cover "CrossLint::Rule*"

  include CrossLint::Core

  ROOT = File.expand_path("/app")

  RULES = "#{ROOT}/.config/tests/rules".freeze

  NAMES_CLASS = <<~RUBY
    class NamesClass < CrossLint::Rule
      def check(artifact)
        signature = artifact.companion("signature")
        return [] unless signature.exist?
        return [] if signature.read.include?(artifact.match["path"].capitalize)

        [violation(artifact, "\#{signature.path} names no class", detail: artifact.match["path"])]
      end
    end
  RUBY

  def test_reports_what_a_ruby_rule_finds_as_violations_of_its_policy
    result = check(files: {"lib/a.rb" => "", "sig/a.rbs" => "class A\n", "lib/b.rb" => "", "sig/b.rbs" => "class C\n", "lib/c.rb" => ""})

    assert_equal [Violation.new(plugin: "tests", policy: "names-match", artifact: "lib/b.rb", role: "ruby-file", message: "sig/b.rbs names no class",
      severity: :error, detail: "b")], result.findings
    assert_equal [[], true, "checked 3 ruby-file artifacts: 1 error"], [result.faults, result.failed, result.summary.line]
  end

  def test_gives_a_ruby_rule_the_severity_its_rule_line_and_the_configuration_give
    files = {"lib/b.rb" => "", "sig/b.rbs" => ""}

    assert_equal [:warning], check(files:, severity: :warning).findings.map(&:severity)
    assert_equal [:error], check(files:, severity: :warning, override: :error).findings.map(&:severity)
  end

  def test_shows_a_rule_the_artifact_its_match_and_its_companions
    seen = []
    rule = Class.new(CrossLint::Rule) do
      define_method(:check) do |artifact|
        signature = artifact.companion("signature")
        seen << [artifact.path, artifact.role, artifact.match, artifact.match.frozen?, artifact.read]
        seen << [signature.name, signature.path, signature.exist?, signature.read]
        []
      end
    end
    check(code: {"names_class.rb" => ->(namespace) { namespace.const_set(:NamesClass, rule) }},
      files: {"lib/x/a.rb" => "# a\n", "sig/x/a.rbs" => "class A\n"})

    assert_equal [["lib/x/a.rb", "ruby-file", {"path" => "x/a"}, true, "# a\n"], ["signature", "sig/x/a.rbs", true, "class A\n"]], seen
  end

  def test_makes_one_instance_of_a_rule_for_the_whole_check
    counting = <<~RUBY
      class NamesClass < CrossLint::Rule
        def check(artifact)
          @count = (@count || 0) + 1
          [violation(artifact, "artifact \#{@count}")]
        end
      end
    RUBY

    assert_equal ["artifact 1", "artifact 2"], check(code: {"names_class.rb" => counting}, files: {"lib/a.rb" => "", "lib/b.rb" => ""}).findings.map(&:message)
  end

  def test_loads_each_rule_once_and_only_for_an_enabled_policy
    loads = []
    code = {"names_class.rb" => ->(namespace) { loads << namespace.module_eval(NAMES_CLASS) }}
    check(code:, files: {"lib/a.rb" => ""}, policies: 2)

    assert_equal 1, loads.size
    check(code:, files: {"lib/a.rb" => ""}, override: nil, enabled: false)

    assert_equal 1, loads.size
  end

  def test_stops_at_a_rule_file_the_plugin_lacks_before_it_checks
    mistake = assert_raises(Mistake) { check(code: {}, files: {"lib/a.rb" => ""}) }

    assert_equal [".config/tests/plugin.kdl:3", %(no file "rules/names_class.rb" in the plugin's folder)], [mistake.location, mistake.message]
  end

  def test_stops_only_the_plugin_whose_rule_raises
    raising = "class NamesClass < CrossLint::Rule\n  def check(artifact) = raise(\"boom on \#{artifact.path}\")\nend\n"
    result = check(code: {"names_class.rb" => raising}, files: {"lib/a.rb" => "", "lib/b.rb" => ""}, others: true)
    fault = result.faults.fetch(0)

    assert_equal [["tests", "names-class", "lib/a.rb", "raised RuntimeError: boom on lib/a.rb"]],
      result.faults.map { |each| [each.plugin, each.rule, each.artifact, each.message] }
    assert_equal "#{RULES}/names_class.rb:2", fault.trace.first[/\A.*?:\d+/]
    assert_equal [["other", "lib/a.rb"], ["other", "lib/b.rb"]], result.findings.map { |violation| [violation.plugin, violation.artifact] }
  end

  def test_stops_a_plugin_whose_rule_fails_to_load_and_runs_none_of_its_policies
    result = check(code: {"names_class.rb" => "raise ArgumentError, 'no'\n"}, files: {"lib/a.rb" => ""}, others: true)

    assert_equal [["tests", "names-class", nil, "raised ArgumentError: no"]], result.faults.map { |each| [each.plugin, each.rule, each.artifact, each.message] }
    assert_equal ["other"], result.findings.map(&:plugin)
  end

  def test_says_what_is_wrong_with_a_rules_class
    {
      "class Other < CrossLint::Rule\nend\n" => "defines no class NamesClass in rules/names_class.rb",
      "NamesClass = 3\n" => "defines no class NamesClass in rules/names_class.rb",
      "class NamesClass\nend\n" => "has a class NamesClass that doesn't inherit from CrossLint::Rule",
      "class NamesClass < CrossLint::Rule\nend\n" => "has no check method",
      "class NamesClass < CrossLint::Rule\n  def initialize(x) = super()\nend\n" => "raised ArgumentError: wrong number of arguments (given 0, expected 1)"
    }.each do |source, message|
      assert_equal [message], check(code: {"names_class.rb" => source}, files: {"lib/a.rb" => ""}).faults.map(&:message), source
    end
  end

  def test_finds_no_class_for_a_rule_name_no_class_can_have
    assert_equal ["defines no class 9lives in rules/9lives.rb"],
      check(name: "9lives", code: {"9lives.rb" => ""}, files: {"lib/a.rb" => ""}).faults.map(&:message)
  end

  def test_says_what_is_wrong_with_what_a_rule_returns
    {
      "nil" => "returned NilClass from check, where check returns an array of violations",
      %("no") => "returned String from check, where check returns an array of violations",
      %(["no"]) => "returned an array holding String, where check returns violations",
      %([violation(artifact, :no)]) => "made a violation whose message is :no, which is no string",
      %([violation(artifact, "no", detail: :x)]) => "made a violation whose detail is :x, which is no string",
      %([violation(artifact.path, "no")]) => %(made a violation of "lib/a.rb", which is no artifact it was given),
      %(@last.then { |last| @last = artifact; last ? [violation(last, "no")] : [] }) => "returned a violation of lib/a.rb, which isn't the artifact it checked",
      %(artifact.companion("stub")) => %(raised KeyError: artifact "ruby-file" has no companion "stub")
    }.each do |body, message|
      source = "class NamesClass < CrossLint::Rule\n  def check(artifact)\n    #{body}\n  end\nend\n"

      assert_equal [message], check(code: {"names_class.rb" => source}, files: {"lib/a.rb" => "", "lib/b.rb" => ""}).faults.map(&:message), body
    end
  end

  def test_stops_a_rule_that_exits_rather_than_ending_the_check
    source = "class NamesClass < CrossLint::Rule\n  def check(artifact) = exit(0)\nend\n"
    faults = begin
      check(code: {"names_class.rb" => source}, files: {"lib/a.rb" => ""}).faults
    rescue SystemExit
      # Mutant reads a test process that exits with 0 as one that passed.
      flunk "the rule's exit ended the check"
    end

    assert_equal ["raised SystemExit: exit"], faults.map(&:message)
  end

  def test_stops_a_rule_that_recurses_without_end_in_its_plugin_not_the_check
    recurses = "class NamesClass < CrossLint::Rule\n  def check(artifact) = check(artifact)\nend\n"
    at_load = "def self.forever = forever\nforever\n"
    ran = check(code: {"names_class.rb" => recurses}, files: {"lib/a.rb" => ""}, others: true)
    loading = check(code: {"names_class.rb" => at_load}, files: {"lib/a.rb" => ""})

    assert_equal [["tests", "rule names-class on lib/a.rb raised SystemStackError: stack level too deep"]],
      ran.faults.map { |fault| [fault.plugin, fault.line.delete_prefix("fault in plugin tests: ")] }
    assert_equal ["raised SystemStackError: stack level too deep"], loading.faults.map(&:message)
    assert_equal ["lib/a.rb"], ran.findings.map(&:artifact)
  end

  def test_gives_a_rule_a_minute_on_each_artifact_unless_told_otherwise
    assert_equal 60, RubyRule::TIME_LIMIT
    tests = plugin("tests", Manifest.new(file: ".config/tests/plugin.kdl", artifacts: [], policies: [], rules: [], helpers: []))
    rule = RubyRule.make(Class.new(CrossLint::Rule), ->(_name, _input) {})

    assert_equal 60, RubyRule.new(plugin: tests, name: "n", rule:).instance_variable_get(:@time_limit)
  end

  def test_stops_a_rule_that_runs_past_its_time_limit_even_one_that_rescues_every_error
    rules = ["loop {}", "begin\n      loop {}\n    rescue\n      []\n    end"].map do |body|
      Class.new(CrossLint::Rule) { class_eval "def check(_artifact)\n    #{body}\n  end", __FILE__, __LINE__ }
    end
    artifact = Artifact.new(plugin: "tests", role: "ruby-file", path: "lib/a.rb", match: {}, companions: [])
    tests = plugin("tests", Manifest.new(file: ".config/tests/plugin.kdl", artifacts: [], policies: [], rules: [], helpers: []))
    faults = rules.map do |rule_class|
      rule = RubyRule.new(plugin: tests, name: "slow", rule: RubyRule.make(rule_class, ->(_name, _input) {}), time_limit: 0.2)
      assert_raises(RubyRule::Stopped) { rule.results(artifact, {}, ->(_) { "" }) }.fault
    end

    assert_equal ["fault in plugin tests: rule slow on lib/a.rb didn't finish within 0.2 seconds, so CrossLint stopped it"] * 2, faults.map(&:line)
  end

  def test_names_the_gem_a_rule_requires_that_crosslint_wasnt_built_with
    message = "requires crosslint_no_such_gem, which is neither in Ruby's standard library nor in the plugin's folder, " \
      "and CrossLint can load no gem it wasn't built with"
    at_load = check(code: {"names_class.rb" => %(require "crosslint_no_such_gem"\n)}, files: {"lib/a.rb" => ""})
    later = check(code: {"names_class.rb" => %(class NamesClass < CrossLint::Rule\n  def check(_) = require("crosslint_no_such_gem")\nend\n)},
      files: {"lib/a.rb" => ""})

    assert_equal [[message, nil], [message, "lib/a.rb"]], [at_load, later].map { |result| result.faults.map { |fault| [fault.message, fault.artifact] }.first }
  end

  def test_refuses_bundler_inline
    assert_equal ["requires bundler/inline, which CrossLint doesn't offer, since it would install gems into CrossLint's folder"],
      check(code: {"names_class.rb" => %(require "bundler/inline"\n)}, files: {"lib/a.rb" => ""}).faults.map(&:message)
  end

  def test_says_which_file_of_the_plugin_a_require_couldnt_find
    tests = plugin("tests", Manifest.new(file: ".config/tests/plugin.kdl", artifacts: [], policies: [], rules: [], helpers: []))
    describe = lambda do |path|
      missing = LoadError.new("cannot load such file")
      missing.define_singleton_method(:path) { path }
      Fault.of(missing, plugin: tests, rule: "r").message
    end

    elsewhere = File.expand_path("/q/names.rb")

    assert_equal ["requires helpers/names.rb, which doesn't exist", "requires #{elsewhere}, which doesn't exist",
      "requires ./names, which doesn't exist", "raised LoadError: cannot load such file"],
      ["#{ROOT}/.config/tests/helpers/names.rb", elsewhere, "./names", nil].map(&describe)
  end

  def test_gives_a_fault_with_no_trace_an_empty_one
    tests = plugin("tests", Manifest.new(file: ".config/tests/plugin.kdl", artifacts: [], policies: [], rules: [], helpers: []))

    assert_equal [], Fault.of(RuntimeError.new("boom"), plugin: tests, rule: "r").trace
  end

  def test_writes_a_fault_as_one_line
    fault = Fault.new(plugin: "tests", rule: "names-class", artifact: "lib/a.rb", message: "raised RuntimeError: boom", trace: [])

    assert_equal ["fault in plugin tests: rule names-class on lib/a.rb raised RuntimeError: boom",
      "fault in plugin tests: rule names-class requires rainbow"], [fault.line, fault.with(artifact: nil, message: "requires rainbow").line]
    assert_equal [fault, fault.line], RubyRule::Stopped.new(fault).then { |stopped| [stopped.fault, stopped.message] }
  end

  def test_finds_no_class_outside_the_plugins_namespace
    assert_equal ["defines no class String in rules/string.rb"],
      check(name: "string", code: {"string.rb" => ""}, files: {"lib/a.rb" => ""}).faults.map(&:message)
    assert_equal ["has a class NamesClass that doesn't inherit from CrossLint::Rule"],
      check(code: {"names_class.rb" => "NamesClass = CrossLint::Rule\n"}, files: {"lib/a.rb" => ""}).faults.map(&:message)
  end

  def test_reports_the_fault_of_each_plugin_that_stops
    raising = "class NamesClass < CrossLint::Rule\n  def check(artifact) = raise(\"boom\")\nend\n"
    result = check(code: {"names_class.rb" => raising}, files: {"lib/a.rb" => ""}, others: raising)

    assert_equal [%w[tests names-class], %w[other names-class]], result.faults.map { |fault| [fault.plugin, fault.rule] }
    assert_equal "checked 1 ruby-file artifact: 2 faults", result.summary.line
  end

  ASKS = <<~RUBY
    class NamesClass < CrossLint::Rule
      def initialize
        @members = helper("members")
      end

      def check(artifact)
        @members.call({"path" => artifact.path}).map { |member| violation(artifact, "no \#{member}", detail: member) }
      end
    end
  RUBY

  def test_calls_its_plugins_helper_from_a_ruby_rule_even_in_initialize
    seen = []
    members = ->(input) { seen << input and ["a", "b"] }
    result = check(code: {"names_class.rb" => ASKS}, files: {"lib/x.rb" => ""}, helpers: {"members" => members})

    assert_equal [[{"path" => "lib/x.rb"}], [["no a", "a"], ["no b", "b"]]], [seen, result.findings.map { |violation| [violation.message, violation.detail] }]
  end

  def test_stops_a_plugin_whose_rule_calls_a_helper_that_fails_or_that_it_doesnt_declare
    failing = ->(_) { raise PluginError, "called helper members, which exited with status 1 before it answered" }

    assert_equal ["called helper members, which exited with status 1 before it answered"],
      check(code: {"names_class.rb" => ASKS}, files: {"lib/x.rb" => ""}, helpers: {"members" => failing}).faults.map(&:message)
    assert_equal [%(called helper "members", which plugin tests doesn't declare)] * 2,
      [{}, {"others" => ->(_) { [] }}].flat_map { |helpers| check(code: {"names_class.rb" => ASKS}, files: {"lib/x.rb" => ""}, helpers:).faults.map(&:message) }
  end

  def test_starts_helpers_before_any_rule_and_stops_them_after_every_rule
    port = CrossLint::Adapters::MemoryHelpers.new({"tests/members" => ->(_) { [] }}, commands: ["node"])
    started = []
    port.define_singleton_method(:start) { |root, plugins| super(root, plugins).tap { |running| started << running } }
    check(code: {"names_class.rb" => ASKS}, files: {"lib/x.rb" => ""}, helpers: {"members" => nil}, running: port)
    assert_raises(Mistake) { check(code: {}, files: {"lib/x.rb" => ""}, helpers: {"members" => nil}, running: port) }

    assert_equal [[true, ROOT], [true, ROOT]], started.map { |running| [running.stopped, running.root] }
    mistake = assert_raises(Mistake) do
      check(code: {"names_class.rb" => "raise 'never loaded'"}, files: {"lib/x.rb" => ""}, helpers: {"members" => nil},
        running: CrossLint::Adapters::MemoryHelpers.new)
    end

    assert_equal ".config/tests/plugin.kdl:9", mistake.location
  end

  def test_ends_every_helper_at_once_on_ctrl_c_before_waiting_for_any_to_stop
    port = CrossLint::Adapters::MemoryHelpers.new({"tests/members" => ->(_) { raise Interrupt }}, commands: ["node"])
    events = []
    port.define_singleton_method(:start) do |root, plugins|
      super(root, plugins).tap do |running|
        running.define_singleton_method(:kill) { events << :kill and super() }
        running.define_singleton_method(:stop) { events << :stop and super() }
      end
    end

    assert_raises(Interrupt) { check(code: {"names_class.rb" => ASKS}, files: {"lib/x.rb" => ""}, helpers: {"members" => nil}, running: port) }
    assert_equal [:kill, :stop], events
  end

  def test_ends_no_helper_at_once_unless_ctrl_c_comes
    port = CrossLint::Adapters::MemoryHelpers.new({"tests/members" => ->(_) { [] }}, commands: ["node"])
    events = []
    port.define_singleton_method(:start) do |root, plugins|
      super(root, plugins).tap { |running| running.define_singleton_method(:kill) { events << :kill and super() } }
    end
    check(code: {"names_class.rb" => ASKS}, files: {"lib/x.rb" => ""}, helpers: {"members" => nil}, running: port)

    assert_empty events
  end

  def test_names_a_rules_class_in_camel_case
    assert_equal %w[SignatureNamesClass NamesClass X Html5Check AB], %w[signature-names-class names_class x html5-check a--b].map { RubyRule.class_name(_1) }
  end

  private

  # A check of a project at ROOT whose plugin "tests" runs the Ruby rule
  # `name` from rules/NAME_WITH_UNDERSCORES.rb on each lib/{path}.rb, with
  # the code in `code` by file name under rules/, as source or a proc.
  # With `others`, a second plugin reports every lib file with no
  # signature, or, when `others` is Ruby source, runs it as a rule
  # "names-class" of its own. The plugin "tests" declares a helper of
  # each name in `helpers`, which answers with its proc, run on "node".
  def check(files:, code: {"names_class.rb" => NAMES_CLASS}, name: "names-class", severity: nil, override: nil, enabled: nil, policies: 1,
    others: false, helpers: {}, running: CrossLint::Adapters::MemoryHelpers.new(helpers.transform_keys { |helper| "tests/#{helper}" }, commands: ["node"]))
    if others.is_a?(String)
      source = others
      code = code.merge("../../other/rules/names_class.rb" => source)
    end
    artifact = ArtifactDeclaration.new(name: "ruby-file", files: PathPattern.new(source: "lib/{path}.rb"), line: 1,
      companions: [CompanionDeclaration.new(name: "signature", pattern: PathPattern.new(source: "sig/{path}.rbs"), line: 2)])
    rule = PolicyRule.new(name:, arguments: {}, severity:, line: 7)
    policies = (1..policies).map { |index| Policy.new(name: "names-match#{index if index > 1}", applies_to: AppliesTo.new(artifact: "ruby-file", line: 6), condition: nil, rules: [rule], line: 5) }
    declaration = RuleDeclaration.new(name:, ruby: "rules/#{name.tr("-", "_")}.rb", line: 3)
    declared = helpers.keys.map { |helper| HelperDeclaration.new(name: helper, command: "node", file: "#{helper}.mjs", line: 9) }
    plugins = [plugin("tests", Manifest.new(file: ".config/tests/plugin.kdl", artifacts: [artifact], policies:, rules: [declaration], helpers: declared))]
    if others
      everything = source ? rule.with(name: "names-class") : PolicyRule.new(name: "companion-exists", arguments: {"companion" => "signature"}, severity: nil, line: 3)
      plugins << plugin("other", Manifest.new(file: ".config/other/plugin.kdl", artifacts: [],
        policies: [Policy.new(name: "all", applies_to: AppliesTo.new(artifact: "tests/ruby-file", line: 2), condition: nil, rules: [everything], line: 1)],
        rules: source ? [RuleDeclaration.new(name: "names-class", ruby: "rules/names_class.rb", line: 3)] : [], helpers: []))
    end
    settings = [PolicySetting.new(name: "tests/names-match", enabled:, severity: override, line: 4)]
    configuration = Configuration.new(file: ".config/crosslint/config.kdl", plugins: plugins.map(&:listing), policies: settings, warnings: nil, verbosity: nil)
    project_files = CrossLint::Adapters::MemoryProjectFiles.new({ROOT => files.keys}, contents: {ROOT => files})
    loaded = code.to_h do |file, text|
      path = File.expand_path(file, RULES)
      [path, text.is_a?(String) ? ->(namespace) { namespace.module_eval(text, path, 1) } : text]
    end
    Check.new(project_files:, plugin_ruby: CrossLint::Adapters::MemoryPluginRuby.new(loaded), helpers: running, steps: {})
      .call(Project.new(root: ROOT, configuration:, plugins:))
  end

  def plugin(name, manifest)
    Plugin.new(name:, folder: "#{ROOT}/.config/#{name}", listing: ListedPlugin.new(name: "./.config/#{name}", ref: nil, settings: [], line: 1), manifest:)
  end
end
