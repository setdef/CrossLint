# frozen_string_literal: true

require "test_helper"

# Core::InitConfiguration against the in-memory configuration port.
class InitConfigurationTest < Minitest::Test
  cover "CrossLint::Core::InitConfiguration*"
  cover "CrossLint::Core::InitResult*"

  Core = CrossLint::Core

  FILE = ".config/crosslint/config.kdl"
  APP = File.expand_path("/app")

  def test_writes_a_configuration_that_lists_the_recommended_plugins
    port = CrossLint::Adapters::MemoryConfiguration.new
    result = Core::InitConfiguration.new(configuration: port).call(APP)

    assert_equal [FILE, ["debt"], [["debt", nil, [], 1]]], [result.file, result.plugins, port.read(APP).plugins.map { |plugin| [plugin.name, plugin.ref, plugin.settings, plugin.line] }]
    assert_equal ["wrote #{FILE}, with the recommended plugins: debt"], result.lines
    assert_empty port.read(APP).policies
    assert_equal [FILE, nil, nil], [port.read(APP).file, port.read(APP).warnings, port.read(APP).verbosity]
  end

  def test_refuses_to_replace_a_configuration_and_leaves_it_as_it_is
    port = project("one")
    mistake = assert_raises(Core::Mistake) { Core::InitConfiguration.new(configuration: port).call(APP) }

    assert_equal [FILE, "already exists, and crosslint init changes nothing in it; crosslint init --force replaces it"], [mistake.file, mistake.message]
    assert_equal ["one"], port.read(APP).plugins.map(&:name)
  end

  def test_refuses_to_replace_a_configuration_even_to_list_what_it_would_do
    assert_raises(Core::Mistake) { Core::InitConfiguration.new(configuration: project("one")).call(APP, dry_run: true) }
  end

  def test_replaces_a_configuration_with_force
    port = project("one")
    result = Core::InitConfiguration.new(configuration: port).call(APP, force: true)

    assert_equal ["replaced #{FILE}, with the recommended plugins: debt"], result.lines
    assert_equal ["debt"], port.read(APP).plugins.map(&:name)
  end

  def test_lists_what_it_would_write_and_writes_nothing_with_dry_run
    port = CrossLint::Adapters::MemoryConfiguration.new
    result = Core::InitConfiguration.new(configuration: port).call(APP, dry_run: true)

    assert_equal ["would write #{FILE}, with the recommended plugins: debt"], result.lines
    refute port.exist?(APP)
  end

  def test_lists_what_it_would_replace_with_force_and_dry_run
    port = project("one")
    result = Core::InitConfiguration.new(configuration: port).call(APP, force: true, dry_run: true)

    assert_equal ["would replace #{FILE}, with the recommended plugins: debt"], result.lines
    assert_equal ["one"], port.read(APP).plugins.map(&:name)
  end

  def test_lists_each_plugin_a_result_has_with_a_comma_between_them
    result = Core::InitResult.new(file: FILE, plugins: %w[debt other], replaced: false, dry_run: false)

    assert_equal ["wrote #{FILE}, with the recommended plugins: debt, other"], result.lines
  end

  private

  def project(*plugins)
    listed = plugins.each_with_index.map { |name, index| Core::ListedPlugin.new(name:, ref: nil, settings: [], line: index + 1) }
    CrossLint::Adapters::MemoryConfiguration.new({APP => Core::Configuration.new(file: FILE, plugins: listed, policies: [], warnings: nil, verbosity: nil)})
  end
end
