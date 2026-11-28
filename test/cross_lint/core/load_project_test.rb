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

  # The CrossLint that loads each project.
  CROSSLINT = Version.parse("1.4.0")

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

  def test_stops_before_reading_a_configuration_that_needs_a_newer_crosslint
    configuration = MemoryConfiguration.new({APP => Mistake.new("unknown node", file: CONFIG, line: 2)},
      minimums: {APP => MinimumVersion.parse("1.5", file: CONFIG, line: 1)})

    [false, true].each do |listed|
      mistake = assert_raises(Mistake) { load_project(configuration:, listed:) }

      assert_equal ["#{CONFIG}:1", "needs CrossLint 1.5 or later, and this is CrossLint 1.4.0; upgrade CrossLint"], [mistake.location, mistake.message]
    end
  end

  def test_reads_a_configuration_that_this_crosslint_or_an_older_one_reads
    ["1.4", "1.3.9"].each do |text|
      configuration = MemoryConfiguration.new({APP => Configuration.new(file: CONFIG, plugins: [listing("./rules/tests")], policies: [], warnings: nil,
        verbosity: nil)}, minimums: {APP => MinimumVersion.parse(text, file: CONFIG, line: 1)})

      assert_equal ["tests"], load_project(configuration:).plugins.map(&:name)
    end
  end

  def test_stops_before_reading_a_manifest_that_needs_a_newer_crosslint_naming_the_plugin
    broken = {"#{APP}/rules/tests" => Mistake.new("unknown node", file: "rules/tests/plugin.kdl", line: 2)}
    newer = {"#{APP}/rules/tests" => MinimumVersion.parse("1.5", file: "rules/tests/plugin.kdl", line: 1)}

    [false, true].each do |listed|
      assert_mistake "rules/tests/plugin.kdl", 1, "plugin tests needs CrossLint 1.5 or later, and this is CrossLint 1.4.0; upgrade CrossLint",
        manifests: broken, minimums: newer, listed:
    end
  end

  def test_reads_a_manifest_that_this_crosslint_reads
    met = {"#{APP}/rules/tests" => MinimumVersion.parse("1.4", file: "rules/tests/plugin.kdl", line: 1)}

    assert_equal ["tests"], load_project(minimums: met).plugins.map(&:name)
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

  CREDENTIALS = "a plugin's URL has a user name or password, which would be in the configuration and on standard error; " \
    "remove it, and give Git the credentials with a Git credential helper (git help credentials)"

  def test_stops_at_the_url_of_a_shared_plugin_that_has_a_user_name_or_password_and_doesnt_print_it
    ["https://user:secret@example.com/o/signatures", "https://secret@example.com/o/signatures", "https://:secret@example.com/o/signatures",
      # Not shared plugins: no scheme but https is one, and CrossLint would print the name.
      "http://user:secret@example.com/o/signatures", "HTTPS://user:secret@example.com/o/signatures"].each do |url|
      shared = shared_plugins({})
      mistake = assert_raises(Mistake) { load_project(plugins: [listing(url, ref: "v1.2.0", line: 2), listing(url, ref: "v1.2.0", line: 3)], shared_plugins: shared) }

      assert_equal [CONFIG, 2, CREDENTIALS], [mistake.file, mistake.line, mistake.message]
      refute_includes mistake.message, "secret"
      assert_empty shared.fetched
    end
  end

  def test_reads_a_shared_plugin_from_the_folder_the_port_fetched
    shared = shared_plugins("v1.2.0" => "#{TOP}cache/a1/signatures")
    project = load_project(plugins: [listing(URL, ref: "v1.2.0", line: 3)], manifests: {"#{TOP}cache/a1/signatures" => tests_manifest("signatures")},
      shared_plugins: shared)

    assert_equal [["signatures", "#{TOP}cache/a1/signatures"]], project.plugins.map { |plugin| [plugin.name, plugin.folder] }
    assert_equal [[URL, "v1.2.0"]], shared.fetched
  end

  def test_reads_a_shared_plugin_from_a_folder_of_its_repository_and_names_it_for_the_folder
    shared = shared_plugins("v1.2.0" => "#{TOP}cache/a1/signatures")
    folder = "#{TOP}cache/a1/signatures/plugins/markdown-links"
    project = load_project(plugins: [listing(URL, ref: "v1.2.0", path: "plugins/markdown-links", line: 3)],
      manifests: {folder => tests_manifest("markdown-links")}, shared_plugins: shared)

    assert_equal [["markdown-links", folder]], project.plugins.map { |plugin| [plugin.name, plugin.folder] }
    assert_equal [[URL, "v1.2.0"]], shared.fetched
  end

  def test_fetches_a_commit_once_for_every_folder_of_it_that_is_listed
    shared = shared_plugins("v1.2.0" => "#{TOP}cache/a1/signatures")
    manifests = %w[one two].to_h { |name| ["#{TOP}cache/a1/signatures/plugins/#{name}", tests_manifest(name)] }
    plugins = [listing(URL, ref: "v1.2.0", path: "plugins/one"), listing(URL, ref: "v1.2.0", path: "plugins/two", line: 2)]

    assert_equal %w[one two], load_project(plugins:, manifests:, shared_plugins: shared).plugins.map(&:name)
    assert_equal [[URL, "v1.2.0"]], shared.fetched
  end

  def test_stops_at_a_path_that_names_no_folder_with_a_manifest_and_names_the_url_ref_and_path
    assert_mistake CONFIG, 1, %(no plugin.kdl in folder "plugins/none" of #{URL} at v1.2.0), shared_plugins: shared_plugins("v1.2.0" => "#{TOP}cache/a1/signatures"),
      plugins: [listing(URL, ref: "v1.2.0", path: "plugins/none")]
  end

  def test_stops_at_a_path_that_could_leave_the_repository_or_isnt_one_without_fetching
    shared = shared_plugins("v1.2.0" => "#{TOP}cache/a1/signatures")
    {"/etc" => "is absolute", "C:/x" => "is absolute", "../x" => %(has ".."), "a/../x" => %(has ".."), "a\\x" => "has a backslash", "" => "is empty",
     "a//x" => "has an empty part"}.each do |path, problem|
      mistake = assert_raises(Mistake) { load_project(plugins: [listing(URL, ref: "v1.2.0", path:, line: 2)], shared_plugins: shared) }

      assert_equal [CONFIG, 2], [mistake.file, mistake.line], path
      assert_operator mistake.message, :start_with?, %(shared plugin "#{URL}" at v1.2.0 has a path= that #{problem}), path
      assert_operator mistake.message, :end_with?, ": #{path.dump}", path
    end
    assert_empty shared.fetched
  end

  def test_stops_at_a_path_on_a_plugin_that_isnt_shared
    assert_mistake CONFIG, 1, "only a shared plugin takes path=", plugins: [listing(".config/crosslint/tests", path: "x")]
    assert_mistake CONFIG, 1, "only a shared plugin takes path=", plugins: [listing("debt", path: "x")], built_in: {"debt" => "#{TOP}c/plugins/debt"}
  end

  def test_stops_at_two_folders_of_a_repository_that_give_one_name_and_at_one_folder_listed_twice
    shared = shared_plugins("v1.2.0" => "#{TOP}cache/a1/signatures")
    manifests = %w[a/same b/same].to_h { |path| ["#{TOP}cache/a1/signatures/plugins/#{path}", tests_manifest("same")] }
    both = [listing(URL, ref: "v1.2.0", path: "plugins/a/same"), listing(URL, ref: "v1.2.0", path: "plugins/b/same", line: 2)]

    assert_mistake CONFIG, 2, %(plugins "#{URL} (plugins/a/same)" and "#{URL} (plugins/b/same)" are both named "same", since a plugin's name is its folder's name),
      plugins: both, manifests:, shared_plugins: shared
    assert_mistake CONFIG, 2, %(plugin "#{URL} (plugins/a/same)" is listed twice; the first is on line 1),
      plugins: [both.first, both.first.with(ref: "v1.2.1", line: 2)], manifests:, shared_plugins: shared
  end

  def test_stops_at_a_folder_of_a_repository_with_the_name_of_a_built_in_plugin
    built_in = {"debt" => "#{TOP}c/plugins/debt"}

    assert_mistake CONFIG, 1, %(plugin "#{URL} (plugins/debt)" is named "debt", the name of a built-in plugin, which no local or shared plugin can have; ) +
      "rename the plugin's folder, since a plugin's name is its folder's name", built_in:, steps: {"track-debt" => RecordingStep.new},
      plugins: [listing(URL, ref: "v1.2.0", path: "plugins/debt")], shared_plugins: shared_plugins("v1.2.0" => "#{TOP}cache/a1/signatures"),
      manifests: {"#{TOP}cache/a1/signatures/plugins/debt" => debt_manifest("debt")}
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
    use_case = LoadProject.new(configuration: MemoryConfiguration.new({APP => configuration}), crosslint: CROSSLINT,
      manifests: MemoryPluginManifests.new({"#{APP}/rules/tests" => debt_manifest("rules/tests")}), crosslint_ruby: MemoryCrossLintRuby.new,
      shared_plugins: shared_plugins({}), helpers: MemoryHelpers.new)

    assert_equal %(unknown step "track-debt"; this CrossLint has none), assert_raises(Mistake) { use_case.call(APP) }.message
  end

  def test_stops_at_a_policy_with_no_block_that_no_step_reports
    assert_mistake "rules/tests/plugin.kdl", 4, %(policy "other" has no applies-to, and no step of the plugin reports it),
      manifest: debt_manifest("rules/tests", step_policies: [StepPolicy.new(name: "has-debt", line: 3), StepPolicy.new(name: "other", line: 4)]),
      steps: {"track-debt" => RecordingStep.new}
  end

  def test_stops_at_a_setting_command_step_or_policy_declared_twice
    twice = ->(field, made) { debt_manifest("rules/tests").with(field => [made.call(2), made.call(3)]) }
    {"setting" => [:settings, ->(line) { SettingDeclaration.new(name: "a", line:) }],
     "command" => [:commands, ->(line) { CommandDeclaration.new(name: "a", help: "A", line:) }]}.each do |kind, (field, made)|
      assert_mistake "rules/tests/plugin.kdl", 3, %(#{kind} "a" is declared twice; the first is on line 2), manifest: twice.call(field, made),
        steps: {"track-debt" => RecordingStep.new}
    end
    assert_mistake "rules/tests/plugin.kdl", 9, %(step "track-debt" is declared twice; the first is on line 9),
      manifest: debt_manifest("rules/tests").then { |manifest| manifest.with(steps: manifest.steps * 2) }, steps: {"track-debt" => RecordingStep.new}
    assert_mistake "rules/tests/plugin.kdl", 3, %(policy "has-test" is declared twice; the first is on line 5),
      manifest: debt_manifest("rules/tests", step_policies: [StepPolicy.new(name: "has-test", line: 3)]), steps: {"track-debt" => RecordingStep.new}
  end

  def test_reads_the_commands_of_a_plugin_that_has_a_step
    manifest = debt_manifest("rules/tests").with(commands: [CommandDeclaration.new(name: "a-1", help: "A", line: 7), CommandDeclaration.new(name: "update", help: "U", line: 8)])
    project = load_project(manifest:, steps: {"track-debt" => RecordingStep.new}, reserved: %w[check init update help])

    assert_equal %w[a-1 update], project.plugins.first.manifest.commands.map(&:name)
  end

  def test_stops_at_a_command_whose_name_isnt_lowercase_letters_digits_and_dashes
    ["Update", "up date", "up_date", "update!", "", "up\ndate"].each do |name|
      commands = [CommandDeclaration.new(name: "ok", help: "A", line: 7), CommandDeclaration.new(name:, help: "A", line: 8)]
      assert_mistake "rules/tests/plugin.kdl", 8, "command #{name.dump} has other characters than lowercase letters, digits, and -",
        manifest: debt_manifest("rules/tests").with(commands:), steps: {"track-debt" => RecordingStep.new}
    end
  end

  def test_stops_at_a_command_named_help
    message = %(command "help" is the name of CrossLint's command help, which a plugin can't take; name the command something else)

    assert_mistake "rules/tests/plugin.kdl", 8, message, steps: {"track-debt" => RecordingStep.new},
      manifest: debt_manifest("rules/tests").with(commands: [CommandDeclaration.new(name: "help", help: "H", line: 8)])
  end

  def test_stops_at_a_plugin_that_adds_commands_and_is_named_for_a_command_of_crosslint
    folder = "#{APP}/rules/check"
    message = "plugin check in #{folder} adds commands, and check is reserved, as a command of CrossLint or a name CrossLint keeps for one; " \
      "rename the plugin's folder, since a plugin's name is its folder's name"

    assert_mistake "rules/check/plugin.kdl", 8, message, plugins: [listing("./rules/check")], reserved: %w[init check],
      manifests: {folder => debt_manifest("rules/check")}, steps: {"track-debt" => RecordingStep.new}
  end

  def test_stops_at_a_flag_of_a_command_named_for_a_global_flag_for_help_or_for_another_flag_of_the_command
    flag = ->(short, long, line = 9) { CommandFlag.new(short:, long:, value: nil, help: "H", line:) }
    folder = "#{APP}/rules/tests"
    stops = lambda do |flags, name, why, line = 9|
      message = "plugin tests in #{folder} gives command \"update\" the flag #{name}, which is #{why}; name the flag another way"
      command = CommandDeclaration.new(name: "update", help: "H", line: 8, flags:)

      assert_mistake "rules/tests/plugin.kdl", line, message, steps: {"track-debt" => RecordingStep.new}, reserved_flags: %w[--quiet -q],
        manifest: debt_manifest("rules/tests").with(commands: [command])
    end

    stops.call([flag.call("q", "again")], "-q", "a global flag of CrossLint")
    stops.call([flag.call(nil, "quiet")], "--quiet", "a global flag of CrossLint")
    stops.call([flag.call("h", "hush")], "-h", "the flag that prints help")
    stops.call([flag.call(nil, "help")], "--help", "the flag that prints help")
    stops.call([flag.call("n", "dry-run", 9), flag.call("n", "now", 10)], "-n", "the name of another flag of the command", 10)
    stops.call([flag.call("n", "dry-run", 9), flag.call("x", "dry-run", 10)], "--dry-run", "the name of another flag of the command", 10)
  end

  def test_reserves_help_and_takes_any_other_flag_when_given_no_global_flags
    command = ->(short, long) { CommandDeclaration.new(name: "update", help: "H", line: 8, flags: [CommandFlag.new(short:, long:, value: nil, help: "H", line: 9)]) }
    message = "plugin tests in #{APP}/rules/tests gives command \"update\" the flag -h, which is the flag that prints help; name the flag another way"

    assert_mistake "rules/tests/plugin.kdl", 9, message, steps: {"track-debt" => RecordingStep.new}, manifest: debt_manifest("rules/tests").with(commands: [command.call("h", "hush")])
    assert_equal ["q"], load_project(steps: {"track-debt" => RecordingStep.new}, manifest: debt_manifest("rules/tests").with(commands: [command.call("q", "quiet")]))
      .plugins.first.manifest.commands.first.flags.map(&:short)
  end

  def test_takes_a_flag_of_a_command_that_has_no_other_ones_name_and_the_same_name_in_another_command
    flags = [CommandFlag.new(short: "n", long: "dry-run", value: nil, help: "H", line: 9)]
    commands = %w[update other].map { |name| CommandDeclaration.new(name:, help: "H", line: 8, flags:) }
    project = load_project(steps: {"track-debt" => RecordingStep.new}, reserved_flags: %w[--quiet -q],
      manifest: debt_manifest("rules/tests").with(commands:))

    assert_equal [flags, flags], project.plugins.first.manifest.commands.map(&:flags)
  end

  def test_reserves_each_name_crosslint_keeps_for_a_command_it_may_add
    assert_equal %w[version completion config plugin plugins list cache doctor explain fix self], LoadProject::RESERVED
    LoadProject::RESERVED.each do |name|
      folder = "#{APP}/rules/#{name}"
      message = "plugin #{name} in #{folder} adds commands, and #{name} is reserved, as a command of CrossLint or a name CrossLint keeps for one; " \
        "rename the plugin's folder, since a plugin's name is its folder's name"

      assert_mistake "rules/#{name}/plugin.kdl", 8, message, plugins: [listing("./rules/#{name}")], manifests: {folder => debt_manifest("rules/#{name}")},
        steps: {"track-debt" => RecordingStep.new}
      assert_equal [name], load_project(plugins: [listing("./rules/#{name}")], manifests: {folder => debt_manifest("rules/#{name}").with(commands: [])},
        steps: {"track-debt" => RecordingStep.new}).plugins.map(&:name)
    end
  end

  def test_stops_at_a_local_or_shared_plugin_with_the_name_of_a_built_in_one
    built_in = %w[debt angular].to_h { |name| [name, "#{TOP}c/plugins/#{name}"] }
    steps = {"track-debt" => RecordingStep.new}
    %w[debt angular].each do |name|
      message = ->(listed) {
        "plugin #{listed.dump} is named #{name.dump}, the name of a built-in plugin, which no local or shared plugin can have; " \
          "rename the plugin's folder, since a plugin's name is its folder's name"
      }
      assert_mistake CONFIG, 2, message.call("./rules/#{name}"), plugins: [listing("./rules/tests"), listing("./rules/#{name}", line: 2)], built_in:, steps:,
        manifests: {"#{APP}/rules/tests" => tests_manifest, "#{APP}/rules/#{name}" => debt_manifest("rules/#{name}")}
      url = "https://example.com/o/#{name}"
      repository = MemorySharedPlugins::Repository.new(tags: {"v1.0.0" => "#{TOP}cache/c3/#{name}"}, branches: [], commits: {})
      assert_mistake CONFIG, 1, message.call(url), plugins: [listing(url, ref: "v1.0.0")], built_in:, steps:,
        shared_plugins: MemorySharedPlugins.new({url => repository}, err: StringIO.new), manifests: {"#{TOP}cache/c3/#{name}" => debt_manifest(name)}
    end
    assert_equal %w[debt tests], load_project(plugins: [listing("debt"), listing("./rules/tests", line: 2)], built_in:, steps:,
      manifests: {"#{TOP}c/plugins/debt" => debt_manifest("debt"), "#{APP}/rules/tests" => tests_manifest}).plugins.map(&:name)
  end

  def test_takes_a_plugin_named_for_a_command_of_crosslint_when_it_adds_no_commands
    manifest = debt_manifest("rules/check").with(commands: [])
    project = load_project(plugins: [listing("./rules/check")], reserved: %w[check], manifests: {"#{APP}/rules/check" => manifest},
      steps: {"track-debt" => RecordingStep.new})

    assert_equal ["check"], project.plugins.map(&:name)
  end

  def test_stops_at_commands_with_no_step_to_do_their_work
    manifest = debt_manifest("rules/tests").with(steps: [], step_policies: [])

    assert_mistake "rules/tests/plugin.kdl", 8, %(command "update" has no step to do its work, and the plugin declares none; declare one with step NAME), manifest:
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

  def test_stops_at_a_piece_declared_twice
    manifest = tests_manifest(artifacts: [artifact(pieces: [piece("test", line: 3), piece("test", line: 4)])])

    assert_mistake "rules/tests/plugin.kdl", 4, %(piece "test" is declared twice; the first is on line 3), manifest:
  end

  def test_stops_at_a_piece_named_primary_since_that_is_the_name_of_the_primary_piece
    manifest = tests_manifest(artifacts: [artifact(pieces: [piece("test", line: 3), piece("primary", line: 4)])])

    assert_mistake "rules/tests/plugin.kdl", 4,
      %(piece "primary" has the name of the artifact's primary piece, which is always called "primary"; name the piece something else), manifest:
  end

  def test_stops_at_a_piece_named_primary_that_a_plugins_ruby_or_helper_declares_naming_the_artifacts_line
    message = %(piece "primary" has the name of the artifact's primary piece, which is always called "primary"; name the piece something else)
    ruby = declaring { |_| [artifact("ruby-file", primary: "lib/{path}.rb", pieces: {"primary" => "lib/{path}.rbi"})] }
    answer = ->(_) { {"artifacts" => [{"name" => "ruby-file", "primary" => "lib/{path}.rb", "pieces" => {"primary" => "lib/{path}.rbi"}}]} }

    assert_mistake "rules/tests/plugin.kdl", 4, message, manifest: declaring_manifest, ruby: ruby
    assert_mistake "rules/tests/plugin.kdl", 4, message, manifest: helped_manifest, helpers: HelperPort.new({"tests/roles" => answer}, commands: ["node"])
  end

  def test_stops_at_a_piece_with_a_placeholder_its_files_pattern_lacks
    manifest = tests_manifest(artifacts: [artifact(pieces: [piece("test", "test/{path}/{name}_test.rb", line: 3)])])

    assert_mistake "rules/tests/plugin.kdl", 3,
      %(piece "test" uses {name}, which the primary pattern "lib/{path}.rb" doesn't have), manifest:
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
    rules = [RuleDeclaration.new(name: "piece-absent", ruby: "a.rb", line: 2)]

    assert_mistake "rules/tests/plugin.kdl", 2, %(rule "piece-absent" has the name of a built-in rule; name it something else),
      manifest: tests_manifest(rules:)
  end

  def test_applies_a_policy_to_an_artifact_of_its_own_plugin_or_another_listed_one
    other = tests_manifest(".config/other", artifacts: [artifact("source-file")], policies: [policy(applies_to: "tests/ruby-file")])
    project = load_project(plugins: [listing("./rules/tests"), listing(".config/other", line: 2)],
      manifests: {"#{APP}/rules/tests" => tests_manifest, "#{APP}/.config/other" => other})

    assert_equal ["tests", "other"], project.plugins.map(&:name)
  end

  def test_reads_a_policy_with_no_applies_to_that_some_artifact_of_its_plugin_has_the_pieces_for
    exists = Condition::PieceExists.new(piece: "test", line: 7)
    project = load_project(manifest: tests_manifest(policies: [policy(applies_to: nil, condition: exists)]))

    assert_nil project.plugins.first.manifest.policies.first.applies_to
  end

  def test_stops_at_a_policy_with_no_applies_to_that_no_artifact_of_its_plugin_has_the_pieces_for
    stub = Condition::PieceExists.new(piece: "stub", line: 7)
    assert_mistake "rules/tests/plugin.kdl", 5, %(policy "has-test" has no applies-to, and plugin tests has no artifact with "stub" and "test", the pieces it names),
      manifest: tests_manifest(policies: [policy(applies_to: nil, condition: stub)])
    assert_mistake "rules/tests/plugin.kdl", 5, %(policy "has-test" has no applies-to, and plugin tests declares no artifact),
      manifest: tests_manifest(artifacts: [], policies: [policy(applies_to: nil, rules: [policy_rule("names-class")])], rules: [RuleDeclaration.new(name: "names-class", ruby: "a.rb", line: 2)])
    assert_mistake "rules/tests/plugin.kdl", 7, %(unknown rule "piece-exist", did you mean "piece-exists"?),
      manifest: tests_manifest(policies: [policy(applies_to: nil, rules: [policy_rule("piece-exist", arguments: {})])])
  end

  def test_adds_the_artifacts_a_plugins_ruby_declares_from_its_settings
    given = []
    ruby = declaring do |settings|
      given << settings
      [artifact("ruby-file", primary: "#{settings.first.name}/{path}.rb", pieces: {"test" => "test/{path}_test.rb"}, key: "{path}", optional: true)]
    end
    manifest = declaring_manifest.with(settings: [SettingDeclaration.new(name: "lib", line: 2)])
    project = load_project(plugins: [listing("./rules/tests", settings: [setting("lib", line: 3)])], manifest:, ruby:)
    declared = project.plugins.first.manifest.artifacts

    assert_equal [[setting("lib", line: 3)]], given
    assert_equal [["ruby-file", "lib/{path}.rb", [["test", "test/{path}_test.rb", 4]], "{path}", true, 4]],
      declared.map { |each| [each.name, each.primary.source, each.pieces.map { [it.name, it.pattern.source, it.line] }, each.key.source, each.optional, each.line] }
  end

  def test_adds_the_artifacts_a_plugins_ruby_declares_to_those_its_manifest_declares
    manifest = declaring_manifest.with(artifacts: [artifact("source-file")])
    project = load_project(manifest:, ruby: declaring { |_| [artifact("ruby-file", primary: "lib/{path}.rb")] })

    assert_equal ["source-file", "ruby-file"], project.plugins.first.manifest.artifacts.map(&:name)
  end

  def test_names_a_file_of_its_plugin_that_a_plugins_ruby_requires_and_lacks
    missing = LoadError.new("cannot load such file")
    missing.define_singleton_method(:path) { "#{APP}/rules/tests/helpers/roles.rb" }

    assert_mistake "rules/tests/plugin.kdl", 4, "fault in plugin tests: artifacts.rb requires helpers/roles.rb, which doesn't exist",
      manifest: declaring_manifest, ruby: {"#{APP}/rules/tests/artifacts.rb" => ->(_) { raise missing }}
  end

  def test_checks_a_policy_against_the_artifacts_a_plugins_ruby_declares
    ruby = declaring { |_| [artifact("ruby-file", primary: "lib/{path}.rb")] }

    assert_mistake "rules/tests/plugin.kdl", 7, %(unknown piece "test"; artifact "ruby-file" declares none),
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

  def test_adds_the_artifacts_a_plugins_helper_declares_from_its_settings_and_stops_the_helper
    given = []
    answer = lambda do |input|
      given << input
      {"artifacts" => [{"name" => "ruby-file", "primary" => "lib/{path}.rb", "pieces" => {"test" => "test/{path}_test.rb"}, "key" => "{path}",
                        "optional" => true, "dotfiles" => false}, {"name" => "plain", "primary" => "{path}.md"}]}
    end
    port = HelperPort.new({"tests/roles" => answer}, commands: ["node"])
    manifest = helped_manifest.with(settings: [SettingDeclaration.new(name: "lib", line: 2)])
    settings = [Setting.new(name: "lib", arguments: ["lib"], properties: {"x" => 1}, children: [setting("y", line: 4)], line: 3)]
    project = load_project(plugins: [listing("./rules/tests", settings:)], manifest:, helpers: port)
    declared = project.plugins.first.manifest.artifacts

    assert_equal [{"settings" => [{"name" => "lib", "arguments" => ["lib"], "properties" => {"x" => 1}, "line" => 3,
                                   "children" => [{"name" => "y", "arguments" => [], "properties" => {}, "children" => [], "line" => 4}]}]}], given
    assert_equal [["ruby-file", "lib/{path}.rb", [["test", "test/{path}_test.rb", 4]], "{path}", true, false, 4], ["plain", "{path}.md", [], nil, false, true, 4]],
      declared.map { |each| [each.name, each.primary.source, each.pieces.map { [it.name, it.pattern.source, it.line] }, each.key&.source, each.optional, each.dotfiles, each.line] }
    assert_equal [[APP, true]], port.started.map { |running| [running.root, running.stopped] }
  end

  def test_says_under_debug_what_the_helper_that_declares_a_plugins_artifacts_gets_and_answers
    debug = CrossLint::Adapters::MemoryDebugOutput.new
    port = HelperPort.new({"tests/roles" => ->(_) { {"artifacts" => []} }}, commands: ["node"])
    load_project(manifest: helped_manifest, helpers: port, debug:)

    assert_equal [%(tests/roles gets {"settings":[]}), %(tests/roles answers {"artifacts":[]})], debug.written("helper")
  end

  def test_says_under_debug_the_projects_root_and_where_each_plugin_is_from
    debug = CrossLint::Adapters::MemoryDebugOutput.new
    load_project(plugins: [listing("./rules/tests"), listing("debt"), listing(URL, ref: "v1.2.0", line: 3)], built_in: {"debt" => "#{TOP}c/plugins/debt"},
      manifests: {"#{APP}/rules/tests" => tests_manifest, "#{TOP}c/plugins/debt" => debt_manifest, "#{TOP}cache/a1/signatures" => tests_manifest("signatures")},
      steps: {"track-debt" => RecordingStep.new}, shared_plugins: shared_plugins("v1.2.0" => "#{TOP}cache/a1/signatures"), debug:)

    assert_equal ["#{APP}, with #{CONFIG}"], debug.written("project")
    assert_equal ["tests, a local plugin, in #{APP}/rules/tests", "debt, a built-in plugin, in #{TOP}c/plugins/debt",
      "signatures, a shared plugin from #{URL} at v1.2.0, in #{TOP}cache/a1/signatures"], debug.written("plugin")
  end

  def test_says_under_debug_the_folder_of_a_shared_plugins_repository_it_is_from
    debug = CrossLint::Adapters::MemoryDebugOutput.new
    folder = "#{TOP}cache/a1/signatures/plugins/markdown-links"
    load_project(plugins: [listing(URL, ref: "v1.2.0", path: "plugins/markdown-links")], manifests: {folder => tests_manifest("markdown-links")},
      shared_plugins: shared_plugins("v1.2.0" => "#{TOP}cache/a1/signatures"), debug:)

    assert_equal ["markdown-links, a shared plugin from #{URL} at v1.2.0 (plugins/markdown-links), in #{folder}"], debug.written("plugin")
  end

  def test_lets_a_policy_with_no_applies_to_apply_to_nothing_when_a_plugins_helper_declares_its_artifacts
    port = HelperPort.new({"tests/roles" => ->(_) { {"artifacts" => []} }}, commands: ["node"])
    project = load_project(manifest: helped_manifest, helpers: port)

    assert_empty project.plugins.first.manifest.artifacts
  end

  def test_stops_at_the_mistake_a_plugins_helper_makes_of_a_setting
    answer = ->(_) { {"mistake" => {"message" => "lib takes a folder", "line" => 3}} }
    manifest = helped_manifest.with(settings: [SettingDeclaration.new(name: "lib", line: 2)])

    assert_mistake CONFIG, 3, "lib takes a folder", plugins: [listing("./rules/tests", settings: [setting("lib", line: 3)])], manifest:,
      helpers: HelperPort.new({"tests/roles" => answer}, commands: ["node"])
  end

  def test_stops_at_what_a_plugins_helper_answers_that_declares_no_artifacts_naming_the_plugin_and_the_artifacts_line
    {
      ->(_) { {"error" => "broken"} } => %(fault in plugin tests: helper "roles" failed: broken),
      ->(_) { raise PluginError, "called helper roles, which exited with status 1 before it answered" } =>
        "fault in plugin tests: called helper roles, which exited with status 1 before it answered",
      ->(_) { [] } => %(fault in plugin tests: helper "roles" answered neither {"artifacts": [...]} nor {"mistake": {"message": TEXT, "line": LINE}}),
      ->(_) { {"artifacts" => {}} } => %(fault in plugin tests: helper "roles" answered neither {"artifacts": [...]} nor {"mistake": {"message": TEXT, "line": LINE}}),
      ->(_) { {"mistake" => {"message" => 3, "line" => 3}} } =>
        %(fault in plugin tests: helper "roles" answered neither {"artifacts": [...]} nor {"mistake": {"message": TEXT, "line": LINE}}),
      ->(_) { {"mistake" => {"message" => "m", "line" => "3"}} } =>
        %(fault in plugin tests: helper "roles" answered neither {"artifacts": [...]} nor {"mistake": {"message": TEXT, "line": LINE}}),
      ->(_) { {"mistake" => "m"} } => %(fault in plugin tests: helper "roles" answered neither {"artifacts": [...]} nor {"mistake": {"message": TEXT, "line": LINE}}),
      ->(_) { {"artifacts" => [3]} } => %(fault in plugin tests: helper "roles" declared an artifact that isn't {"name": NAME, "primary": PATTERN, ...}),
      ->(_) { {"artifacts" => [{"name" => "a", "primary" => "{x}.rb"}]} } =>
        %(fault in plugin tests: helper "roles" declared artifact "a" with a path pattern "{x}.rb" has unknown placeholder "{x}"; expected "{path}" or "{name}"),
      ->(_) { {"artifacts" => [{"name" => "a", "primary" => "a.rb", "colour" => "x"}]} } =>
        %(fault in plugin tests: helper "roles" declared an artifact that isn't {"name": NAME, "primary": PATTERN, ...})
    }.each do |answer, message|
      assert_mistake "rules/tests/plugin.kdl", 4, message, manifest: helped_manifest, helpers: HelperPort.new({"tests/roles" => answer}, commands: ["node"])
    end
  end

  def test_stops_at_a_helper_the_manifest_doesnt_declare_that_its_artifacts_or_a_rule_names
    assert_mistake "rules/tests/plugin.kdl", 4, %(artifacts are declared by helper "roles", which plugin tests doesn't declare),
      manifest: helped_manifest.with(helpers: [])
    rules = [RuleDeclaration.new(name: "names-class", helper: "reader", line: 2)]

    assert_mistake "rules/tests/plugin.kdl", 2, %(rule "names-class" is run by helper "reader", which plugin tests doesn't declare),
      manifest: tests_manifest(policies: [policy(rules: [policy_rule("names-class")])], rules:)
  end

  def test_finds_artifacts_in_the_plugins_namespace_alone_and_lets_them_set_up_in_initialize
    ruby = declaring(<<~RUBY)
      def initialize
        @folder = "lib"
      end

      def declare(_) = [artifact("ruby-file", primary: @folder + "/{path}.rb", pieces: {"test" => "t/{path}"})]
    RUBY
    # A built-in plugin's Artifacts, which test/crosslint_ruby.rb loaded at the top level, is put back.
    loaded = Object.__send__(:remove_const, :Artifacts) if Object.const_defined?(:Artifacts, false)
    Object.const_set(:Artifacts, Class.new(CrossLint::Artifacts))
    project = load_project(manifest: declaring_manifest, ruby:)

    assert_equal ["lib/{path}.rb"], project.plugins.first.manifest.artifacts.map { it.primary.source }
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

  def test_stops_at_a_condition_on_a_piece_the_artifact_lacks
    condition = Condition::All.new(conditions: [Condition::PieceExists.new(piece: "test", line: 7),
      Condition::Not.new(condition: Condition::Any.new(conditions: [Condition::PieceExists.new(piece: "stub", line: 9)], line: 8),
        line: 8)], line: 7)
    project = load_project(manifests: {"#{APP}/rules/tests" => tests_manifest(policies: [policy(condition: Condition::PieceExists.new(piece: "test", line: 7))])})

    assert_equal "test", project.plugins.first.manifest.policies.first.condition.piece
    assert_mistake "rules/tests/plugin.kdl", 9, %(unknown piece "stub"; expected "test"),
      manifest: tests_manifest(policies: [policy(condition:)])
  end

  def test_runs_a_built_in_rule_with_a_piece_of_the_artifact
    project = load_project(manifests: {"#{APP}/rules/tests" => tests_manifest(policies: [policy(rules: [policy_rule("piece-absent")])])})

    assert_equal ["piece-absent"], project.plugins.first.manifest.policies.first.rules.map(&:name)
  end

  def test_stops_at_a_rule_that_is_neither_built_in_nor_declared
    assert_mistake "rules/tests/plugin.kdl", 7, %(unknown rule "piece-exist", did you mean "piece-exists"?),
      manifest: tests_manifest(policies: [policy(rules: [policy_rule("piece-exist")])])
    assert_mistake "rules/tests/plugin.kdl", 7, %(unknown rule "zzz"; expected "piece-exists", "piece-absent", or "names-class"),
      manifest: tests_manifest(rules: [RuleDeclaration.new(name: "names-class", ruby: "a.rb", line: 2)],
        policies: [policy(rules: [policy_rule("zzz"), policy_rule("names-class")])])
  end

  def test_stops_at_a_built_in_rule_with_the_wrong_arguments
    assert_mistake "rules/tests/plugin.kdl", 7, %(rule "piece-exists" needs piece=NAME),
      manifest: tests_manifest(policies: [policy(rules: [policy_rule(arguments: {})])])
    assert_mistake "rules/tests/plugin.kdl", 7, %(unknown argument "peice", did you mean "piece"? for rule "piece-exists"),
      manifest: tests_manifest(policies: [policy(rules: [policy_rule(arguments: {"peice" => "test"})])])
    assert_mistake "rules/tests/plugin.kdl", 7, "piece= takes the name of a piece, as a string",
      manifest: tests_manifest(policies: [policy(rules: [policy_rule(arguments: {"piece" => 3})])])
  end

  def test_stops_at_a_built_in_rule_on_a_piece_the_artifact_lacks
    assert_mistake "rules/tests/plugin.kdl", 7, %(unknown piece "tset", did you mean "test"?),
      manifest: tests_manifest(policies: [policy(rules: [policy_rule(arguments: {"piece" => "tset"})])])
    assert_mistake "rules/tests/plugin.kdl", 7, %(unknown piece "test"; artifact "ruby-file" declares none),
      manifest: tests_manifest(artifacts: [artifact(pieces: [])])
  end

  def test_runs_a_ruby_rule_its_plugin_declares_with_no_arguments
    rules = [RuleDeclaration.new(name: "names-class", ruby: "rules/names_class.rb", line: 2)]
    manifest = tests_manifest(rules:, policies: [policy(rules: [policy_rule("names-class")])])

    assert_empty load_project(manifests: {"#{APP}/rules/tests" => manifest}).unused_rules
    assert_mistake "rules/tests/plugin.kdl", 7, %(rule "names-class" is run by a helper, and takes no style=),
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

    assert_mistake "rules/tests/plugin.kdl", 7, %(unknown rule "names-class"; expected "piece-exists" or "piece-absent"),
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
    condition = Condition::All.new(conditions: [Condition::PieceExists.new(piece: "test", line: 7),
      Condition::PieceExists.new(piece: "sig", line: 7)], line: 7)
    ruby_file = artifact(pieces: [piece("test"), piece("sig", "sig/{path}.rbs")])
    policies = [policy(condition:, rules: [policy_rule, policy_rule("piece-absent", arguments: {"piece" => "sig"}), policy_rule("one")]),
      Policy.new(name: "two", applies_to: AppliesTo.new(artifact: "source-file", line: 11), condition: nil, rules: [policy_rule("two")], line: 10)]
    manifest = tests_manifest(artifacts: [ruby_file, artifact("source-file")], policies:, rules:, helpers:)
    project = load_project(manifest:, policies: [policy_setting("tests/has-test"), policy_setting("tests/two", line: 4)])

    assert_equal [%w[ruby-file source-file], %w[has-test two]],
      [project.plugins.first.manifest.artifacts.map(&:name), project.plugins.first.manifest.policies.map(&:name)]
  end

  def test_stops_at_the_later_of_two_mistakes_in_a_list
    assert_mistake "rules/tests/plugin.kdl", 4, %(piece "stub" uses {name}, which the primary pattern "lib/{path}.rb" doesn't have),
      manifest: tests_manifest(artifacts: [artifact(pieces: [piece("test"), piece("stub", "{name}.rb", line: 4)])])
    assert_mistake "rules/tests/plugin.kdl", 3, %(rule "piece-exists" has the name of a built-in rule; name it something else),
      manifest: tests_manifest(rules: [RuleDeclaration.new(name: "one", ruby: "a.rb", line: 2), RuleDeclaration.new(name: "piece-exists", ruby: "b.rb", line: 3)],
        policies: [policy(rules: [policy_rule("one")])])
    assert_mistake "rules/tests/plugin.kdl", 7, %(unknown rule "zzz"; expected "piece-exists" or "piece-absent"),
      manifest: tests_manifest(policies: [policy(rules: [policy_rule, policy_rule("zzz")])])
    assert_mistake "rules/tests/plugin.kdl", 6, %(unknown artifact "zzz"; expected "ruby-file"),
      manifest: tests_manifest(policies: [policy, policy(applies_to: "zzz").with(name: "other")])
    assert_mistake "rules/tests/plugin.kdl", 8, %(unknown piece "zzz"; expected "test"),
      manifest: tests_manifest(policies: [policy(condition: Condition::Any.new(conditions: [Condition::PieceExists.new(piece: "test", line: 7),
        Condition::PieceExists.new(piece: "zzz", line: 8)], line: 7))])
  end

  def test_lists_the_plugins_on_disk_without_checking_them_against_each_other_or_running_their_ruby
    broken = tests_manifest("rules/two", policies: [policy.with(applies_to: AppliesTo.new(artifact: "nope", line: 6))])
      .with(artifacts_ruby: ArtifactsRuby.new(ruby: "missing.rb", line: 9))
    manifests = {"#{APP}/rules/tests" => tests_manifest, "#{APP}/rules/two" => broken}
    plugins = [listing("./rules/tests"), listing("./rules/two", line: 2)]
    listing = load_project(plugins:, manifests:, listed: true)

    assert_equal [CONFIG, ["tests", "two"], []], [listing.file, listing.plugins.map(&:name), listing.unfetched]
    assert_kind_of PluginListing, listing
    assert_raises(Mistake) { load_project(plugins:, manifests:) }
  end

  def test_lists_no_command_that_a_run_would_refuse
    steps = {"track-debt" => RecordingStep.new}
    folder = "#{APP}/rules/fix"
    mistake = assert_raises(Mistake) { load_project(plugins: [listing("./rules/fix")], manifests: {folder => debt_manifest("rules/fix")}, steps:, listed: true) }

    assert_equal ["rules/fix/plugin.kdl", 8], [mistake.file, mistake.line]
    assert_includes mistake.message, "plugin fix in #{folder} adds commands, and fix is reserved"
    twice = debt_manifest("rules/tests").with(commands: [CommandDeclaration.new(name: "go", help: "A", line: 7), CommandDeclaration.new(name: "go", help: "B", line: 8)])

    duplicate = assert_raises(Mistake) { load_project(manifest: twice, steps:, listed: true) }

    assert_equal ["rules/tests/plugin.kdl", %(command "go" is declared twice; the first is on line 7)], [duplicate.file, duplicate.message]
    named = debt_manifest("rules/tests").with(commands: [CommandDeclaration.new(name: "Go", help: "A", line: 7)])

    assert_equal "command \"Go\" has other characters than lowercase letters, digits, and -", assert_raises(Mistake) { load_project(manifest: named, steps:, listed: true) }.message
  end

  def test_lists_a_project_that_lists_no_plugin
    listing = load_project(plugins: [], listed: true)

    assert_equal [[], []], [listing.plugins, listing.unfetched]
  end

  def test_lists_a_shared_plugin_only_once_it_is_in_the_cache_and_fetches_nothing
    shared = shared_plugins("v1.2.0" => "#{TOP}cache/a1/signatures")
    manifests = {"#{TOP}cache/a1/signatures" => tests_manifest("signatures"), "#{APP}/rules/tests" => tests_manifest}
    plugins = [listing(URL, ref: "v1.2.0", line: 3), listing("./rules/tests", line: 4)]
    before = load_project(plugins:, manifests:, shared_plugins: shared, listed: true)

    assert_equal [["tests"], [plugins.first]], [before.plugins.map(&:name), before.unfetched]
    assert_empty shared.fetched
    shared.fetch(URL, "v1.2.0")
    after = load_project(plugins:, manifests:, shared_plugins: shared, listed: true)

    assert_equal [["signatures", "tests"], []], [after.plugins.map(&:name), after.unfetched]
    assert_equal [[URL, "v1.2.0"]], shared.fetched
  end

  def test_lists_with_the_mistakes_a_listing_can_have_and_no_other
    assert_raises(Mistake) { load_project(plugins: [listing(URL)], listed: true) }.then do |mistake|
      assert_equal %(shared plugin "#{URL}" needs ref=, a tag or a full commit SHA), mistake.message
    end
    assert_raises(Mistake) { load_project(plugins: [listing(".x")], start: "/elsewhere/lib", listed: true) }.then do |mistake|
      assert_match(/\Ano \.config\/crosslint\/config\.kdl in \/elsewhere\/lib/, mistake.message)
    end
    mistake = assert_raises(Mistake) { load_project(plugins: [listing("./rules/missing")], listed: true) }

    assert_equal [CONFIG, 1, "no plugin.kdl in rules/missing"], [mistake.file, mistake.line, mistake.message]
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
    use_case = LoadProject.new(configuration: MemoryConfiguration.new({APP => configuration}), crosslint: CROSSLINT, manifests: MemoryPluginManifests.new,
      crosslint_ruby: MemoryCrossLintRuby.new, shared_plugins: shared_plugins({}), helpers: MemoryHelpers.new)
    mistake = assert_raises(Mistake) { use_case.call(APP) }

    assert_equal %(unknown built-in plugin "debt"; this CrossLint has none), mistake.message
  end

  def test_applies_a_policy_to_the_whole_name_after_the_plugin
    assert_mistake "rules/tests/plugin.kdl", 6, %(unknown artifact "ruby/file", did you mean "ruby-file"?),
      manifest: tests_manifest(policies: [policy(applies_to: "tests/ruby/file")])
  end

  def test_takes_any_string_as_a_piece_name
    name = Class.new(String).new("test")

    assert_equal 1, load_project(manifest: tests_manifest(policies: [policy(rules: [policy_rule(arguments: {"piece" => name})])])).plugins.size
  end

  def test_raises_the_mistakes_the_ports_raise
    configuration = MemoryConfiguration.new({APP => Mistake.new("broken", file: CONFIG, line: 2)})
    mistake = assert_raises(Mistake) do
      LoadProject.new(configuration:, crosslint: CROSSLINT, manifests: MemoryPluginManifests.new, crosslint_ruby: MemoryCrossLintRuby.new, shared_plugins: shared_plugins({}), helpers: MemoryHelpers.new).call(APP)
    end

    assert_equal "#{CONFIG}:2", mistake.location
  end

  private

  MemoryConfiguration = CrossLint::Adapters::MemoryConfiguration
  MemoryPluginManifests = CrossLint::Adapters::MemoryPluginManifests
  MemoryCrossLintRuby = CrossLint::Adapters::MemoryCrossLintRuby
  MemorySharedPlugins = CrossLint::Adapters::MemorySharedPlugins
  MemoryHelpers = CrossLint::Adapters::MemoryHelpers

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
    shared_plugins: shared_plugins({}), reserved: nil, reserved_flags: nil, listed: false, helpers: MemoryHelpers.new, configuration: nil,
    minimums: {}, debug: nil)
    manifests ||= {"#{APP}/rules/tests" => manifest || tests_manifest}
    configuration ||= MemoryConfiguration.new({APP => Configuration.new(file: CONFIG, plugins:, policies:, warnings: nil, verbosity: nil)})
    use_case = LoadProject.new(configuration:, crosslint: CROSSLINT,
      manifests: MemoryPluginManifests.new(manifests, minimums:), crosslint_ruby: MemoryCrossLintRuby.new(ruby), shared_plugins:, built_in:, steps:,
      helpers:, debug:, **{reserved:, reserved_flags:}.compact)
    listed ? use_case.listed(start) : use_case.call(start)
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

  # A plugin whose helper "roles" declares its artifacts.
  def helped_manifest = tests_manifest(artifacts: [], policies: [policy(applies_to: nil)],
    helpers: [HelperDeclaration.new(name: "roles", command: "node", file: "roles.mjs", line: 3)]).with(artifacts_helper: ArtifactsHelper.new(helper: "roles", line: 4))

  # The in-memory helpers port, which keeps each set of helpers it starts.
  class HelperPort < MemoryHelpers
    def started = @started ||= []

    def start(root, plugins) = super.tap { |running| started << running }
  end

  def declaring_manifest(policies: [policy(applies_to: nil)]) = tests_manifest(artifacts: [], policies:).with(artifacts_ruby: ArtifactsRuby.new(ruby: "artifacts.rb", line: 4))

  def assert_mistake(file, line, message, **options)
    mistake = assert_raises(Mistake) { load_project(**options) }

    assert_equal [file, line, message], [mistake.file, mistake.line, mistake.message]
  end

  def listing(name, ref: nil, settings: [], line: 1, path: nil) = ListedPlugin.new(name:, ref:, path:, settings:, line:)

  def setting(name, line:) = Setting.new(name:, arguments: [], properties: {}, children: [], line:)

  def policy_setting(name, line: 3) = PolicySetting.new(name:, enabled: false, severity: nil, line:)

  def tests_manifest(folder = "rules/tests", artifacts: [artifact], policies: [policy], rules: [], helpers: [])
    Manifest.new(file: folder.empty? ? "plugin.kdl" : "#{folder}/plugin.kdl", artifacts:, policies:, rules:, helpers:)
  end

  def debt_manifest(folder = "debt", step: "track-debt", step_policies: [StepPolicy.new(name: "has-debt", line: 3)])
    tests_manifest(folder).with(step_policies:, settings: [SettingDeclaration.new(name: "file", line: 4)],
      commands: [CommandDeclaration.new(name: "update", help: "Rewrite the debt file to list the current violations", line: 8)], steps: [StepDeclaration.new(name: step, line: 9)])
  end

  def artifact(name = "ruby-file", pieces: [piece("test", line: 3)], line: 1)
    ArtifactDeclaration.new(name:, primary: PathPattern.new(source: "lib/{path}.rb"), pieces:, line:)
  end

  def piece(name, pattern = "test/{path}_test.rb", line: 3)
    PieceDeclaration.new(name:, pattern: PathPattern.new(source: pattern), line:)
  end

  def policy(applies_to: "ruby-file", condition: nil, rules: [policy_rule], line: 5)
    Policy.new(name: "has-test", applies_to: applies_to && AppliesTo.new(artifact: applies_to, line: 6), condition:, rules:, line:)
  end

  def policy_rule(name = "piece-exists", arguments: BuiltInRule.named(name) ? {"piece" => "test"} : {})
    PolicyRule.new(name:, arguments:, severity: nil, line: 7)
  end
end
