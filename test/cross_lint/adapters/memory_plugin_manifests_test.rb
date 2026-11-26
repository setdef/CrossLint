# frozen_string_literal: true

require "test_helper"

class MemoryPluginManifestsTest < Minitest::Test
  cover "CrossLint::Adapters::MemoryPluginManifests*"

  include CrossLint::Testing::PluginManifestsContract
  include CrossLint::Core

  def base = "/memory"

  def manifests_port(example: [], broken: [])
    held = example.to_h { |folder| [File.expand_path(folder, base), example_manifest(folder)] }
    broken.each { |folder| held[File.expand_path(folder, base)] = Mistake.new("unknown node", file: "#{folder}/plugin.kdl", line: 2) }
    CrossLint::Adapters::MemoryPluginManifests.new(held)
  end

  def test_holds_no_manifest_unless_it_is_given_some
    assert_nil CrossLint::Adapters::MemoryPluginManifests.new.read("/memory", "plugins/x")
  end

  def test_raises_a_mistake_of_any_kind_it_holds
    kind = Class.new(Mistake)
    port = CrossLint::Adapters::MemoryPluginManifests.new({File.expand_path("/memory/x") => kind.new("broken")})

    assert_raises(kind) { port.read("/memory", "x") }
  end

  def test_names_the_file_it_is_given
    assert_equal "plugin.json", CrossLint::Adapters::MemoryPluginManifests.new(file: "plugin.json").file
    assert_equal "plugin.kdl", CrossLint::Adapters::MemoryPluginManifests.new.file
  end

  private

  def example_manifest(folder)
    artifact = ArtifactDeclaration.new(name: "ruby-file", files: PathPattern.new(source: "lib/{path}.rb"),
      companions: [CompanionDeclaration.new(name: "signature", pattern: PathPattern.new(source: "sig/{path}.rbs"), line: 3)], line: 1)
    policy = Policy.new(name: "has-signature", applies_to: AppliesTo.new(artifact: "ruby-file", line: 7), condition: nil,
      rules: [PolicyRule.new(name: "companion-exists", arguments: {"companion" => "signature"}, severity: :warning, line: 8)], line: 6)
    Manifest.new(file: folder.empty? ? "plugin.kdl" : "#{folder}/plugin.kdl", artifacts: [artifact], policies: [policy],
      rules: [RuleDeclaration.new(name: "names-class", ruby: "rules/names_class.rb", line: 11)],
      helpers: [HelperDeclaration.new(name: "members", command: "node", file: "helpers/members.mjs", line: 12)])
  end
end
