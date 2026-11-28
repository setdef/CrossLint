# frozen_string_literal: true

require "test_helper"

class HelpTest < Minitest::Test
  cover "CrossLint::Help*"

  def test_renders_the_short_help
    assert_equal <<~HELP, CrossLint::Help.new(fixture_spec).short
      Does things

      Examples:
        Run it:
          Runs the thing once.
          $ tool run

          $ tool stop

      Run tool --help to list every command.
    HELP
  end

  def test_renders_only_the_first_two_examples_in_the_short_help
    source = File.read(File.join(__dir__, "..", "fixtures", "tool.usage.kdl"))
    spec = CrossLint::UsageSpec.new(source.sub(%(example "tool stop"\n), %(example "tool stop"\nexample "tool go"\n)))

    refute_includes CrossLint::Help.new(spec).short, "tool go"
    assert_includes CrossLint::Help.new(spec).render, "tool go"
  end

  def test_renders_the_programs_help
    assert_equal <<~HELP, CrossLint::Help.new(fixture_spec).render
      Tool 1.2.3

      Does things

      Usage: tool [FLAGS] [SUBCOMMAND]

      Commands:
        run   Run the thing
        stop  Stop the thing
        show  Show a thing
        help  Explain a command

      Flags:
        -v, --verbose       Say more
            --color <when>  Color the output
                            Choices: auto, never
                            Default: auto
        -h, --help          Print help
        -V, --version       Print version

      Examples:
        Run it:
          Runs the thing once.
          $ tool run

          $ tool stop

      Exit status:
        0   It worked.
        64  The command line has a mistake.
    HELP
  end

  def test_renders_a_commands_help
    assert_equal <<~HELP, CrossLint::Help.new(fixture_spec).render(fixture_spec.commands.first)
      Runs the thing.

      Then stops.

      Usage: tool run [FLAGS]

      Flags:
        -n, --dry-run      Do nothing
        -o, --out <file>   Writes the output to this file
            --mode <mode>  Pick a mode
                           Choices: only

      Global flags:
        -v, --verbose  Say more
        -h, --help     Print help
        -V, --version  Print version

      Examples:
        Try it:
          $ tool run -n

      Exit status:
        0   It worked.
        64  The command line has a mistake.
    HELP
  end

  def test_lists_the_commands_of_plugins_and_a_line_for_each_thing_that_keeps_one_from_showing_after_the_programs_commands
    help = CrossLint::Help.new(fixture_spec, plugins: plugins(notes: ["signatures isn't fetched yet"]))

    assert_includes help.render, <<~HELP
      Commands:
        run   Run the thing
        stop  Stop the thing
        show  Show a thing
        help  Explain a command

      Plugin commands:
        debt update                 Rewrite the debt file
        debt drop-paid-off-entries  Drop each entry no violation matches
        signatures isn't fetched yet

      Flags:
    HELP
  end

  def test_lists_the_commands_of_plugins_alone_when_there_is_no_note
    assert_includes CrossLint::Help.new(fixture_spec, plugins:).render, <<~HELP
      Plugin commands:
        debt update                 Rewrite the debt file
        debt drop-paid-off-entries  Drop each entry no violation matches

      Flags:
    HELP
  end

  def test_lists_only_the_notes_when_no_plugin_adds_a_command_and_wraps_them
    note = "#{'a' * 60} #{'b' * 60}"

    assert_includes CrossLint::Help.new(fixture_spec, plugins: plugins(commands: [], notes: [note])).render, "\n\nPlugin commands:\n  #{'a' * 60}\n  #{'b' * 60}\n\nFlags:\n"
  end

  def test_shows_no_plugin_section_when_there_is_nothing_to_say_of_plugins
    refute_includes CrossLint::Help.new(fixture_spec).render, "Plugin commands"
    refute_includes CrossLint::Help.new(fixture_spec, plugins: plugins(commands: [], notes: [])).render, "Plugin commands"
    refute_includes CrossLint::Help.new(fixture_spec, plugins:).render(fixture_spec.commands.first), "Plugin commands"
  end

  def test_renders_the_help_of_a_plugin
    assert_equal <<~HELP, CrossLint::Help.new(fixture_spec).plugin("debt", plugins.commands.map(&:last).take(2))
      The commands of the debt plugin

      Usage: tool debt COMMAND [FLAGS]

      Commands:
        update                 Rewrite the debt file
        drop-paid-off-entries  Drop each entry no violation matches

      Global flags:
        -v, --verbose  Say more
        -h, --help     Print help
        -V, --version  Print version
    HELP
  end

  def test_renders_the_help_of_a_plugins_command
    assert_equal <<~HELP, CrossLint::Help.new(fixture_spec).plugin_command("debt", plugins.commands.first.last)
      Rewrite the debt file

      Usage: tool debt update [FLAGS]

      Global flags:
        -v, --verbose  Say more
        -h, --help     Print help
        -V, --version  Print version
    HELP
  end

  def test_renders_the_flags_of_a_plugins_command_as_it_does_those_of_a_command_of_its_own
    flags = [
      CrossLint::Core::CommandFlag.new(short: "n", long: "dry-run", value: nil, help: "Write nothing", line: 2),
      CrossLint::Core::CommandFlag.new(short: nil, long: "since", value: "rev", help: "From a revision", line: 3),
]
    command = CrossLint::Core::CommandDeclaration.new(name: "update", help: "Rewrite the debt file", line: 1, flags:)

    assert_equal <<~HELP, CrossLint::Help.new(fixture_spec).plugin_command("debt", command)
      Rewrite the debt file

      Usage: tool debt update [FLAGS]

      Flags:
        -n, --dry-run      Write nothing
            --since <rev>  From a revision

      Global flags:
        -v, --verbose  Say more
        -h, --help     Print help
        -V, --version  Print version
    HELP
  end

  def test_has_no_plugin_commands_unless_it_is_given_some
    assert_equal CrossLint::Help::Plugins.new(commands: [], notes: []), CrossLint::Help::Plugins.none
  end

  def test_leaves_out_what_a_command_does_not_have
    assert_equal <<~HELP, CrossLint::Help.new(fixture_spec).render(fixture_spec.commands[1])
      Stop the thing

      Usage: tool stop [FLAGS]

      Global flags:
        -v, --verbose  Say more
        -h, --help     Print help
        -V, --version  Print version

      Exit status:
        0   It worked.
        64  The command line has a mistake.
    HELP
  end

  def test_shows_the_arguments_of_a_command
    assert_equal <<~HELP, CrossLint::Help.new(fixture_spec).render(fixture_spec.commands[2])
      Show a thing

      Usage: tool show [FLAGS] [thing]

      Arguments:
        [thing]  The thing to show

      Global flags:
        -v, --verbose  Say more
        -h, --help     Print help
        -V, --version  Print version

      Exit status:
        0   It worked.
        64  The command line has a mistake.
    HELP
  end

  def test_shows_the_long_about_and_the_text_after_the_help_as_written
    spec = CrossLint::UsageSpec.new(<<~KDL)
      name "Tool"
      bin "tool"
      version "1"
      about "Short"
      long_about "One line\\n\\n  Indented line"
      after_long_help "Last\\nlines"
    KDL

    assert_equal <<~HELP, CrossLint::Help.new(spec).render
      Tool 1

      One line

      Indented line

      Usage: tool [FLAGS] [SUBCOMMAND]

      Flags:
        -h, --help     Print help
        -V, --version  Print version

      Last
      lines
    HELP
  end

  def test_wraps_a_line_wider_than_100_columns_between_words
    exactly = "#{'a' * 98} b"
    spec = CrossLint::UsageSpec.new(<<~KDL)
      name "Tool"
      bin "tool"
      version "1"
      about "#{exactly} c"
      flag "--x" help="#{'d' * 81} e f"
      example "tool" help="#{'g' * 94} h"
    KDL
    lines = CrossLint::Help.new(spec).render.lines(chomp: true)

    assert_equal [exactly, "c"], lines[2..3]
    assert_includes lines, "      --x        #{'d' * 81} e"
    assert_includes lines, "#{' ' * 17}f"
    assert_includes lines, "    #{'g' * 94} h"
  end

  def test_wraps_a_line_one_column_too_wide
    spec = CrossLint::UsageSpec.new(<<~KDL)
      name "Tool"
      bin "tool"
      version "1"
      about "#{'a' * 98} bc"
      example "tool" help="#{'g' * 94} hi"
    KDL
    lines = CrossLint::Help.new(spec).render.lines(chomp: true)

    assert_equal ["a" * 98, "bc"], lines[2..3]
    assert_includes lines, "    #{'g' * 94}"
    assert_includes lines, "    hi"
  end

  def test_ends_no_line_with_a_space
    spec = CrossLint::UsageSpec.new(%(name "T"\nbin "t"\nversion "1"\nabout "a"\nflag "--x" help="b\\n\\nc  "))

    assert_includes CrossLint::Help.new(spec).render, "      --x        b\n\n#{' ' * 17}c\n"
  end

  def test_shows_a_flag_with_empty_help_by_its_name_alone
    spec = CrossLint::UsageSpec.new(%(name "T"\nbin "t"\nversion "1"\nabout "a"\nflag "--x" help=""))

    assert_includes CrossLint::Help.new(spec).render, "Flags:\n      --x\n"
  end

  def test_keeps_a_word_wider_than_a_line_whole
    spec = CrossLint::UsageSpec.new(%(name "T"\nbin "t"\nversion "1"\nabout "x #{'a' * 120} y"))

    assert_equal ["x", "a" * 120, "y"], CrossLint::Help.new(spec).render.lines(chomp: true)[2..4]
  end

  def test_the_shipped_help_has_every_text_of_the_spec
    spec = shipped_spec
    help = CrossLint::Help.new(spec)
    pages = [help.render, *spec.commands.map { |command| help.render(command) }]
    texts = [
      spec.long_about,
      spec.after_long_help,
      *spec.commands.flat_map { |command| [command.help, command.long_help] },
      *(spec.flags + spec.commands.flat_map(&:flags)).flat_map { |flag| [flag.long_help || flag.help, *flag.choices] },
      *(spec.examples + spec.commands.flat_map(&:examples)).flat_map { |example| [example.code, example.header, example.help] },
      *spec.commands.flat_map(&:arguments).flat_map { |argument| [argument.name, argument.help] },
      *spec.exit_codes.map(&:meaning),
].compact

    texts.each { |text| assert_includes squeeze(pages.join), squeeze(text) }
    pages.each do |page|
      assert_predicate page, :ascii_only?
      assert_operator page.lines.map { |line| line.chomp.size }.max, :<=, CrossLint::Help::WIDTH
    end
  end

  private

  # +text+ with every run of spaces and line breaks as one space, so that
  # wrapping doesn't matter.
  def squeeze(text) = text.gsub(/\s+/, " ")

  def plugins(commands: nil, notes: [])
    core = CrossLint::Core
    update = core::CommandDeclaration.new(name: "update", help: "Rewrite the debt file", line: 1)
    prune = core::CommandDeclaration.new(name: "drop-paid-off-entries", help: "Drop each entry no violation matches", line: 2)
    CrossLint::Help::Plugins.new(commands: commands || [["debt", update], ["debt", prune]], notes:)
  end
end
