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

  def example_configuration_port
    core = CrossLint::Core
    plugins = [
      core::ListedPlugin.new(name: "https://github.com/OWNER/REPO", ref: "v1.2.0", settings: [], line: 1),
      core::ListedPlugin.new(name: "angular", ref: nil, line: 2, settings: [
        core::Setting.new(name: "src-dir", arguments: ["src"], properties: {}, children: [], line: 3),
        core::Setting.new(name: "role", arguments: ["store"], properties: {"files" => "{path}.store.ts"}, line: 4,
          children: [core::Setting.new(name: "expects", arguments: ["spec"], properties: {}, children: [], line: 5)])
      ]),
      core::ListedPlugin.new(name: ".config/crosslint/signatures", ref: nil, settings: [], line: 8)
    ]
    policies = [
      core::PolicySetting.new(name: "angular/prefer-css-over-scss", enabled: nil, severity: :error, line: 9),
      core::PolicySetting.new(name: "angular/spec-exists", enabled: nil, severity: :warning, line: 10),
      core::PolicySetting.new(name: "signatures/has-test", enabled: false, severity: nil, line: 11)
    ]
    configuration = core::Configuration.new(file: FILE, plugins:, policies:, warnings: :error, verbosity: :silent)
    CrossLint::Adapters::MemoryConfiguration.new({folder("example") => configuration})
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
