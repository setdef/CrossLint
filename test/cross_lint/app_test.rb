# frozen_string_literal: true

require "test_helper"
require "open3"

class AppTest < Minitest::Test
  cover "CrossLint::App*"

  App = CrossLint::App
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
    write(@base, "app/.config/crosslint/config.kdl", %(plugin "debt"\n))
    write(@base, "debt/plugin.kdl", MANIFEST)
    mistake = assert_raises(Mistake) { Dir.chdir(@base) { App.new.load_project(File.join(@base, "app")) } }

    assert_equal ".config/crosslint/config.kdl:1: unknown built-in plugin \"debt\"; this CrossLint has none",
      "#{mistake.location}: #{mistake.message}"
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
  def memory_app(files: ["a.md"], ruby: nil)
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
      plugins: @base)
  end
end
