# frozen_string_literal: true

require "test_helper"

# The value objects of the core that have behavior beyond their fields.
class CoreValuesTest < Minitest::Test
  cover "CrossLint::Core::Mistake*"
  cover "CrossLint::Core::Spelling*"
  cover "CrossLint::Core::Condition*"
  cover "CrossLint::Core::ArtifactDeclaration*"
  cover "CrossLint::Core::ListedPlugin*"
  cover "CrossLint::Core::BuiltInRule*"
  cover "CrossLint::Core::Project*"

  include CrossLint::Core

  def test_a_mistake_names_where_it_is
    assert_equal ["plugin.kdl:2", "unknown"], [Mistake.new("unknown", file: "plugin.kdl", line: 2).location, Mistake.new("unknown").message]
    assert_equal "plugin.kdl", Mistake.new("x", file: "plugin.kdl").location
    assert_equal "", Mistake.new("x").location
  end

  def test_spelling_names_the_nearest_known_word
    assert_equal "files", Spelling.nearest("file", ["files", "companion"])
    assert_nil Spelling.nearest("zzz", ["files"])
    assert_equal %(unknown node "file", did you mean "files"?), Spelling.unknown("node", "file", ["files"])
    assert_equal %(unknown node "zzz"; there are none), Spelling.unknown("node", "zzz", [])
    assert_equal %(unknown node "zzz"; it takes none), Spelling.unknown("node", "zzz", [], none: "it takes none")
    assert_equal %(unknown node "\\u00E9"; expected "a"), Spelling.unknown("node", "é", ["a"])
  end

  def test_spelling_lists_words_as_in_a_sentence
    assert_equal ["a", "a or b", "a, b, or c", "a, b, c, or d"], [["a"], %w[a b], %w[a b c], %w[a b c d]].map { |words| Spelling.list(words) }
  end

  def test_a_condition_holds_its_companion_conditions
    a = Condition::CompanionExists.new(companion: "a", line: 1)
    b = Condition::CompanionExists.new(companion: "b", line: 2)
    c = Condition::CompanionExists.new(companion: "c", line: 3)
    condition = Condition::All.new(conditions: [a, Condition::Not.new(condition: Condition::Any.new(conditions: [b, c], line: 2), line: 2)], line: 1)

    assert_equal [a, b, c], condition.companion_conditions
    assert_equal [b, c], Condition::Any.new(conditions: [Condition::All.new(conditions: [b, c], line: 2)], line: 1).companion_conditions
    assert_equal [a], a.companion_conditions
  end

  def test_an_artifact_finds_its_companion_by_name
    test = CompanionDeclaration.new(name: "test", pattern: PathPattern.new(source: "test/{path}_test.rb"), line: 2)
    sig = CompanionDeclaration.new(name: "sig", pattern: PathPattern.new(source: "sig/{path}.rbs"), line: 3)
    artifact = ArtifactDeclaration.new(name: "ruby-file", files: PathPattern.new(source: "lib/{path}.rb"), companions: [test, sig], line: 1)

    assert_equal [test, sig, nil], %w[test sig stub].map { |name| artifact.companion(name) }
  end

  def test_a_listed_plugin_is_local_shared_or_built_in_by_its_name
    kinds = [".config/x", "./x", "/x", "https://github.com/o/r", "debt", "http://example.com/x", "x/.y"].map do |name|
      ListedPlugin.new(name:, ref: nil, settings: [], line: 1).kind
    end

    assert_equal %i[local local local shared built_in built_in built_in], kinds
  end

  def test_the_built_in_rules
    assert_equal [["companion-exists", ["companion"], :error], ["companion-absent", ["companion"], :error]],
      BuiltInRule::ALL.map { |rule| [rule.name, rule.arguments, rule.severity] }
    assert_equal BuiltInRule::ALL.last, BuiltInRule.named("companion-absent")
    assert_nil BuiltInRule.named("companion")
  end

  def test_a_project_lists_the_ruby_rules_no_policy_of_their_plugin_runs
    used = RuleDeclaration.new(name: "used", ruby: "a.rb", line: 1)
    unused = RuleDeclaration.new(name: "unused", ruby: "b.rb", line: 2)
    policy = Policy.new(name: "p", applies_to: AppliesTo.new(artifact: "a", line: 4), condition: nil,
      rules: [PolicyRule.new(name: "used", arguments: {}, severity: nil, line: 5)], line: 3)
    one = plugin("one", Manifest.new(file: "one/plugin.kdl", artifacts: [], policies: [policy], rules: [used, unused], helpers: []))
    two = plugin("two", Manifest.new(file: "two/plugin.kdl", artifacts: [], policies: [], rules: [used], helpers: []))
    configuration = Configuration.new(file: ".config/crosslint/config.kdl", plugins: [one.listing, two.listing], policies: [],
      warnings: nil, verbosity: nil)
    project = Project.new(root: "/app", configuration:, plugins: [one, two])

    assert_equal [[one, unused], [two, used]], project.unused_rules
  end

  private

  def plugin(name, manifest)
    Plugin.new(name:, folder: "/app/#{name}", listing: ListedPlugin.new(name: "./#{name}", ref: nil, settings: [], line: 1), manifest:)
  end
end
