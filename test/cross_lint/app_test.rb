# frozen_string_literal: true

require "test_helper"

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
    write(@base, "app/.config/crosslint.kdl", %(plugin "debt"\n))
    write(@base, "debt/plugin.kdl", MANIFEST)
    mistake = assert_raises(Mistake) { Dir.chdir(@base) { App.new.load_project(File.join(@base, "app")) } }

    assert_equal ".config/crosslint.kdl:1: unknown built-in plugin \"debt\"; this CrossLint has none",
      "#{mistake.location}: #{mistake.message}"
  end

  def test_takes_each_folder_with_a_manifest_as_a_built_in_plugin
    write(@base, "plugins/debt/plugin.kdl", MANIFEST)
    FileUtils.mkdir_p(File.join(@base, "plugins/other"))
    write(@base, "app/.config/crosslint.kdl", %(plugin "debt"\n))
    app = App.new(plugins: File.join(@base, "plugins"))

    assert_equal [["debt", File.join(@base, "plugins/debt")]], app.load_project(File.join(@base, "app")).plugins.map { |plugin| [plugin.name, plugin.folder] }
    write(@base, "app/.config/crosslint.kdl", %(plugin "other"\n))
    mistake = assert_raises(Mistake) { app.load_project(File.join(@base, "app")) }

    assert_equal %(unknown built-in plugin "other"; expected "debt"), mistake.message
  end

  def test_reads_through_the_ports_it_is_given
    configuration = CrossLint::Core::Configuration.new(file: "crosslint.json", plugins: [], policies: [], warnings: nil, verbosity: nil)
    app = App.new(configuration: CrossLint::Adapters::MemoryConfiguration.new({"/app" => configuration}, file: "crosslint.json"),
      manifests: CrossLint::Adapters::MemoryPluginManifests.new)
    mistake = assert_raises(Mistake) { app.load_project("/app") }

    assert_equal "crosslint.json", mistake.location
  end
end
