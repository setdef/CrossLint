# frozen_string_literal: true

require "test_helper"

class MemoryPluginManifestsTest < Minitest::Test
  cover "CrossLint::Adapters::MemoryPluginManifests*"

  include CrossLint::Testing::PluginManifestsContract
  include CrossLint::Core

  def base = "/memory"

  def manifests_port(example: [], broken: [], minimum: {})
    held = example.to_h { |folder| [File.expand_path(folder, base), example_manifest(folder)] }
    broken.each { |folder| held[File.expand_path(folder, base)] = Mistake.new("unknown node", file: "#{folder}/plugin.kdl", line: 2) }
    minimums = minimum.to_h do |folder, text|
      [File.expand_path(folder, base), CrossLint::Core::MinimumVersion.parse(text, file: "#{folder}/plugin.kdl", line: 0)]
    end
    CrossLint::Adapters::MemoryPluginManifests.new(held, minimums:)
  end

  def test_holds_no_manifest_unless_it_is_given_some
    assert_nil CrossLint::Adapters::MemoryPluginManifests.new.read("/memory", "plugins/x")
  end

  def test_raises_a_mistake_of_any_kind_it_holds
    kind = Class.new(Mistake)
    port = CrossLint::Adapters::MemoryPluginManifests.new({ File.expand_path("/memory/x") => kind.new("broken") })

    assert_raises(kind) { port.read("/memory", "x") }
  end

  def test_names_the_file_it_is_given
    assert_equal "plugin.json", CrossLint::Adapters::MemoryPluginManifests.new(file: "plugin.json").file
    assert_equal "plugin.kdl", CrossLint::Adapters::MemoryPluginManifests.new.file
  end

  private

  def example_manifest(folder)
    pieces = [
      PieceDeclaration.new(name: "signature", pattern: PathPattern.new(source: "sig/{path}.rbs"), line: 3),
      PieceDeclaration.new(name: "test", pattern: PathPattern.new(source: "test/{path}_test.rb"), line: 4),
]
    artifact = ArtifactDeclaration.new(name: "ruby-file", primary: PathPattern.new(source: "lib/{path}.rb"), pieces:, line: 1)
    Manifest.new(file: folder.empty? ? "plugin.kdl" : "#{folder}/plugin.kdl", artifacts: [artifact], policies: example_policies,
      rules: [RuleDeclaration.new(name: "names-class", ruby: "rules/names_class.rb", line: 33)],
      helpers: [HelperDeclaration.new(name: "members", command: "node", file: "helpers/members.mjs", line: 34)],
      step_policies: [StepPolicy.new(name: "has-debt", line: 36)],
      settings: [SettingDeclaration.new(name: "file", line: 37), SettingDeclaration.new(name: "report-entries", line: 38)],
      commands: [CommandDeclaration.new(name: "update", help: "Rewrite the debt file to list the current violations", line: 39)], steps: [StepDeclaration.new(name: "track-debt", line: 40)])
  end

  def example_policies
    applies = AppliesTo.new(artifact: "ruby-file", line: 8)
    signature = Condition::PieceExists.new(piece: "signature", line: 20)
    test = Condition::PieceExists.new(piece: "test", line: 20)
    [
      Policy.new(name: "has-signature", applies_to: applies, condition: nil, line: 7,
        rules: [PolicyRule.new(name: "piece-exists", arguments: { "piece" => "signature" }, severity: :warning, line: 9)]),
      Policy.new(name: "names-match", applies_to: applies, line: 12,
        condition: Condition::Not.new(condition: test, line: 14),
        rules: [PolicyRule.new(name: "names-class", arguments: {}, severity: nil, line: 15)]),
      Policy.new(name: "covered", applies_to: applies, line: 18,
        condition: Condition::All.new(conditions: [signature, test], line: 20),
        rules: [PolicyRule.new(name: "piece-exists", arguments: { "piece" => "test" }, severity: :error, line: 21)]),
      Policy.new(name: "either", applies_to: applies, line: 24,
        condition: Condition::Any.new(conditions: [signature, Condition::Not.new(condition: test, line: 27)], line: 26),
        rules: [PolicyRule.new(name: "piece-absent", arguments: { "piece" => "signature" }, severity: nil, line: 29)]),
    ]
  end
end
