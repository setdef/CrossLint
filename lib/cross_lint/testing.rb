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
        assert_equal [nil, nil, nil], configuration.plugins.map(&:ref)
        assert_empty configuration.plugins.flat_map(&:settings)
        assert_empty configuration.policies
        assert_nil configuration.warnings
        assert_nil configuration.verbosity
      end

      def test_reads_the_ref_and_kind_of_each_plugin
        plugins = example_configuration.plugins

        assert_equal [["https://github.com/OWNER/REPO", "v1.2.0", :shared], ["angular", nil, :built_in],
          [".config/crosslint/signatures", nil, :local]], plugins.map { |plugin| [plugin.name, plugin.ref, plugin.kind] }
      end

      def test_reads_the_settings_block_of_a_plugin
        settings = example_configuration.plugins.fetch(1).settings
        source = settings.fetch(0)
        role = settings.fetch(1)
        expects = role.children.fetch(0)

        assert_equal [["src-dir", ["src"]], ["role", ["store"]], ["expects", ["spec"]]],
          [source, role, expects].map { |setting| [setting.name, setting.arguments] }
        assert_equal({"files" => "{path}.store.ts"}, role.properties)
        assert_empty source.properties
        assert_empty source.children
        assert_empty expects.properties
        assert_empty expects.children
      end

      def test_reads_what_a_policy_line_changes
        policies = example_configuration.policies
        lines = policies.map(&:line)

        assert_equal [["angular/prefer-css-over-scss", nil, :error], ["angular/spec-exists", nil, :warning], ["signatures/has-test", false, nil]],
          policies.map { |policy| [policy.name, policy.enabled, policy.severity] }
        assert_equal lines.sort, lines.uniq
      end

      def test_reads_warnings_and_verbosity
        configuration = example_configuration

        assert_equal [:error, :silent], [configuration.warnings, configuration.verbosity]
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

      private

      def example_configuration = example_configuration_port.read(folder("example"))
    end

    module PluginManifestsContract
      def test_reads_the_artifacts_rules_and_helpers_a_manifest_declares
        port = manifests_port(example: ["plugins/signatures"])
        manifest = read_manifest(port, "plugins/signatures")
        artifact = manifest.artifacts.fetch(0)

        assert_equal "plugins/signatures/#{port.file}", manifest.file
        assert_equal ["ruby-file", "lib/{path}.rb", [["signature", "sig/{path}.rbs"], ["test", "test/{path}_test.rb"]]],
          [artifact.name, artifact.files.source, artifact.companions.map { |companion| [companion.name, companion.pattern.source] }]
        assert_equal [["names-class", "rules/names_class.rb"]], manifest.rules.map { |rule| [rule.name, rule.ruby] }
        assert_equal [["members", "node", "helpers/members.mjs"]],
          manifest.helpers.map { |helper| [helper.name, helper.command, helper.file] }
      end

      def test_reads_what_each_policy_applies_to_and_runs
        policies = signatures_manifest.policies

        assert_equal ["has-signature", "names-match", "covered", "either"], policies.map(&:name)
        assert_equal ["ruby-file"], policies.map { |policy| policy.applies_to.artifact }.uniq
        rules = policies.map { |policy| policy.rules.fetch(0) }

        assert_equal [1, 1, 1, 1], policies.map { |policy| policy.rules.size }
        assert_equal %w[companion-exists names-class companion-exists companion-absent], rules.map(&:name)
        assert_equal ["companion=signature", "", "companion=test", "companion=signature"],
          rules.map { |rule| rule.arguments.map { |key, value| "#{key}=#{value}" }.join(" ") }
      end

      def test_reads_the_when_condition_of_a_policy
        conditions = signatures_manifest.policies.map { |policy| without_lines(policy.condition) }
        not_test = Core::Condition::Not.new(condition: exists("test"), line: 0)

        assert_equal [without_lines(nil), without_lines(not_test),
          without_lines(Core::Condition::All.new(conditions: [exists("signature"), exists("test")], line: 0)),
          without_lines(Core::Condition::Any.new(conditions: [exists("signature"), not_test], line: 0))], conditions
      end

      def test_reads_the_severity_of_a_rule_line_when_it_has_one
        severities = signatures_manifest.policies.map { |policy| policy.rules.map(&:severity) }

        assert_equal [[:warning], [nil], [:error], [nil]], severities
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

      def signatures_manifest = read_manifest(manifests_port(example: ["plugins/signatures"]), "plugins/signatures")

      def exists(companion) = Core::Condition::CompanionExists.new(companion:, line: 0)

      # Lines differ between adapters, so conditions are compared without them.
      def without_lines(condition) = condition.inspect.gsub(/,? line=\d+/, "")
    end
  end
end
