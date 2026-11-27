# frozen_string_literal: true

require "test_helper"

# The value objects of the core that have behavior beyond their fields.
class CoreValuesTest < Minitest::Test
  cover "CrossLint::Core::Mistake*"
  cover "CrossLint::Core::Mistakes*"
  cover "CrossLint::Core::Spelling*"
  cover "CrossLint::Core::Condition*"
  cover "CrossLint::Core::ArtifactDeclaration*"
  cover "CrossLint::Core::ListedPlugin*"
  cover "CrossLint::Core::BuiltInRule*"
  cover "CrossLint::Core::Project*"
  cover "CrossLint::Core::Policy*"
  cover "CrossLint::Core::Plugin*"
  cover "CrossLint::Core::CommandFlag*"
  cover "CrossLint::Core::CommandDeclaration*"

  include CrossLint::Core

  def test_a_command_flag_is_written_as_the_usage_spec_writes_one_with_each_name_it_takes_and_no_more_than_its_help
    flag = CommandFlag.new(short: "s", long: "since", value: "rev", help: "H", line: 1)
    bare = CommandFlag.new(short: nil, long: "dry-run", value: nil, help: "H", line: 2)

    assert_equal [["--since <rev>", ["--since", "-s"]], ["--dry-run", ["--dry-run"]]], [flag, bare].map { |each| [each.usage, each.names] }
    assert_equal [[nil, nil, nil]] * 2, [flag, bare].map { |each| [each.long_help, each.choices, each.default] }
    given = CommandFlag.new(short: nil, long: "mode", value: "m", help: "H", line: 3, long_help: "Long", choices: %w[a b], default: "a")

    assert_equal ["Long", %w[a b], "a"], [given.long_help, given.choices, given.default]
  end

  def test_a_command_declares_no_flag_unless_given
    assert_equal [], CommandDeclaration.new(name: "update", help: "H", line: 1).flags
  end

  def test_an_artifact_declaration_has_no_key_isnt_optional_and_may_match_dot_named_files_unless_given
    declaration = ArtifactDeclaration.new(name: "doc", primary: PathPattern.new(source: "{path}.md"), pieces: [], line: 1)

    assert_equal [nil, false, true], [declaration.key, declaration.optional, declaration.dotfiles]
  end

  def test_a_policy_names_each_piece_its_condition_and_rules_name_once
    exists = ->(name) { Condition::PieceExists.new(piece: name, line: 2) }
    rule = ->(arguments) { PolicyRule.new(name: "r", arguments:, severity: nil, line: 3) }
    policy = Policy.new(name: "p", applies_to: nil, condition: Condition::All.new(conditions: [exists.call("stub"), exists.call("css")], line: 2),
      rules: [rule.call({"piece" => "stub"}), rule.call({}), rule.call({"piece" => "spec"})], line: 1)

    assert_equal %w[stub css spec], policy.pieces
    assert_equal ["spec"], policy.with(condition: nil, rules: [rule.call({"piece" => "spec"})]).pieces
  end

  def test_a_plugin_applies_a_policy_to_what_its_applies_to_names_or_else_to_each_artifact_with_its_pieces
    declaration = ->(name, *pieces) do
      ArtifactDeclaration.new(name:, primary: PathPattern.new(source: "{path}.#{name}"), line: 1,
        pieces: pieces.map { |piece| PieceDeclaration.new(name: piece, pattern: PathPattern.new(source: "{path}.#{piece}"), line: 2) })
    end
    manifest = Manifest.new(file: "plugin.kdl", artifacts: [declaration.call("a", "spec"), declaration.call("b"), declaration.call("c", "spec", "stub")],
      policies: [], rules: [], helpers: [])
    plugin = Plugin.new(name: "tests", folder: "/tests", listing: ListedPlugin.new(name: "./tests", ref: nil, settings: [], line: 1), manifest:)
    rule = PolicyRule.new(name: "piece-exists", arguments: {"piece" => "spec"}, severity: nil, line: 3)
    policy = Policy.new(name: "p", applies_to: nil, condition: nil, rules: [rule], line: 1)

    assert_equal [%w[tests a], %w[tests c]], plugin.targets(policy)
    assert_equal [%w[tests c]], plugin.targets(policy.with(condition: Condition::PieceExists.new(piece: "stub", line: 2)))
    assert_equal [%w[tests b]], plugin.targets(policy.with(applies_to: AppliesTo.new(artifact: "b", line: 2)))
    assert_equal [%w[other b]], plugin.targets(policy.with(applies_to: AppliesTo.new(artifact: "other/b", line: 2)))
  end

  def test_a_mistake_names_where_it_is
    assert_equal ["plugin.kdl:2", "unknown"], [Mistake.new("unknown", file: "plugin.kdl", line: 2).location, Mistake.new("unknown").message]
    assert_equal "plugin.kdl", Mistake.new("x", file: "plugin.kdl").location
    assert_equal "", Mistake.new("x").location
  end

  def test_one_mistake_stands_alone_and_several_are_listed_together
    first = Mistake.new("is wrong", file: "a.json")
    second = Mistake.new("is wrong too", file: "b.json", line: 3)

    assert_same first, Mistakes.of([first])
    many = Mistakes.of([first, second])

    assert_kind_of Mistake, many
    assert_equal [[first, second], "2 mistakes: a.json: is wrong; b.json:3: is wrong too", nil, nil], [many.all, many.message, many.file, many.line]
  end

  def test_spelling_names_the_nearest_known_word
    assert_equal "files", Spelling.nearest("file", ["files", "piece"])
    assert_nil Spelling.nearest("zzz", ["files"])
    assert_equal %(unknown node "file", did you mean "files"?), Spelling.unknown("node", "file", ["files"])
    assert_equal %(unknown node "zzz"; there are none), Spelling.unknown("node", "zzz", [])
    assert_equal %(unknown node "zzz"; it takes none), Spelling.unknown("node", "zzz", [], none: "it takes none")
    assert_equal %(unknown node "\\u00E9"; expected "a"), Spelling.unknown("node", "é", ["a"])
  end

  def test_spelling_lists_words_as_in_a_sentence
    assert_equal ["a", "a or b", "a, b, or c", "a, b, c, or d"], [["a"], %w[a b], %w[a b c], %w[a b c d]].map { |words| Spelling.list(words) }
  end

  def test_a_condition_holds_its_piece_conditions
    a = Condition::PieceExists.new(piece: "a", line: 1)
    b = Condition::PieceExists.new(piece: "b", line: 2)
    c = Condition::PieceExists.new(piece: "c", line: 3)
    condition = Condition::All.new(conditions: [a, Condition::Not.new(condition: Condition::Any.new(conditions: [b, c], line: 2), line: 2)], line: 1)

    assert_equal [a, b, c], condition.piece_conditions
    assert_equal [b, c], Condition::Any.new(conditions: [Condition::All.new(conditions: [b, c], line: 2)], line: 1).piece_conditions
    assert_equal [a], a.piece_conditions
  end

  def test_an_artifact_finds_its_piece_by_name
    test = PieceDeclaration.new(name: "test", pattern: PathPattern.new(source: "test/{path}_test.rb"), line: 2)
    sig = PieceDeclaration.new(name: "sig", pattern: PathPattern.new(source: "sig/{path}.rbs"), line: 3)
    artifact = ArtifactDeclaration.new(name: "ruby-file", primary: PathPattern.new(source: "lib/{path}.rb"), pieces: [test, sig], line: 1)

    assert_equal [test, sig, nil], %w[test sig stub].map { |name| artifact.piece(name) }
  end

  def test_a_listed_plugin_is_local_shared_or_built_in_by_its_name
    kinds = [".config/x", "./x", "/x", "https://github.com/o/r", "debt", "http://example.com/x", "x/.y"].map do |name|
      ListedPlugin.new(name:, ref: nil, settings: [], line: 1).kind
    end

    assert_equal %i[local local local shared built_in built_in built_in], kinds
  end

  def test_a_listed_plugin_is_shared_by_its_kind_or_when_the_port_accepts_its_name
    https = CrossLint::Adapters::MemorySharedPlugins.new(err: StringIO.new)
    files = CrossLint::Adapters::MemorySharedPlugins.new(err: StringIO.new, schemes: ["file://"])
    shared = [".config/x", "file:///x", "https://example.com/o/r", "debt"].map do |name|
      listing = ListedPlugin.new(name:, ref: nil, settings: [], line: 1)
      [listing.shared?(https), listing.shared?(files)]
    end

    assert_equal [[false, false], [false, true], [true, true], [false, false]], shared
  end

  def test_a_local_plugin_is_never_shared_whatever_the_port_accepts
    everything = CrossLint::Adapters::MemorySharedPlugins.new(err: StringIO.new, schemes: [""])

    assert_equal [false, true], ["./x", "x"].map { |name| ListedPlugin.new(name:, ref: nil, settings: [], line: 1).shared?(everything) }
  end

  def test_the_built_in_rules
    assert_equal [["piece-exists", ["piece"], :error], ["piece-absent", ["piece"], :error]],
      BuiltInRule::ALL.map { |rule| [rule.name, rule.arguments, rule.severity] }
    assert_equal BuiltInRule::ALL.last, BuiltInRule.named("piece-absent")
    assert_nil BuiltInRule.named("piece")
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
