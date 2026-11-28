# frozen_string_literal: true

require "test_helper"

# Rules a plugin's helper runs, declared as rule NAME helper=HELPER and
# run by Core::Check through the in-memory helpers port: what the helper
# is sent, what its answer becomes, and how its faults stop the plugin.
class HelperRuleTest < Minitest::Test
  cover "CrossLint::Core::HelperRule*"
  cover "CrossLint::Core::Check*"

  include CrossLint::Core

  ROOT = File.expand_path("/app")

  def test_sends_the_helper_the_rule_and_the_artifact_with_its_pieces
    seen = []
    check(files: ["lib/a.rb", "sig/a.rbs"], answer: -> (input) { (seen << input) && { "violations" => [] } })

    assert_equal [
{
"rule" => "names-class",
"artifact" => {
"path" => "lib/a.rb",
"name" => "lib/a.rb",
"role" => "ruby-file",
"line" => nil,
"match" => { "path" => "a" },
"key" => "a",
"pieces" => { "signature" => { "path" => "sig/a.rbs", "exists" => true }, "test" => { "path" => "test/a_test.rb", "exists" => false } },
},
},
], seen
  end

  def test_sends_the_helper_the_artifacts_name_and_the_line_its_regex_matched_at
    seen = []
    function = ruby_file.with(regex: Regex.new(source: 'def (?<function>\w+)'), name_pattern: PathPattern.new(source: "{path}:{function}", captures: %w[function]))
    check(files: ["lib/a.rb"], contents: { "lib/a.rb" => "# a\ndef run\nend\ndef walk\nend\n" }, artifact: function, answer: -> (input) { (seen << input) && { "violations" => [] } })

    assert_equal [["a:run", 2], ["a:walk", 4]], seen.map { |input| input["artifact"].values_at("name", "line") }
  end

  def test_reports_what_the_helper_answers_as_violations_of_its_policy
    answer = -> (_) { { "violations" => [{ "message" => "names no class", "detail" => "A" }, { "message" => "has no test" }] } }
    result = check(files: ["lib/a.rb"], answer:)

    assert_equal [["lib/a.rb", "ruby-file", "names-match", "has no test", nil, :error], ["lib/a.rb", "ruby-file", "names-match", "names no class", "A", :error]],
      result.findings.map { |violation| [violation.artifact, violation.role, violation.policy, violation.message, violation.detail, violation.severity] }
    assert_equal [[], "checked 1 ruby-file artifact: 2 errors"], [result.faults, result.summary.line]
  end

  def test_stops_only_the_plugin_whose_helper_fails_says_so_or_answers_what_isnt_violations
    {
      -> (_) { raise PluginError, "called helper reader, which exited with status 1 before it answered" } =>
        "called helper reader, which exited with status 1 before it answered",
      -> (_) { { "error" => "can't read lib/a.rb" } } => %(failed in helper "reader": can't read lib/a.rb),
      -> (_) { [] } => %(got an answer from helper "reader" that isn't {"violations": [...]}),
      -> (_) { { "violations" => {} } } => %(got an answer from helper "reader" that isn't {"violations": [...]}),
      -> (_) { { "violations" => [3] } } => %(got a violation from helper "reader" that isn't {"message": TEXT, "detail": TEXT}),
      -> (_) { { "violations" => [{ "message" => 3 }] } } => %(got a violation from helper "reader" that isn't {"message": TEXT, "detail": TEXT}),
      -> (_) { { "violations" => [{ "message" => "m", "detail" => 3 }] } } => %(got a violation from helper "reader" that isn't {"message": TEXT, "detail": TEXT}),
    }.each do |answer, message|
      result = check(files: ["lib/a.rb"], answer:, others: true)

      assert_equal [["tests", "names-class", "lib/a.rb", message]], result.faults.map { |fault| [fault.plugin, fault.rule, fault.artifact, fault.message] }, message
      assert_equal ["other"], result.findings.map(&:plugin), message
    end
  end

  def test_gives_a_helpers_rule_the_severity_its_rule_line_gives_or_error
    answer = -> (_) { { "violations" => [{ "message" => "m" }] } }

    assert_equal [[:error], [:warning]], [nil, :warning].map { |severity| check(files: ["lib/a.rb"], answer:, severity:).findings.map(&:severity) }
  end

  def test_says_under_debug_what_the_helper_gets_and_answers_as_json
    debug = CrossLint::Adapters::MemoryDebugOutput.new
    check(files: ["lib/a.rb"], answer: -> (_) { { "violations" => [{ "message" => "no class Café" }] } }, debug:)

    assert_equal [
      %(tests/reader gets {"rule":"names-class","artifact":{"path":"lib/a.rb","name":"lib/a.rb","role":"ruby-file","line":null,"match":{"path":"a"},) +
        %("key":"a","pieces":{"signature":{"path":"sig/a.rbs","exists":false},"test":{"path":"test/a_test.rb","exists":false}}}}),
      %(tests/reader answers {"violations":[{"message":"no class Café"}]}),
], debug.written("helper")
  end

  private

  def ruby_file
    ArtifactDeclaration.new(name: "ruby-file", primary: PathPattern.new(source: "lib/{path}.rb"), line: 1, key: PathPattern.new(source: "{path}"),
      pieces: %w[signature test].map { |name| PieceDeclaration.new(name:, pattern: PathPattern.new(source: (name == "test") ? "test/{path}_test.rb" : "sig/{path}.rbs"), line: 2) })
  end

  def check(files:, answer:, contents: {}, severity: nil, others: false, artifact: ruby_file, debug: nil)
    rule = PolicyRule.new(name: "names-class", arguments: {}, severity:, line: 7)
    policy = Policy.new(name: "names-match", applies_to: AppliesTo.new(artifact: "ruby-file", line: 6), condition: nil, rules: [rule], line: 5)
    manifest = Manifest.new(file: ".config/tests/plugin.kdl", artifacts: [artifact], policies: [policy],
      rules: [RuleDeclaration.new(name: "names-class", helper: "reader", line: 3)], helpers: [HelperDeclaration.new(name: "reader", command: "node", file: "reader.mjs", line: 9)])
    plugins = [plugin("tests", manifest)]
    if others
      everything = PolicyRule.new(name: "piece-exists", arguments: { "piece" => "test" }, severity: nil, line: 3)
      plugins << plugin("other", Manifest.new(file: ".config/other/plugin.kdl", artifacts: [], helpers: [], rules: [],
        policies: [Policy.new(name: "all", applies_to: AppliesTo.new(artifact: "tests/ruby-file", line: 2), condition: nil, rules: [everything], line: 1)]))
    end
    configuration = Configuration.new(file: ".config/crosslint/config.kdl", plugins: plugins.map(&:listing), policies: [], warnings: nil, verbosity: nil)
    project_files = CrossLint::Adapters::MemoryProjectFiles.new({ ROOT => files }, contents: { ROOT => contents })
    helpers = CrossLint::Adapters::MemoryHelpers.new({ "tests/reader" => answer }, commands: ["node"])
    Check.new(project_files:, crosslint_ruby: CrossLint::Adapters::MemoryCrossLintRuby.new, helpers:, steps: {}, debug:)
      .call(Project.new(root: ROOT, configuration:, plugins:))
  end

  def plugin(name, manifest)
    Plugin.new(name:, folder: "#{ROOT}/.config/#{name}", listing: ListedPlugin.new(name: "./.config/#{name}", ref: nil, settings: [], line: 1), manifest:)
  end
end
