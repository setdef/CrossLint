# frozen_string_literal: true

require "minitest"
require_relative "core"

module CrossLint
  module Testing
    module ConfigurationContract
      def test_finds_the_root_in_the_folder_it_starts_from
        port = configuration_port({"app" => ["one"]})

        assert_equal folder("app"), port.find_root(folder("app"))
      end

      def test_finds_the_nearest_root_above_the_folder_it_starts_from
        port = configuration_port({"app" => ["one"], "app/inner" => ["two"]})

        assert_equal folder("app/inner"), port.find_root(folder("app/inner/deep/er"))
        assert_equal folder("app"), port.find_root(folder("app/other"))
      end

      def test_finds_no_root_when_no_folder_above_has_a_configuration
        root = configuration_port({"app" => ["one"]}).find_root(folder("elsewhere"))

        assert_equal [root_outside], [root]
      end

      def test_reads_the_plugins_in_the_order_they_are_listed
        port = configuration_port({"app" => ["one", ".config/two", "three"]})
        configuration = port.read(folder("app"))
        lines = configuration.plugins.map(&:line)

        assert_equal [port.file, ["one", ".config/two", "three"]], [configuration.file, configuration.plugins.map(&:name)]
        assert_equal lines.sort, lines.uniq
        assert_operator lines.fetch(0), :>=, 1
      end

      def test_names_the_file_and_line_of_a_mistake
        port = configuration_port({}, broken: "app")
        mistake = assert_raises(Core::Mistake) { port.read(folder("app")) }

        assert_equal [port.file, 2], [mistake.file, mistake.line]
      end

      def test_names_the_file_when_the_project_has_no_configuration
        port = configuration_port({"app" => ["one"]})
        mistake = assert_raises(Core::Mistake) { port.read(folder("elsewhere")) }

        assert_equal port.file, mistake.file
      end
    end

    module PluginManifestsContract
      def test_reads_the_artifacts_policies_rules_and_helpers_a_manifest_declares
        port = manifests_port(example: ["plugins/signatures"])
        manifest = read_manifest(port, "plugins/signatures")
        artifact = manifest.artifacts.fetch(0)
        policy = manifest.policies.fetch(0)

        assert_equal "plugins/signatures/#{port.file}", manifest.file
        assert_equal ["ruby-file", "lib/{path}.rb", [["signature", "sig/{path}.rbs"]]],
          [artifact.name, artifact.files.source, artifact.companions.map { |companion| [companion.name, companion.pattern.source] }]
        assert_equal ["has-signature", "ruby-file", nil, [["companion-exists", {"companion" => "signature"}, :warning]]],
          [policy.name, policy.applies_to.artifact, policy.condition, policy.rules.map { |rule| [rule.name, rule.arguments, rule.severity] }]
        assert_equal [["names-class", "rules/names_class.rb"]], manifest.rules.map { |rule| [rule.name, rule.ruby] }
        assert_equal [["members", "node", "helpers/members.mjs"]],
          manifest.helpers.map { |helper| [helper.name, helper.command, helper.file] }
      end

      def test_reads_the_manifest_of_the_root_folder_itself
        port = manifests_port(example: [""])

        assert_equal port.file, read_manifest(port, "").file
      end

      def test_reads_nothing_from_a_folder_with_no_manifest
        assert_nil manifests_port(example: ["plugins/signatures"]).read(base, "plugins/other")
      end

      def test_names_the_file_and_line_of_a_mistake
        port = manifests_port(broken: ["plugins/broken"])
        mistake = assert_raises(Core::Mistake) { port.read(base, "plugins/broken") }

        assert_equal ["plugins/broken/#{port.file}", 2], [mistake.file, mistake.line]
      end

      private

      def read_manifest(port, folder) = port.read(base, folder) || raise(Minitest::Assertion, "#{folder} has no manifest")
    end
  end
end
