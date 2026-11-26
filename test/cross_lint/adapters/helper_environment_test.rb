# frozen_string_literal: true

require "test_helper"

# What environment a helper starts with: docs/design/plugins.md says it is
# the one CrossLint was started with.
class HelperEnvironmentTest < Minitest::Test
  cover "CrossLint::Adapters::HelperEnvironment*"

  UNSET = CrossLint::Adapters::HelperEnvironment::UNSET

  def test_gives_back_each_value_the_launcher_saved_and_removes_what_it_saved_as_unset
    env = {"RUBYOPT" => "-rbundler/setup -W0", "BUNDLER_ORIG_RUBYOPT" => "-W0", "BUNDLE_GEMFILE" => "/app/Gemfile",
           "BUNDLER_ORIG_BUNDLE_GEMFILE" => UNSET, "GEM_HOME" => "/app/gems", "BUNDLER_ORIG_GEM_HOME" => "/start/gems", "OTHER" => "kept"}

    assert_equal({"RUBYOPT" => "-W0", "BUNDLE_GEMFILE" => nil, "GEM_HOME" => "/start/gems", "BUNDLER_ORIG_RUBYOPT" => nil,
                  "BUNDLER_ORIG_BUNDLE_GEMFILE" => nil, "BUNDLER_ORIG_GEM_HOME" => nil}, environment(env).changes)
  end

  def test_changes_nothing_in_an_environment_the_launcher_didnt_touch
    assert_empty environment({"RUBYOPT" => "-W0", "PATH" => path("/a", "/b")}).changes
    assert_empty environment({"RUBYOPT" => "-W0"}, app_folder: File.expand_path("/app/bin")).changes
  end

  def test_takes_the_apps_folder_out_of_the_saved_path_and_nothing_else
    app = File.expand_path("/app/bin")
    saved = path(app, "/usr/bin", "", "/app/binary", app, "")
    env = {"PATH" => path("/app/gems/bin", app, "/usr/bin"), "BUNDLER_ORIG_PATH" => saved}

    assert_equal path("/usr/bin", "", "/app/binary", ""), environment(env, app_folder: app).changes.fetch("PATH")
    assert_equal saved, environment(env).changes.fetch("PATH")
  end

  def test_compares_folders_as_paths_not_as_text
    app = File.expand_path("/app/bin")
    folders = ["#{app}/", File.join(File.dirname(app), ".", "bin")]
    env = {"BUNDLER_ORIG_PATH" => [*folders, File.expand_path("/usr/bin")].join(File::PATH_SEPARATOR)}

    assert_equal [path("/usr/bin")] * 2, [environment(env, app_folder: app).changes.fetch("PATH"), environment(env, app_folder: "#{app}/").changes.fetch("PATH")]
  end

  def test_keeps_an_empty_folder_even_when_the_current_folder_is_the_apps
    Dir.mktmpdir("crosslint") do |base|
      app = File.realpath(base)
      kept = Dir.chdir(app) { environment({"PATH" => [app, "", "/usr/bin"].join(File::PATH_SEPARATOR)}, app_folder: app).changes.fetch("PATH") }

      assert_equal ["", "/usr/bin"].join(File::PATH_SEPARATOR), kept
    end
  end

  def test_takes_the_apps_folder_of_the_ruby_it_runs_on_out_of_the_path_unless_told_otherwise
    Dir.mktmpdir("crosslint") do |base|
      write(base, "app/fledge.cfg", "")
      bin = File.join(base, "app", "bin")
      changes = with_bindir(bin) { environment({"PATH" => path(bin, "/usr/bin")}).changes }

      assert_equal path("/usr/bin"), changes.fetch("PATH")
    end
  end

  def test_takes_the_apps_folder_out_of_a_path_the_launcher_didnt_save
    app = File.expand_path("/app/bin")

    assert_equal path("/usr/bin"), environment({"PATH" => path(app, "/usr/bin")}, app_folder: app).changes.fetch("PATH")
  end

  def test_says_a_variable_as_the_helper_has_it
    env = {"PATH" => path("/app/bin", "/usr/bin"), "BUNDLER_ORIG_PATH" => path("/usr/bin"), "RUBYOPT" => "-rx", "BUNDLER_ORIG_RUBYOPT" => UNSET, "OTHER" => "kept"}
    environment = environment(env)

    assert_equal [path("/usr/bin"), "none", "kept", "none"], [environment.fetch("PATH", "none"), environment.fetch("RUBYOPT", "none"),
      environment.fetch("OTHER", "none"), environment.fetch("MISSING", "none")]
  end

  def test_knows_the_folder_of_a_ruby_a_fledge_app_carries_by_the_file_above_it
    Dir.mktmpdir("crosslint") do |base|
      write(base, "plain/bin/ruby", "")
      write(base, "app/bin/ruby", "")
      write(base, "app/fledge.cfg", "")
      write(base, "windows/ruby/bin/ruby.exe", "")
      write(base, "windows/fledge.cfg", "")
      found = ["plain/bin", "app/bin", "windows/ruby/bin"].map do |folder|
        with_bindir(File.join(base, folder)) { CrossLint::Adapters::HelperEnvironment.app_folder }
      end

      assert_equal [nil, File.join(base, "app", "bin"), File.join(base, "windows", "ruby", "bin")], found
    end
  end

  def test_takes_none_of_the_apps_folder_in_the_checkout_the_tests_run_in
    assert_nil CrossLint::Adapters::HelperEnvironment.app_folder
  end

  private

  def environment(env, **options) = CrossLint::Adapters::HelperEnvironment.new(env, **options)

  def path(*folders) = folders.map { |folder| folder.empty? ? folder : File.expand_path(folder) }.join(File::PATH_SEPARATOR)

  def with_bindir(folder)
    original = RbConfig::CONFIG["bindir"]
    RbConfig::CONFIG["bindir"] = folder
    yield
  ensure
    RbConfig::CONFIG["bindir"] = original
  end
end
