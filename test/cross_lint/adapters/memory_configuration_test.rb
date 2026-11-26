# frozen_string_literal: true

require "test_helper"

class MemoryConfigurationTest < Minitest::Test
  cover "CrossLint::Adapters::MemoryConfiguration*"

  include CrossLint::Testing::ConfigurationContract

  FILE = ".config/crosslint.kdl"

  def configuration_port(projects, broken: nil)
    held = projects.to_h do |project, plugins|
      listed = plugins.each_with_index.map { |name, index| CrossLint::Core::ListedPlugin.new(name:, ref: nil, settings: [], line: index + 1) }
      [folder(project), CrossLint::Core::Configuration.new(file: FILE, plugins: listed, policies: [], warnings: nil, verbosity: nil)]
    end
    held[folder(broken)] = CrossLint::Core::Mistake.new("unknown node", file: FILE, line: 2) if broken
    CrossLint::Adapters::MemoryConfiguration.new(held)
  end

  def folder(path) = File.join("/memory", path)

  def root_outside = nil

  def test_holds_no_project_unless_it_is_given_some
    port = CrossLint::Adapters::MemoryConfiguration.new
    mistake = assert_raises(CrossLint::Core::Mistake) { port.read("/memory/app") }

    assert_nil port.find_root("/memory/app")
    assert_equal [FILE, "doesn't exist"], [mistake.file, mistake.message]
  end

  def test_raises_a_mistake_of_any_kind_it_holds
    kind = Class.new(CrossLint::Core::Mistake)
    port = CrossLint::Adapters::MemoryConfiguration.new({"/memory/app" => kind.new("broken")})

    assert_raises(kind) { port.read("/memory/app") }
  end

  def test_names_the_file_it_is_given
    assert_equal "crosslint.json", CrossLint::Adapters::MemoryConfiguration.new(file: "crosslint.json").file
    assert_equal FILE, CrossLint::Adapters::MemoryConfiguration.new.file
  end
end
