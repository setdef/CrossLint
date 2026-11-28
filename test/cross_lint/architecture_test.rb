# frozen_string_literal: true

require "test_helper"
require "open3"
require "rbconfig"

# How the code divides: what the core may load, what may name the Angular
# plugin, what the app ships, and which files have signatures.
class ArchitectureTest < Minitest::Test
  def test_the_core_loads_with_nothing_outside_rubys_standard_library
    script = 'require "cross_lint/core"; puts $LOADED_FEATURES'
    out, err, status = Open3.capture3({ "RUBYOPT" => nil }, RbConfig.ruby, "--disable-gems", "-I", File.join(ROOT, "lib"), "-e", script)

    assert_predicate status, :success?, err
    core = File.join(ROOT, "lib", "cross_lint", "core")
    standard = [RbConfig::CONFIG.fetch("rubylibdir"), RbConfig::CONFIG.fetch("archdir")]
    outside = out.lines(chomp: true).select { |feature| File.absolute_path?(feature) }.reject do |feature|
      feature.start_with?(*standard) || feature == "#{core}.rb" || feature.start_with?("#{core}/")
    end

    assert_empty outside
  end

  # So that the Angular plugin can move to a repository of its own; the
  # documents describe it, and its own folder holds its tests.
  def test_no_code_outside_the_angular_plugins_folder_refers_to_it
    folder = ["plugins", "angular"].join("/")
    code = Dir.glob(["{lib,test,tasks,exe,.github,.config}/**/*", "build/*", "*"], File::FNM_DOTMATCH, base: ROOT)
      .reject { |file| file.start_with?("docs/") || file.end_with?(".md") || !File.file?(File.join(ROOT, file)) }

    assert_empty code.select { |file| File.binread(File.join(ROOT, file)).include?(folder) }
  end

  # A plugin's test fixtures, node_modules among them, would grow the app.
  def test_the_app_ships_no_plugins_tests_or_their_fixtures
    shipped = Gem::Specification.load(File.join(ROOT, "cross_lint.gemspec")).files

    assert_includes shipped, "plugins/debt/plugin.kdl"
    assert_empty shipped.grep(%r{\Aplugins/[^/]+/test(/|\z)})
  end

  # The other folders of plugins/ are shared plugins, which a project
  # fetches.
  def test_the_app_ships_the_built_in_plugins_alone
    shipped = Gem::Specification.load(File.join(ROOT, "cross_lint.gemspec")).files

    assert_equal CrossLint::App::BUILT_IN, shipped.grep(%r{\Aplugins/}).map { it.split("/")[1] }.uniq.sort
    assert_includes Dir.children(File.join(ROOT, "plugins")), "agents-md"
  end

  def test_every_file_under_lib_has_a_signature_at_the_matching_path_under_sig
    missing = Dir.glob("lib/**/*.rb", base: ROOT).map { |file| file.sub(%r{\Alib/(.*)\.rb\z}, 'sig/\1.rbs') }
      .reject { |signature| File.file?(File.join(ROOT, signature)) }

    assert_empty missing
  end
end
