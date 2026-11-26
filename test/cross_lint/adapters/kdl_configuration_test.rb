# frozen_string_literal: true

require "test_helper"

class KDLConfigurationTest < Minitest::Test
  cover "CrossLint::Adapters::KDLConfiguration*"

  include CrossLint::Testing::ConfigurationContract

  Mistake = CrossLint::Core::Mistake
  FILE = ".config/crosslint/config.kdl"

  # The tests run in their base, so that a mutation of the adapter that
  # writes a configuration to the path FILE, relative to the folder it runs
  # in, writes it there and not over the checkout's own configuration.
  def setup
    @base = Dir.mktmpdir("crosslint")
    @folder = Dir.pwd
    Dir.chdir(@base)
  end

  def teardown
    Dir.chdir(@folder)
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

  def test_reads_the_path_of_a_shared_plugin_and_no_path_as_nil
    plugins = read(%(plugin "#{URL}" ref="v1.2.0" path="plugins/markdown-links"\nplugin "#{URL}" ref="v1.2.0"\n)).plugins

    assert_equal ["plugins/markdown-links", nil], plugins.map(&:path)
  end

  def test_refuses_a_path_that_is_not_a_string
    assert_refuses 1, "path= takes a string, not 1", %(plugin "#{URL}" ref="v1" path=1)
  end

  def test_sets_the_ref_of_the_plugin_with_the_path_it_is_given_and_leaves_the_path_and_the_others_as_they_were
    text = %(plugin "#{URL}" ref="v1.0.0" path="plugins/a"\nplugin "#{URL}" ref="v1.0.0" path="plugins/b"\nplugin "#{URL}" ref="v1.0.0"\n)

    assert_equal text.sub(%(ref="v1.0.0" path="plugins/b"), %(ref="v1.1.0" path="plugins/b")), set_refs(text, [URL, "plugins/b"] => "v1.1.0")
    assert_equal text.sub(%(ref="v1.0.0"\n), %(ref="v1.1.0"\n)), set_refs(text, [URL, nil] => "v1.1.0")
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

  # Denies each File.rename in this thread while :crosslint_config_rename_denied
  # is set, as Windows does over a file another program has open.
  module DeniedRenames
    def rename(from, to)
      raise Errno::EACCES, "#{from}, #{to}" if Thread.current[:crosslint_config_rename_denied]

      super
    end
  end
  File.singleton_class.prepend(DeniedRenames)

  URL = "https://example.com/OWNER/REPO"

  def test_sets_a_ref_and_leaves_every_other_byte_as_it_was
    text = "// A comment, with a ref=\"v1.0.0\" in it\r\n\tplugin   \"#{URL}\"\t ref=\"v1.0.0\"  { \r\n  src-dir \"src\"\r\n}\r\n\r\n" \
      "plugin \"angular\" // ref=\"v1.0.0\"\r\nwarnings \"error\"  \r\n"

    assert_equal text.sub("ref=\"v1.0.0\"  {", "ref=\"v2.0.0\"  {"), set_refs(text, [URL, nil] => "v2.0.0")
  end

  def test_sets_the_refs_of_every_plugin_it_is_given_wherever_they_are_on_a_line
    text = %(plugin "#{URL}/a" ref="v1"; plugin "#{URL}/b" ref="v1"\nplugin "#{URL}/c"\\\n  ref="v1"\nplugin "#{URL}/d" ref="v1"\n)

    # Each ref is longer or shorter than the one it replaces, so that a
    # change made before the one after it would move that one.
    assert_equal text.sub(%(/a" ref="v1"), %(/a" ref="v10.20.30")).sub(%(/b" ref="v1"), %(/b" ref="v")).sub(%(/c"\\\n  ref="v1"), %(/c"\\\n  ref="version-400")),
      set_refs(text, ["#{URL}/a", nil] => "v10.20.30", ["#{URL}/b", nil] => "v", ["#{URL}/c", nil] => "version-400")
  end

  def test_counts_columns_in_characters_and_lines_by_every_line_ending_kdl_has
    ["\r\n", "\n", "\u0085", "\u000B", "\u000C", "\u2028", "\u2029"].each do |ending|
      text = "// é#{ending}plugin \"é\" ref=\"v1\"#{ending}"

      assert_equal "// é#{ending}plugin \"é\" ref=\"v2\"#{ending}", set_refs(text, ["é", nil] => "v2"), "after #{ending.dump}"
    end
  end

  def test_sets_a_ref_written_as_a_raw_string
    assert_equal %(plugin "#{URL}" ref=#"v2"#\n), set_refs(%(plugin "#{URL}" ref=#"v1"#\n), [URL, nil] => "v2")
    assert_equal %(plugin "#{URL}" ref=##"v2"##\n), set_refs(%(plugin "#{URL}" ref=##"v1"##\n), [URL, nil] => "v2")
  end

  def test_sets_a_ref_before_the_argument_and_one_on_a_plugin_with_settings
    assert_equal %(plugin ref="v2" "#{URL}"\n), set_refs(%(plugin ref="v1" "#{URL}"\n), [URL, nil] => "v2")
    assert_equal %(plugin "#{URL}" ref="v2" {\n  ref "v1"\n}\n), set_refs(%(plugin "#{URL}" ref="v1" {\n  ref "v1"\n}\n), [URL, nil] => "v2")
  end

  def test_leaves_a_plugin_it_is_not_given_a_ref_for_and_a_node_that_is_not_a_plugin
    text = %(plugin "#{URL}" ref="v1"\nplugin "#{URL}/other" ref="v1"\npolicy "#{URL}" severity="error"\nwarnings "all"\n)

    assert_equal text.sub(%(REPO" ref="v1"), %(REPO" ref="v2")), set_refs(text, [URL, nil] => "v2")
  end

  def test_writes_nothing_when_no_plugin_is_given_a_ref
    path = write(@base, "project/#{FILE}", %(plugin "#{URL}" ref="v1"\n))
    inode = File.stat(path).ino
    CrossLint::Adapters::KDLConfiguration.new.set_refs(File.join(@base, "project"), {["https://example.com/other", nil] => "v2"})

    assert_equal [inode, [".config"]], [File.stat(path).ino, Dir.children(File.join(@base, "project"))]
  end

  def test_keeps_the_permissions_of_the_file_and_leaves_no_other_file
    skip "Windows has no permission bits to keep" if Gem.win_platform?

    path = write(@base, "project/#{FILE}", %(plugin "#{URL}" ref="v1"\n))
    File.chmod(0o640, path)
    set_refs_in("project", [URL, nil] => "v2")

    assert_equal [0o640, ["config.kdl"]], [File.stat(path).mode & 0o777, Dir.children(File.dirname(path))]
  end

  def test_leaves_the_file_as_it_was_when_the_system_denies_the_rename
    path = write(@base, "project/#{FILE}", %(plugin "#{URL}" ref="v1"\n))
    mistake = begin
      Thread.current[:crosslint_config_rename_denied] = true
      assert_raises(Mistake) { set_refs_in("project", [URL, nil] => "v2") }
    ensure
      Thread.current[:crosslint_config_rename_denied] = nil
    end

    assert_equal [FILE, nil, "couldn't be replaced, since permission was denied; close any program that has it open, and run again"],
      [mistake.file, mistake.line, mistake.message]
    assert_equal [%(plugin "#{URL}" ref="v1"\n), ["config.kdl"]], [File.binread(path), Dir.children(File.dirname(path))]
  end

  def test_writes_the_configuration_as_kdl_with_a_blank_line_between_its_kinds
    core = CrossLint::Core
    plugins = [core::ListedPlugin.new(name: URL, ref: "v1", settings: [], line: 0),
      core::ListedPlugin.new(name: URL, ref: "v1", path: "plugins/a", settings: [], line: 0),
      core::ListedPlugin.new(name: "angular", ref: nil, line: 0, settings: [
        core::Setting.new(name: "role", arguments: ["store"], properties: {"files" => "{path}.store.ts"}, line: 0,
          children: [core::Setting.new(name: "expects", arguments: [], properties: {}, children: [], line: 0)])
      ])]
    policies = [core::PolicySetting.new(name: "angular/spec-exists", enabled: false, severity: :warning, line: 0),
      core::PolicySetting.new(name: "angular/stub-exists", enabled: nil, severity: nil, line: 0)]
    CrossLint::Adapters::KDLConfiguration.new.write(folder("project"), core::Configuration.new(file: FILE, plugins:, policies:, warnings: :all, verbosity: nil))

    assert_equal <<~KDL, File.binread(File.join(@base, "project", FILE))
      plugin "#{URL}" ref="v1"
      plugin "#{URL}" ref="v1" path="plugins/a"
      plugin "angular" {
        role "store" files="{path}.store.ts" {
          expects
        }
      }

      policy "angular/spec-exists" enabled=#false severity="warning"
      policy "angular/stub-exists"

      warnings "all"
    KDL
  end

  def test_writes_a_string_with_the_short_escape_kdl_has_for_each_character_that_has_one_and_u_for_the_rest
    setting = CrossLint::Core::Setting.new(name: "text", arguments: ["a\"b\\c\nd\te\rf\u0001g\u007fh\u0085i j k é"], properties: {}, children: [], line: 0)
    plugin = CrossLint::Core::ListedPlugin.new(name: "a", ref: nil, settings: [setting], line: 0)
    CrossLint::Adapters::KDLConfiguration.new.write(folder("project"),
      CrossLint::Core::Configuration.new(file: FILE, plugins: [plugin], policies: [], warnings: nil, verbosity: nil))

    assert_equal %(plugin "a" {\n  text "a\\"b\\\\c\\nd\\te\\rf\\u{1}g\\u{7f}h\\u{85}i\\u{2028}j\\u{2029}k é"\n}\n), File.read(File.join(@base, "project", FILE), encoding: Encoding::UTF_8)
  end

  def test_writes_a_value_that_is_not_a_string_as_kdl_does
    setting = CrossLint::Core::Setting.new(name: "limit", arguments: [nil, true], properties: {"on" => false}, children: [], line: 0)
    plugin = CrossLint::Core::ListedPlugin.new(name: "a", ref: nil, settings: [setting], line: 0)
    CrossLint::Adapters::KDLConfiguration.new.write(folder("project"),
      CrossLint::Core::Configuration.new(file: FILE, plugins: [plugin], policies: [], warnings: nil, verbosity: nil))

    assert_equal %(plugin "a" {\n  limit #null #true on=#false\n}\n), File.binread(File.join(@base, "project", FILE))
  end

  def test_refuses_to_write_a_value_that_kdl_has_no_use_for_here_and_writes_nothing
    setting = CrossLint::Core::Setting.new(name: "limit", arguments: [:three], properties: {}, children: [], line: 0)
    plugin = CrossLint::Core::ListedPlugin.new(name: "a", ref: nil, settings: [setting], line: 0)
    configuration = CrossLint::Core::Configuration.new(file: FILE, plugins: [plugin], policies: [], warnings: nil, verbosity: nil)
    error = assert_raises(ArgumentError) { CrossLint::Adapters::KDLConfiguration.new.write(folder("project"), configuration) }

    assert_equal "can't write :three as a KDL value", error.message
    refute File.exist?(File.join(@base, "project", FILE))
  end

  def test_leaves_the_file_as_it_was_when_the_system_denies_the_rename_of_a_write
    path = write(@base, "project/#{FILE}", %(plugin "#{URL}" ref="v1"\n))
    configuration = CrossLint::Core::Configuration.new(file: FILE, plugins: [], policies: [], warnings: nil, verbosity: nil)
    mistake = begin
      Thread.current[:crosslint_config_rename_denied] = true
      assert_raises(Mistake) { CrossLint::Adapters::KDLConfiguration.new.write(File.join(@base, "project"), configuration) }
    ensure
      Thread.current[:crosslint_config_rename_denied] = nil
    end

    assert_equal [FILE, nil, "couldn't be written, since permission was denied; close any program that has it open, and run again"],
      [mistake.file, mistake.line, mistake.message]
    assert_equal [%(plugin "#{URL}" ref="v1"\n), ["config.kdl"]], [File.binread(path), Dir.children(File.dirname(path))]
  end

  def test_names_a_folder_that_does_not_exist_when_it_asks_or_writes
    missing = File.join(@base, "missing")
    port = CrossLint::Adapters::KDLConfiguration.new
    configuration = CrossLint::Core::Configuration.new(file: FILE, plugins: [], policies: [], warnings: nil, verbosity: nil)

    assert_equal "no folder #{missing}", assert_raises(Mistake) { port.exist?(missing) }.message
    assert_equal "no folder #{missing}", assert_raises(Mistake) { port.write(missing, configuration) }.message
    refute File.exist?(missing)
  end

  def test_does_not_take_a_folder_named_like_the_configuration_for_one_it_has
    FileUtils.mkdir_p(File.join(@base, "app", FILE))

    refute CrossLint::Adapters::KDLConfiguration.new.exist?(File.join(@base, "app"))
  end

  def test_refuses_to_set_the_ref_of_a_plugin_that_has_none_or_one_it_cant_rewrite
    assert_refuses_to_set 2, %(plugin "#{URL}" has no ref= with a string to rewrite), %(warnings "all"\nplugin "#{URL}"\n)
    assert_refuses_to_set 1, %(plugin "#{URL}" has no ref= with a string to rewrite), %(plugin "#{URL}" ref=#null\n)
    assert_refuses_to_set 1, %(plugin "#{URL}" has no ref= with a string to rewrite), %(plugin "#{URL}" ref=1\n)
    assert_refuses_to_set 3, %(can't rewrite ref="v1\\nx", which isn't written as plain text between quotes on one line; write it as ref="v1\\nx"),
      %(warnings "all"\nplugin "#{URL}" \\\n  ref="""\n  v1\n  x\n  """\n)
    assert_refuses_to_set 1, %(can't rewrite ref="v1\\"x", which isn't written as plain text between quotes on one line; write it as ref="v1\\"x"),
      %(plugin "#{URL}" ref="v1\\"x"\n)
    assert_refuses_to_set 1, %(can't rewrite ref="v1", which isn't written as plain text between quotes on one line; write it as ref="v1"), %(plugin "#{URL}" ref=v1\n)
    assert_refuses_to_set 1, %(can't rewrite ref="v1.0.0", which isn't written as plain text between quotes on one line; write it as ref="v1.0.0"),
      %(plugin "#{URL}" ref="v\\u{31}.0.0"\n)
  end

  def test_leaves_the_file_as_it_was_when_one_of_its_refs_cant_be_rewritten
    text = %(plugin "#{URL}/a" ref="v1"\nplugin "#{URL}/b" ref=1\n)
    path = write(@base, "project/#{FILE}", text)

    assert_raises(Mistake) { set_refs_in("project", ["#{URL}/a", nil] => "v2", ["#{URL}/b", nil] => "v2") }
    assert_equal text, File.binread(path)
  end

  def test_names_the_file_when_it_sets_a_ref_in_a_project_with_no_configuration
    mistake = assert_raises(Mistake) { CrossLint::Adapters::KDLConfiguration.new.set_refs(File.join(@base, "nowhere"), {[URL, nil] => "v1"}) }

    assert_equal [FILE, "doesn't exist"], [mistake.file, mistake.message]
  end

  def test_refuses_to_set_a_ref_in_a_configuration_that_isnt_valid_kdl
    write(@base, "project/#{FILE}", %(plugin "#{URL}" ref="v1" {\n))
    mistake = assert_raises(Mistake) { set_refs_in("project", [URL, nil] => "v2") }

    assert_equal [FILE, 2], [mistake.file, mistake.line]
  end

  private

  # `text` as a configuration, after its plugins' refs are set.
  def set_refs(text, refs)
    write(@base, "project/#{FILE}", text)
    set_refs_in("project", refs)
    File.binread(File.join(@base, "project", FILE)).force_encoding(Encoding::UTF_8)
  end

  def set_refs_in(project, refs) = CrossLint::Adapters::KDLConfiguration.new.set_refs(File.join(@base, project), refs)

  def assert_refuses_to_set(line, message, text)
    write(@base, "project/#{FILE}", text)
    mistake = assert_raises(Mistake) { set_refs_in("project", [URL, nil] => "v2") }

    assert_equal [FILE, line, message], [mistake.file, mistake.line, mistake.message]
    assert_equal text, File.binread(File.join(@base, "project", FILE)), "the file changed"
  end

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
