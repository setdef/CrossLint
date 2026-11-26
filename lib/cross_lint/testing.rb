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

      def test_sets_the_ref_of_a_plugin_and_changes_nothing_else
        port = example_configuration_port
        before = port.read(folder("example"))
        port.set_refs(folder("example"), {"https://github.com/OWNER/REPO" => "v1.3.0"})
        after = port.read(folder("example"))

        assert_equal ["v1.3.0", nil, nil], after.plugins.map(&:ref)
        assert_equal before.with(plugins: [before.plugins.first.with(ref: "v1.3.0"), *before.plugins.drop(1)]), after
      end

      def test_changes_nothing_when_it_is_given_no_ref_or_one_for_a_plugin_the_configuration_doesnt_list
        port = example_configuration_port
        before = port.read(folder("example"))
        port.set_refs(folder("example"), {})
        port.set_refs(folder("example"), {"https://github.com/OWNER/OTHER" => "v2.0.0"})

        assert_equal before, port.read(folder("example"))
      end

      def test_names_the_file_when_the_project_it_sets_refs_in_has_no_configuration
        port = configuration_port({"app" => ["one"]})
        mistake = assert_raises(Core::Mistake) { port.set_refs(folder("elsewhere"), {"one" => "v1.0.0"}) }

        assert_equal port.file, mistake.file
      end

      def test_says_whether_a_project_has_a_configuration_in_the_folder_itself
        port = configuration_port({"app" => ["one"]})

        assert port.exist?(folder("app"))
        refute port.exist?(folder("app/inner"))
        refute port.exist?(folder("elsewhere"))
      end

      def test_writes_a_configuration_that_reads_back_as_it_was_written
        port = configuration_port({})
        root = folder("fresh")
        written = written_configuration(port.file)
        port.write(root, written)

        assert port.exist?(root)
        assert_equal root, port.find_root(folder("fresh/inner"))
        assert_equal without_lines(written), without_lines(port.read(root))
      end

      def test_replaces_the_configuration_it_has_whole
        port = configuration_port({"app" => ["one", "two"]})
        written = written_configuration(port.file).with(plugins: [], policies: [], warnings: nil, verbosity: nil)
        port.write(folder("app"), written)

        assert_equal without_lines(written), without_lines(port.read(folder("app")))
      end

      def test_writes_the_configuration_of_one_project_and_no_other
        port = configuration_port({"app" => ["one"]})
        port.write(folder("other"), written_configuration(port.file))

        assert_equal ["one"], port.read(folder("app")).plugins.map(&:name)
      end

      private

      def example_configuration = example_configuration_port.read(folder("example"))

      # A configuration with every kind of line, and strings that need
      # escapes to be written.
      def written_configuration(file)
        plugin = ->(name, ref, settings) { Core::ListedPlugin.new(name:, ref:, settings:, line: 0) }
        setting = ->(name, arguments, properties, children) { Core::Setting.new(name:, arguments:, properties:, children:, line: 0) }
        angular = plugin.call("angular", nil, [
          setting.call("src-dir", ["a \"b\"\\c\td\ne\u0001f\u2028g é"], {}, []),
          setting.call("role", ["store"], {"files" => "{path}.store.ts"}, [setting.call("expects", [], {}, [])])
        ])
        debt = plugin.call("debt", nil, [setting.call("report-entries", [], {"commented" => "warning", "matching" => "^\\d+$"}, [])])
        Core::Configuration.new(file:, plugins: [plugin.call("https://github.com/OWNER/REPO", "v1.2.0", []), angular, debt],
          policies: [Core::PolicySetting.new(name: "angular/spec-exists", enabled: false, severity: :warning, line: 0),
            Core::PolicySetting.new(name: "debt/has-debt", enabled: nil, severity: :error, line: 0)],
          warnings: :none, verbosity: :quiet)
      end

      def without_lines(configuration)
        settings = ->(each) { each.map { |setting| setting.with(line: 0, children: settings.call(setting.children)) } }
        configuration.with(plugins: configuration.plugins.map { |plugin| plugin.with(line: 0, settings: settings.call(plugin.settings)) },
          policies: configuration.policies.map { |policy| policy.with(line: 0) })
      end
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
        assert_equal ["ruby-file"] * 4, policies.filter_map(&:applies_to).map(&:artifact)
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

      def test_reads_the_settings_commands_and_steps_a_manifest_declares
        manifest = signatures_manifest
        names = [manifest.step_policies, manifest.settings, manifest.commands, manifest.steps].map { |each| each.map(&:name) }
        lines = [manifest.step_policies, manifest.settings, manifest.commands, manifest.steps].flat_map { |each| each.map(&:line) }

        assert_equal [["has-debt"], ["file", "report-entries"], ["update"], ["track-debt"]], names
        assert_equal ["Rewrite the debt file to list the current violations"], manifest.commands.map(&:help)
        assert_equal lines.sort, lines.uniq
        assert_operator lines.first, :>, manifest.policies.last.line
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

    module ProjectFilesContract
      def test_lists_every_file_git_sees_and_none_it_ignores
        listed = ["README.md", "lib/app.rb", "lib/app/deep/one.rb", ".hidden"]
        port = project_files_port(listed:, ignored: ["coverage/index.html", "lib/app.rb.orig"])

        assert_equal listed.sort, port.files(project_root).sort
      end

      def test_says_whether_a_path_exists_by_its_exact_name
        port = project_files_port(listed: ["lib/app/one.rb"], ignored: ["tmp/cache.bin"])
        found = ["lib/app/one.rb", "lib/app", "tmp/cache.bin", "lib/app/One.rb", "Lib/app/one.rb", "lib/app/two.rb", "lib/app/one"]

        assert_equal [true, true, true, false, false, false, false], found.map { |path| port.exist?(project_root, path) }
      end

      def test_reads_a_file_by_its_exact_name
        port = project_files_port(listed: ["lib/app.rb"], ignored: ["tmp/cache.txt"])
        text = port.read(project_root, "lib/app.rb")

        assert_equal ["lib/app.rb\n", Encoding::UTF_8, "tmp/cache.txt\n"], [text, text.encoding, port.read(project_root, "tmp/cache.txt")]
        missing = ["lib/App.rb", "lib/other.rb"].map { |path| assert_raises(Errno::ENOENT) { port.read(project_root, path) }.message }

        assert_equal ["No such file or directory - lib/App.rb", "No such file or directory - lib/other.rb"], missing
      end

      def test_stops_at_a_root_outside_a_git_working_tree
        root = outside_root
        mistake = assert_raises(Core::Mistake) { project_files_port(listed: []).files(root) }

        assert_equal "#{root} isn't in a Git working tree, and CrossLint lists a project's files with Git; " \
          "run git init in the project's root", mistake.message
      end
    end

    module PluginRubyContract
      def test_puts_a_files_constants_in_the_namespace_it_is_given
        namespace = Module.new
        plugin_ruby_port({"tests/rules/a.rb" => "class NamesClass < CrossLint::Rule\nend\n"}).load(ruby_plugin("tests"), "rules/a.rb", 3, namespace)

        assert_operator namespace.const_get(:NamesClass, false), :<, CrossLint::Rule
        refute Object.const_defined?(:NamesClass, false)
      end

      def test_keeps_two_plugins_classes_of_one_name_apart
        files = {"one/a.rb" => "class Same < CrossLint::Rule\n  def name = 1\nend\n", "two/a.rb" => "class Same < CrossLint::Rule\n  def name = 2\nend\n"}
        port = plugin_ruby_port(files)
        found = %w[one two].map do |plugin|
          namespace = Module.new
          port.load(ruby_plugin(plugin), "a.rb", 3, namespace)
          namespace.const_get(:Same, false).new.name
        end

        assert_equal [1, 2], found
      end

      def test_stops_at_a_file_the_plugins_folder_lacks
        mistake = assert_raises(Core::Mistake) { plugin_ruby_port({}).load(ruby_plugin("tests"), "rules/missing.rb", 7, Module.new) }

        assert_equal ["tests/plugin.kdl:7", %(no file "rules/missing.rb" in the plugin's folder)], [mistake.location, mistake.message]
      end

      def test_raises_what_the_file_raises
        port = plugin_ruby_port({"tests/a.rb" => "raise ArgumentError, \"boom\"\n"})
        error = assert_raises(ArgumentError) { port.load(ruby_plugin("tests"), "a.rb", 3, Module.new) }

        assert_equal "boom", error.message
      end

      private

      def ruby_plugin(name)
        manifest = Core::Manifest.new(file: "#{name}/plugin.kdl", artifacts: [], policies: [], rules: [], helpers: [])
        listing = Core::ListedPlugin.new(name: "./#{name}", ref: nil, settings: [], line: 1)
        Core::Plugin.new(name:, folder: File.join(plugin_base, name), listing:, manifest:)
      end
    end

    module HelpersContract
      def test_answers_each_request_with_what_the_helper_answers
        running = helpers_port.start(helper_root, [helper_plugin])
        answers = [[1, "two"], {"three" => nil}, "café"].map { |input| running.call(helper_plugin, "echo", input) }
        running.stop

        assert_equal [{"echo" => [1, "two"]}, {"echo" => {"three" => nil}}, {"echo" => "café"}], answers
      end

      def test_says_what_a_failing_helper_did_and_wrote
        running = helpers_port.start(helper_root, [helper_plugin])
        error = assert_raises(Core::PluginError) { running.call(helper_plugin, "fails", {}) }
        running.stop

        assert_equal "called helper fails, which exited with status 3 before it answered, and wrote:\nnope", error.message
      end

      def test_stops_before_any_helper_starts_at_a_command_not_on_the_path
        plugin = helper_plugin(command: "crosslint-no-such-command")
        mistake = assert_raises(Core::Mistake) { helpers_port.start(helper_root, [plugin]) }

        assert_equal ["tests/plugin.kdl:4", %(plugin tests needs crosslint-no-such-command on the PATH for its helper "echo", and there is none)],
          [mistake.location, mistake.message]
      end
    end

    module ReportContract
      def test_reports_each_violation_in_order
        port = report_port
        port.write(result([violation("lib/b.rb", "no test file at test/b_test.rb"), violation("lib/a.rb", "no sig", :warning)]))

        assert_equal [["lib/b.rb", "no test file at test/b_test.rb", "tests", "has-test", :error], ["lib/a.rb", "no sig", "tests", "has-test", :warning]],
          reported.fetch(:findings)
      end

      def test_reports_each_notice_apart_from_the_findings
        port = report_port
        port.write(result([], notices: [Core::Notice.new(file: ".config/tests/plugin.kdl", line: 3, message: "no file matches")]))

        assert_empty reported.fetch(:findings)
        assert_equal [[".config/tests/plugin.kdl", 3, "no file matches"]], reported.fetch(:notices)
      end

      def test_reports_no_finding_and_no_summary_when_a_check_starts
        report_port.start([["ruby-file", 2]])

        assert_empty reported.fetch(:findings)
        assert_empty reported.fetch(:notices)
        assert_nil reported.fetch(:summary)
      end

      def test_reports_the_summary_unless_quiet_or_silent
        port = report_port
        port.write(result([]))

        assert_equal "checked 2 ruby-file artifacts: no violations", reported.fetch(:summary)
      end

      def test_reports_no_summary_when_quiet
        port = report_port
        port.write(result([violation("lib/a.rb", "no test")], verbosity: :quiet))

        assert_equal [1, nil], [reported.fetch(:findings).size, reported.fetch(:summary)]
      end

      def test_reports_nothing_when_silent
        port = report_port
        port.write(result([], verbosity: :silent))

        assert_empty reported.fetch(:findings)
        assert_empty reported.fetch(:notices)
        assert_empty reported.fetch(:faults)
        assert_nil reported.fetch(:summary)
      end

      def test_reports_each_stale_entry_apart_from_the_violations
        stale = Core::Stale.new(plugin: "tests", policy: "has-test", artifact: "lib/b.rb", file: "debt.tsv", line: 2, message: "is stale")
        port = report_port
        port.write(result([violation("lib/a.rb", "no test"), stale]))

        assert_equal [[["lib/a.rb", "no test", "tests", "has-test", :error]], [["lib/b.rb", "is stale", "tests", "has-test"]]],
          [reported.fetch(:findings), reported.fetch(:stale)]
      end

      def test_reports_each_file_a_step_wrote_unless_silent
        port = report_port
        port.write(result([], wrote: ["wrote debt.tsv: 1 entry added, 0 removed"]))
        port.write(result([], verbosity: :silent, wrote: ["wrote other.tsv"]))

        assert_equal ["wrote debt.tsv: 1 entry added, 0 removed"], reported.fetch(:wrote)
      end

      def test_reports_each_fault_even_when_silent
        faults = [Core::Fault.new(plugin: "tests", rule: "names-class", artifact: "lib/a.rb", message: "raised RuntimeError: boom", trace: ["a.rb:1"]),
          Core::Fault.new(plugin: "other", rule: "uses-gem", artifact: nil, message: "requires rainbow", trace: [])]
        port = report_port
        port.write(result([], verbosity: :silent, faults:))

        assert_equal [["tests", "names-class", "lib/a.rb", "raised RuntimeError: boom"], ["other", "uses-gem", nil, "requires rainbow"]],
          reported.fetch(:faults)
        assert_empty reported.fetch(:findings)
      end

      private

      def violation(path, message, severity = :error)
        Core::Violation.new(plugin: "tests", policy: "has-test", artifact: path, role: "ruby-file", message:, severity:, detail: nil)
      end

      def result(findings, notices: [], verbosity: :normal, faults: [], wrote: [])
        summary = Core::Summary.new(kinds: [["ruby-file", 2]], faults: 0, errors: 0, warnings: 0, warnings_shown: true)
        Core::CheckResult.new(notices:, findings:, summary:, verbosity:, failed: false, faults:, wrote:)
      end
    end

    module DebtFilesContract
      def test_reads_no_entries_and_no_header_from_a_file_that_doesnt_exist
        debt = debt_files_port.read(debt_root, "missing/debt.tsv")

        assert_equal ["missing/debt.tsv", 0, nil], [debt.file, debt.entries.size, debt.header]
      end

      def test_reads_back_each_entry_it_wrote_in_order_with_its_line
        port = debt_files_port
        entries = [Core::DebtEntry.fresh(rule: "tests/has-test", artifact: "lib/b.rb", comment: "a\ttab, a \"quote\",\r\nand lines"),
          Core::DebtEntry.fresh(rule: "has-test", artifact: "lib/a.rb", detail: "name\twith a tab"),
          Core::DebtEntry.fresh(rule: "tests/has-test", artifact: "lib/caf\u00e9.rb", comment: "caf\u00e9")]
        port.write(debt_root, "debt.tsv", Core::DebtFile.new(file: "debt.tsv", entries:, header: nil))
        read = port.read(debt_root, "debt.tsv")

        assert_equal "debt.tsv", read.file
        assert_equal entries.map { |entry| [entry.rule, entry.artifact, entry.comment, entry.detail] },
          read.entries.map { |entry| [entry.rule, entry.artifact, entry.comment, entry.detail] }
        lines = read.entries.map(&:line)

        assert_equal [2, lines.sort, lines.uniq], [lines.first, lines, lines]
        assert read.entries.all?(&:source)
        refute_nil read.header
      end

      def test_writes_back_what_it_read_unchanged
        port = debt_files_port
        port.write(debt_root, "debt.tsv", Core::DebtFile.new(file: "debt.tsv", header: nil,
          entries: [Core::DebtEntry.fresh(rule: "tests/has-test", artifact: "lib/a.rb", comment: "later")]))
        read = port.read(debt_root, "debt.tsv")
        port.write(debt_root, "debt.tsv", read)

        assert_equal read, port.read(debt_root, "debt.tsv")
      end

      def test_keeps_the_header_of_a_file_with_no_entries
        port = debt_files_port
        port.write(debt_root, "debt.tsv", Core::DebtFile.new(file: "debt.tsv", entries: [], header: nil))
        read = port.read(debt_root, "debt.tsv")

        assert_equal [], read.entries
        refute_nil read.header
      end

      def test_makes_the_folder_of_a_file_it_writes
        port = debt_files_port
        port.write(debt_root, "new/folder/debt.tsv", Core::DebtFile.new(file: "new/folder/debt.tsv", header: nil,
          entries: [Core::DebtEntry.fresh(rule: "tests/has-test", artifact: "lib/a.rb")]))

        assert_equal ["lib/a.rb"], port.read(debt_root, "new/folder/debt.tsv").entries.map(&:artifact)
      end

      def test_names_the_file_and_line_of_a_mistake
        mistake = assert_raises(Core::Mistake) { debt_files_port(broken: "debt.tsv").read(debt_root, "debt.tsv") }

        assert_equal ["debt.tsv", 3], [mistake.file, mistake.line]
      end
    end

    module SharedPluginsContract
      TAGS = %w[v1.0.0 v1.2.0 v1.10.0 2.0.0-rc.1 latest].freeze

      def test_accepts_the_urls_of_https_and_no_other_scheme_unless_it_is_told_to
        port = shared_plugins_port
        urls = ["https://github.com/OWNER/REPO", "http://github.com/OWNER/REPO", "git@github.com:OWNER/REPO.git", "ext::sh -c id", "/tmp/repo", ""]

        assert_equal [true, false, false, false, false, false], urls.map { |url| port.accepts?(url) }
      end

      def test_returns_one_folder_for_a_url_and_ref_and_another_for_another_ref
        port = shared_plugins_port
        folder = port.fetch(repository_url, "v1.0.0")

        assert_equal folder, port.fetch(repository_url, "v1.0.0")
        refute_equal folder, port.fetch(repository_url, "v1.2.0")
      end

      def test_fetches_a_commit_by_its_full_sha
        port = shared_plugins_port
        folder = port.fetch(repository_url, commit_sha)

        assert_equal folder, port.fetch(repository_url, commit_sha)
        refute_equal folder, port.fetch(repository_url, "v1.0.0")
      end

      def test_says_what_it_fetches_the_first_time_only
        port = shared_plugins_port
        2.times { port.fetch(repository_url, "v1.0.0") }
        port.fetch(repository_url, "v1.2.0")

        assert_equal "crosslint: fetching #{repository_url} at v1.0.0\ncrosslint: fetching #{repository_url} at v1.2.0\n", said
      end

      def test_makes_no_request_for_a_plugin_it_fetched_even_when_the_repository_is_gone
        port = shared_plugins_port
        folder = port.fetch(repository_url, "v1.0.0")
        remove_repository

        assert_equal folder, port.fetch(repository_url, "v1.0.0")
        assert_equal ["crosslint: fetching #{repository_url} at v1.0.0"], said.lines(chomp: true)
      end

      def test_refuses_a_ref_that_names_a_branch_and_no_tag
        error = assert_raises(Core::FetchError) { shared_plugins_port.fetch(repository_url, "main") }

        assert_equal "main is a branch, and a ref is a tag or a full 40-character commit SHA", error.message
      end

      def test_refuses_a_ref_that_names_no_tag
        error = assert_raises(Core::FetchError) { shared_plugins_port.fetch(repository_url, "v9.9.9") }

        assert_equal "the repository has no tag v9.9.9, and a ref is a tag or a full 40-character commit SHA", error.message
      end

      def test_refuses_a_commit_the_repository_doesnt_have
        sha = "0" * 39 + "1"
        error = assert_raises(Core::FetchError) { shared_plugins_port.fetch(repository_url, sha) }

        assert_includes error.message, sha
      end

      def test_refuses_a_ref_that_is_neither_a_tag_name_nor_a_full_sha
        port = shared_plugins_port
        refs = ["", "a:b", "-v1", "main^", "v1 2", "v1.0.0:refs/heads/x"]
        messages = refs.map { |ref| assert_raises(Core::FetchError) { port.fetch(repository_url, ref) }.message }

        assert_equal(refs.map { |ref| "#{ref.dump} is neither a tag name nor a full 40-character commit SHA" }, messages)
        assert_empty said
      end

      def test_refuses_a_repository_that_isnt_there
        assert_raises(Core::FetchError) { shared_plugins_port.fetch(missing_repository_url, "v1.0.0") }
        assert_raises(Core::FetchError) { shared_plugins_port.fetch(missing_repository_url, commit_sha) }
      end

      def test_refuses_a_url_it_doesnt_accept_without_a_request
        port = shared_plugins_port

        errors = [assert_raises(Core::FetchError) { port.fetch("ext::sh -c id", "v1.0.0") }, assert_raises(Core::FetchError) { port.tags("ext::sh -c id") }]

        assert(errors.all? { |error| error.message.start_with?("ext::sh -c id doesn't start with https://") })
        assert_empty said
      end

      def test_gives_no_folder_for_a_plugin_it_hasnt_fetched_and_makes_no_request_for_it
        port = shared_plugins_port

        assert_nil port.cached(repository_url, "v1.0.0")
        assert_nil port.cached(repository_url, commit_sha)
        assert_empty said
        port.fetch(repository_url, "v1.0.0")
        assert_nil port.cached(repository_url, "v1.2.0")
        assert_equal "crosslint: fetching #{repository_url} at v1.0.0\n", said
      end

      def test_gives_the_folder_it_fetched_without_a_request_even_when_the_repository_is_gone
        port = shared_plugins_port
        folder = port.fetch(repository_url, "v1.0.0")
        remove_repository
        said_before = said

        assert_equal folder, port.cached(repository_url, "v1.0.0")
        assert_equal said_before, said
      end

      def test_gives_no_folder_for_a_url_or_ref_it_would_refuse_to_fetch
        port = shared_plugins_port

        assert_nil port.cached("ext::sh -c id", "v1.0.0")
        assert_nil port.cached(repository_url, "main^")
        assert_nil port.cached(repository_url, "")
        assert_empty said
      end

      def test_lists_the_names_of_the_repositorys_tags
        assert_equal TAGS.sort, shared_plugins_port.tags(repository_url).sort
      end

      def test_says_what_it_lists
        shared_plugins_port.tags(repository_url)

        assert_equal "crosslint: listing the tags of #{repository_url}\n", said
      end

      def test_refuses_to_list_the_tags_of_a_repository_that_isnt_there
        assert_raises(Core::FetchError) { shared_plugins_port.tags(missing_repository_url) }
      end
    end
  end
end
