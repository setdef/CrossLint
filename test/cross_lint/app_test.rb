# frozen_string_literal: true

require "test_helper"
require "digest"
require "open3"

class AppTest < Minitest::Test
  cover "CrossLint::App*"

  App = CrossLint::App
  Core = CrossLint::Core
  Mistake = CrossLint::Core::Mistake

  MANIFEST = %(artifact "a" {\n  files "{path}.md"\n  companion "c" "{path}.txt"\n}\n) +
    %(policy "p" {\n  applies-to "a"\n  rule "companion-exists" companion="c"\n}\n)

  def setup
    @base = Dir.mktmpdir("crosslint")
  end

  def teardown
    FileUtils.rm_rf(@base)
  end

  def test_reads_crosslints_own_configuration_and_plugins
    project = App.new(plugin_ruby: LoadedPlugins::PluginRuby.new).load_project(File.join(ROOT, "lib", "cross_lint"))

    assert_equal [ROOT, [["signatures", File.join(ROOT, ".config/crosslint/signatures")], ["markdown-links", File.join(ROOT, "plugins/markdown-links")], ["decision-log", File.join(ROOT, "plugins/decision-log")]]],
      [project.root, project.plugins.map { |plugin| [plugin.name, plugin.folder] }]
    assert_equal [["ruby-file"], ["markdown-file"], %w[index document]], project.plugins.map { it.manifest.artifacts.map(&:name) }
  end

  def test_a_dry_run_of_a_plugins_command_lists_the_changes_and_writes_nothing
    write(@base, ".config/crosslint/config.kdl", %(plugin "debt"\nplugin ".config/crosslint/tests"\n))
    write(@base, ".config/crosslint/tests/plugin.kdl", MANIFEST.sub("{path}.md", "lib/{path}.md"))
    write(@base, "lib/a.md", "")
    Open3.capture3("git", "init", "-q", chdir: @base)
    dry = App.new.check(@base, command: ["debt", "update"], flags: {"dry-run" => true})

    assert_equal ["would add tests/p on lib/a.md", "would write .config/crosslint/debt.tsv: 1 entry added, 0 removed"], dry.wrote
    refute_path_exists File.join(@base, ".config/crosslint/debt.tsv")
  end

  def test_names_each_way_the_global_flags_are_written_and_refuses_a_plugin_command_flag_written_as_one
    assert_equal %w[--quiet -q --silent -s --no-color --debug --project -C --help -h --version -V], App.global_flag_names(CrossLint::UsageSpec.load)
    write(@base, "plugins/tool/plugin.kdl", %(step "track-debt"\npolicy "has-debt"\ncommand "go" help="Goes" {\n  flag "-q --quick" help="Quick"\n}\n))
    write(@base, "app/.config/crosslint/config.kdl", %(plugin "tool"\n))
    plugins = File.join(@base, "plugins")
    built_in = ["tool"]
    message = /\Aplugin tool in .* gives command "go" the flag -q, which is a global flag of CrossLint; name the flag another way\z/

    assert_match message, assert_raises(Mistake) { App.new(plugins:, built_in:).load_project(File.join(@base, "app")) }.message
    assert_equal ["tool"], App.new(plugins:, built_in:, reserved_flags: ["-Q"]).load_project(File.join(@base, "app")).plugins.map(&:name)
  end

  def test_finds_the_built_in_plugins_in_crosslints_plugins_folder
    assert_equal File.join(ROOT, "plugins"), App::PLUGINS
    write(@base, "app/.config/crosslint/config.kdl", %(plugin "debt" {\n  file "debt.tsv"\n}\n))
    project = App.new.load_project(File.join(@base, "app"))

    assert_equal [["debt", File.join(ROOT, "plugins", "debt"), ["track-debt"]]],
      project.plugins.map { |plugin| [plugin.name, plugin.folder, plugin.manifest.steps.map(&:name)] }
  end

  # ng-nudge counted its debt file as an artifact (lib/console-output.js:16).
  def test_tracks_debt_with_the_built_in_debt_plugin
    write(@base, ".config/crosslint/config.kdl", %(plugin "debt" {\n  report-entries commented="none"\n}\nplugin ".config/crosslint/tests"\n))
    write(@base, ".config/crosslint/tests/plugin.kdl", MANIFEST.sub("{path}.md", "lib/{path}.md"))
    write(@base, "lib/a.md", "")
    write(@base, "lib/b.md", "")
    Open3.capture3("git", "init", "-q", chdir: @base)
    before = App.new.check(@base)
    updated = App.new.check(@base, command: ["debt", "update"])
    debt = File.binread(File.join(@base, ".config/crosslint/debt.tsv"))

    assert_equal [true, 2, false], [before.failed, before.violations.size, updated.failed]
    assert_equal ["wrote .config/crosslint/debt.tsv: 2 entries added, 0 removed"], updated.wrote
    assert_equal "Rule\tArtifact\tComment\ntests/p\tlib/a.md\t\ntests/p\tlib/b.md\t\n", debt
    File.binwrite(File.join(@base, ".config/crosslint/debt.tsv"), debt.sub("lib/a.md\t", "lib/a.md\tlater"))
    write(@base, "b.txt", "")
    after = App.new.check(@base)

    assert_equal [["lib/b.md", Core::Stale], [".config/crosslint/debt.tsv", Core::Violation]].sort,
      after.findings.map { |finding| [finding.artifact, finding.class] }.sort
    assert_equal ["checked 2 a artifacts: 1 error, 1 stale entry, 1 accepted as debt", true], [after.summary.line, after.failed]
  end

  def test_checks_a_project_it_has_loaded_as_a_plugins_command_when_it_is_told_to
    write(@base, ".config/crosslint/config.kdl", %(plugin "debt"\nplugin ".config/crosslint/tests"\n))
    write(@base, ".config/crosslint/tests/plugin.kdl", MANIFEST.sub("{path}.md", "lib/{path}.md"))
    write(@base, "lib/a.md", "")
    Open3.capture3("git", "init", "-q", chdir: @base)
    app = App.new
    project = app.load_project(@base)

    assert_equal [true, true], [app.check_project(project).failed, app.check(@base).failed]
    assert_equal [false, ["wrote .config/crosslint/debt.tsv: 1 entry added, 0 removed"]],
      app.check_project(project, command: ["debt", "update"]).then { |result| [result.failed, result.wrote] }
    refute app.check(@base).failed
  end

  def test_lists_what_a_project_has_on_disk_without_fetching_a_shared_plugin
    url = "https://example.test/OWNER/signatures"
    write(@base, ".config/crosslint/config.kdl", %(plugin "debt"\nplugin #{url.dump} ref="v1.0.0"\n))
    err = StringIO.new
    shared_plugins = CrossLint::Adapters::GitSharedPlugins.new(err:, cache: File.join(@base, "cache"))
    listing = App.new(err:, shared_plugins:).listing(@base)

    assert_equal [".config/crosslint/config.kdl", ["debt"], [url]], [listing.file, listing.plugins.map(&:name), listing.unfetched.map(&:name)]
    assert_empty err.string
  end

  def test_names_the_commands_of_each_built_in_plugin_whether_or_not_a_project_lists_it
    write(@base, "plugins/debt/plugin.kdl", %(step "track-debt"\npolicy "has-debt"\ncommand "update" help="Updates"\ncommand "prune" help="Prunes"\n))
    write(@base, "plugins/other/plugin.kdl", MANIFEST)

    assert_equal({"debt" => %w[update prune], "other" => []}, App.new(plugins: File.join(@base, "plugins"), built_in: %w[debt other]).built_in_commands)
    assert_equal({"debt" => ["update"], "angular" => []}, App.new.built_in_commands.slice("debt", "angular"))
  end

  def test_refuses_a_plugin_that_adds_commands_and_is_named_for_a_command_of_the_usage_spec_it_is_given_or_the_shipped_one
    write(@base, "plugins/check/plugin.kdl", %(step "track-debt"\npolicy "has-debt"\ncommand "update" help="Updates"\n))
    write(@base, "plugins/tool/plugin.kdl", %(step "track-debt"\npolicy "has-debt"\ncommand "update" help="Updates"\n))
    write(@base, "app/.config/crosslint/config.kdl", %(plugin "check"\n))
    plugins = File.join(@base, "plugins")
    built_in = %w[check tool]

    assert_match(/\Aplugin check in .* adds commands, and check is reserved/, assert_raises(Mistake) { App.new(plugins:, built_in:).load_project(File.join(@base, "app")) }.message)
    assert_equal ["check"], App.new(plugins:, built_in:, reserved: ["other"]).load_project(File.join(@base, "app")).plugins.map(&:name)
    write(@base, "app/.config/crosslint/config.kdl", %(plugin "tool"\n))

    assert_equal ["tool"], App.new(plugins:, built_in:).load_project(File.join(@base, "app")).plugins.map(&:name)
    assert_match(/\Aplugin tool in .* adds commands, and tool is reserved/, assert_raises(Mistake) { App.new(plugins:, built_in:, reserved: ["tool"]).load_project(File.join(@base, "app")) }.message)
  end

  # The other folders of CrossLint's plugins folder are shared plugins.
  def test_takes_each_folder_with_a_manifest_that_it_names_as_a_built_in_plugin
    write(@base, "plugins/debt/plugin.kdl", MANIFEST)
    FileUtils.mkdir_p(File.join(@base, "plugins/other"))
    write(@base, "plugins/shared/plugin.kdl", MANIFEST)
    write(@base, "app/.config/crosslint/config.kdl", %(plugin "debt"\n))
    app = App.new(plugins: File.join(@base, "plugins"), built_in: %w[debt other])

    assert_equal [["debt", File.join(@base, "plugins/debt")]], app.load_project(File.join(@base, "app")).plugins.map { |plugin| [plugin.name, plugin.folder] }
    write(@base, "app/.config/crosslint/config.kdl", %(plugin "other"\n))
    mistake = assert_raises(Mistake) { app.load_project(File.join(@base, "app")) }

    assert_equal %(unknown built-in plugin "other"; expected "debt"), mistake.message
    write(@base, "app/.config/crosslint/config.kdl", %(plugin "shared"\n))
    mistake = assert_raises(Mistake) { app.load_project(File.join(@base, "app")) }

    assert_equal %(unknown built-in plugin "shared"; expected "debt"), mistake.message
    assert_equal %w[angular debt], App::BUILT_IN
  end

  def test_checks_crosslint_itself_with_git
    result = App.new(plugin_ruby: LoadedPlugins::PluginRuby.new).check(ROOT)
    markdown, = Open3.capture3("git", "-C", ROOT, "ls-files", "-z", "--cached", "--others", "--exclude-standard", "*.md")

    documents = markdown.split("\0").uniq.size

    assert_equal [false, [["ruby-file", Dir.glob("lib/**/*.rb", base: ROOT).size], ["markdown-file", documents], ["index", 1], ["document", documents]]],
      [result.failed, result.summary.kinds]
  end

  def test_checks_through_the_ports_it_is_given_with_the_options_given
    result = memory_app.check("/app", warnings: :error, verbosity: :quiet, all: true)

    assert_equal [:quiet, true, ["a.md"]], [result.verbosity, result.failed, result.violations.map(&:artifact)]
    assert_equal [:normal, false], memory_app.check("/app").then { |normal| [normal.verbosity, normal.failed] }
    assert_equal [CrossLint::Core::Artifact], memory_app(files: ["a.md", "a.txt"]).check("/app", all: true).findings.map(&:class)
    assert_empty memory_app(files: ["a.md", "a.txt"]).check("/app").findings
  end

  def test_reports_as_text_unless_asked_for_json
    out = StringIO.new
    err = StringIO.new
    result = memory_app.check("/app")
    App.new.report(out:, err:).write(result)
    App.new.report(out:, err:, color: true).write(result)
    App.new.report(out:, err:, json: true).write(result)
    lines = out.string.lines(chomp: true)

    assert_equal ["a.md: warning: no c file at a.txt (local/p)", "a.md: \e[33mwarning: no c file at a.txt\e[0m (local/p)"], lines.take(2)
    assert_equal "warning", JSON.parse(lines.last).fetch("findings").first.fetch("severity")
  end

  def test_runs_a_ruby_rule_from_its_file_in_the_plugins_folder
    write(@base, ".config/crosslint/config.kdl", %(plugin ".config/crosslint/r"\n))
    write(@base, ".config/crosslint/r/plugin.kdl", %(artifact "a" {\n  files "{path}.md"\n}\nrule "says-hi" ruby="hi.rb"\n) +
      %(policy "p" {\n  applies-to "a"\n  rule "says-hi"\n}\n))
    write(@base, ".config/crosslint/r/hi.rb", %(class SaysHi < CrossLint::Rule\n  def check(artifact) = [violation(artifact, "hi")]\nend\n))
    write(@base, "a.md", "")
    Open3.capture3("git", "init", "-q", chdir: @base)

    assert_equal [["a.md", "hi"]], App.new.check(@base).violations.map { |violation| [violation.artifact, violation.message] }
  end

  def test_says_what_it_will_check_before_any_rule_runs
    write(@base, ".config/crosslint/config.kdl", %(plugin ".config/crosslint/local"\n))
    write(@base, ".config/crosslint/local/plugin.kdl", MANIFEST)
    write(@base, "a.md", "")
    Open3.capture3("git", "init", "-q", chdir: @base)
    started = []
    App.new.check(@base, started: ->(kinds) { started << kinds })

    assert_equal [[["a", 1]]], started
  end

  def test_runs_the_ruby_that_declares_a_plugins_artifacts_from_its_file
    write(@base, ".config/crosslint/config.kdl", %(plugin ".config/crosslint/r" {\n  folder "docs"\n}\n))
    write(@base, ".config/crosslint/r/plugin.kdl", %(setting "folder"\nartifacts ruby="artifacts.rb"\npolicy "p" {\n  rule "companion-exists" companion="c"\n}\n))
    write(@base, ".config/crosslint/r/artifacts.rb", <<~RUBY)
      class Artifacts < CrossLint::Artifacts
        def declare(settings) = [artifact("doc", files: settings.first.arguments.first + "/{path}.md", companions: {"c" => "{path}.txt"})]
      end
    RUBY
    write(@base, "docs/a.md", "")
    Open3.capture3("git", "init", "-q", chdir: @base)
    result = App.new.check(@base)

    assert_equal [["docs/a.md", "no c file at a.txt"]], result.violations.map { |violation| [violation.artifact, violation.message] }
  end

  def test_runs_a_helper_as_a_process_writing_its_standard_error_with_debug
    write(@base, ".config/crosslint/config.kdl", %(plugin ".config/crosslint/r"\n))
    write(@base, ".config/crosslint/r/plugin.kdl", %(artifact "a" {\n  files "{path}.md"\n}\nrule "asks" ruby="asks.rb"\n) +
      %(helper "h" command="sh" file="h.sh"\npolicy "p" {\n  applies-to "a"\n  rule "asks"\n}\n))
    write(@base, ".config/crosslint/r/asks.rb", %(class Asks < CrossLint::Rule\n  def check(artifact) = [violation(artifact, helper("h").call(1))]\nend\n))
    write(@base, ".config/crosslint/r/h.sh", %(while read -r line; do echo said >&2; echo '"hi"'; done\n))
    write(@base, "a.md", "")
    Open3.capture3("git", "init", "-q", chdir: @base)
    err = StringIO.new

    assert_equal ["hi"], App.new(err:).check(@base).violations.map(&:message)
    assert_empty err.string
    assert_equal ["hi"], App.new(err:, debug: true).check(@base).violations.map(&:message)
    assert_equal "crosslint: helper h: said\n", err.string
    assert_output(nil, "crosslint: helper h: said\n") { App.new(debug: true).check(@base) }
  end

  def test_runs_a_shared_plugin_fetched_from_a_repository_and_fetches_it_once
    url = shared_repository
    write(@base, ".config/crosslint/config.kdl", %(plugin #{url.dump} ref="v1.0.0"\n))
    write(@base, "a.md", "")
    Open3.capture3("git", "init", "-q", chdir: @base)
    err = StringIO.new
    app = -> { App.new(err:, shared_plugins: CrossLint::Adapters::GitSharedPlugins.new(err:, cache: File.join(@base, "cache"), schemes: ["file://"])) }
    first = app.call.check(@base)
    FileUtils.rm_rf(File.join(@base, "origin"))
    second = app.call.check(@base)

    assert_equal [[["a.md", "no c file at a.txt"]]] * 2, [first, second].map { |result| result.violations.map { |violation| [violation.artifact, violation.message] } }
    assert_equal [[["shared-docs", "p"]]] * 2, [first, second].map { |result| result.violations.map { |violation| [violation.plugin, violation.policy] } }
    assert_equal ["crosslint: fetching #{url} at v1.0.0"], err.string.lines(chomp: true)
  end

  def test_stops_at_a_shared_plugin_whose_ref_is_a_branch_naming_the_plugin_and_its_url
    url = shared_repository
    write(@base, ".config/crosslint/config.kdl", %(plugin #{url.dump} ref="main"\n))
    app = App.new(err: StringIO.new, shared_plugins: CrossLint::Adapters::GitSharedPlugins.new(err: StringIO.new, cache: File.join(@base, "cache"),
      schemes: ["file://"]))
    mistake = assert_raises(Mistake) { app.check(@base) }

    assert_equal [".config/crosslint/config.kdl:1", "couldn't fetch shared plugin shared-docs from #{url} at main: main is a branch, " \
      "and a ref is a tag or a full 40-character commit SHA"], [mistake.location, mistake.message]
  end

  def test_moves_a_shared_plugin_to_its_newest_tag_in_the_configuration_file_and_nothing_else
    url = shared_repository(tags: %w[v1.0.0 v1.2.0 v1.10.0-rc.1])
    text = "// The checks of this project\r\nplugin #{url.dump} ref=\"v1.0.0\" // pinned\r\nwarnings \"all\"\r\n"
    path = write(@base, ".config/crosslint/config.kdl", text)
    err = StringIO.new
    app = App.new(err:, shared_plugins: CrossLint::Adapters::GitSharedPlugins.new(err:, cache: File.join(@base, "cache"), schemes: ["file://"]))
    dry = app.update(@base, dry_run: true)

    assert_equal [["#{url}: would move from v1.0.0 to v1.2.0"], text], [dry.lines, File.binread(path)]
    assert_equal ["#{url}: moved from v1.0.0 to v1.2.0"], app.update(@base).lines
    assert_equal text.sub("v1.0.0", "v1.2.0"), File.binread(path)
    assert_equal ["#{url}: is at its newest tag, v1.2.0"], app.update(@base).lines
    assert_equal ["crosslint: listing the tags of #{url}"] * 3, err.string.lines(chomp: true)
  end

  def test_writes_the_configuration_with_the_recommended_plugins_through_the_port_it_is_given
    configuration = CrossLint::Adapters::MemoryConfiguration.new
    app = App.new(configuration:)
    dry = app.init("/app", dry_run: true)

    assert_equal [["would write .config/crosslint/config.kdl, with the recommended plugins: debt"], false], [dry.lines, configuration.exist?("/app")]
    assert_equal ["wrote .config/crosslint/config.kdl, with the recommended plugins: debt"], app.init("/app").lines
    assert_equal ["debt"], configuration.read("/app").plugins.map(&:name)
    assert_raises(Mistake) { app.init("/app") }
    assert_raises(Mistake) { app.init("/app", dry_run: true) }
    assert_equal ["replaced .config/crosslint/config.kdl, with the recommended plugins: debt"], app.init("/app", force: true).lines
  end

  def test_moves_a_project_from_ng_nudge_through_the_ports_it_is_given
    configuration = CrossLint::Adapters::MemoryConfiguration.new
    debt = Core::DebtFile.new(file: ".config/ng-nudge/debt.tsv", entries: [], header: "Rule\tArtifact\tComment\n")
    debt_files = CrossLint::Adapters::MemoryDebtFiles.new({"/app/.config/ng-nudge/debt.tsv" => debt})
    ng_nudge = CrossLint::Adapters::MemoryNgNudge.new({"/app" => {".config/ng-nudge/rc.json" => "{}"}})
    javascript = CrossLint::Adapters::MemoryJavaScript.new({}, globs: {"**/*.pipe.ts" => ["a.pipe.ts"]})
    project_files = CrossLint::Adapters::MemoryProjectFiles.new({"/app" => []})
    app = App.new(configuration:, debt_files:, ng_nudge:, javascript:, project_files:)
    seen = []
    dry = app.move_from_ng_nudge("/app", dry_run: true, planned: ->(changes, _notes) { seen << changes })

    assert_equal [dry.changes, true, false], [seen.first, dry.dry_run, configuration.exist?("/app")]
    assert_equal ["node-glob finds src/a.pipe.ts as a pipe, and CrossLint doesn't", Core::NgNudge::Move::WHY], dry.notes
    assert_equal [false, ["angular", "debt"]], [app.move_from_ng_nudge("/app").dry_run, configuration.read("/app").plugins.map(&:name)]
    assert_equal [false, true], [debt_files.exist?("/app", ".config/ng-nudge/debt.tsv"), debt_files.exist?("/app", ".config/crosslint/debt.tsv")]
    assert_raises(Mistake) { app.move_from_ng_nudge("/app") }
    assert_equal "replace .config/crosslint/config.kdl, with the plugins angular and debt", app.move_from_ng_nudge("/app", force: true).changes.first
  end

  def test_moves_a_project_from_ng_nudge_with_its_files_and_node_unless_it_is_given_other_ports
    write(@base, ".config/ng-nudge/rc.json", %({"rules": {"has-debt": {"withComment": {"maxSeverity": "none", "matching": "^a"}}}}))
    write(@base, ".config/ng-nudge/debt.tsv", "Rule\tArtifact\tComment\nspec-exists\tapp/card\tabc\n")
    result = App.new.move_from_ng_nudge(@base)

    assert_equal [false, true], [result.dry_run, File.file?(File.join(@base, ".config/crosslint/config.kdl"))]
    assert_equal ["Rule\tArtifact\tComment\nspec-exists\tapp/card\tabc\n", false],
      [File.binread(File.join(@base, ".config/crosslint/debt.tsv")), File.exist?(File.join(@base, ".config/ng-nudge/debt.tsv"))]
  end

  # The https URLs these tests use differ, so that the cache the tests
  # share holds no fetch of another test's.
  def test_fetches_a_shared_plugin_with_git_into_the_cache_of_the_user_unless_it_is_given_another_port
    url = "https://example.test/#{SecureRandom.hex(8)}/shared-docs"
    write(@base, ".config/crosslint/config.kdl", %(plugin "#{url}" ref="v1.0.0"\n))
    write(@base, "a.md", "")
    Open3.capture3("git", "init", "-q", chdir: @base)
    err = StringIO.new
    result = rewriting(url, shared_repository) { App.new(err:).check(@base) }

    assert_equal ["a.md"], result.violations.map(&:artifact)
    assert_equal ["crosslint: fetching #{url} at v1.0.0"], err.string.lines(chomp: true)
    key = Digest::SHA256.hexdigest("#{url}\0v1.0.0")[0, 32]
    assert_equal [MANIFEST], Dir.glob(File.join(CACHE, "**", "plugins", key, "shared-docs", "plugin.kdl")).map { |file| File.binread(file) }
  end

  def test_runs_helpers_through_the_port_it_is_given
    helpers = CrossLint::Adapters::MemoryHelpers.new
    def helpers.start(*) = raise(CrossLint::Core::Mistake, "asked")

    assert_equal "asked", assert_raises(Mistake) { memory_app(helpers:).check("/app") }.message
  end

  def test_loads_ruby_rules_through_the_port_it_is_given
    rule = ->(namespace) { namespace.const_set(:SaysHi, Class.new(CrossLint::Rule) { define_method(:check) { |artifact| [violation(artifact, "hi")] } }) }
    app = memory_app(ruby: {File.expand_path("/app/local/hi.rb") => rule})

    assert_equal ["hi", "no c file at a.txt"], app.check("/app").violations.map(&:message)
  end

  def test_shows_each_faults_trace_only_with_debug
    fault = CrossLint::Core::Fault.new(plugin: "p", rule: "r", artifact: nil, message: "raised RuntimeError: boom", trace: ["hi.rb:1"])
    result = memory_app.check("/app").with(faults: [fault])
    lines = [{}, {debug: true}, {json: true}, {json: true, debug: true}].map do |options|
      err = StringIO.new
      App.new.report(out: StringIO.new, err:, **options).write(result)
      err.string.lines.grep(/hi\.rb:1/).size
    end

    assert_equal [0, 1, 0, 1], lines
  end

  def test_reads_through_the_ports_it_is_given
    configuration = CrossLint::Core::Configuration.new(file: "crosslint.json", plugins: [], policies: [], warnings: nil, verbosity: nil)
    app = App.new(configuration: CrossLint::Adapters::MemoryConfiguration.new({"/app" => configuration}, file: "crosslint.json"),
      manifests: CrossLint::Adapters::MemoryPluginManifests.new)
    mistake = assert_raises(Mistake) { app.load_project("/app") }

    assert_equal "crosslint.json", mistake.location
  end

  private

  # A repository of a plugin called shared-docs, with these tags, on the
  # branch main, in the test's base. Its file URL.
  def shared_repository(tags: ["v1.0.0"])
    repository_at(File.join(@base, "origin", "shared-docs"), {"plugin.kdl" => MANIFEST}, tags:)
  end

  # A project at /app whose plugin, local, warns of each a.md with no
  # a.txt beside it.
  def memory_app(files: ["a.md"], ruby: nil, helpers: nil)
    core = CrossLint::Core
    configuration = core::Configuration.new(file: ".config/crosslint/config.kdl", warnings: nil, verbosity: nil, policies: [],
      plugins: [core::ListedPlugin.new(name: "./local", ref: nil, settings: [], line: 1)])
    artifact = core::ArtifactDeclaration.new(name: "a", files: core::PathPattern.new(source: "{path}.md"), line: 1,
      companions: [core::CompanionDeclaration.new(name: "c", pattern: core::PathPattern.new(source: "{path}.txt"), line: 2)])
    policy = core::Policy.new(name: "p", applies_to: core::AppliesTo.new(artifact: "a", line: 2), condition: nil, line: 1,
      rules: [core::PolicyRule.new(name: "companion-exists", arguments: {"companion" => "c"}, severity: :warning, line: 3)] +
        (ruby ? [core::PolicyRule.new(name: "says-hi", arguments: {}, severity: nil, line: 4)] : []))
    rules = ruby ? [core::RuleDeclaration.new(name: "says-hi", ruby: "hi.rb", line: 5)] : []
    manifest = core::Manifest.new(file: "local/plugin.kdl", artifacts: [artifact], policies: [policy], rules:, helpers: [])
    App.new(configuration: CrossLint::Adapters::MemoryConfiguration.new({"/app" => configuration}),
      manifests: CrossLint::Adapters::MemoryPluginManifests.new({File.expand_path("/app/local") => manifest}),
      project_files: CrossLint::Adapters::MemoryProjectFiles.new({"/app" => files}), plugin_ruby: CrossLint::Adapters::MemoryPluginRuby.new(ruby || {}),
      helpers:, plugins: @base)
  end
end
