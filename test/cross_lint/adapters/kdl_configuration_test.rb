# frozen_string_literal: true

require "test_helper"

class KDLConfigurationTest < Minitest::Test
  cover "CrossLint::Adapters::KDLConfiguration*"

  include CrossLint::Testing::ConfigurationContract

  Mistake = CrossLint::Core::Mistake
  FILE = ".config/crosslint/config.kdl"

  def setup
    @base = Dir.mktmpdir("crosslint")
  end

  def teardown
    FileUtils.rm_rf(@base)
  end

  def configuration_port(projects, broken: nil)
    projects.each { |project, plugins| write(@base, "#{project}/#{FILE}", plugins.map { |name| "plugin #{name.dump}\n" }.join) }
    write(@base, "#{broken}/#{FILE}", %(plugin "one"\nplugn "two"\n)) if broken
    CrossLint::Adapters::KDLConfiguration.new
  end

  def example_configuration_port
    write(@base, "example/#{FILE}", <<~KDL)
      plugin "https://github.com/OWNER/REPO" ref="v1.2.0"
      plugin "angular" {
        src-dir "src"
        role "store" files="{path}.store.ts" {
          expects "spec"
        }
      }
      plugin ".config/crosslint/signatures"
      policy "angular/prefer-css-over-scss" severity="error"
      policy "angular/spec-exists" severity="warning"
      policy "signatures/has-test" enabled=#false
      warnings "error"
      verbosity "silent"
    KDL
    CrossLint::Adapters::KDLConfiguration.new
  end

  def folder(path) = File.join(@base, path).tap { |full| FileUtils.mkdir_p(full) }

  # The tests may run inside a project, such as CrossLint's own checkout.
  def root_outside
    above = File.dirname(@base)
    above = File.dirname(above) until File.file?(File.join(above, FILE)) || File.dirname(above) == above
    above if File.file?(File.join(above, FILE))
  end

  def test_reads_the_example_in_the_configuration_reference
    configuration = read(doc_blocks("docs/reference/configuration.md", "kdl").fetch(0))
    angular, debt, signatures = configuration.plugins

    assert_equal [["angular", nil, 1], ["debt", nil, 4], [".config/crosslint/signatures", nil, 7]],
      configuration.plugins.map { |plugin| [plugin.name, plugin.ref, plugin.line] }
    assert_equal [setting("src-dir", ["src"], {}, 2)], angular.settings
    assert_equal [setting("report-entries", [], {"commented" => "warning"}, 5)], debt.settings
    assert_empty signatures.settings
    assert_equal [policy("angular/prefer-css-over-scss", nil, :error, 9), policy("signatures/has-test", false, nil, 10)],
      configuration.policies
    assert_equal [:all, nil], [configuration.warnings, configuration.verbosity]
  end

  def test_reads_the_configuration_in_the_readme
    configuration = read(doc_blocks("README.md", "kdl").fetch(1))

    assert_equal [".config/crosslint/signatures"], configuration.plugins.map(&:name)
  end

  def test_reads_a_shared_plugin_with_its_ref
    plugin = read(%(plugin "https://github.com/OWNER/REPO" ref="v1.2.0")).plugins.fetch(0)

    assert_equal ["https://github.com/OWNER/REPO", "v1.2.0", :shared], [plugin.name, plugin.ref, plugin.kind]
  end

  def test_reads_settings_inside_settings
    plugin = read(%(plugin "angular" {\n  role "store" files="{path}.store.ts" {\n    expects "spec"\n  }\n}\n)).plugins.fetch(0)

    assert_equal [CrossLint::Core::Setting.new(name: "role", arguments: ["store"], properties: {"files" => "{path}.store.ts"},
      children: [setting("expects", ["spec"], {}, 3)], line: 2)], plugin.settings
  end

  def test_reads_each_mode
    %w[all none error].each { |mode| assert_equal mode.to_sym, read(%(plugin "a"\nwarnings "#{mode}")).warnings }
    %w[normal quiet silent].each { |mode| assert_equal mode.to_sym, read(%(plugin "a"\nverbosity "#{mode}")).verbosity }
  end

  def test_reads_a_policy_setting_with_either_property
    assert_equal [policy("a/b", true, nil, 1), policy("a/c", nil, :warning, 2), policy("a/d", false, :error, 3)],
      read(%(policy "a/b" enabled=#true\npolicy "a/c" severity="warning"\npolicy "a/d" enabled=#false severity="error")).policies
  end

  def test_refuses_a_node_it_does_not_know
    assert_refuses 2, %(unknown node "plugn", did you mean "plugin"?), %(plugin "a"\nplugn "b")
    assert_refuses 1, %(unknown node "zzz"; expected "plugin", "policy", "warnings", or "verbosity"), %(zzz)
  end

  def test_refuses_a_plugin_written_wrong
    assert_refuses 1, "plugin has 0 arguments; write it as plugin NAME { ... }", %(plugin)
    assert_refuses 1, "plugin has 2 arguments; write it as plugin NAME { ... }", %(plugin "a" "b")
    assert_refuses 1, "plugin has 3 where a string goes; write it as plugin NAME { ... }", %(plugin 3)
    assert_refuses 1, %(unknown property "rev", did you mean "ref"?), %(plugin "https://x" rev="v1")
    assert_refuses 1, "ref= takes a string, not 1", %(plugin "https://x" ref=1)
  end

  def test_refuses_a_policy_setting_written_wrong
    assert_refuses 1, "policy has 0 arguments; write it as policy PLUGIN/POLICY enabled=#false", %(policy enabled=#false)
    assert_refuses 1, %(unknown property "enable", did you mean "enabled"?), %(policy "a/b" enable=#false)
    assert_refuses 1, %(enabled= takes #true or #false, not "no"), %(policy "a/b" enabled="no")
    assert_refuses 1, %(unknown severity "err", did you mean "error"?), %(policy "a/b" severity="err")
    assert_refuses 1, "severity= takes a string, not true", %(policy "a/b" severity=#true)
    assert_refuses 2, %(unknown node "x"; policy takes no children), %(policy "a/b" enabled=#false {\n  x\n}\n)
    assert_refuses 1, %(policy "a/b" changes nothing; give it enabled=#false or severity=), %(policy "a/b")
  end

  def test_refuses_a_mode_written_wrong
    assert_refuses 2, %(unknown warnings "some"; expected "all", "none", or "error"), %(plugin "a"\nwarnings "some")
    assert_refuses 1, %(unknown verbosity "quite", did you mean "quiet"?), %(verbosity "quite")
    assert_refuses 3, "warnings is set twice; the first is on line 2", %(plugin "a"\nwarnings "all"\nwarnings "none")
    assert_refuses 2, "verbosity is set twice; the first is on line 1", %(verbosity "quiet"\nverbosity "quiet")
    assert_refuses 1, "warnings has 2 arguments; write it as warnings MODE", %(warnings "none" "error")
    assert_refuses 1, %(unknown property "x"; warnings takes none), %(warnings "all" x=1)
    assert_refuses 1, %(unknown node "y"; verbosity takes no children), %(verbosity "quiet" { y; })
  end

  def test_names_the_line_of_a_syntax_error
    assert_refuses 2, "isn't valid KDL: Unexpected NEWLINE in string literal", %(plugin "a"\nplugin "b\n)
  end

  def test_reads_a_file_that_starts_with_a_byte_order_mark
    assert_equal ["a"], read(%(\xEF\xBB\xBFplugin "a"\n)).plugins.map(&:name)
  end

  def test_refuses_a_file_that_is_not_utf_8
    mistake = assert_raises(Mistake) { read(%(plugin "\xFF"\n)) }

    assert_equal [FILE, nil, "isn't valid UTF-8"], [mistake.file, mistake.line, mistake.message]
  end

  def test_refuses_a_type_annotation
    assert_refuses 1, "plugin has the type annotation (local), which CrossLint doesn't read", %((local)plugin "a")
    assert_refuses 1, "plugin has the type annotation (path), which CrossLint doesn't read", %(plugin (path)"a")
    assert_refuses 1, "plugin has the type annotation (u8), which CrossLint doesn't read", %(plugin "a" ref=(u8)1)
  end

  def test_finds_no_root_from_a_folder_that_does_not_exist
    mistake = assert_raises(Mistake) { configuration_port({}).find_root(File.join(@base, "missing")) }

    assert_equal ["", "no folder #{File.join(@base, "missing")}"], [mistake.location, mistake.message]
  end

  def test_finds_the_root_from_a_relative_folder
    configuration_port({"app" => ["one"]})
    Dir.chdir(folder("app/lib")) do
      assert_equal File.realpath(File.join(@base, "app")), File.realpath(CrossLint::Adapters::KDLConfiguration.new.find_root("."))
    end
  end

  def test_does_not_take_a_folder_named_like_the_configuration_for_it
    FileUtils.mkdir_p(File.join(@base, "app", FILE))
    root = CrossLint::Adapters::KDLConfiguration.new.find_root(folder("app"))

    assert_equal [root_outside], [root]
  end

  def test_does_not_read_the_old_path_of_the_configuration
    write(@base, "app/.config/crosslint.kdl", %(plugin "one"\n))
    write(@base, "app/lib/.keep", "")

    root = CrossLint::Adapters::KDLConfiguration.new.find_root(folder("app/lib"))

    assert_equal [root_outside], [root]
  end

  def test_finds_the_nearest_folder_with_the_configuration
    configuration_port({"app" => ["one"], "app/inner" => ["two"]})

    assert_equal File.join(@base, "app", "inner"), CrossLint::Adapters::KDLConfiguration.new.find_root(folder("app/inner/lib"))
  end

  def test_says_the_configuration_does_not_exist
    mistake = assert_raises(Mistake) { configuration_port({}).read(folder("empty")) }

    assert_equal [FILE, nil, "doesn't exist"], [mistake.file, mistake.line, mistake.message]
  end

  def test_refuses_a_null_where_a_value_goes
    assert_refuses 1, "ref= takes a string, not nil", %(plugin "https://x" ref=#null)
    assert_refuses 1, "enabled= takes #true or #false, not nil", %(policy "a/b" enabled=#null)
    assert_refuses 1, "warnings has nil where a string goes; write it as warnings MODE", %(warnings #null)
  end

  def test_finds_no_root_above_the_top_folder
    assert_nil CrossLint::Adapters::KDLConfiguration.new.find_root(File.expand_path("/"))
  end

  def test_names_the_configuration_file
    assert_equal FILE, CrossLint::Adapters::KDLConfiguration.new.file
  end

  private

  def read(text)
    write(@base, "project/#{FILE}", text)
    CrossLint::Adapters::KDLConfiguration.new.read(File.join(@base, "project"))
  end

  def assert_refuses(line, message, text)
    mistake = assert_raises(Mistake) { read(text) }

    assert_equal [FILE, line, message], [mistake.file, mistake.line, mistake.message]
  end

  def setting(name, arguments, properties, line)
    CrossLint::Core::Setting.new(name:, arguments:, properties:, children: [], line:)
  end

  def policy(name, enabled, severity, line) = CrossLint::Core::PolicySetting.new(name:, enabled:, severity:, line:)
end
