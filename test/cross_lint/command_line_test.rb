# frozen_string_literal: true

require "test_helper"

class CommandLineTest < Minitest::Test
  cover "CrossLint::CommandLine*"

  def test_with_no_words_it_runs_no_command_with_the_defaults
    line = read

    assert_equal [:run, nil, { "color" => "auto" }], [line.action, line.command, line.flags]
  end

  def test_names_a_command
    line = read("run")

    assert_equal [:run, "run", {}], [line.action, line.command.name, line.flags]
  end

  def test_reads_long_flags
    assert_equal({ "verbose" => true, "dry-run" => true }, read("--verbose", "run", "--dry-run").flags)
  end

  def test_reads_a_long_flag_value_after_an_equals_sign_or_in_the_next_word
    assert_equal({ "out" => "a=b" }, read("run", "--out=a=b").flags)
    assert_equal({ "out" => "x" }, read("run", "--out", "x").flags)
    assert_equal({ "out" => "--dry-run" }, read("run", "--out", "--dry-run").flags)
    assert_equal({ "out" => "x", "dry-run" => true }, read("run", "--out", "x", "-n").flags)
    assert_equal({ "out" => "x", "dry-run" => true }, read("run", "-o", "x", "-n").flags)
  end

  def test_reads_short_flags_alone_or_together
    assert_equal({ "verbose" => true, "dry-run" => true }, read("run", "-v", "-n").flags)
    assert_equal({ "verbose" => true, "dry-run" => true }, read("run", "-vn").flags)
  end

  def test_reads_a_short_flag_value_in_the_same_word_or_the_next
    assert_equal({ "out" => "x" }, read("run", "-o", "x").flags)
    assert_equal({ "out" => "nv" }, read("run", "-onv").flags)
    assert_equal({ "dry-run" => true, "out" => "x" }, read("run", "-no", "x").flags)
  end

  def test_gives_the_value_of_a_flag_that_takes_one
    line = read("--verbose", "run", "-o", "x")

    assert_equal ["x", nil, nil, "auto"], [line.value("out"), line.value("verbose"), line.value("mode"), read.value("color")]
  end

  def test_a_value_given_wins_over_the_default
    assert_equal({ "color" => "never" }, read("--color", "never").flags)
  end

  def test_tells_a_flag_given_from_one_with_only_its_default
    assert_equal [false, true, true, false], [
      read.given?("color"),
      read("--color", "auto").given?("color"),
      read("--verbose").given?("verbose"),
      read("--verbose").given?("auto"),
]
  end

  def test_checks_a_value_against_the_choices
    assert_error "--color takes auto or never, not bad", "--color=bad"
    assert_error "--mode takes only, not other", "run", "--mode", "other"
    assert_error "--warnings takes all, none, or error, not some", "check", "--warnings=some", spec: shipped_spec
    assert_equal({ "mode" => "only" }, read("run", "--mode", "only").flags)
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
    assert_equal({ "color" => "auto" }, read("--help").flags)
    assert_equal({ "color" => "auto" }, read("-V").flags)
  end

  def test_takes_every_word_after_a_double_dash_as_an_argument
    assert_equal "run", read("--", "run").command.name
    assert_error "tool run takes no arguments; remove --help", "run", "--", "--help"
  end

  def test_refuses_an_argument_after_the_command
    assert_error "tool run takes no arguments; remove extra", "run", "extra"
  end

  def test_help_takes_the_command_to_explain
    assert_nil read("help").topic
    assert_nil read("run").topic
    assert_equal ["help", "run"], [read("help", "run").command.name, read("help", "run").topic.name]
    assert_equal "stop", read("--verbose", "help", "-v", "stop").topic.name
    assert_equal "run", read("help", "--", "run").topic.name
  end

  def test_help_keeps_the_words_that_are_no_command_of_the_program_for_the_plugins
    line = read("help", "debt", "update")

    assert_equal [["debt", "update"], nil, "help"], [line.words, line.topic, line.command.name]
    assert_equal [["zzzzzz"], nil], [read("help", "zzzzzz").words, read("help", "zzzzzz").topic]
    assert_equal [["debt", "run"], nil], [read("help", "debt", "run").words, read("help", "debt", "run").topic]
    assert_empty read("help", "run").words
    assert_empty read("help").words
    assert_equal ["x y"], read("help", "x y").words
  end

  def test_help_checks_the_flags_of_the_help_command_after_words_it_keeps
    assert_error "tool help has no flag --out; tool help --help lists them", "help", "debt", "--out"
  end

  def test_help_takes_one_command_at_most
    assert_error "tool help takes one command at most; remove stop", "help", "run", "stop"
    assert_error 'tool help takes one command at most; remove "x y"', "help", "run", "x y"
  end

  def test_keeps_the_words_that_are_no_command_of_the_program_for_the_plugins
    assert_equal [["debt", "update"], nil, :run], [read("debt", "update").words, read("debt", "update").command, read("debt", "update").action]
    assert_equal ["-"], read("-").words
    assert_equal [["runn"], { "color" => "auto" }], [read("runn").words, read("runn").flags]
    assert_empty read.words
    assert_empty read("run").words
  end

  def test_reads_a_word_after_the_first_that_is_no_command_as_one_more_of_the_plugins
    assert_equal ["debt", "run", "stop"], read("debt", "run", "stop").words
    assert_equal ["debt", "update"], read("--verbose", "debt", "--color", "never", "update", "-v").words
    assert_equal({ "verbose" => true, "color" => "never" }, read("--verbose", "debt", "--color", "never", "update", "-v").flags)
  end

  def test_knows_only_the_top_level_flags_after_the_words_of_a_plugin
    assert_error "tool debt update has no flag --dry-run; tool debt update --help lists them", "debt", "update", "--dry-run"
    assert_error "tool debt has no flag -x; tool debt --help lists them", "debt", "-x"
    assert_equal %w[verbose color help version], read("debt", "update").known_flags.map(&:long)
  end

  def test_asks_for_the_help_of_a_plugin_command_and_keeps_its_words
    line = read("debt", "update", "--help", "--bogus")

    assert_equal [:help, nil, ["debt", "update"]], [line.action, line.command, line.words]
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

  def test_reads_the_flags_a_plugins_command_declares_once_it_has_the_plugins_name_and_the_commands
    asked = []
    declared = [
      CrossLint::Core::CommandFlag.new(short: "s", long: "since", value: "rev", help: "H", line: 1),
      CrossLint::Core::CommandFlag.new(short: "d", long: "dry", value: nil, help: "H", line: 2),
]
    plugin_flags = -> (words, project) { (asked << [words, project]) && declared }
    line = -> (*words) { CrossLint::CommandLine.new(fixture_spec, words, plugin_flags:) }

    assert_equal({ "verbose" => true, "since" => "x", "dry" => true, "color" => "auto" }, line.call("debt", "update", "-v", "--since", "x", "-d").flags)
    assert_equal({ "since" => "y", "color" => "auto" }, line.call("debt", "update", "-sy").flags)
    assert_equal [%w[debt update], nil], asked.first
    assert_equal %w[verbose color since dry help version], line.call("debt", "update").known_flags.map(&:long)
    asked.clear
    line.call("debt", "update", "extra", "--since", "x")

    assert_equal [[%w[debt update], nil]], asked
  end

  def test_asks_for_no_plugins_flags_before_two_words_or_after_a_command_of_crosslints_own
    asked = []
    declared = [CrossLint::Core::CommandFlag.new(short: "z", long: "zed", value: nil, help: "H", line: 2)]
    plugin_flags = -> (words, project) { (asked << [words, project]) && declared }
    ["--zed", "-z"].each do |flag|
      [[flag], ["debt", flag], ["help", "debt", "update", flag], ["run", flag]].each do |words|
        assert_raises(CrossLint::CommandLine::Error, words.inspect) { CrossLint::CommandLine.new(fixture_spec, words, plugin_flags:) }
      end
    end

    assert_empty asked
  end

  def test_asks_for_a_plugins_flags_once_for_each_pair_of_words_and_with_the_project_given_after_them
    asked = []
    plugin_flags = -> (words, project) { (asked << [words, project]) && [] }
    [["--quiet", "--no-color", "-C", "x", "--dry"], ["-qC", "y", "--dry", "--", "--zzz"], ["--dry", "--project=z"]].each do |after|
      assert_raises(CrossLint::CommandLine::Error) { CrossLint::CommandLine.new(shipped_spec, ["debt", "update", *after], plugin_flags:) }
    end

    assert_equal [[%w[debt update], "x"], [%w[debt update], "y"], [%w[debt update], "z"]], asked.uniq
    assert_equal [], CrossLint::CommandLine.new(shipped_spec, ["debt", "update", "--quiet"], plugin_flags: -> (*) { raise "asked" }).flags.keys - ["quiet"]
  end

  def test_stops_at_a_flag_the_plugins_command_doesnt_declare_naming_the_nearest_spelling
    declared = [CrossLint::Core::CommandFlag.new(short: "d", long: "dry-run", value: nil, help: "H", line: 2)]
    line = -> (*words) { CrossLint::CommandLine.new(fixture_spec, words, plugin_flags: -> (_words, _project) { declared }) }

    error = assert_raises(CrossLint::CommandLine::Error) { line.call("debt", "update", "--dry-ran") }

    assert_equal "tool debt update has no flag --dry-ran; did you mean --dry-run?", error.message
    assert_equal "tool debt update has no flag -x; tool debt update --help lists them",
      assert_raises(CrossLint::CommandLine::Error) { line.call("debt", "update", "-x") }.message
    assert_equal "tool debt has no flag --dry-run; tool debt --help lists them",
      assert_raises(CrossLint::CommandLine::Error) { line.call("debt", "--dry-run", "update") }.message
  end

  def test_quotes_a_word_that_is_not_printable_ascii
    assert_error "tool has no flag \"--v\\u00E9rbose\"; did you mean --verbose?", "--vérbose"
    assert_error 'tool run takes no arguments; remove "x y"', "run", "x y"
    assert_error '--color takes auto or never, not "a b"', "--color", "a b"
  end

  def test_leaves_the_words_it_is_given_as_they_were
    words = ["run", "-o", "x"].freeze

    assert_equal({ "out" => "x" }, CrossLint::CommandLine.new(fixture_spec, words).flags)
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
