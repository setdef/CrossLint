# frozen_string_literal: true

require "test_helper"

class UsageSpecTest < Minitest::Test
  cover "CrossLint::UsageSpec*"

  Spec = CrossLint::UsageSpec

  # The texts every spec has, for a spec that tests something else.
  TOP = %(name "T"\nbin "t"\nversion "1"\nabout "a"\n)

  def test_reads_the_texts_at_the_top
    spec = fixture_spec

    assert_equal ["2.0.0", "Tool", "tool", "1.2.3", "Someone", "MIT", "https://example.com/tool", "Does things"],
      [spec.min_usage_version, spec.name, spec.bin, spec.version, spec.author, spec.license, spec.repository, spec.about]
    assert_nil spec.long_about
    assert_nil spec.after_long_help
  end

  def test_reads_the_top_level_flags
    assert_equal [
      Spec::Flag.new(short: "v", long: "verbose", value: nil, help: "Say more", long_help: nil, choices: nil,
        default: nil, global: true),
      Spec::Flag.new(short: nil, long: "color", value: "when", help: "Color the output", long_help: nil,
        choices: ["auto", "never"], default: "auto", global: false)
    ], fixture_spec.flags
  end

  def test_global_flags_are_those_marked_global
    assert_equal ["verbose"], fixture_spec.global_flags.map(&:long)
  end

  def test_reads_commands_with_their_flags_and_examples
    run, stop = fixture_spec.commands

    assert_equal Spec::Command.new(name: "run", help: "Run the thing", long_help: "Runs the thing.\n\nThen stops.",
      flags: [
        Spec::Flag.new(short: "n", long: "dry-run", value: nil, help: "Do nothing", long_help: nil, choices: nil,
          default: nil, global: false),
        Spec::Flag.new(short: "o", long: "out", value: "file", help: "Write here",
          long_help: "Writes the output to this file", choices: nil, default: nil, global: false),
        Spec::Flag.new(short: nil, long: "mode", value: "mode", help: "Pick a mode", long_help: nil,
          choices: ["only"], default: nil, global: false)
      ],
      examples: [Spec::Example.new(code: "tool run -n", header: "Try it", help: nil)]), run
    assert_equal Spec::Command.new(name: "stop", help: "Stop the thing", long_help: nil, flags: [], examples: []), stop
  end

  def test_reads_examples_and_exit_codes
    spec = fixture_spec

    assert_equal [
      Spec::Example.new(code: "tool run", header: "Run it", help: "Runs the thing once."),
      Spec::Example.new(code: "tool stop", header: nil, help: nil)
    ], spec.examples
    assert_equal [Spec::ExitCode.new(code: 0, meaning: "It worked."),
      Spec::ExitCode.new(code: 64, meaning: "The command line has a mistake.")], spec.exit_codes
  end

  def test_reads_plain_strings_and_integers
    spec = fixture_spec
    run = spec.commands.first
    values = [spec.bin, run.name, run.flags.first.long, spec.examples.first.code, spec.exit_codes.first.meaning,
      spec.flags.last.choices.first, spec.flags.last.default, spec.exit_codes.first.code]

    assert_equal [String] * 7 + [Integer], values.map(&:class)
  end

  def test_leaves_out_what_a_node_does_not_give
    spec = Spec.new(%(#{TOP}cmd "a" help="A"\nflag "--b" help="B"))

    assert_nil spec.min_usage_version
    assert_equal Spec::Command.new(name: "a", help: "A", long_help: nil, flags: [], examples: []), spec.commands.first
    assert_equal Spec::Flag.new(short: nil, long: "b", value: nil, help: "B", long_help: nil, choices: nil,
      default: nil, global: false), spec.flags.first
  end

  def test_refuses_a_spec_without_the_texts_the_help_shows
    assert_refuses "the spec has no name, which the help shows", %(bin "t"\nversion "1"\nabout "a")
    assert_refuses "the spec has no bin, which the help shows", %(name "T"\nversion "1"\nabout "a")
    assert_refuses "the spec has no version, which the help shows", %(name "T"\nbin "t"\nabout "a")
    assert_refuses "the spec has no about, which the help shows", %(name "T"\nbin "t"\nversion "1")
  end

  def test_refuses_a_command_or_flag_without_help
    assert_refuses %(cmd "a" has no help=, which the help shows), %(#{TOP}cmd "a")
    assert_refuses %(flag "-b --b" has no help=, which the help shows), %(#{TOP}flag "-b --b")
    assert_refuses %(flag "--c" has no help=, which the help shows), %(#{TOP}cmd "a" help="A" { flag "--c"; })
  end

  def test_a_flag_shows_how_it_is_written
    flags = fixture_spec.flags

    assert_equal ["--verbose", "--color <when>"], flags.map(&:usage)
  end

  def test_loads_the_spec_beside_lib_by_default
    assert_equal File.join(ROOT, "crosslint.usage.kdl"), Spec::PATH
    assert_equal "crosslint", shipped_spec.bin
  end

  def test_the_shipped_spec_has_the_version_the_gemspec_reads
    assert_equal File.read(Spec::PATH)[/^version "([^"]+)"$/, 1], shipped_spec.version
    assert_equal Gem::Specification.load(File.join(ROOT, "cross_lint.gemspec")).version.to_s, shipped_spec.version
  end

  def test_the_shipped_spec_has_three_commands_and_global_flags
    spec = shipped_spec

    assert_equal %w[check init update], spec.commands.map(&:name)
    assert_equal %w[quiet silent no-color debug project], spec.global_flags.map(&:long)
    assert_equal [0, 1, 2, 130], spec.exit_codes.map(&:code)
  end

  def test_refuses_a_node_it_does_not_read
    assert_refuses "hidden is a node CrossLint doesn't read", %(hidden "x")
    assert_refuses "hidden is a node CrossLint doesn't read", %(flag "--a" { hidden #true; })
    assert_refuses "hidden is a node CrossLint doesn't read", %(cmd "a" { hidden #true; })
    assert_refuses "hidden is a node CrossLint doesn't read", %(example "a" { hidden #true; })
    assert_refuses "hidden is a node CrossLint doesn't read", %(exit_code 0 "a" { hidden #true; })
    assert_refuses "hidden is a node CrossLint doesn't read", %(about "a" { hidden #true; })
    assert_refuses "hidden is a node CrossLint doesn't read", %(flag "--a <b>" { choices "c" { hidden #true; }; })
  end

  def test_refuses_a_property_it_does_not_read
    assert_refuses "about has hide=, which CrossLint doesn't read", %(about "a" hide=#true)
    assert_refuses "flag has hide=, which CrossLint doesn't read", %(flag "--a" hide=#true)
    assert_refuses "cmd has hide=, which CrossLint doesn't read", %(cmd "a" hide=#true)
    assert_refuses "example has hide=, which CrossLint doesn't read", %(example "a" hide=#true)
    assert_refuses "exit_code has hide=, which CrossLint doesn't read", %(exit_code 0 "a" hide=#true)
    assert_refuses "default has hide=, which CrossLint doesn't read", %(flag "--a <b>" { default "c" hide=#true; })
  end

  def test_refuses_the_wrong_number_of_arguments
    assert_refuses "about has 2 arguments, and CrossLint reads 1", %(about "a" "b")
    assert_refuses "exit_code has 1 arguments, and CrossLint reads 2", %(exit_code 0)
    assert_refuses "cmd has 0 arguments, and CrossLint reads 1", %(cmd)
    assert_refuses "example has 2 arguments, and CrossLint reads 1", %(example "a" "b")
    assert_refuses "flag has 0 arguments, and CrossLint reads 1", %(flag)
  end

  def test_refuses_a_flag_it_cannot_read
    assert_refuses %(flag "-q --quiet [x]" has "[x]", which CrossLint doesn't read), %(flag "-q --quiet [x]")
    assert_refuses %(flag "-qq --quiet" has "-qq", which CrossLint doesn't read), %(flag "-qq --quiet")
    assert_refuses %(flag "--Quiet" has "--Quiet", which CrossLint doesn't read), %(flag "--Quiet")
    assert_refuses %(flag "--quiet <X>" has "<X>", which CrossLint doesn't read), %(flag "--quiet <X>")
    assert_refuses %(flag "-q" has no long name), %(flag "-q")
  end

  def test_reads_flag_names_of_letters_digits_and_dashes
    flag, = Spec.new(%(#{TOP}flag "-0 --dry-run2 <out_file-2>" help="x")).flags

    assert_equal ["0", "dry-run2", "out_file-2"], [flag.short, flag.long, flag.value]
    assert_equal "Z", Spec.new(%(#{TOP}flag "-Z --z" help="x")).flags.first.short
  end

  def test_refuses_unknown_flags_other_than_error
    assert_refuses %(unknown_flags is "warn", and CrossLint only stops at an unknown flag), %(unknown_flags "warn")
    assert_equal "a", Spec.new(%(#{TOP}unknown_flags "error")).about
  end

  private

  def assert_refuses(message, source)
    error = assert_raises(Spec::Error) { Spec.new(source) }

    assert_equal message, error.message
  end
end
