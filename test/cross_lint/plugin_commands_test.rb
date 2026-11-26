# frozen_string_literal: true

require "test_helper"

class PluginCommandsTest < Minitest::Test
  cover "CrossLint::PluginCommands*"

  Core = CrossLint::Core

  FILE = ".config/crosslint/config.kdl"

  def setup
    @debt = plugin("debt", "update" => "Rewrite the debt file", "prune" => "Drop stale entries")
    @plain = plugin("signatures")
    @commands = CrossLint::PluginCommands.new(shipped_spec)
  end

  def test_finds_the_plugin_and_its_command
    found = @commands.find(%w[debt update], [@plain, @debt], FILE, -> { {} })

    assert_equal [@debt, "update"], [found.first, found.last.name]
    assert_equal @debt.manifest.commands.last, @commands.find(%w[debt prune], [@plain, @debt], FILE, -> { {} }).last
  end

  def test_finds_the_plugin_alone_when_no_command_is_given
    assert_equal [@debt, nil], @commands.find(%w[debt], [@plain, @debt], FILE, -> { {} })
  end

  def test_says_a_plugin_that_adds_no_commands_adds_none
    assert_refused "signatures is a plugin the configuration lists, and it adds no commands", %w[signatures update]
    assert_refused "signatures is a plugin the configuration lists, and it adds no commands", %w[signatures]
  end

  def test_names_the_nearest_command_of_a_plugin_or_lists_them
    assert_refused "crosslint debt has no command updat; did you mean update?", %w[debt updat]
    assert_refused "crosslint debt has no command zzzzzz; its commands are update and prune", %w[debt zzzzzz]
    assert_refused %(crosslint debt has no command "x y"; its commands are update and prune), ["debt", "x y"]
  end

  def test_refuses_a_word_after_the_command
    assert_refused "crosslint debt update takes no arguments; remove extra", %w[debt update extra]
    assert_refused %(crosslint debt update takes no arguments; remove "x y"), ["debt", "update", "x y", "more"]
  end

  def test_says_which_configuration_lacks_the_built_in_plugin_a_command_belongs_to
    built_in = -> { {"debt" => %w[update prune], "angular" => []} }

    assert_refused "debt update is a command of the debt plugin, which #{FILE} doesn't list", %w[debt update], plugins: [@plain], built_in: built_in
    assert_refused "debt prune is a command of the debt plugin, which #{FILE} doesn't list", %w[debt prune], plugins: [], built_in: built_in
    assert_refused "crosslint has no command debt, and the configuration lists no plugin of that name; crosslint --help lists the commands", %w[debt other],
      plugins: [@plain], built_in: built_in
    assert_refused "crosslint has no command debt, and the configuration lists no plugin of that name; crosslint --help lists the commands", %w[debt],
      plugins: [@plain], built_in: built_in
  end

  def test_names_the_nearest_command_of_crosslint_and_the_nearest_plugin_of_the_project
    assert_refused "crosslint has no command chek, and the configuration lists no plugin of that name; did you mean check?", %w[chek], plugins: [@plain]
    assert_refused "crosslint has no command deb, and the configuration lists no plugin of that name; did you mean debt?", %w[deb update]
    assert_refused "crosslint has no command updat, and the configuration lists no plugin of that name; did you mean update?", %w[updat], plugins: [@plain, @debt]
    assert_refused "crosslint has no command intt, and the configuration lists no plugin of that name; did you mean init?", %w[intt]
    assert_refused "crosslint has no command sinatures, and the configuration lists no plugin of that name; crosslint --help lists the commands", %w[sinatures]
    assert_refused %(crosslint has no command "x y", and the configuration lists no plugin of that name; crosslint --help lists the commands), ["x y"]
    both = plugin("chec2", "do" => "Does it")

    assert_refused "crosslint has no command chec, and the configuration lists no plugin of that name; did you mean check or chec2?", %w[chec], plugins: [both]
  end

  def test_names_the_nearest_command_of_crosslint_for_a_word_when_the_project_cant_be_read
    refusal = @commands.refusal("chek")

    assert_instance_of CrossLint::CommandLine::Error, refusal
    assert_equal "crosslint has no command chek; did you mean check?", refusal.message
    assert_nil @commands.refusal("debt")
    assert_equal %(crosslint has no command "ch\\u00E9ck"; did you mean check?), @commands.refusal("ch\u00E9ck").message
  end

  private

  def plugin(name, commands = {})
    declared = commands.each_with_index.map { |(command, help), index| Core::CommandDeclaration.new(name: command, help:, line: index + 1) }
    manifest = Core::Manifest.new(file: "#{name}/plugin.kdl", artifacts: [], policies: [], rules: [], helpers: [], commands: declared)
    Core::Plugin.new(name:, folder: "/x/#{name}", manifest:, listing: Core::ListedPlugin.new(name:, ref: nil, settings: [], line: 1))
  end

  def assert_refused(message, words, plugins: [@plain, @debt], built_in: -> { {} })
    error = assert_raises(CrossLint::CommandLine::Error) { @commands.find(words, plugins, FILE, built_in) }

    assert_equal message, error.message
  end
end
