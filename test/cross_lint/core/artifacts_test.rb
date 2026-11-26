# frozen_string_literal: true

require "test_helper"

# CrossLint::Artifacts, which a plugin's Ruby that declares artifacts
# inherits from.
class ArtifactsTest < Minitest::Test
  cover "CrossLint::Artifacts*"

  include CrossLint::Core

  def setup
    @declarer = CrossLint::Artifacts.new
    @declarer.instance_variable_set(:@crosslint_line, 4)
    @declarer.instance_variable_set(:@crosslint_configuration, ".config/crosslint/config.kdl")
  end

  def test_declares_an_artifact_on_the_line_that_names_its_file
    declared = @declarer.artifact("component", files: "src/{path}.component.ts", companions: {"spec" => "src/{path}.component.spec.ts"},
      key: "{path}", optional: true)

    assert_equal ArtifactDeclaration.new(name: "component", files: PathPattern.new(source: "src/{path}.component.ts"), line: 4,
      companions: [CompanionDeclaration.new(name: "spec", pattern: PathPattern.new(source: "src/{path}.component.spec.ts"), line: 4)],
      key: PathPattern.new(source: "{path}"), optional: true), declared
  end

  def test_declares_an_artifact_with_no_companions_no_key_and_not_optional_unless_given
    assert_equal ArtifactDeclaration.new(name: "doc", files: PathPattern.new(source: "{path}.md"), companions: [], line: 4),
      @declarer.artifact("doc", files: "{path}.md")
  end

  # The KDL reader gives a setting's strings as a kind of String.
  def test_declares_an_artifact_from_strings_of_a_kind_of_string
    kind = Class.new(String)
    declared = @declarer.artifact(kind.new("doc"), files: kind.new("{path}.md"), companions: Class.new(Hash)[kind.new("note") => kind.new("{path}.txt")],
      key: kind.new("{path}"))

    assert_equal [["doc", "{path}.md", "note", "{path}.txt", "{path}"]],
      [[declared.name, declared.files.source, declared.companions.first.name, declared.companions.first.pattern.source, declared.key.source]]
  end

  def test_refuses_an_artifact_it_cant_declare
    {
      -> { @declarer.artifact(:doc, files: "{path}.md") } => "declared an artifact named :doc, which is no string",
      -> { @declarer.artifact("doc", files: 3) } => %(declared artifact "doc" with the pattern 3, which is no string),
      -> { @declarer.artifact("doc", files: "{pth}.md") } =>
        %(declared artifact "doc" with a path pattern "{pth}.md" has unknown placeholder "{pth}", did you mean "{path}"?),
      -> { @declarer.artifact("doc", files: "{path}.md", key: "") } => %(declared artifact "doc" with a path pattern "" is empty),
      -> { @declarer.artifact("doc", files: "{path}.md", companions: "a") } => %(declared artifact "doc" with companions "a", which is no hash),
      -> { @declarer.artifact("doc", files: "{path}.md", companions: {a: "b"}) } =>
        %(declared artifact "doc" with a companion named :a, which is no string),
      -> { @declarer.artifact("doc", files: "{path}.md", companions: {"a" => nil}) } => %(declared artifact "doc" with the pattern nil, which is no string),
      -> { @declarer.artifact("doc", files: "{path}.md", optional: "yes") } => %(declared artifact "doc" with optional: "yes", which is neither true nor false),
      -> { @declarer.declare([]) } => "has no declare method"
    }.each do |call, message|
      assert_equal message, assert_raises(PluginError, &call).message
    end
  end

  def test_makes_a_mistake_naming_the_configuration_and_the_settings_line
    mistake = @declarer.mistake("src-dir takes a folder", Setting.new(name: "src-dir", arguments: [], properties: {}, children: [], line: 7))

    assert_equal [".config/crosslint/config.kdl", 7, "src-dir takes a folder"], [mistake.file, mistake.line, mistake.message]
  end
end
