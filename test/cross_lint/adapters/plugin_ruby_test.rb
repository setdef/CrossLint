# frozen_string_literal: true

require "test_helper"

class FilePluginRubyTest < Minitest::Test
  cover "CrossLint::Adapters::FilePluginRuby*"

  include CrossLint::Testing::PluginRubyContract

  def setup
    @base = Dir.mktmpdir("crosslint")
  end

  def teardown
    FileUtils.rm_rf(@base)
  end

  def plugin_ruby_port(files)
    files.each { |path, source| write(@base, path, source) }
    CrossLint::Adapters::FilePluginRuby.new
  end

  def plugin_base = @base

  def test_runs_a_file_that_requires_another_in_the_plugins_folder
    port = plugin_ruby_port({"tests/rules/a.rb" => %(require_relative "../lib/names"\nclass A < CrossLint::Rule\n  NAME = PluginRubyTestNames.call\nend\n),
                             "tests/lib/names.rb" => "PluginRubyTestNames = -> { \"a\" }\n"})
    namespace = Module.new
    port.load(ruby_plugin("tests"), "rules/a.rb", 3, namespace)

    assert_equal "a", namespace.const_get(:A, false)::NAME
  end

  def test_raises_the_load_error_of_a_gem_crosslint_wasnt_built_with
    port = plugin_ruby_port({"tests/a.rb" => %(require "crosslint_no_such_gem"\n)})
    error = assert_raises(LoadError) { port.load(ruby_plugin("tests"), "a.rb", 3, Module.new) }

    assert_equal "crosslint_no_such_gem", error.path
  end

  def test_takes_a_folder_for_no_file
    FileUtils.mkdir_p(File.join(@base, "tests/rules"))

    assert_raises(CrossLint::Core::Mistake) { CrossLint::Adapters::FilePluginRuby.new.load(ruby_plugin("tests"), "rules", 3, Module.new) }
  end
end

class MemoryPluginRubyTest < Minitest::Test
  cover "CrossLint::Adapters::MemoryPluginRuby*"

  include CrossLint::Testing::PluginRubyContract

  def plugin_ruby_port(files)
    CrossLint::Adapters::MemoryPluginRuby.new(files.to_h do |path, source|
      [File.join(plugin_base, path), ->(namespace) { namespace.module_eval(source, File.join(plugin_base, path), 1) }]
    end)
  end

  def plugin_base = File.expand_path("/memory/plugins")

  def test_holds_no_file_unless_it_is_given_some
    assert_raises(CrossLint::Core::Mistake) { CrossLint::Adapters::MemoryPluginRuby.new.load(ruby_plugin("tests"), "a.rb", 1, Module.new) }
  end
end
