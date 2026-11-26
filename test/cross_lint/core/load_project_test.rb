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

  def test_stops_at_a_shared_plugin
    assert_mistake CONFIG, 1, %(shared plugin "https://github.com/o/r" needs ref=, a tag or a full commit SHA),
      plugins: [listing("https://github.com/o/r")]
    assert_mistake CONFIG, 1, "CrossLint can't fetch shared plugins yet", plugins: [listing("https://github.com/o/r", ref: "v1.2.0")]
  end

  def test_reads_a_built_in_plugin_from_its_folder
    project = load_project(plugins: [listing("debt")], built_in: {"debt" => "#{TOP}c/plugins/debt"},
      manifests: {"#{TOP}c/plugins/debt" => tests_manifest("debt")})

    assert_equal [["debt", "#{TOP}c/plugins/debt"]], project.plugins.map { |plugin| [plugin.name, plugin.folder] }
  end

  def test_stops_at_a_built_in_plugin_crosslint_does_not_have
    assert_mistake CONFIG, 1, %(unknown built-in plugin "dept", did you mean "debt"?), plugins: [listing("dept")],
      built_in: {"debt" => "#{TOP}c/plugins/debt", "angular" => "#{TOP}c/plugins/angular"}
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
      manifests: MemoryPluginManifests.new({"#{APP}/rules/tests" => debt_manifest("rules/tests")}))

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
    use_case = LoadProject.new(configuration: MemoryConfiguration.new({APP => configuration}), manifests: MemoryPluginManifests.new)
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
    mistake = assert_raises(Mistake) { LoadProject.new(configuration:, manifests: MemoryPluginManifests.new).call(APP) }

    assert_equal "#{CONFIG}:2", mistake.location
  end

  private

  MemoryConfiguration = CrossLint::Adapters::MemoryConfiguration
  MemoryPluginManifests = CrossLint::Adapters::MemoryPluginManifests

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

  def load_project(plugins: [listing("./rules/tests")], policies: [], manifests: nil, manifest: nil, built_in: {}, steps: {}, start: APP)
    manifests ||= {"#{APP}/rules/tests" => manifest || tests_manifest}
    configuration = Configuration.new(file: CONFIG, plugins:, policies:, warnings: nil, verbosity: nil)
    LoadProject.new(configuration: MemoryConfiguration.new({APP => configuration}),
      manifests: MemoryPluginManifests.new(manifests), built_in:, steps:).call(start)
  end

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
