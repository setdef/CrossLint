# frozen_string_literal: true

require "test_helper"

# Core::LoadProject against the in-memory adapters: every requirement of
# the configuration and plugin references that isn't about KDL.
class LoadProjectTest < Minitest::Test
  cover "CrossLint::Core::LoadProject*"

  include CrossLint::Core

  CONFIG = ".config/crosslint/config.kdl"

  # Absolute paths as File.expand_path gives them, with a drive on Windows.
  TOP = File.expand_path("/")
  APP = File.expand_path("/app")

  def test_finds_the_project_from_a_folder_inside_it
    project = load_project(start: "#{APP}/lib/deep")

    assert_equal APP, project.root
    assert_equal ["tests"], project.plugins.map(&:name)
  end

  def test_says_how_to_write_a_configuration_when_there_is_none
    mistake = assert_raises(Mistake) { load_project(plugins: [listing(".x")], start: "/elsewhere/lib") }

    assert_equal ["", "no .config/crosslint/config.kdl in /elsewhere/lib or any folder above it; " \
      "run crosslint init in the project's root to write one"], [mistake.location, mistake.message]
  end

  def test_stops_when_the_configuration_lists_no_plugin
    assert_mistake CONFIG, nil, "lists no plugin, so no check would run; list one with plugin NAME", plugins: []
  end

  def test_stops_at_a_plugin_listed_twice
    assert_mistake CONFIG, 4, %(plugin ".config/crosslint/tests" is listed twice; the first is on line 1),
      plugins: [listing(".config/crosslint/tests"), listing(".config/crosslint/tests", line: 4)],
      manifests: {"#{APP}/.config/crosslint/tests" => tests_manifest(".config/crosslint/tests")}
  end

  def test_reads_a_local_plugin_from_its_folder_relative_to_the_root
    manifests = {"#{APP}/rules/tests" => tests_manifest("rules/tests"), APP => tests_manifest("")}
    project = load_project(plugins: [listing("./a/../rules/./tests/"), listing("/", line: 2)], manifests:)

    assert_equal [["tests", "#{APP}/rules/tests"], ["app", APP]], project.plugins.map { |plugin| [plugin.name, plugin.folder] }
    assert_equal "./a/../rules/./tests/", project.plugins.first.listing.name
  end

  def test_reads_a_local_plugin_above_the_root
    project = load_project(plugins: [listing("../shared/tests")], manifests: {"#{TOP}shared/tests" => tests_manifest("../shared/tests")})

    assert_equal [["tests", "#{TOP}shared/tests"]], project.plugins.map { |plugin| [plugin.name, plugin.folder] }
  end

  def test_stops_at_a_local_plugin_with_no_manifest
    assert_mistake CONFIG, 1, "no plugin.kdl in .config/crosslint/missing", plugins: [listing(".config/crosslint/missing")]
    assert_mistake CONFIG, 1, "no plugin.kdl in ../..", plugins: [listing("../../x/..")]
  end

  def test_stops_at_a_setting_the_plugins_manifest_doesnt_declare
    plugin = listing(".config/crosslint/tests", settings: [setting("src-dir", line: 2), setting("other", line: 3)])

    assert_mistake CONFIG, 2, %(unknown setting "src-dir"; plugin tests takes none), plugins: [plugin],
      manifests: {"#{APP}/.config/crosslint/tests" => tests_manifest(".config/crosslint/tests")}
    assert_mistake CONFIG, 2, %(unknown setting "fiel", did you mean "file"?), plugins: [listing("debt", settings: [setting("fiel", line: 2)])],
      built_in: {"debt" => "#{TOP}c/plugins/debt"}, manifests: {"#{TOP}c/plugins/debt" => debt_manifest}, steps: {"track-debt" => RecordingStep.new}
  end

  def test_stops_at_a_ref_for_a_local_or_built_in_plugin
    assert_mistake CONFIG, 1, "only a shared plugin takes ref=", plugins: [listing(".config/crosslint/tests", ref: "v1")]
    assert_mistake CONFIG, 1, "only a shared plugin takes ref=", plugins: [listing("debt", ref: "v1")], built_in: {"debt" => "#{TOP}c/plugins/debt"}
  end

  URL = "https://example.com/o/signatures"

  def test_stops_at_a_shared_plugin_with_no_ref
    assert_mistake CONFIG, 1, %(shared plugin "#{URL}" needs ref=, a tag or a full commit SHA), plugins: [listing(URL)]
  end

  def test_reads_a_shared_plugin_from_the_folder_the_port_fetched
    shared = shared_plugins("v1.2.0" => "#{TOP}cache/a1/signatures")
    project = load_project(plugins: [listing(URL, ref: "v1.2.0", line: 3)], manifests: {"#{TOP}cache/a1/signatures" => tests_manifest("signatures")},
      shared_plugins: shared)

    assert_equal [["signatures", "#{TOP}cache/a1/signatures"]], project.plugins.map { |plugin| [plugin.name, plugin.folder] }
    assert_equal [[URL, "v1.2.0"]], shared.fetched
  end

  def test_reads_a_shared_plugin_at_a_commit_sha
    sha = "a" * 40
    repository = MemorySharedPlugins::Repository.new(tags: {}, branches: [], commits: {sha => "#{TOP}cache/b2/signatures"})
    shared = MemorySharedPlugins.new({URL => repository}, err: StringIO.new)
    project = load_project(plugins: [listing(URL, ref: sha)], manifests: {"#{TOP}cache/b2/signatures" => tests_manifest("signatures")}, shared_plugins: shared)

    assert_equal [["signatures", "#{TOP}cache/b2/signatures"]], project.plugins.map { |plugin| [plugin.name, plugin.folder] }
  end

  def test_reads_a_shared_plugin_at_a_url_the_port_accepts_that_isnt_https
    url = "file:///tmp/signatures"
    repository = MemorySharedPlugins::Repository.new(tags: {"v1.0.0" => "#{TOP}cache/c3/signatures"}, branches: [], commits: {})
    shared = MemorySharedPlugins.new({url => repository}, err: StringIO.new, schemes: ["file://"])
    project = load_project(plugins: [listing(url, ref: "v1.0.0")], manifests: {"#{TOP}cache/c3/signatures" => tests_manifest("signatures")},
      shared_plugins: shared)

    assert_equal ["signatures"], project.plugins.map(&:name)
    assert_mistake CONFIG, 1, %(unknown built-in plugin "file:///tmp/signatures"; this CrossLint has none), plugins: [listing(url)]
  end

  def test_names_the_plugin_and_the_url_when_a_fetch_fails
    assert_mistake CONFIG, 2, %(couldn't fetch shared plugin signatures from #{URL} at v9.9.9: the repository has no tag v9.9.9, ) +
      "and a ref is a tag or a full 40-character commit SHA", plugins: [listing(URL, ref: "v9.9.9", line: 2)],
      shared_plugins: shared_plugins("v1.2.0" => "#{TOP}cache/a1/signatures")
    assert_mistake CONFIG, 1, %(couldn't fetch shared plugin signatures from #{URL} at main: main is a branch, ) +
      "and a ref is a tag or a full 40-character commit SHA", plugins: [listing(URL, ref: "main")], shared_plugins: shared_plugins({})
  end

  def test_stops_at_a_shared_plugin_whose_url_names_no_plugin
    assert_mistake CONFIG, 1, %(can't name a plugin from "https://example.com/o/a b", whose last path segment has other characters ) +
      "than letters, digits, and . _ -; a plugin's name is its repository's name", plugins: [listing("https://example.com/o/a b", ref: "v1")]
  end

  def test_stops_at_a_shared_plugin_with_no_manifest_in_its_root
    assert_mistake CONFIG, 1, "no plugin.kdl in the root of #{URL} at v1.2.0", plugins: [listing(URL, ref: "v1.2.0")],
      shared_plugins: shared_plugins("v1.2.0" => "#{TOP}cache/a1/signatures")
  end

  def test_stops_at_a_shared_plugin_with_the_name_of_a_local_one
    plugins = [listing("./rules/signatures"), listing(URL, ref: "v1.2.0", line: 2)]
    manifests = {"#{APP}/rules/signatures" => tests_manifest("rules/signatures"), "#{TOP}cache/a1/signatures" => tests_manifest("signatures")}

    assert_mistake CONFIG, 2, %(plugins "./rules/signatures" and "#{URL}" are both named "signatures", since a plugin's name is its folder's name),
      plugins:, manifests:, shared_plugins: shared_plugins("v1.2.0" => "#{TOP}cache/a1/signatures")
  end

  def test_reads_a_built_in_plugin_from_its_folder
    project = load_project(plugins: [listing("debt")], built_in: {"debt" => "#{TOP}c/plugins/debt"},
      manifests: {"#{TOP}c/plugins/debt" => tests_manifest("debt")})

    assert_equal [["debt", "#{TOP}c/plugins/debt"]], project.plugins.map { |plugin| [plugin.name, plugin.folder] }
  end

  def test_stops_at_a_built_in_plugin_crosslint_does_not_have
    assert_mistake CONFIG, 1, %(unknown built-in plugin "dept", did you mean "debt"?), plugins: [listing("dept")],
      built_in: {"debt" => "#{TOP}c/plugins/debt", "docs" => "#{TOP}c/plugins/docs"}
    assert_mistake CONFIG, 1, %(unknown built-in plugin "zzz"; expected "debt"), plugins: [listing("zzz")],
      built_in: {"debt" => "#{TOP}c/plugins/debt"}
    assert_mistake CONFIG, 1, %(unknown built-in plugin "debt"; this CrossLint has none), plugins: [listing("debt")]
  end

  def test_has_each_step_read_its_plugins_settings
    step = RecordingStep.new
    settings = [setting("file", line: 2)]
    load_project(plugins: [listing("debt", settings:)], built_in: {"debt" => "#{TOP}c/plugins/debt"},
      manifests: {"#{TOP}c/plugins/debt" => debt_manifest}, steps: {"track-debt" => step})

    assert_equal [[settings, CONFIG]], step.read
  end

  def test_stops_at_a_mistake_a_step_finds_in_its_settings
    step = RecordingStep.new(Mistake.new("file takes one path", file: CONFIG, line: 2))

    assert_mistake CONFIG, 2, "file takes one path", plugins: [listing("debt", settings: [setting("file", line: 2)])],
      built_in: {"debt" => "#{TOP}c/plugins/debt"}, manifests: {"#{TOP}c/plugins/debt" => debt_manifest}, steps: {"track-debt" => step}
  end

  def test_stops_at_a_step_crosslint_doesnt_have
    assert_mistake "rules/tests/plugin.kdl", 9, %(unknown step "track-dept", did you mean "track-debt"?),
      manifest: debt_manifest("rules/tests", step: "track-dept"), steps: {"track-debt" => RecordingStep.new}
    assert_mistake "rules/tests/plugin.kdl", 9, %(unknown step "track-debt"; this CrossLint has none), manifest: debt_manifest("rules/tests")
  end

  def test_stops_at_a_policy_a_step_reports_that_the_manifest_doesnt_declare_with_no_block
    assert_mistake "rules/tests/plugin.kdl", 9, %(step "track-debt" reports policy "has-debt"; declare it as policy "has-debt", with no block),
      manifest: debt_manifest("rules/tests", step_policies: []), steps: {"track-debt" => RecordingStep.new}
  end

  def test_stops_at_each_policy_a_step_reports_that_the_manifest_doesnt_declare
    assert_mistake "rules/tests/plugin.kdl", 9, %(step "track-debt" reports policy "more"; declare it as policy "more", with no block),
      manifest: debt_manifest("rules/tests"), steps: {"track-debt" => RecordingStep.new(policies: ["has-debt", "more"])}
  end

  def test_stops_at_the_first_setting_the_manifest_doesnt_declare_after_one_it_does
    assert_mistake CONFIG, 3, %(unknown setting "other"; expected "file"),
      plugins: [listing("debt", settings: [setting("file", line: 2), setting("other", line: 3)])], built_in: {"debt" => "#{TOP}c/plugins/debt"},
      manifests: {"#{TOP}c/plugins/debt" => debt_manifest}, steps: {"track-debt" => RecordingStep.new}
  end

  def test_has_no_step_unless_it_is_given_some
    configuration = Configuration.new(file: CONFIG, plugins: [listing("./rules/tests")], policies: [], warnings: nil, verbosity: nil)
    use_case = LoadProject.new(configuration: MemoryConfiguration.new({APP => configuration}),
      manifests: MemoryPluginManifests.new({"#{APP}/rules/tests" => debt_manifest("rules/tests")}), plugin_ruby: MemoryPluginRuby.new,
      shared_plugins: shared_plugins({}))

    assert_equal %(unknown step "track-debt"; this CrossLint has none), assert_raises(Mistake) { use_case.call(APP) }.message
  end

  def test_stops_at_a_policy_with_no_block_that_no_step_reports
    assert_mistake "rules/tests/plugin.kdl", 4, %(policy "other" has no applies-to, and no step of the plugin reports it),
      manifest: debt_manifest("rules/tests", step_policies: [StepPolicy.new(name: "has-debt", line: 3), StepPolicy.new(name: "other", line: 4)]),
      steps: {"track-debt" => RecordingStep.new}
  end

  def test_stops_at_a_setting_flag_step_or_policy_declared_twice
    twice = ->(kind, field, made) { debt_manifest("rules/tests").with(field => [made.new(name: "a", line: 2), made.new(name: "a", line: 3)]) }
    {"setting" => [:settings, SettingDeclaration], "flag" => [:flags, FlagDeclaration]}.each do |kind, (field, made)|
      assert_mistake "rules/tests/plugin.kdl", 3, %(#{kind} "a" is declared twice; the first is on line 2), manifest: twice.call(kind, field, made),
        steps: {"track-debt" => RecordingStep.new}
    end
    assert_mistake "rules/tests/plugin.kdl", 9, %(step "track-debt" is declared twice; the first is on line 9),
      manifest: debt_manifest("rules/tests").then { |manifest| manifest.with(steps: manifest.steps * 2) }, steps: {"track-debt" => RecordingStep.new}
    assert_mistake "rules/tests/plugin.kdl", 3, %(policy "has-test" is declared twice; the first is on line 5),
      manifest: debt_manifest("rules/tests", step_policies: [StepPolicy.new(name: "has-test", line: 3)]), steps: {"track-debt" => RecordingStep.new}
  end

  def test_lets_the_configuration_change_a_policy_a_step_reports
    project = load_project(plugins: [listing("debt")], policies: [policy_setting("debt/has-debt")], built_in: {"debt" => "#{TOP}c/plugins/debt"},
      manifests: {"#{TOP}c/plugins/debt" => debt_manifest}, steps: {"track-debt" => RecordingStep.new})

    assert_equal ["debt/has-debt"], project.configuration.policies.map(&:name)
  end

  def test_stops_at_two_plugins_with_one_name
    assert_mistake CONFIG, 2, %(plugins ".config/a/tests" and "./rules/../tests" are both named "tests", ) +
      "since a plugin's name is its folder's name",
      plugins: [listing(".config/a/tests"), listing("./rules/../tests", line: 2)],
      manifests: {"#{APP}/.config/a/tests" => tests_manifest(".config/a/tests"), "#{APP}/tests" => tests_manifest("tests")}
  end

  def test_stops_at_an_artifact_declared_twice
    manifest = tests_manifest(artifacts: [artifact(line: 1), artifact(line: 6)])

    assert_mistake "rules/tests/plugin.kdl", 6, %(artifact "ruby-file" is declared twice; the first is on line 1), manifest:
  end

  def test_stops_at_a_companion_declared_twice
    manifest = tests_manifest(artifacts: [artifact(companions: [companion("test", line: 3), companion("test", line: 4)])])

    assert_mistake "rules/tests/plugin.kdl", 4, %(companion "test" is declared twice; the first is on line 3), manifest:
  end

  def test_stops_at_a_companion_with_a_placeholder_its_files_pattern_lacks
    manifest = tests_manifest(artifacts: [artifact(companions: [companion("test", "test/{path}/{name}_test.rb", line: 3)])])

    assert_mistake "rules/tests/plugin.kdl", 3,
      %(companion "test" uses {name}, which the files pattern "lib/{path}.rb" doesn't have), manifest:
  end

  def test_stops_at_a_policy_declared_twice
    manifest = tests_manifest(policies: [policy(line: 5), policy(line: 9)])

    assert_mistake "rules/tests/plugin.kdl", 9, %(policy "has-test" is declared twice; the first is on line 5), manifest:
  end

  def test_stops_at_a_rule_or_helper_declared_twice
    rules = [RuleDeclaration.new(name: "names-class", ruby: "a.rb", line: 2), RuleDeclaration.new(name: "names-class", ruby: "b.rb", line: 3)]
    helpers = [HelperDeclaration.new(name: "members", command: "node", file: "a.mjs", line: 2),
      HelperDeclaration.new(name: "members", command: "node", file: "b.mjs", line: 8)]

    assert_mistake "rules/tests/plugin.kdl", 3, %(rule "names-class" is declared twice; the first is on line 2),
      manifest: tests_manifest(rules:, policies: [policy(rules: [policy_rule("names-class")])])
    assert_mistake "rules/tests/plugin.kdl", 8, %(helper "members" is declared twice; the first is on line 2),
      manifest: tests_manifest(helpers:)
  end

  def test_stops_at_a_ruby_rule_with_the_name_of_a_built_in_rule
    rules = [RuleDeclaration.new(name: "companion-absent", ruby: "a.rb", line: 2)]

    assert_mistake "rules/tests/plugin.kdl", 2, %(rule "companion-absent" has the name of a built-in rule; name it something else),
      manifest: tests_manifest(rules:)
  end

  def test_applies_a_policy_to_an_artifact_of_its_own_plugin_or_another_listed_one
    other = tests_manifest(".config/other", artifacts: [artifact("source-file")], policies: [policy(applies_to: "tests/ruby-file")])
    project = load_project(plugins: [listing("./rules/tests"), listing(".config/other", line: 2)],
      manifests: {"#{APP}/rules/tests" => tests_manifest, "#{APP}/.config/other" => other})

    assert_equal ["tests", "other"], project.plugins.map(&:name)
  end

  def test_reads_a_policy_with_no_applies_to_that_some_artifact_of_its_plugin_has_the_companions_for
    exists = Condition::CompanionExists.new(companion: "test", line: 7)
    project = load_project(manifest: tests_manifest(policies: [policy(applies_to: nil, condition: exists)]))

    assert_nil project.plugins.first.manifest.policies.first.applies_to
  end

  def test_stops_at_a_policy_with_no_applies_to_that_no_artifact_of_its_plugin_has_the_companions_for
    stub = Condition::CompanionExists.new(companion: "stub", line: 7)
    assert_mistake "rules/tests/plugin.kdl", 5, %(policy "has-test" has no applies-to, and plugin tests has no artifact with "stub" and "test", the companions it names),
      manifest: tests_manifest(policies: [policy(applies_to: nil, condition: stub)])
    assert_mistake "rules/tests/plugin.kdl", 5, %(policy "has-test" has no applies-to, and plugin tests declares no artifact),
      manifest: tests_manifest(artifacts: [], policies: [policy(applies_to: nil, rules: [policy_rule("names-class")])], rules: [RuleDeclaration.new(name: "names-class", ruby: "a.rb", line: 2)])
    assert_mistake "rules/tests/plugin.kdl", 7, %(unknown rule "companion-exist", did you mean "companion-exists"?),
      manifest: tests_manifest(policies: [policy(applies_to: nil, rules: [policy_rule("companion-exist", arguments: {})])])
  end

  def test_adds_the_artifacts_a_plugins_ruby_declares_from_its_settings
    given = []
    ruby = declaring do |settings|
      given << settings
      [artifact("ruby-file", files: "#{settings.first.name}/{path}.rb", companions: {"test" => "test/{path}_test.rb"}, key: "{path}", optional: true)]
    end
    manifest = declaring_manifest.with(settings: [SettingDeclaration.new(name: "lib", line: 2)])
    project = load_project(plugins: [listing("./rules/tests", settings: [setting("lib", line: 3)])], manifest:, ruby:)
    declared = project.plugins.first.manifest.artifacts

    assert_equal [[setting("lib", line: 3)]], given
    assert_equal [["ruby-file", "lib/{path}.rb", [["test", "test/{path}_test.rb", 4]], "{path}", true, 4]],
      declared.map { |each| [each.name, each.files.source, each.companions.map { [_1.name, _1.pattern.source, _1.line] }, each.key.source, each.optional, each.line] }
  end

  def test_adds_the_artifacts_a_plugins_ruby_declares_to_those_its_manifest_declares
    manifest = declaring_manifest.with(artifacts: [artifact("source-file")])
    project = load_project(manifest:, ruby: declaring { |_| [artifact("ruby-file", files: "lib/{path}.rb")] })

    assert_equal ["source-file", "ruby-file"], project.plugins.first.manifest.artifacts.map(&:name)
  end

  def test_names_a_file_of_its_plugin_that_a_plugins_ruby_requires_and_lacks
    missing = LoadError.new("cannot load such file")
    missing.define_singleton_method(:path) { "#{APP}/rules/tests/helpers/roles.rb" }

    assert_mistake "rules/tests/plugin.kdl", 4, "fault in plugin tests: artifacts.rb requires helpers/roles.rb, which doesn't exist",
      manifest: declaring_manifest, ruby: {"#{APP}/rules/tests/artifacts.rb" => ->(_) { raise missing }}
  end

  def test_checks_a_policy_against_the_artifacts_a_plugins_ruby_declares
    ruby = declaring { |_| [artifact("ruby-file", files: "lib/{path}.rb")] }

    assert_mistake "rules/tests/plugin.kdl", 7, %(unknown companion "test"; artifact "ruby-file" declares none),
      manifest: declaring_manifest(policies: [policy]), ruby:
  end

  def test_lets_a_policy_with_no_applies_to_apply_to_nothing_when_a_plugins_ruby_declares_its_artifacts
    project = load_project(manifest: declaring_manifest, ruby: declaring { |_| [] })

    assert_empty project.plugins.first.manifest.artifacts
  end

  def test_stops_at_the_mistake_a_plugins_ruby_makes_of_a_setting
    ruby = declaring { |settings| raise mistake("lib takes a folder", settings.first) }
    manifest = declaring_manifest.with(settings: [SettingDeclaration.new(name: "lib", line: 2)])

    assert_mistake CONFIG, 3, "lib takes a folder", plugins: [listing("./rules/tests", settings: [setting("lib", line: 3)])], manifest:, ruby:
  end

  def test_stops_at_what_a_plugins_ruby_raises_naming_the_plugin_and_the_line_that_names_the_file
    file = "rules/tests/plugin.kdl"
    assert_mistake file, 4, "fault in plugin tests: artifacts.rb raised RuntimeError: broken", manifest: declaring_manifest,
      ruby: declaring { |_| raise "broken" }
    assert_mistake file, 4, "fault in plugin tests: artifacts.rb has no declare method", manifest: declaring_manifest, ruby: declaring
    assert_mistake file, 4, "fault in plugin tests: artifacts.rb defines no class Artifacts", manifest: declaring_manifest,
      ruby: {"#{APP}/rules/tests/artifacts.rb" => ->(namespace) { namespace.const_set(:Artifacts, 3) }}
    assert_mistake file, 4, "fault in plugin tests: artifacts.rb defines no class Artifacts", manifest: declaring_manifest,
      ruby: {"#{APP}/rules/tests/artifacts.rb" => ->(_) {}}
    assert_mistake file, 4, "fault in plugin tests: artifacts.rb has a class Artifacts that doesn't inherit from CrossLint::Artifacts",
      manifest: declaring_manifest, ruby: declaring("def declare(_) = []", superclass: Object)
    assert_mistake file, 4, "fault in plugin tests: artifacts.rb returned Hash from declare, where declare returns an array of artifacts",
      manifest: declaring_manifest, ruby: declaring { |_| {} }
    assert_mistake file, 4, "fault in plugin tests: artifacts.rb returned Array from declare, where declare returns an array of artifacts",
      manifest: declaring_manifest, ruby: declaring { |_| [3] }
    assert_mistake file, 4, %(no file "artifacts.rb" in the plugin's folder), manifest: declaring_manifest
  end

  def test_finds_artifacts_in_the_plugins_namespace_alone_and_lets_them_set_up_in_initialize
    ruby = declaring(<<~RUBY)
      def initialize
        @folder = "lib"
      end

      def declare(_) = [artifact("ruby-file", files: @folder + "/{path}.rb", companions: {"test" => "t/{path}"})]
    RUBY
    # A built-in plugin's Artifacts, which test/plugin_ruby.rb loaded at the top level, is put back.
    loaded = Object.__send__(:remove_const, :Artifacts) if Object.const_defined?(:Artifacts, false)
    Object.const_set(:Artifacts, Class.new(CrossLint::Artifacts))
    project = load_project(manifest: declaring_manifest, ruby:)

    assert_equal ["lib/{path}.rb"], project.plugins.first.manifest.artifacts.map { _1.files.source }
    assert_mistake "rules/tests/plugin.kdl", 4, "fault in plugin tests: artifacts.rb defines no class Artifacts", manifest: declaring_manifest,
      ruby: {"#{APP}/rules/tests/artifacts.rb" => ->(_) {}}
  ensure
    Object.__send__(:remove_const, :Artifacts) if Object.const_defined?(:Artifacts, false)
    Object.const_set(:Artifacts, loaded) if loaded
  end

  def test_stops_at_a_policy_for_an_artifact_no_listed_plugin_declares
    assert_mistake "rules/tests/plugin.kdl", 6, %(unknown artifact "rubyfile", did you mean "ruby-file"?),
      manifest: tests_manifest(policies: [policy(applies_to: "rubyfile")])
    assert_mistake "rules/tests/plugin.kdl", 6, %(unknown artifact "zzz"; expected "ruby-file"),
      manifest: tests_manifest(policies: [policy(applies_to: "tests/zzz")])
    assert_mistake "rules/tests/plugin.kdl", 6, %(unknown plugin "test", did you mean "tests"?),
      manifest: tests_manifest(policies: [policy(applies_to: "test/ruby-file")])
    assert_mistake "rules/tests/plugin.kdl", 6, %(unknown artifact "ruby-file"; tests declares none),
      manifest: tests_manifest(artifacts: [], policies: [policy])
  end

  def test_stops_at_a_condition_on_a_companion_the_artifact_lacks
    condition = Condition::All.new(conditions: [Condition::CompanionExists.new(companion: "test", line: 7),
      Condition::Not.new(condition: Condition::Any.new(conditions: [Condition::CompanionExists.new(companion: "stub", line: 9)], line: 8),
        line: 8)], line: 7)
    project = load_project(manifests: {"#{APP}/rules/tests" => tests_manifest(policies: [policy(condition: Condition::CompanionExists.new(companion: "test", line: 7))])})

    assert_equal "test", project.plugins.first.manifest.policies.first.condition.companion
    assert_mistake "rules/tests/plugin.kdl", 9, %(unknown companion "stub"; expected "test"),
      manifest: tests_manifest(policies: [policy(condition:)])
  end

  def test_runs_a_built_in_rule_with_a_companion_of_the_artifact
    project = load_project(manifests: {"#{APP}/rules/tests" => tests_manifest(policies: [policy(rules: [policy_rule("companion-absent")])])})

    assert_equal ["companion-absent"], project.plugins.first.manifest.policies.first.rules.map(&:name)
  end

  def test_stops_at_a_rule_that_is_neither_built_in_nor_declared
    assert_mistake "rules/tests/plugin.kdl", 7, %(unknown rule "companion-exist", did you mean "companion-exists"?),
      manifest: tests_manifest(policies: [policy(rules: [policy_rule("companion-exist")])])
    assert_mistake "rules/tests/plugin.kdl", 7, %(unknown rule "zzz"; expected "companion-exists", "companion-absent", or "names-class"),
      manifest: tests_manifest(rules: [RuleDeclaration.new(name: "names-class", ruby: "a.rb", line: 2)],
        policies: [policy(rules: [policy_rule("zzz"), policy_rule("names-class")])])
  end

  def test_stops_at_a_built_in_rule_with_the_wrong_arguments
    assert_mistake "rules/tests/plugin.kdl", 7, %(rule "companion-exists" needs companion=NAME),
      manifest: tests_manifest(policies: [policy(rules: [policy_rule(arguments: {})])])
    assert_mistake "rules/tests/plugin.kdl", 7, %(unknown argument "companoin", did you mean "companion"? for rule "companion-exists"),
      manifest: tests_manifest(policies: [policy(rules: [policy_rule(arguments: {"companoin" => "test"})])])
    assert_mistake "rules/tests/plugin.kdl", 7, "companion= takes the name of a companion, as a string",
      manifest: tests_manifest(policies: [policy(rules: [policy_rule(arguments: {"companion" => 3})])])
  end

  def test_stops_at_a_built_in_rule_on_a_companion_the_artifact_lacks
    assert_mistake "rules/tests/plugin.kdl", 7, %(unknown companion "tset", did you mean "test"?),
      manifest: tests_manifest(policies: [policy(rules: [policy_rule(arguments: {"companion" => "tset"})])])
    assert_mistake "rules/tests/plugin.kdl", 7, %(unknown companion "test"; artifact "ruby-file" declares none),
      manifest: tests_manifest(artifacts: [artifact(companions: [])])
  end

  def test_runs_a_ruby_rule_its_plugin_declares_with_no_arguments
    rules = [RuleDeclaration.new(name: "names-class", ruby: "rules/names_class.rb", line: 2)]
    manifest = tests_manifest(rules:, policies: [policy(rules: [policy_rule("names-class")])])

    assert_empty load_project(manifests: {"#{APP}/rules/tests" => manifest}).unused_rules
    assert_mistake "rules/tests/plugin.kdl", 7, %(rule "names-class" is written in Ruby, and takes no style=),
      manifest: tests_manifest(rules:, policies: [policy(rules: [policy_rule("names-class", arguments: {"style" => "strict"})])])
  end

  def test_reports_a_ruby_rule_no_policy_runs
    rules = [RuleDeclaration.new(name: "names-class", ruby: "a.rb", line: 2), RuleDeclaration.new(name: "unused", ruby: "b.rb", line: 3)]
    manifest = tests_manifest(rules:, policies: [policy(rules: [policy_rule("names-class")])])
    project = load_project(manifests: {"#{APP}/rules/tests" => manifest})

    assert_equal [["tests", "unused"]], project.unused_rules.map { |plugin, rule| [plugin.name, rule.name] }
  end

  def test_runs_no_ruby_rule_of_another_plugin
    other = tests_manifest(".config/other", rules: [RuleDeclaration.new(name: "names-class", ruby: "a.rb", line: 2)])

    assert_mistake "rules/tests/plugin.kdl", 7, %(unknown rule "names-class"; expected "companion-exists" or "companion-absent"),
      plugins: [listing("./rules/tests"), listing(".config/other", line: 2)],
      manifests: {"#{APP}/rules/tests" => tests_manifest(policies: [policy(rules: [policy_rule("names-class")])]), "#{APP}/.config/other" => other}
  end

  def test_changes_a_policy_of_a_listed_plugin
    project = load_project(policies: [PolicySetting.new(name: "tests/has-test", enabled: false, severity: nil, line: 3)])

    assert_equal ["tests/has-test"], project.configuration.policies.map(&:name)
  end

  def test_stops_at_a_change_to_a_policy_no_listed_plugin_has
    assert_mistake CONFIG, 3, %(unknown plugin "test", did you mean "tests"?), policies: [policy_setting("test/has-test")]
    assert_mistake CONFIG, 3, %(unknown policy "has-tests", did you mean "has-test"?), policies: [policy_setting("tests/has-tests")]
    assert_mistake CONFIG, 3, %(unknown policy "has-test"; tests declares none), policies: [policy_setting("tests/has-test")],
      manifest: tests_manifest(policies: [])
  end

  def test_stops_at_a_change_to_a_policy_that_names_no_plugin
    ["has-test", "/has-test", "tests/", ""].each do |name|
      assert_mistake CONFIG, 3, "policy #{name.dump} names no plugin; write it as PLUGIN/POLICY", policies: [policy_setting(name)]
    end
  end

  def test_stops_at_a_policy_changed_twice
    assert_mistake CONFIG, 4, %(policy "tests/has-test" is set twice; the first is on line 3),
      policies: [policy_setting("tests/has-test"), policy_setting("tests/has-test", line: 4)]
  end

  def test_reads_a_plugin_that_declares_several_of_each_thing
    rules = [RuleDeclaration.new(name: "one", ruby: "a.rb", line: 20), RuleDeclaration.new(name: "two", ruby: "b.rb", line: 21)]
    helpers = [HelperDeclaration.new(name: "one", command: "node", file: "a.mjs", line: 22),
      HelperDeclaration.new(name: "two", command: "node", file: "b.mjs", line: 23)]
    condition = Condition::All.new(conditions: [Condition::CompanionExists.new(companion: "test", line: 7),
      Condition::CompanionExists.new(companion: "sig", line: 7)], line: 7)
    ruby_file = artifact(companions: [companion("test"), companion("sig", "sig/{path}.rbs")])
    policies = [policy(condition:, rules: [policy_rule, policy_rule("companion-absent", arguments: {"companion" => "sig"}), policy_rule("one")]),
      Policy.new(name: "two", applies_to: AppliesTo.new(artifact: "source-file", line: 11), condition: nil, rules: [policy_rule("two")], line: 10)]
    manifest = tests_manifest(artifacts: [ruby_file, artifact("source-file")], policies:, rules:, helpers:)
    project = load_project(manifest:, policies: [policy_setting("tests/has-test"), policy_setting("tests/two", line: 4)])

    assert_equal [%w[ruby-file source-file], %w[has-test two]],
      [project.plugins.first.manifest.artifacts.map(&:name), project.plugins.first.manifest.policies.map(&:name)]
  end

  def test_stops_at_the_later_of_two_mistakes_in_a_list
    assert_mistake "rules/tests/plugin.kdl", 4, %(companion "stub" uses {name}, which the files pattern "lib/{path}.rb" doesn't have),
      manifest: tests_manifest(artifacts: [artifact(companions: [companion("test"), companion("stub", "{name}.rb", line: 4)])])
    assert_mistake "rules/tests/plugin.kdl", 3, %(rule "companion-exists" has the name of a built-in rule; name it something else),
      manifest: tests_manifest(rules: [RuleDeclaration.new(name: "one", ruby: "a.rb", line: 2), RuleDeclaration.new(name: "companion-exists", ruby: "b.rb", line: 3)],
        policies: [policy(rules: [policy_rule("one")])])
    assert_mistake "rules/tests/plugin.kdl", 7, %(unknown rule "zzz"; expected "companion-exists" or "companion-absent"),
      manifest: tests_manifest(policies: [policy(rules: [policy_rule, policy_rule("zzz")])])
    assert_mistake "rules/tests/plugin.kdl", 6, %(unknown artifact "zzz"; expected "ruby-file"),
      manifest: tests_manifest(policies: [policy, policy(applies_to: "zzz").with(name: "other")])
    assert_mistake "rules/tests/plugin.kdl", 8, %(unknown companion "zzz"; expected "test"),
      manifest: tests_manifest(policies: [policy(condition: Condition::Any.new(conditions: [Condition::CompanionExists.new(companion: "test", line: 7),
        Condition::CompanionExists.new(companion: "zzz", line: 8)], line: 7))])
  end

  def test_names_the_first_of_two_listings_when_a_plugin_is_listed_again
    assert_mistake CONFIG, 4, %(plugin "./rules/tests" is listed twice; the first is on line 1),
      plugins: [listing("./rules/tests"), listing(".config/other", line: 2), listing("./rules/tests", line: 4)],
      manifests: {"#{APP}/rules/tests" => tests_manifest, "#{APP}/.config/other" => tests_manifest(".config/other")}
    assert_mistake CONFIG, 5, %(policy "tests/has-test" is set twice; the first is on line 3),
      policies: [policy_setting("tests/has-test"), policy_setting("tests/two", line: 4), policy_setting("tests/has-test", line: 5)],
      manifest: tests_manifest(policies: [policy, policy.with(name: "two")])
  end

  def test_names_a_local_plugins_folder_as_written_without_dots_or_extra_slashes
    assert_mistake CONFIG, 1, "no plugin.kdl in x/y", plugins: [listing("./x/./y//")]
    assert_mistake CONFIG, 1, "no plugin.kdl in x", plugins: [listing("//x")]
    assert_mistake CONFIG, 1, "no plugin.kdl in the project's root", plugins: [listing(".")]
  end

  def test_names_a_built_in_plugins_folder_by_its_name
    assert_mistake CONFIG, 1, "no plugin.kdl in debt", plugins: [listing("debt")], built_in: {"debt" => "#{TOP}c/plugins/debt"}
  end

  def test_has_no_built_in_plugins_unless_it_is_given_some
    configuration = Configuration.new(file: CONFIG, plugins: [listing("debt")], policies: [], warnings: nil, verbosity: nil)
    use_case = LoadProject.new(configuration: MemoryConfiguration.new({APP => configuration}), manifests: MemoryPluginManifests.new,
      plugin_ruby: MemoryPluginRuby.new, shared_plugins: shared_plugins({}))
    mistake = assert_raises(Mistake) { use_case.call(APP) }

    assert_equal %(unknown built-in plugin "debt"; this CrossLint has none), mistake.message
  end

  def test_applies_a_policy_to_the_whole_name_after_the_plugin
    assert_mistake "rules/tests/plugin.kdl", 6, %(unknown artifact "ruby/file", did you mean "ruby-file"?),
      manifest: tests_manifest(policies: [policy(applies_to: "tests/ruby/file")])
  end

  def test_takes_any_string_as_a_companion_name
    name = Class.new(String).new("test")

    assert_equal 1, load_project(manifest: tests_manifest(policies: [policy(rules: [policy_rule(arguments: {"companion" => name})])])).plugins.size
  end

  def test_raises_the_mistakes_the_ports_raise
    configuration = MemoryConfiguration.new({APP => Mistake.new("broken", file: CONFIG, line: 2)})
    mistake = assert_raises(Mistake) do
      LoadProject.new(configuration:, manifests: MemoryPluginManifests.new, plugin_ruby: MemoryPluginRuby.new, shared_plugins: shared_plugins({})).call(APP)
    end

    assert_equal "#{CONFIG}:2", mistake.location
  end

  private

  MemoryConfiguration = CrossLint::Adapters::MemoryConfiguration
  MemoryPluginManifests = CrossLint::Adapters::MemoryPluginManifests
  MemoryPluginRuby = CrossLint::Adapters::MemoryPluginRuby
  MemorySharedPlugins = CrossLint::Adapters::MemorySharedPlugins

  # A step that records the settings it is given to read, and raises
  # `mistake` when it reads them.
  class RecordingStep
    attr_reader :read

    def initialize(mistake = nil, policies: ["has-debt"])
      @mistake = mistake
      @policies = policies
      @read = []
    end

    attr_reader :policies

    def check_settings(settings, file)
      @read << [settings, file]
      raise @mistake if @mistake
    end

    def call(_input) = raise("not called")
  end

  def load_project(plugins: [listing("./rules/tests")], policies: [], manifests: nil, manifest: nil, built_in: {}, steps: {}, start: APP, ruby: {},
    shared_plugins: shared_plugins({}))
    manifests ||= {"#{APP}/rules/tests" => manifest || tests_manifest}
    configuration = Configuration.new(file: CONFIG, plugins:, policies:, warnings: nil, verbosity: nil)
    LoadProject.new(configuration: MemoryConfiguration.new({APP => configuration}),
      manifests: MemoryPluginManifests.new(manifests), plugin_ruby: MemoryPluginRuby.new(ruby), shared_plugins:, built_in:, steps:).call(start)
  end

  # A port with one repository, at URL, that has these tags and a branch
  # called main.
  def shared_plugins(tags)
    repository = MemorySharedPlugins::Repository.new(tags:, branches: ["main"], commits: {})
    MemorySharedPlugins.new({URL => repository}, err: StringIO.new)
  end

  # A plugin whose artifacts.rb defines Artifacts with `body`, as the
  # plugin's code would, in the namespace CrossLint gives it.
  def declaring(body = nil, superclass: CrossLint::Artifacts, &declare)
    {"#{APP}/rules/tests/artifacts.rb" => lambda do |namespace|
      found = Class.new(superclass)
      found.define_method(:declare, &declare) if declare
      found.class_eval(body) if body
      namespace.const_set(:Artifacts, found)
    end}
  end

  def declaring_manifest(policies: [policy(applies_to: nil)]) = tests_manifest(artifacts: [], policies:).with(artifacts_ruby: ArtifactsRuby.new(ruby: "artifacts.rb", line: 4))

  def assert_mistake(file, line, message, **options)
    mistake = assert_raises(Mistake) { load_project(**options) }

    assert_equal [file, line, message], [mistake.file, mistake.line, mistake.message]
  end

  def listing(name, ref: nil, settings: [], line: 1) = ListedPlugin.new(name:, ref:, settings:, line:)

  def setting(name, line:) = Setting.new(name:, arguments: [], properties: {}, children: [], line:)

  def policy_setting(name, line: 3) = PolicySetting.new(name:, enabled: false, severity: nil, line:)

  def tests_manifest(folder = "rules/tests", artifacts: [artifact], policies: [policy], rules: [], helpers: [])
    Manifest.new(file: folder.empty? ? "plugin.kdl" : "#{folder}/plugin.kdl", artifacts:, policies:, rules:, helpers:)
  end

  def debt_manifest(folder = "debt", step: "track-debt", step_policies: [StepPolicy.new(name: "has-debt", line: 3)])
    tests_manifest(folder).with(step_policies:, settings: [SettingDeclaration.new(name: "file", line: 4)],
      flags: [FlagDeclaration.new(name: "update-debt", line: 8)], steps: [StepDeclaration.new(name: step, line: 9)])
  end

  def artifact(name = "ruby-file", companions: [companion("test", line: 3)], line: 1)
    ArtifactDeclaration.new(name:, files: PathPattern.new(source: "lib/{path}.rb"), companions:, line:)
  end

  def companion(name, pattern = "test/{path}_test.rb", line: 3)
    CompanionDeclaration.new(name:, pattern: PathPattern.new(source: pattern), line:)
  end

  def policy(applies_to: "ruby-file", condition: nil, rules: [policy_rule], line: 5)
    Policy.new(name: "has-test", applies_to: applies_to && AppliesTo.new(artifact: applies_to, line: 6), condition:, rules:, line:)
  end

  def policy_rule(name = "companion-exists", arguments: BuiltInRule.named(name) ? {"companion" => "test"} : {})
    PolicyRule.new(name:, arguments:, severity: nil, line: 7)
  end
end
