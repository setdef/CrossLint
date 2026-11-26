# frozen_string_literal: true

require "test_helper"

class CommandLineTest < Minitest::Test
  cover "CrossLint::CommandLine*"

  def test_with_no_words_it_runs_no_command_with_the_defaults
    line = read

    assert_equal [:run, nil, {"color" => "auto"}], [line.action, line.command, line.flags]
  end

  def test_names_a_command
    line = read("run")

    assert_equal [:run, "run", {}], [line.action, line.command.name, line.flags]
  end

  def test_reads_long_flags
    assert_equal({"verbose" => true, "dry-run" => true}, read("--verbose", "run", "--dry-run").flags)
  end

  def test_reads_a_long_flag_value_after_an_equals_sign_or_in_the_next_word
    assert_equal({"out" => "a=b"}, read("run", "--out=a=b").flags)
    assert_equal({"out" => "x"}, read("run", "--out", "x").flags)
    assert_equal({"out" => "--dry-run"}, read("run", "--out", "--dry-run").flags)
    assert_equal({"out" => "x", "dry-run" => true}, read("run", "--out", "x", "-n").flags)
    assert_equal({"out" => "x", "dry-run" => true}, read("run", "-o", "x", "-n").flags)
  end

  def test_reads_short_flags_alone_or_together
    assert_equal({"verbose" => true, "dry-run" => true}, read("run", "-v", "-n").flags)
    assert_equal({"verbose" => true, "dry-run" => true}, read("run", "-vn").flags)
  end

  def test_reads_a_short_flag_value_in_the_same_word_or_the_next
    assert_equal({"out" => "x"}, read("run", "-o", "x").flags)
    assert_equal({"out" => "nv"}, read("run", "-onv").flags)
    assert_equal({"dry-run" => true, "out" => "x"}, read("run", "-no", "x").flags)
  end

  def test_a_value_given_wins_over_the_default
    assert_equal({"color" => "never"}, read("--color", "never").flags)
  end

  def test_checks_a_value_against_the_choices
    assert_error "--color takes auto or never, not bad", "--color=bad"
    assert_error "--mode takes only, not other", "run", "--mode", "other"
    assert_error "--warnings takes all, none, or error, not some", "check", "--warnings=some", spec: shipped_spec
    assert_equal({"mode" => "only"}, read("run", "--mode", "only").flags)
  end

  def test_a_flag_that_takes_a_value_needs_one
    assert_error "--out takes a value, as in --out <file>", "run", "--out"
    assert_error "--out takes a value, as in --out <file>", "run", "-o"
  end

  def test_a_flag_that_takes_no_value_refuses_one
    assert_error "--verbose takes no value; remove =yes", "--verbose=yes"
    assert_error "--verbose takes no value; remove =\"\"", "--verbose="
  end

  def test_asks_for_help_or_the_version_and_reads_no_further
    assert_equal [:help, nil], action_and_command("--help", "--bogus")
    assert_equal [:help, nil], action_and_command("-h")
    assert_equal [:help, "run"], action_and_command("run", "--help")
    assert_equal [:help, "run"], action_and_command("run", "-nhx")
    assert_equal [:version, nil], action_and_command("--version", "bogus")
    assert_equal [:version, "run"], action_and_command("run", "-V")
  end

  def test_help_and_version_are_no_flags_of_their_own
    assert_equal({"color" => "auto"}, read("--help").flags)
    assert_equal({"color" => "auto"}, read("-V").flags)
  end

  def test_takes_every_word_after_a_double_dash_as_an_argument
    assert_equal "run", read("--", "run").command.name
    assert_error "tool run takes no arguments; remove --help", "run", "--", "--help"
  end

  def test_refuses_an_argument_after_the_command
    assert_error "tool run takes no arguments; remove extra", "run", "extra"
  end

  def test_refuses_a_command_it_does_not_have
    assert_error "tool has no command runn; did you mean run?", "runn"
    assert_error "tool has no command -; tool --help lists them", "-"
    assert_error "tool has no command zzzzzz; tool --help lists them", "zzzzzz"
  end

  def test_refuses_a_flag_it_does_not_have
    assert_error "tool has no flag --verbos; did you mean --verbose?", "--verbos"
    assert_error "tool has no flag -x; tool --help lists them", "-x"
    assert_error "tool run has no flag --dryrun; did you mean --dry-run?", "run", "--dryrun"
    assert_error "tool run has no flag -x; tool run --help lists them", "run", "-nx"
  end

  def test_suggests_a_one_letter_flag
    assert_error "tool run has no flag -N; did you mean -n?", "run", "-N"
  end

  def test_knows_only_the_top_level_flags_before_a_command
    assert_error "tool has no flag --dry-run; tool --help lists them", "--dry-run", "run"
    assert_error "tool run has no flag --color; tool run --help lists them", "run", "--color", "never"
  end

  def test_lists_the_flags_it_knows_where_it_is
    assert_equal %w[verbose color help version], CrossLint::CommandLine.new(fixture_spec, []).known_flags.map(&:long)
    assert_equal %w[dry-run out mode verbose help version],
      CrossLint::CommandLine.new(fixture_spec, ["run"]).known_flags.map(&:long)
  end

  def test_quotes_a_word_that_is_not_printable_ascii
    assert_error "tool has no flag \"--v\\u00E9rbose\"; did you mean --verbose?", "--vérbose"
    assert_error 'tool has no command "x y"; tool --help lists them', "x y"
    assert_error 'tool has no command "\xFF"; tool --help lists them', "\xFF".b
    assert_error 'tool run takes no arguments; remove "x y"', "run", "x y"
    assert_error '--color takes auto or never, not "a b"', "--color", "a b"
  end

  def test_leaves_the_words_it_is_given_as_they_were
    words = ["run", "-o", "x"].freeze

    assert_equal({"out" => "x"}, CrossLint::CommandLine.new(fixture_spec, words).flags)
  end

  def test_the_help_and_version_flags
    assert_equal ["h", "help", nil, "Print help", true], flag_fields(CrossLint::CommandLine::HELP)
    assert_equal ["V", "version", nil, "Print version", true], flag_fields(CrossLint::CommandLine::VERSION)
  end

  private

  def read(*words, spec: fixture_spec) = CrossLint::CommandLine.new(spec, words)

  def action_and_command(*words)
    line = read(*words)
    [line.action, line.command&.name]
  end

  def assert_error(message, *words, spec: fixture_spec)
    error = assert_raises(CrossLint::CommandLine::Error) { read(*words, spec:) }

    assert_equal message, error.message
  end

  def flag_fields(flag) = [flag.short, flag.long, flag.value, flag.help, flag.global]
end
