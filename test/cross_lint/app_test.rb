# frozen_string_literal: true

require "test_helper"
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

  def test_reads_crosslints_own_configuration_and_plugin
    project = App.new.load_project(File.join(ROOT, "lib", "cross_lint"))

    assert_equal [ROOT, [["signatures", File.join(ROOT, ".config/crosslint/signatures")]]],
      [project.root, project.plugins.map { |plugin| [plugin.name, plugin.folder] }]
    assert_equal ["ruby-file"], project.plugins.first.manifest.artifacts.map(&:name)
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
    updated = App.new.check(@base, flags: ["update-debt"])
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

  def test_takes_each_folder_with_a_manifest_as_a_built_in_plugin
    write(@base, "plugins/debt/plugin.kdl", MANIFEST)
    FileUtils.mkdir_p(File.join(@base, "plugins/other"))
    write(@base, "app/.config/crosslint/config.kdl", %(plugin "debt"\n))
    app = App.new(plugins: File.join(@base, "plugins"))

    assert_equal [["debt", File.join(@base, "plugins/debt")]], app.load_project(File.join(@base, "app")).plugins.map { |plugin| [plugin.name, plugin.folder] }
    write(@base, "app/.config/crosslint/config.kdl", %(plugin "other"\n))
    mistake = assert_raises(Mistake) { app.load_project(File.join(@base, "app")) }

    assert_equal %(unknown built-in plugin "other"; expected "debt"), mistake.message
  end

  def test_checks_crosslint_itself_with_git
    result = App.new.check(ROOT)

    assert_equal [false, Dir.glob("lib/**/*.rb", base: ROOT).size], [result.failed, result.summary.artifacts]
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
