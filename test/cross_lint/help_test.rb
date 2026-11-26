# frozen_string_literal: true

require "test_helper"

class HelpTest < Minitest::Test
  cover "CrossLint::Help*"

  def test_renders_the_programs_help
    assert_equal <<~HELP, CrossLint::Help.new(fixture_spec).render
      Tool 1.2.3

      Does things

      Usage: tool [FLAGS] [SUBCOMMAND]

      Commands:
        run   Run the thing
        stop  Stop the thing

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

  def test_leaves_out_what_a_command_does_not_have
    assert_equal <<~HELP, CrossLint::Help.new(fixture_spec).render(fixture_spec.commands.last)
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
    exactly = "#{"a" * 98} b"
    spec = CrossLint::UsageSpec.new(<<~KDL)
      name "Tool"
      bin "tool"
      version "1"
      about "#{exactly} c"
      flag "--x" help="#{"d" * 81} e f"
      example "tool" help="#{"g" * 94} h"
    KDL
    lines = CrossLint::Help.new(spec).render.lines(chomp: true)

    assert_equal [exactly, "c"], lines[2..3]
    assert_includes lines, "      --x        #{"d" * 81} e"
    assert_includes lines, "#{" " * 17}f"
    assert_includes lines, "    #{"g" * 94} h"
  end

  def test_wraps_a_line_one_column_too_wide
    spec = CrossLint::UsageSpec.new(<<~KDL)
      name "Tool"
      bin "tool"
      version "1"
      about "#{"a" * 98} bc"
      example "tool" help="#{"g" * 94} hi"
    KDL
    lines = CrossLint::Help.new(spec).render.lines(chomp: true)

    assert_equal ["a" * 98, "bc"], lines[2..3]
    assert_includes lines, "    #{"g" * 94}"
    assert_includes lines, "    hi"
  end

  def test_ends_no_line_with_a_space
    spec = CrossLint::UsageSpec.new(%(name "T"\nbin "t"\nversion "1"\nabout "a"\nflag "--x" help="b\\n\\nc  "))

    assert_includes CrossLint::Help.new(spec).render, "      --x        b\n\n#{" " * 17}c\n"
  end

  def test_keeps_a_word_wider_than_a_line_whole
    spec = CrossLint::UsageSpec.new(%(name "T"\nbin "t"\nversion "1"\nabout "x #{"a" * 120} y"))

    assert_equal ["x", "a" * 120, "y"], CrossLint::Help.new(spec).render.lines(chomp: true)[2..4]
  end

  def test_the_shipped_help_has_every_text_of_the_spec
    spec = shipped_spec
    help = CrossLint::Help.new(spec)
    pages = [help.render, *spec.commands.map { |command| help.render(command) }]
    texts = [spec.long_about, spec.after_long_help, *spec.commands.flat_map { |command| [command.help, command.long_help] },
      *(spec.flags + spec.commands.flat_map(&:flags)).flat_map { |flag| [flag.long_help || flag.help, *flag.choices] },
      *(spec.examples + spec.commands.flat_map(&:examples)).flat_map { |example| [example.code, example.header, example.help] },
      *spec.exit_codes.map(&:meaning)].compact

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
end
