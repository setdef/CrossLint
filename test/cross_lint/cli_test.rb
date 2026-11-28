# frozen_string_literal: true

require "test_helper"
require "json"
require "open3"

class CLITest < Minitest::Test
  cover "CrossLint::CLI*"

  # A mistake of a kind that no code of CrossLint's raises, to tell a mistake
  # from one of its subclasses.
  class RareMistake < CrossLint::Core::Mistake; end

  # Absolute paths as File.expand_path gives them, with a drive on Windows.
  TOP = File.expand_path("/")
  WORK = File.expand_path("/work")

  # A spec that raises +error+ when CrossLint reads its flags.
  class BrokenSpec < CrossLint::UsageSpec
    def initialize(error) = @error = error
    def flags = raise(@error)
  end

  def test_prints_the_version
    assert_equal ["tool 1.2.3\n", "", 0], run_cli("--version")
  end

  def test_prints_the_help
    help = CrossLint::Help.new(fixture_spec)

    assert_equal [help.render, "", 0], run_cli("--help")
    assert_equal [help.render(fixture_spec.commands.first), "", 0], run_cli("run", "--help")
  end

  def test_prints_a_short_help_with_no_command
    short = <<~HELP
      Does things

      Examples:
        Run it:
          Runs the thing once.
          $ tool run

          $ tool stop

      Run tool --help to list every command.
    HELP

    assert_equal [short, "", 0], run_cli
    assert_equal [short, "", 0], run_cli("--color", "never")
  end

  def test_help_prints_what_help_flags_print
    help = CrossLint::Help.new(fixture_spec)

    assert_equal run_cli("--help"), run_cli("help")
    assert_equal [help.render(fixture_spec.commands.first), "", 0], run_cli("help", "run")
    assert_equal run_cli("run", "--help"), run_cli("help", "run")
    assert_equal [help.render(fixture_spec.commands.last), "", 0], run_cli("help", "--help")
  end

  def test_help_says_when_it_has_no_such_command
    assert_equal ["", "crosslint: tool has no command runn, and the configuration lists no plugin of that name; did you mean run?\n", 2],
      run_cli("help", "runn")
  end

  def test_says_a_command_does_not_work_yet
    assert_equal ["", "crosslint: tool run doesn't work yet\n", 2], run_cli("run")
  end

  def test_says_what_is_wrong_with_the_command_line
    assert_equal ["", "crosslint: tool has no flag --bogus; tool --help lists them\n", 2], run_cli("--bogus")
  end

  def test_reads_the_shipped_spec_when_given_none
    out = StringIO.new
    status = CrossLint::CLI.new(["--version"], out:, err: StringIO.new, env: {}).run

    assert_equal ["crosslint #{shipped_spec.version}\n", 0], [out.string, status]
  end

  def test_exits_with_130_when_interrupted
    result = begin
      run_cli(spec: BrokenSpec.new(Interrupt.new))
    rescue Interrupt
      "the interrupt reached the caller"
    end

    assert_equal ["", "", 130], result
  end

  def test_reports_a_bug_and_where_to_send_it
    out, err, status = run_cli(spec: BrokenSpec.new(RuntimeError.new("boom")))

    assert_equal ["", 2], [out, status]
    assert_equal <<~ERR, err
      crosslint: stopped on a bug in CrossLint: RuntimeError: boom
      crosslint: please report it at https://forum.setdef.com/c/crosslint, with the command you ran and what crosslint --version prints
      crosslint: run it again with --debug to see where it stopped
    ERR
  end

  def test_reports_a_load_error_as_a_bug
    _, err, status = run_cli(spec: BrokenSpec.new(LoadError.new("cannot load such file -- kdl")))

    assert_equal 2, status
    assert_equal "crosslint: stopped on a bug in CrossLint: LoadError: cannot load such file -- kdl\n", err.lines.first
  end

  def test_shows_where_a_bug_stopped_it_with_debug
    _, err, status = run_cli("--debug", spec: BrokenSpec.new(RuntimeError.new("boom")))
    lines = err.lines(chomp: true)

    assert_equal 2, status
    assert_equal "crosslint: please report it at https://forum.setdef.com/c/crosslint, with the command you ran and what crosslint --version prints", lines[1]
    assert_match(/\Acrosslint:   from .*cli_test\.rb:\d+:in 'CLITest::BrokenSpec#flags'\z/, lines[2])
    assert_operator lines.size, :>, 3
    assert(lines.drop(2).all? { |line| line.start_with?("crosslint:   from ") })
  end

  def test_shows_no_trace_for_a_bug_that_has_none
    error = RuntimeError.new("boom")
    def error.backtrace = nil
    _, err, status = run_cli("--debug", spec: BrokenSpec.new(error))

    assert_equal [2, 2], [err.lines.size, status]
  end

  def test_shows_where_a_bug_stopped_it_when_debug_is_set
    _, err, = run_cli(spec: BrokenSpec.new(RuntimeError.new("boom")), env: {"DEBUG" => "1"})

    assert_match(/\Acrosslint:   from /, err.lines[2])
    _, err, = run_cli(spec: BrokenSpec.new(RuntimeError.new("boom")), env: {"DEBUG" => ""})

    assert_equal "crosslint: run it again with --debug to see where it stopped\n", err.lines[2]
  end

  def test_writes_the_text_of_an_error_as_it_is_to_standard_error
    _, err, = run_cli(spec: BrokenSpec.new(RuntimeError.new("bôom \xFF".b.force_encoding("UTF-8"))))

    assert_equal "crosslint: stopped on a bug in CrossLint: RuntimeError: bôom \xFF\n".b, err.lines.first.b
  end

  def test_check_prints_each_violation_and_the_summary_and_exits_with_1
    assert_equal ["lib/b.rb: no test file at test/b_test.rb (tests/has-test)\n",
      "crosslint: checked 2 ruby-file artifacts: 1 error\n", 1], check("check", app: app)
  end

  # On a terminal, the first line comes before CrossLint reads any project
  # file beyond its configuration, or starts a helper, so a large project
  # never sits silent while a rule reads its files.
  def test_check_says_what_it_is_checking_first_when_standard_error_is_a_terminal
    assert_equal "crosslint: checking 2 ruby-file artifacts\ncrosslint: checked 2 ruby-file artifacts: 1 error\n", check("check", app: app, err_tty: true)[1]
    assert_equal "", check("check", "--quiet", app: app, err_tty: true)[1]
  end

  def test_check_exits_with_0_when_every_check_passes
    assert_equal ["", "crosslint: checked 1 ruby-file artifact: no violations\n", 0],
      check("check", app: app(files: ["lib/a.rb", "test/a_test.rb"]))
  end

  def test_check_finds_the_project_from_the_project_flag
    summary = "crosslint: checked 2 ruby-file artifacts: 1 error\n"

    assert_equal summary, check("check", "-C", "#{WORK}/app/lib", app: app)[1]
    assert_equal summary, check("check", "--project", "#{WORK}/app", app: app)[1]
    assert_match(/\Acrosslint: no \.config\/crosslint\/config\.kdl in .*elsewhere or any folder above it/,
      check("check", "-C", "#{TOP}elsewhere", app: app)[1])
  end

  def test_check_writes_a_path_in_a_message_as_it_is
    message = check("check", "-C", "#{TOP}elsewhere/café", app: app)[1]

    assert_match(/\Acrosslint: no \.config\/crosslint\/config\.kdl in .*elsewhere\/café or any folder above it/, message)
  end

  def test_check_takes_warnings_from_the_flag_over_the_configuration
    warned = app(severity: :warning)

    assert_equal ["lib/b.rb: warning: no test file at test/b_test.rb (tests/has-test)\n",
      "crosslint: checked 2 ruby-file artifacts: 1 warning\n", 0], check("check", app: warned)
    assert_equal 1, check("check", "--warnings=error", app: warned)[2]
    assert_equal ["", "crosslint: checked 2 ruby-file artifacts: no errors\n", 0], check("check", "--warnings", "none", app: warned)
    assert_equal 1, check("check", app: app(severity: :warning, warnings: :error))[2]
    assert_equal 0, check("check", "--warnings=all", app: app(severity: :warning, warnings: :error))[2]
  end

  def test_check_prints_only_what_fails_with_quiet
    assert_equal ["lib/b.rb: no test file at test/b_test.rb (tests/has-test)\n", "", 1], check("check", "-q", app: app)
    assert_equal ["", "", 0], check("check", "--quiet", app: app(severity: :warning))
    assert_equal ["lib/b.rb: no test file at test/b_test.rb (tests/has-test)\n", "", 1], check("check", app: app(verbosity: :quiet))
  end

  def test_check_prints_nothing_with_silent
    assert_equal ["", "", 1], check("check", "-s", app: app)
    assert_equal ["", "", 1], check("check", "--silent", "--quiet", app: app)
    assert_equal ["", "", 1], check("check", app: app(verbosity: :silent))
  end

  def test_check_lists_no_passing_artifact_with_all_and_quiet
    assert_equal ["lib/b.rb: no test file at test/b_test.rb (tests/has-test)\n", "", 1], check("check", "--all", "--quiet", app: app)
    assert_equal ["", "", 0], check("check", "--all", "-q", app: app(files: ["lib/a.rb", "test/a_test.rb"]))
  end

  def test_check_exits_with_1_when_silent_and_a_warning_fails_it
    warned = app(severity: :warning)

    assert_equal ["", "", 1], check("check", "--silent", "--warnings=error", app: warned)
    assert_equal ["", "", 0], check("check", "--silent", app: warned)
  end

  def test_check_lists_passing_artifacts_with_all
    assert_equal "lib/a.rb: ruby-file passes\nlib/b.rb: no test file at test/b_test.rb (tests/has-test)\n",
      check("check", "-a", app: app)[0]
    assert_equal check("check", "-a", app: app), check("check", "--all", app: app)
  end

  def test_check_prints_json_with_json
    out, err, status = check("check", "--json", app: app)

    assert_equal [{"path" => "lib/b.rb", "message" => "no test file at test/b_test.rb", "plugin" => "tests", "policy" => "has-test",
                   "artifact" => "lib/b.rb", "role" => "ruby-file", "severity" => "error", "detail" => "test", "line" => nil}], JSON.parse(out).fetch("findings")
    assert_equal ["crosslint_version", CrossLint::UsageSpec.load.version], JSON.parse(out).first
    assert_equal ["crosslint: checked 2 ruby-file artifacts: 1 error\n", 1], [err, status]
  end

  def test_check_takes_only_the_flags_the_usage_spec_gives_it
    assert_equal ["", "crosslint: crosslint check has no flag --update-debt; crosslint check --help lists them\n", 2],
      check("check", "--update-debt", app: app)
    assert_equal ["", "crosslint: crosslint check has no flag --upate; crosslint check --help lists them\n", 2], check("check", "--upate", app: app)
    assert_equal 1, check("check", "--warnings=error", "--all", "--json", "--quiet", app: app)[2]
  end

  def test_a_plugins_command_runs_the_check_and_tells_the_plugins_step_its_name
    out, err, status = check("debt", "update", app: app(debt: true))

    assert_equal ["", 0], [out, status]
    assert_equal "crosslint: wrote .config/crosslint/debt.tsv: 1 entry added, 0 removed\ncrosslint: checked 2 ruby-file artifacts: 1 accepted as debt\n", err
    assert_equal 1, check("check", app: app(debt: true))[2]
  end

  def test_a_plugins_command_passes_whatever_the_check_found
    assert_equal 1, check("check", "--warnings=error", app: app(debt: true))[2]
    assert_equal 0, check("debt", "update", app: app(debt: true))[2]
    assert_equal 0, check("debt", "update", app: app(debt: true, files: ["lib/a.rb", "test/a_test.rb"]))[2]
  end

  def test_a_plugins_command_takes_the_global_flags_before_or_after_its_words
    assert_equal ["", "", 0], check("debt", "update", "--silent", app: app(debt: true))
    assert_equal ["", "", 0], check("--silent", "debt", "update", app: app(debt: true))
    assert_equal ["", "crosslint: wrote .config/crosslint/debt.tsv: 1 entry added, 0 removed\n", 0], check("-q", "debt", "update", app: app(debt: true))
    assert_equal 0, check("debt", "-C", "#{WORK}/app", "update", app: app(debt: true))[2]
  end

  def test_a_plugins_command_takes_no_other_flags
    assert_equal ["", "crosslint: crosslint debt update has no flag --json; did you mean --version?\n", 2],
      check("debt", "update", "--json", app: app(debt: true))
    assert_equal ["", "crosslint: crosslint debt update has no flag --warnings; crosslint debt update --help lists them\n", 2],
      check("debt", "update", "--warnings=none", app: app(debt: true))
    assert_equal ["", "crosslint: crosslint debt update takes no arguments; remove extra\n", 2], check("debt", "update", "extra", app: app(debt: true))
  end

  def test_a_plugins_command_takes_the_flags_it_declares_and_tells_its_step
    project = app(debt: true)
    expected = ["lib/b.rb: no test file at test/b_test.rb (tests/has-test)\n", "crosslint: would add tests/has-test on lib/b.rb (test)\ncrosslint: would write .config/crosslint/debt.tsv: 1 entry added, 0 removed\n" \
      "crosslint: checked 2 ruby-file artifacts: 1 error\n", 0]

    assert_equal expected, check("debt", "update", "--dry-run", app: project)
    assert_equal expected, check("debt", "update", "-n", app: project)
    assert_equal expected, check("-C", "#{WORK}/app", "debt", "update", "-n", app: project)
    assert_equal 1, check("check", app: project)[2]
    assert_equal 0, check("debt", "update", app: project)[2]
    assert_equal 0, check("check", app: project)[2]
  end

  def test_a_plugins_flag_named_as_a_flag_of_check_is_the_plugins_own
    json = CrossLint::Core::CommandFlag.new(short: nil, long: "json", value: nil, help: "Prints JSON", line: 2)
    out, err, status = check("debt", "update", "--json", app: app(debt: true, debt_flags: [json]))

    assert_equal ["", 0, false], [out, status, err.start_with?("{")]
  end

  def test_a_plugins_flag_named_for_the_warnings_flag_of_check_takes_any_value
    warnings = CrossLint::Core::CommandFlag.new(short: nil, long: "warnings", value: "mode", help: "Its own mode", line: 2)
    project = app(debt: true, debt_flags: [warnings])

    assert_equal 0, check("debt", "update", "--warnings", "banana", app: project)[2]
    assert_equal 0, check("debt", "update", "--warnings=banana", app: project)[2]
  end

  def test_a_flag_a_plugins_command_doesnt_declare_stops_with_2_naming_the_nearest_spelling
    assert_equal ["", "crosslint: crosslint debt update has no flag --dry-ran; did you mean --dry-run?\n", 2],
      check("debt", "update", "--dry-ran", app: app(debt: true))
    assert_equal ["", "crosslint: crosslint debt update has no flag -x; crosslint debt update --help lists them\n", 2],
      check("debt", "update", "-x", app: app(debt: true))
    assert_equal ["", "crosslint: crosslint debt has no flag --dry-run; crosslint debt --help lists them\n", 2],
      check("debt", "--dry-run", "update", app: app(debt: true))
    assert_equal ["", "crosslint: crosslint check has no flag --dry-run; crosslint check --help lists them\n", 2],
      check("check", "--dry-run", app: app(debt: true))
  end

  def test_a_flag_of_a_plugin_that_isnt_listed_stops_as_one_of_no_command_does_and_one_of_a_project_that_cant_be_read_with_its_mistake
    assert_equal ["", "crosslint: crosslint debt update has no flag --dry-run; crosslint debt update --help lists them\n", 2],
      check("debt", "update", "--dry-run", app: app)
    broken = app(broken: CrossLint::Core::Mistake.new("lists nothing", file: ".config/crosslint/config.kdl"))

    assert_equal ["", "crosslint: .config/crosslint/config.kdl: lists nothing\n", 2], check("debt", "update", "--dry-run", app: broken)
  end

  def test_a_plugins_flag_that_takes_a_global_flags_name_stops_with_2_naming_the_plugin
    flag = CrossLint::Core::CommandFlag.new(short: "q", long: "dry-run", value: nil, help: "Writes nothing", line: 9)
    out, err, status = check("debt", "update", "--dry-run", app: app(debt: true, debt_flags: [flag]))

    assert_equal ["", 2], [out, status]
    assert_match(/\Acrosslint: debt\/plugin\.kdl:9: plugin debt in .* gives command "update" the flag -q, which is a global flag of CrossLint; name the flag another way\n\z/, err)
  end

  def test_a_plugins_command_help_shows_its_flags_as_a_command_of_crosslints_own_does
    out, err, status = helping("debt", "update", "--help", app: app(debt: true))

    assert_equal ["", 0], [err, status]
    assert_includes out, "Usage: crosslint debt update [FLAGS]\n\nFlags:\n  -n, --dry-run  List the entries update would add and remove, and write nothing\n\nGlobal flags:\n"
    assert_equal [out, "", 0], helping("help", "debt", "update", app: app(debt: true))
  end

  def test_a_plugins_command_stops_with_2_naming_what_is_missing
    assert_equal ["", "crosslint: debt update is a command of the debt plugin, which .config/crosslint/config.kdl doesn't list\n", 2],
      check("debt", "update", app: app)
    assert_equal ["", "crosslint: crosslint debt has no command updat; did you mean update?\n", 2], check("debt", "updat", app: app(debt: true))
    assert_equal ["", "crosslint: crosslint has no command chekc, and the configuration lists no plugin of that name; did you mean check?\n", 2],
      check("chekc", "now", app: app(debt: true))
  end

  def test_a_word_that_is_a_flags_name_stops_with_2_and_names_the_flag
    assert_equal ["", "crosslint: crosslint has no command version, and the configuration lists no plugin of that name; did you mean --version?\n", 2],
      check("version", app: app)
    assert_equal ["", "crosslint: crosslint has no command quiet, and the configuration lists no plugin of that name; did you mean --quiet?\n", 2],
      check("quiet", app: app(debt: true))
  end

  def test_a_word_when_the_project_cant_be_read_stops_with_the_mistake_unless_it_is_a_typo_or_a_flags_name_or_help_is_asked
    mistake = CrossLint::Core::Mistake.new("lists nothing", file: ".config/crosslint/config.kdl")
    broken = app(broken: mistake)

    assert_equal ["", "crosslint: .config/crosslint/config.kdl: lists nothing\n", 2], check("bogus", app: broken)
    assert_equal ["", "crosslint: .config/crosslint/config.kdl: lists nothing\n", 2], check("debt", app: broken)
    assert_equal ["", "crosslint: crosslint has no command version; did you mean --version?\n", 2], check("version", app: broken)
    assert_equal ["", "crosslint: crosslint has no command version; did you mean --version?\n", 2], helping("version", "--help", app: broken)
    assert_equal 0, helping("bogus", "--help", app: broken).last
    assert_equal 0, helping("help", "bogus", app: broken).last
  end

  def test_a_mistyped_command_fetches_no_shared_plugin
    fetched = StringIO.new

    assert_equal ["", "crosslint: crosslint has no command chek, and the configuration lists no plugin of that name; did you mean check?\n", 2],
      check("chek", "update", app: app(shared: true, fetch_log: fetched))
    assert_equal ["", "crosslint: crosslint has no command signatuers, and the configuration lists no plugin of that name; did you mean signatures?\n", 2],
      check("signatuers", "update", app: app(shared: true, fetch_log: fetched))
    assert_equal ["", "crosslint: crosslint has no command chek, and the configuration lists no plugin of that name; did you mean check?\n", 2],
      helping("chek", "--help", app: app(shared: true, fetch_log: fetched))
    assert_equal "", fetched.string
  end

  def test_a_word_that_names_a_shared_plugin_not_fetched_yet_fetches_it_and_only_then
    fetched = StringIO.new
    out, err, status = check("signatures", "update", app: app(shared: true, fetch_log: fetched))

    assert_equal ["", 2], [out, status]
    assert_includes err, "couldn't fetch shared plugin signatures"
    assert_equal "crosslint: fetching #{SHARED} at v1.0.0\n", fetched.string
  end

  def test_a_plugins_command_stops_with_2_at_a_mistake_in_the_project_and_names_a_typo_of_a_command_of_crosslint
    mistake = CrossLint::Core::Mistake.new("lists nothing", file: ".config/crosslint/config.kdl")

    assert_equal ["", "crosslint: .config/crosslint/config.kdl: lists nothing\n", 2], check("debt", "update", app: app(broken: mistake))
    assert_equal ["", "crosslint: crosslint has no command chekc; did you mean check?\n", 2], check("chekc", "now", app: app(broken: mistake))
  end

  def test_the_program_help_lists_the_commands_of_the_projects_plugins_after_its_own
    out, err, status = helping("--help", app: app(debt: true))

    assert_equal [["", 0], true], [[err, status], out.include?("\nPlugin commands:\n  debt update  Rewrite the debt file to list the current violations\n\nFlags:\n")]
    assert_equal [out, "", 0], helping("help", app: app(debt: true))
    assert_equal [out, "", 0], helping("-h", app: app(debt: true))
    refute_includes helping("--help", app: app)[0], "Plugin commands"
  end

  def test_help_of_a_command_of_crosslint_reads_no_project
    broken = app(broken: CrossLint::Core::Mistake.new("lists nothing", file: "x"))

    assert_equal [CrossLint::Help.new(shipped_spec).render(shipped_spec.commands.first), "", 0], helping("check", "--help", app: broken)
  end

  def test_the_program_help_says_why_it_shows_no_plugin_commands_and_exits_with_0
    mistake = CrossLint::Core::Mistake.new("lists nothing", file: ".config/crosslint/config.kdl", line: 2)
    out, err, status = helping("--help", app: app(broken: mistake))
    heading = "Plugin commands:\n  Not shown, because CrossLint couldn't read the project's plugins: .config/crosslint/config.kdl:2:\n  lists nothing\n\nFlags:\n"

    assert_equal ["", 0, true], [err, status, out.include?(heading)]
    assert_equal [out, "", 0], helping("help", app: app(broken: mistake))
    outside = run_cli("--help", spec: shipped_spec, app: app(debt: true))

    assert_equal [0, true], [outside[2], outside[0].include?("Plugin commands:\n  Not shown, because CrossLint couldn't read the project's plugins: no .config/crosslint/config.kdl\n  in ")]
  end

  def test_the_program_help_names_a_shared_plugin_not_fetched_yet
    out, err, status = helping("--help", app: app(debt: true, shared: true))
    heading = "Plugin commands:\n  debt update  Rewrite the debt file to list the current violations\n  signatures isn't fetched yet, so its commands aren't shown; crosslint check fetches it\n\n"

    assert_equal ["", 0, true], [err, status, out.include?(heading)]
  end

  def test_help_for_a_plugin_lists_its_commands
    help = CrossLint::Help.new(shipped_spec)
    manifest = app(debt: true).load_project("#{WORK}/app").plugins.first.manifest
    page = help.plugin("debt", manifest.commands)

    assert_equal [page, "", 0], helping("debt", "--help", app: app(debt: true))
    assert_equal [page, "", 0], helping("help", "debt", app: app(debt: true))
    assert_equal [page, "", 0], helping("debt", app: app(debt: true))
    assert_includes page, "Usage: crosslint debt COMMAND [FLAGS]\n"
  end

  def test_help_for_a_plugins_command_says_what_it_does
    help = CrossLint::Help.new(shipped_spec)
    manifest = app(debt: true).load_project("#{WORK}/app").plugins.first.manifest
    page = help.plugin_command("debt", manifest.commands.first)

    assert_equal [page, "", 0], helping("debt", "update", "--help", app: app(debt: true))
    assert_equal [page, "", 0], helping("help", "debt", "update", app: app(debt: true))
    assert_equal [page, "", 0], helping("--help", "debt", "update", app: app(debt: true)).then { |_, _, status| [page, "", status] }
    assert_includes page, "Usage: crosslint debt update [FLAGS]\n"
  end

  def test_help_shows_whatever_other_flags_the_line_has_in_either_order
    manifest = app(debt: true).load_project("#{WORK}/app").plugins.first.manifest
    page = CrossLint::Help.new(shipped_spec).plugin_command("debt", manifest.commands.first)

    ["-n", "--dry-run", "--bogus", "-x", "--silent"].each do |flag|
      assert_equal [page, "", 0], helping("debt", "update", flag, "--help", app: app(debt: true)), flag
      assert_equal [page, "", 0], helping("debt", "update", "-h", flag, app: app(debt: true)), flag
    end
    assert_equal [CrossLint::Help.new(shipped_spec).render(shipped_spec.commands.first), "", 0],
      helping("check", "--warnings", "banana", "--help", app: app(debt: true))
  end

  def test_help_with_a_flag_before_it_in_a_project_that_cant_be_read_prints_the_programs_help_as_help_alone_does
    mistake = CrossLint::Core::Mistake.new("lists nothing", file: ".config/crosslint/config.kdl")
    broken = app(broken: mistake)
    alone = helping("debt", "update", "--help", app: broken)

    assert_equal [["", 0], true], [alone.values_at(1, 2), alone[0].include?("Plugin commands:\n  Not shown, because")]
    assert_equal alone, helping("debt", "update", "-n", "--help", app: broken)
    assert_equal alone, helping("debt", "update", "-n", "-h", app: broken)
    assert_equal alone, helping("debt", "update", "--help", "-n", app: broken)
  end

  def test_a_flag_after_two_dashes_isnt_help
    assert_equal ["", "crosslint: crosslint check takes no arguments; remove --help\n", 2], helping("check", "--", "--help", app: app(debt: true))
  end

  def test_help_for_a_word_that_names_no_plugin_or_command_stops_with_2
    assert_equal ["", "crosslint: crosslint debt has no command updat; did you mean update?\n", 2], helping("debt", "updat", "--help", app: app(debt: true))
    assert_equal ["", "crosslint: debt update is a command of the debt plugin, which .config/crosslint/config.kdl doesn't list\n", 2],
      helping("help", "debt", "update", app: app)
    assert_equal ["", "crosslint: crosslint has no command zzzzzz, and the configuration lists no plugin of that name; crosslint --help lists the commands\n", 2],
      helping("help", "zzzzzz", app: app)
    assert_equal ["", "crosslint: tests is a plugin the configuration lists, and it adds no commands\n", 2], helping("help", "tests", app: app)
  end

  def test_help_for_a_plugin_that_cant_be_read_prints_the_programs_help_unless_the_word_is_a_typo_of_a_command
    mistake = CrossLint::Core::Mistake.new("lists nothing", file: ".config/crosslint/config.kdl")
    out, err, status = helping("debt", "--help", app: app(broken: mistake))

    assert_equal [["", 0], true], [[err, status], out.start_with?("CrossLint ") && out.include?("Plugin commands:\n  Not shown, because")]
    assert_equal ["", "crosslint: crosslint has no command chekc; did you mean check?\n", 2], helping("chekc", "--help", app: app(broken: mistake))
  end

  def test_a_plugins_command_reads_the_project_of_the_folder_it_runs_in_and_refuses_a_plugin_named_for_a_command_of_the_spec_it_is_given
    Dir.mktmpdir("crosslint") do |project|
      write(project, ".config/crosslint/config.kdl", %(plugin ".config/crosslint/run"\n))
      write(project, ".config/crosslint/run/plugin.kdl", %(step "track-debt"\npolicy "has-debt"\ncommand "go" help="Goes"\n))
      out, err, status = Dir.chdir(project) { run_cli("go", "now") }

      assert_equal ["", 2], [out, status]
      assert_match(%r{\Acrosslint: \.config/crosslint/run/plugin\.kdl:3: plugin run in .* adds commands, and run is reserved, as a command of CrossLint}, err)
    end
  end

  def test_a_version_flag_after_a_plugins_words_prints_the_version
    assert_equal ["crosslint #{shipped_spec.version}\n", "", 0], check("debt", "--version", app: app(debt: true))
    assert_equal ["crosslint #{shipped_spec.version}\n", "", 0], check("debt", "update", "-V", app: app(debt: true))
  end

  def test_help_for_a_command_of_crosslint_lists_no_plugin_commands_and_reads_no_project
    spy = Class.new(CrossLint::App) { def listing(_) = raise("read the project") }.new
    check_help = CrossLint::Help.new(shipped_spec).render(shipped_spec.commands.first)

    assert_equal [check_help, "", 0], check("check", "--help", app: spy)
    assert_equal [check_help, "", 0], check("help", "check", app: spy)
    assert_equal [check_help, "", 0], helping("check", "--help", app: app(debt: true))
  end

  def test_help_names_a_listed_plugin_though_another_is_not_fetched_yet
    debt = CrossLint::Help.new(shipped_spec).plugin("debt", built_in_manifests.fetch(File.join(CrossLint::App::PLUGINS, "debt")).commands)

    assert_equal [debt, "", 0], helping("debt", "--help", app: app(debt: true, shared: true))
  end

  def test_help_treats_a_kind_of_mistake_as_one_when_the_plugins_cant_be_read
    broken = app(broken: RareMistake.new("lists nothing", file: ".config/crosslint/config.kdl"))

    assert_includes helping("--help", app: broken)[0], "Plugin commands:\n  Not shown, because"
    assert_includes helping("debt", "--help", app: broken)[0], "Plugin commands:\n  Not shown, because"
  end

  def test_help_for_a_plugin_not_fetched_yet_prints_the_programs_help_with_the_reason
    out, err, status = helping("signatures", "update", "--help", app: app(shared: true))

    assert_equal ["", 0], [err, status]
    assert_includes out, "  signatures isn't fetched yet, so its commands aren't shown; crosslint check fetches it\n"
  end

  def test_check_colors_the_messages_only_on_a_terminal_or_when_forced
    red = "lib/b.rb: \e[31mno test file at test/b_test.rb\e[0m (tests/has-test)\n"
    plain = "lib/b.rb: no test file at test/b_test.rb (tests/has-test)\n"

    assert_equal plain, check("check", app: app)[0]
    assert_equal red, check("check", app: app, tty: true)[0]
    assert_equal red, check("check", app: app, env: {"FORCE_COLOR" => "1"})[0]
    assert_equal plain, check("check", app: app, env: {"FORCE_COLOR" => ""})[0]
    assert_equal plain, check("check", "--no-color", app: app, tty: true, env: {"FORCE_COLOR" => "1"})[0]
    assert_equal plain, check("check", app: app, tty: true, env: {"NO_COLOR" => "1", "FORCE_COLOR" => "1"})[0]
    assert_equal red, check("check", app: app, tty: true, env: {"NO_COLOR" => ""})[0]
    assert_equal plain, check("check", app: app, tty: true, env: {"TERM" => "dumb", "FORCE_COLOR" => "1"})[0]
    assert_equal red, check("check", app: app, tty: true, env: {"TERM" => "xterm"})[0]
    refute_includes check("check", "--json", app: app, tty: true)[0], "\e["
  end

  def test_check_warns_of_each_ruby_rule_no_policy_runs
    warning = %(crosslint: .config/tests/plugin.kdl:3: warning: no policy runs rule "unused", so CrossLint doesn't load it\n)

    assert_equal warning, check("check", app: app(unused: true))[1].lines.first
    assert_equal warning, check("check", app: app(unused: true, verbosity: :normal))[1].lines.first
    [["-q"], ["--silent"]].each { |flags| assert_empty check("check", *flags, app: app(unused: true))[1] }
    assert_equal "crosslint: checked 2 ruby-file artifacts: 1 error\n", check("check", "--warnings=none", app: app(unused: true))[1]
    %i[quiet silent].each { |verbosity| assert_empty check("check", app: app(unused: true, verbosity:))[1] }
  end

  def test_check_reads_the_project_in_the_folder_it_runs_in_or_a_folder_relative_to_it
    Dir.mktmpdir("crosslint") do |folder|
      write(folder, "app/.config/crosslint/config.kdl", %(plugin "."\n))
      write(folder, "app/plugin.kdl", %(helper "h" command="node" file="h.mjs"\n))
      # A .git file that points nowhere keeps Git from finding a
      # repository in a folder above.
      write(folder, "app/.git", "gitdir: nowhere\n")
      FileUtils.mkdir_p(File.join(folder, "app/lib"))
      outside = ->(root) { "crosslint: #{root} isn't in a Git working tree, and CrossLint lists a project's files with Git; run git init in the project's root\n" }

      Dir.chdir(File.join(folder, "app/lib")) { assert_equal ["", outside.call(File.dirname(Dir.pwd)), 2], check("check") }
      Dir.chdir(folder) { assert_equal ["", outside.call(File.join(Dir.pwd, "app")), 2], check("check", "-C", "app/lib") }
    end
  end

  def test_check_reports_a_fault_and_exits_with_2
    fault = "crosslint: fault in plugin tests: rule raises on lib/a.rb raised RuntimeError: boom\n"

    assert_equal ["", "#{fault}crosslint: run it again with --debug to see where each fault was raised\n" \
      "crosslint: checked 2 ruby-file artifacts: 1 fault\n", 2], check("check", app: app(raises: true))
    assert_equal ["", fault, 2], check("check", "--silent", app: app(raises: true))
    debugged = check("check", "--debug", app: app(raises: true))[1].lines

    assert_equal [fault, "crosslint:   from raises.rb:1:in 'check'\n"], debugged.take(2)
  end

  def test_check_writes_what_a_helper_writes_to_standard_error_with_debug
    Dir.mktmpdir("crosslint") do |project|
      write(project, ".config/crosslint/config.kdl", %(plugin "."\n))
      write(project, "plugin.kdl", %(artifact "a" {\n  primary "{path}.md"\n}\nhelper "asks" command=(crosslint)"ruby" file="asks.rb"\nrule "asks" helper="asks"\nhelper "h" command="sh" file="h.sh"\n) +
        %(policy "p" {\n  applies-to "a"\n  rule "asks"\n}\n))
      write(project, "asks.rb", %(class Asks < CrossLint::Rule\n  def check(artifact) = (helper("h").call(1) && [])\nend\n))
      write(project, "h.sh", %(while read -r line; do echo said >&2; echo 1; done\n))
      write(project, "a.md", "")
      Open3.capture3("git", "init", "-q", chdir: project)

      assert_equal ["", "crosslint: checked 1 a artifact: no violations\n", 0], check("check", "-C", project)
      assert_equal "crosslint: helper h: said\n", check("check", "-C", project, "--debug")[1].lines.first
    end
  end

  def test_check_writes_no_file
    Dir.mktmpdir("crosslint") do |project|
      write(project, ".config/crosslint/config.kdl", %(plugin "."\n))
      write(project, "plugin.kdl", %(artifact "a" {\n  primary "{path}.md"\n  piece "b" "{path}.txt"\n}\n) +
        %(policy "p" {\n  applies-to "a"\n  rule "piece-exists" piece="b"\n}\n))
      write(project, "a.md", "")
      Open3.capture3("git", "init", "-q", chdir: project)
      snapshot = lambda do
        Dir.glob("**/*", File::FNM_DOTMATCH, base: project).sort.map do |path|
          full = File.join(project, path)
          [path, File.file?(full) ? [File.binread(full), File.mtime(full)] : nil]
        end
      end
      before = snapshot.call

      assert_equal 1, check("check", "-C", project, "--all")[2]
      assert_equal before, snapshot.call
    end
  end

  def test_check_names_the_file_and_line_of_a_mistake
    mistake = CrossLint::Core::Mistake.new(%(unknown node "file", did you mean "files"?), file: ".config/tests/plugin.kdl", line: 2)

    assert_equal ["", %(crosslint: .config/tests/plugin.kdl:2: unknown node "file", did you mean "files"?\n), 2],
      check("check", app: app(broken: mistake))
    assert_equal "crosslint: .config/crosslint/config.kdl: lists nothing\n",
      check("check", app: app(broken: CrossLint::Core::Mistake.new("lists nothing", file: ".config/crosslint/config.kdl")))[1]
  end

  def test_update_moves_each_shared_plugin_and_says_so_on_standard_error
    app, configuration = update_app
    lines = ["crosslint: #{ONE}: moved from v1.0.0 to v1.2.0\n", "crosslint: #{TWO}: is at its newest tag, v3.0.0\n"]

    assert_equal ["", lines.join, 0], update("update", app:)
    assert_equal ["v1.2.0", "v3.0.0"], configuration.read("#{WORK}/app").plugins.map(&:ref)
  end

  def test_update_lists_what_it_would_move_and_changes_nothing_with_dry_run
    %w[--dry-run -n].each do |flag|
      app, configuration = update_app

      assert_equal ["", "crosslint: #{ONE}: would move from v1.0.0 to v1.2.0\ncrosslint: #{TWO}: is at its newest tag, v3.0.0\n", 0],
        update("update", flag, app:)
      assert_equal ["v1.0.0", "v3.0.0"], configuration.read("#{WORK}/app").plugins.map(&:ref)
    end
  end

  def test_update_stays_within_the_compatible_versions_and_moves_to_the_highest_with_latest
    tags = %w[v1.0.0 v1.2.0 v2.0.0]
    app, configuration = update_app(one: tags)

    assert_equal ["", "crosslint: #{ONE}: moved from v1.0.0 to v1.2.0; newer incompatible versions: v2.0.0; crosslint update --latest moves to v2.0.0, or, when v2.0.0 needs a newer CrossLint, to the newest tag below it that this CrossLint reads\n" \
      "crosslint: #{TWO}: is at its newest tag, v3.0.0\n", 0], update("update", app:)
    assert_equal "v1.2.0", configuration.read("#{WORK}/app").plugins.first.ref

    app, configuration = update_app(one: tags)

    assert_equal ["", "crosslint: #{ONE}: would move from v1.0.0 to v2.0.0\ncrosslint: #{TWO}: is at its newest tag, v3.0.0\n", 0], update("update", "--latest", "-n", app:)
    assert_equal "v1.0.0", configuration.read("#{WORK}/app").plugins.first.ref
    assert_equal 0, update("update", "--latest", app:)[2]
    assert_equal "v2.0.0", configuration.read("#{WORK}/app").plugins.first.ref
  end

  def test_update_says_what_it_did_unless_silent
    assert_equal 2, update("update", "--quiet", app: update_app.first)[1].lines.size
    assert_equal ["", "", 0], update("update", "--silent", app: update_app.first)
  end

  def test_update_finds_the_project_from_the_project_flag
    app, configuration = update_app

    assert_equal 0, update("update", "-C", "#{WORK}/app/lib", app:)[2]
    assert_equal "v1.2.0", configuration.read("#{WORK}/app").plugins.first.ref
  end

  def test_update_names_the_file_and_line_of_a_plugin_whose_tags_it_cant_list
    app, = update_app(missing: true)

    assert_equal ["", "crosslint: .config/crosslint/config.kdl:2: couldn't list the tags of shared plugin #{TWO}: no repository at #{TWO}\n", 2],
      update("update", app:)
  end

  def test_init_writes_the_configuration_and_says_so_on_standard_error
    configuration = CrossLint::Adapters::MemoryConfiguration.new
    out, err, status = init("init", app: CrossLint::App.new(configuration:))

    assert_equal ["", "crosslint: wrote .config/crosslint/config.kdl, with the recommended plugins: debt\n", 0], [out, err, status]
    assert_equal ["debt"], configuration.read("#{WORK}/app").plugins.map(&:name)
  end

  def test_init_says_what_it_did_unless_silent
    assert_equal ["", "", 0], init("init", "--silent", app: CrossLint::App.new(configuration: CrossLint::Adapters::MemoryConfiguration.new))
    assert_equal 1, init("init", "--quiet", app: CrossLint::App.new(configuration: CrossLint::Adapters::MemoryConfiguration.new))[1].lines.size
  end

  def test_init_refuses_to_replace_a_configuration_unless_it_is_forced
    app, configuration = update_app

    assert_equal ["", "crosslint: .config/crosslint/config.kdl: already exists, and crosslint init changes nothing in it; crosslint init --force replaces it\n", 2],
      init("init", app:)
    assert_equal [ONE, TWO], configuration.read("#{WORK}/app").plugins.map(&:name)
    %w[--force -f].each do |flag|
      app, configuration = update_app

      assert_equal ["", "crosslint: replaced .config/crosslint/config.kdl, with the recommended plugins: debt\n", 0], init("init", flag, app:)
      assert_equal ["debt"], configuration.read("#{WORK}/app").plugins.map(&:name)
    end
  end

  def test_init_lists_what_it_would_write_and_writes_nothing_with_dry_run
    %w[--dry-run -n].each do |flag|
      configuration = CrossLint::Adapters::MemoryConfiguration.new

      assert_equal ["", "crosslint: would write .config/crosslint/config.kdl, with the recommended plugins: debt\n", 0],
        init("init", flag, app: CrossLint::App.new(configuration:))
      refute configuration.exist?("#{WORK}/app")
    end
  end

  def test_init_writes_in_the_current_folder_unless_it_is_told_otherwise
    Dir.mktmpdir do |project|
      assert_equal ["", "crosslint: wrote .config/crosslint/config.kdl, with the recommended plugins: debt\n", 0],
        Dir.chdir(project) { run_cli("init", spec: shipped_spec) }
      assert_equal %(plugin "debt"\n), File.binread(File.join(project, ".config/crosslint/config.kdl"))
    end
  end

  def test_init_from_ng_nudge_says_each_change_before_it_makes_it_and_what_to_do_next
    app, configuration, debt_files = ng_nudge_app({"srcDir" => "./app/"})
    lines = ["crosslint: will write .config/crosslint/config.kdl, with the plugins angular and debt\n",
      "crosslint: will move .config/ng-nudge/debt.tsv to .config/crosslint/debt.tsv, byte for byte, with 0 entries\n",
      %(crosslint: will convert srcDir "./app/" to src-dir "app"\n),
      %(crosslint: will set src-dir "app" in the angular plugin\n), "crosslint: #{CrossLint::CLI::NEXT_STEPS}\n"]

    assert_equal ["", lines.join, 0], init("init", "--from-ng-nudge", app:)
    assert_equal [%w[angular debt], false], [configuration.read("#{WORK}/app").plugins.map(&:name), debt_files.exist?("#{WORK}/app", ".config/ng-nudge/debt.tsv")]
    assert_equal "moved from ng-nudge; next, replace ng-nudge's dev dependency and each npx ng-nudge in your scripts and CI with crosslint check, " \
      "and run crosslint debt update once", CrossLint::CLI::NEXT_STEPS
  end

  def test_init_from_ng_nudge_says_each_file_node_glob_and_crosslint_find_differently_after_the_changes_and_before_what_to_do_next
    app, = ng_nudge_app({}, globs: {"**/*.pipe.ts" => %w[a.pipe.ts]}, files: %w[src/b.pipe.ts])
    err = init("init", "--from-ng-nudge", app:)[1]

    assert_equal ["crosslint: will write .config/crosslint/config.kdl, with the plugins angular and debt\n",
      "crosslint: will move .config/ng-nudge/debt.tsv to .config/crosslint/debt.tsv, byte for byte, with 0 entries\n",
      "crosslint: node-glob finds src/a.pipe.ts as a pipe, and CrossLint doesn't\n", "crosslint: CrossLint finds src/b.pipe.ts as a pipe, and node-glob doesn't\n",
      "crosslint: #{CrossLint::Core::NgNudge::Move::WHY}\n", "crosslint: #{CrossLint::CLI::NEXT_STEPS}\n"], err.lines
    assert_equal "", init("init", "--from-ng-nudge", "--silent", app: ng_nudge_app({}, globs: {"**/*.pipe.ts" => %w[a.pipe.ts]}).first)[1]
  end

  def test_init_from_ng_nudge_moves_a_project_and_says_the_differences_with_a_glob_the_project_has_and_git
    Dir.mktmpdir do |project|
      write(project, ".config/ng-nudge/rc.json", "{}")
      write(project, "src/app/a.pipe.ts", "")
      write(project, "src/app/.x/b.pipe.ts", "")
      write(project, "node_modules/glob/index.js", "exports.glob = async (pattern) => pattern === '**/*.pipe.ts' ? ['app/a.pipe.ts', 'app/c.pipe.ts', 'app/.x/b.pipe.ts'] : [];\n")
      Open3.capture3("git", "init", "-q", chdir: project)
      out, err, status = run_cli("init", "--from-ng-nudge", "-C", project, spec: shipped_spec)

      assert_equal ["", 0], [out, status]
      assert_includes err, "crosslint: node-glob finds src/app/.x/b.pipe.ts as a pipe, and CrossLint doesn't\n"
      assert_includes err, "crosslint: node-glob finds src/app/c.pipe.ts as a pipe, and CrossLint doesn't\n"
      assert_includes err, "crosslint: #{CrossLint::Core::NgNudge::Move::WHY}\n"
      refute_includes err, "src/app/a.pipe.ts"
      assert File.file?(File.join(project, ".config/crosslint/config.kdl"))
    end
  end

  def test_init_from_ng_nudge_lists_what_it_would_change_and_changes_nothing_with_dry_run
    %w[--dry-run -n].each do |flag|
      app, configuration, debt_files = ng_nudge_app({})
      lines = "crosslint: would write .config/crosslint/config.kdl, with the plugins angular and debt\n" \
        "crosslint: would move .config/ng-nudge/debt.tsv to .config/crosslint/debt.tsv, byte for byte, with 0 entries\n"

      assert_equal ["", lines, 0], init("init", "--from-ng-nudge", flag, app:)
      refute configuration.exist?("#{WORK}/app")
      assert debt_files.exist?("#{WORK}/app", ".config/ng-nudge/debt.tsv")
    end
  end

  def test_init_from_ng_nudge_makes_the_changes_and_says_nothing_with_silent
    app, configuration, = ng_nudge_app({})

    assert_equal ["", "", 0], init("init", "--from-ng-nudge", "--silent", app:)
    assert configuration.exist?("#{WORK}/app")
  end

  def test_init_from_ng_nudge_replaces_what_is_there_only_with_force
    app, configuration, = ng_nudge_app({}, existing: true)
    refusal = "crosslint: .config/crosslint/config.kdl: already exists, and crosslint init --from-ng-nudge changes nothing in the configuration; " \
      "crosslint init --from-ng-nudge --force replaces it\n"

    assert_equal ["", refusal, 2], init("init", "--from-ng-nudge", app:)
    assert_equal [], configuration.read("#{WORK}/app").plugins
    %w[--force -f].each do |flag|
      app, configuration, = ng_nudge_app({}, existing: true)

      assert_equal 0, init("init", "--from-ng-nudge", flag, app:)[2]
      assert_equal ["angular", "debt"], configuration.read("#{WORK}/app").plugins.map(&:name)
    end
  end

  def test_init_from_ng_nudge_names_the_key_it_cannot_carry_and_exits_with_2
    app, configuration, = ng_nudge_app({"rules" => {"has-debt" => {"withComment" => 3}}})

    assert_equal ["", "crosslint: .config/ng-nudge/rc.json: rules.has-debt.withComment: is 3, and it takes true, false, \"none\", \"warning\", \"error\", " \
      "or an object with maxSeverity and matching\n", 2], init("init", "--from-ng-nudge", app:)
    refute configuration.exist?("#{WORK}/app")
  end

  def test_init_from_ng_nudge_says_every_problem_on_a_line_of_its_own_and_exits_with_2
    app, configuration, = ng_nudge_app({"srcDir" => "../x", "options" => {"verbosity" => "loud"}})

    assert_equal ["", "crosslint: .config/ng-nudge/rc.json: srcDir: is \"../x\", which is outside the project; write a path inside it, relative to the project's root\n" \
      "crosslint: .config/ng-nudge/rc.json: options.verbosity: is \"loud\", and it takes \"normal\", \"quiet\", or \"silent\"\n", 2], init("init", "--from-ng-nudge", app:)
    refute configuration.exist?("#{WORK}/app")
  end

  def test_init_from_ng_nudge_moves_a_project_with_the_real_files_and_node
    Dir.mktmpdir do |project|
      rc = {"srcDir" => "./app/", "artifacts" => {"store" => {"pattern" => "**/*.store.ts", "expects" => ["spec"]}},
            "rules" => {"has-debt" => {"severity" => "warning", "withComment" => {"maxSeverity" => "warning", "matching" => "^ticket-\\d+\\b"}},
                        "prefer-css-over-scss" => {"enabled" => false}}, "options" => {"verbosity" => "quiet"}}
      debt = "Rule\tArtifact\tComment\r\nspec-exists\tapp/card\tticket-12 later\r\nstub-exists\tapp/list\t\r\n"
      File.binwrite(File.join(project, ".config/ng-nudge/rc.json").tap { |path| FileUtils.mkdir_p(File.dirname(path)) }, JSON.generate(rc))
      File.binwrite(File.join(project, ".config/ng-nudge/debt.tsv"), debt)
      out, err, status = run_cli("init", "--from-ng-nudge", "-C", project, spec: shipped_spec)

      assert_equal ["", 0], [out, status]
      assert_includes err, "crosslint: will move .config/ng-nudge/debt.tsv to .config/crosslint/debt.tsv, byte for byte, with 2 entries\n"
      assert_includes err, "crosslint: couldn't compare the files node-glob finds with the files CrossLint finds, since the project has no glob package\n"
      assert_equal debt.b, File.binread(File.join(project, ".config/crosslint/debt.tsv"))
      refute File.exist?(File.join(project, ".config/ng-nudge/debt.tsv"))
      assert_equal <<~KDL, File.read(File.join(project, ".config/crosslint/config.kdl"), encoding: Encoding::UTF_8)
        plugin "angular" {
          src-dir "app"
          role "store" files="{path}.store.ts" {
            expects "spec"
          }
        }
        plugin "debt" {
          report-entries commented="warning" matching="\\\\Aticket-\\\\d+(?:(?<![A-Za-z0-9_])(?=[A-Za-z0-9_])|(?<=[A-Za-z0-9_])(?![A-Za-z0-9_]))"
        }

        policy "debt/has-debt" severity="warning"
        policy "angular/prefer-css-over-scss" enabled=#false

        verbosity "quiet"
      KDL
      assert_equal %w[angular debt], CrossLint::App.new(crosslint_ruby: LoadedPlugins::CrossLintRuby.new).load_project(project).plugins.map(&:name)
    end
  end

  def test_init_from_ng_nudge_refuses_a_matching_when_node_is_not_there_and_changes_nothing
    Dir.mktmpdir do |project|
      rc = {"rules" => {"has-debt" => {"withComment" => {"maxSeverity" => "none", "matching" => "^TODO"}}}}
      write(project, ".config/ng-nudge/rc.json", JSON.generate(rc))
      write(project, ".config/ng-nudge/debt.tsv", "Rule\tArtifact\tComment\nspec-exists\tapp/card\tTODO\n")
      app = CrossLint::App.new(javascript: CrossLint::Adapters::NodeJavaScript.new(command: "crosslint-no-such-node"))
      out, err, status = run_cli("init", "--from-ng-nudge", "-C", project, spec: shipped_spec, app:)

      assert_equal ["", 2], [out, status]
      assert_match(/\Acrosslint: \.config\/ng-nudge\/rc\.json: rules\.has-debt\.withComment\.matching: CrossLint tests the expression, "\^TODO", with JavaScript on each comment of the debt file, and couldn't run crosslint-no-such-node/, err)
      refute File.exist?(File.join(project, ".config/crosslint"))
      assert File.exist?(File.join(project, ".config/ng-nudge/debt.tsv"))
    end
  end

  def test_init_from_ng_nudge_refuses_a_matching_node_rejects_and_says_what_node_said_and_changes_nothing
    ["^*", "\\b+", "${2}"].each do |expression|
      Dir.mktmpdir do |project|
        rc = {"rules" => {"has-debt" => {"withComment" => {"maxSeverity" => "none", "matching" => expression}}}}
        write(project, ".config/ng-nudge/rc.json", JSON.generate(rc))
        write(project, ".config/ng-nudge/debt.tsv", "Rule\tArtifact\tComment\n")
        out, err, status = run_cli("init", "--from-ng-nudge", "-C", project, spec: shipped_spec)

        assert_equal ["", 2], [out, status]
        assert_match(/\Acrosslint: \.config\/ng-nudge\/rc\.json: rules\.has-debt\.withComment\.matching: is #{Regexp.escape(expression.dump)}, which JavaScript refuses: Invalid regular expression: .*: Nothing to repeat; write it another way, or remove it\n\z/, err)
        refute File.exist?(File.join(project, ".config/crosslint"))
        assert File.exist?(File.join(project, ".config/ng-nudge/debt.tsv"))
      end
    end
  end

  def test_init_names_the_folder_that_does_not_exist
    missing = File.join(Dir.tmpdir, "crosslint-missing-#{SecureRandom.hex(8)}")

    assert_equal ["", "crosslint: no folder #{missing}\n", 2], run_cli("init", "-C", missing, spec: shipped_spec)
  end

  def test_update_builds_the_app_it_needs_and_works_from_the_current_folder_unless_it_is_told_otherwise
    Dir.mktmpdir do |base|
      url = "https://example.test/#{SecureRandom.hex(8)}/signatures"
      origin = repository_at(File.join(base, "origin", "signatures"), {"plugin.kdl" => ""}, tags: %w[v1.0.0 v1.2.0])
      config = write(base, "project/.config/crosslint/config.kdl", %(plugin "#{url}" ref="v1.0.0"\n))
      out, err, status = rewriting(url, origin) { Dir.chdir(File.join(base, "project")) { run_cli("update", spec: shipped_spec) } }

      assert_equal ["", "crosslint: listing the tags of #{url}\ncrosslint: fetching #{url} at v1.2.0\ncrosslint: #{url}: moved from v1.0.0 to v1.2.0\n", 0],
        [out, err, status]
      assert_equal %(plugin "#{url}" ref="v1.2.0"\n), File.binread(config)
    end
  end

  def test_update_says_nothing_it_is_not_asked_to_when_no_plugin_is_shared
    Dir.mktmpdir do |project|
      write(project, ".config/crosslint/config.kdl", %(plugin ".config/crosslint/tests"\n))

      assert_equal ["", "", 0], run_cli("update", "-C", project, spec: shipped_spec)
    end
  end

  private

  ONE = "https://example.com/OWNER/one"
  TWO = "https://example.com/OWNER/two"

  # An app, and the configuration it holds, for the project at WORK/app,
  # which lists the shared plugins ONE at v1.0.0 and TWO at v3.0.0,
  # whose repositories have tags to move ONE to v1.2.0.
  def update_app(missing: false, one: %w[v1.0.0 v1.2.0])
    core = CrossLint::Core
    plugins = [core::ListedPlugin.new(name: ONE, ref: "v1.0.0", settings: [], line: 1), core::ListedPlugin.new(name: TWO, ref: "v3.0.0", settings: [], line: 2)]
    configuration = CrossLint::Adapters::MemoryConfiguration.new({"#{WORK}/app" => core::Configuration.new(file: ".config/crosslint/config.kdl", plugins:,
      policies: [], warnings: nil, verbosity: nil)})
    tags = ->(names) { CrossLint::Adapters::MemorySharedPlugins::Repository.new(tags: names.to_h { |name| [name, "/cache/#{name}"] }, branches: [], commits: {}) }
    repositories = {ONE => tags.call(one)}
    repositories[TWO] = tags.call(%w[v3.0.0]) unless missing
    shared_plugins = CrossLint::Adapters::MemorySharedPlugins.new(repositories, err: StringIO.new)
    [CrossLint::App.new(configuration:, shared_plugins:), configuration]
  end

  # An app that holds an ng-nudge project at WORK/app, with the rc.json
  # `rc` and an empty debt file, and the configuration and debt files it
  # holds. With `existing`, the project has a configuration already.
  def ng_nudge_app(rc, existing: false, globs: {}, files: [])
    core = CrossLint::Core
    root = "#{WORK}/app"
    configuration = CrossLint::Adapters::MemoryConfiguration.new
    configuration.write(root, core::Configuration.new(file: ".config/crosslint/config.kdl", plugins: [], policies: [], warnings: nil, verbosity: nil)) if existing
    debt = core::DebtFile.new(file: ".config/ng-nudge/debt.tsv", entries: [], header: "Rule\tArtifact\tComment\n")
    debt_files = CrossLint::Adapters::MemoryDebtFiles.new({File.join(root, ".config/ng-nudge/debt.tsv") => debt})
    ng_nudge = CrossLint::Adapters::MemoryNgNudge.new({root => {".config/ng-nudge/rc.json" => JSON.generate(rc)}})
    javascript = CrossLint::Adapters::MemoryJavaScript.new({}, globs: globs)
    project_files = CrossLint::Adapters::MemoryProjectFiles.new({root => files})
    [CrossLint::App.new(configuration:, debt_files:, ng_nudge:, javascript:, project_files:), configuration, debt_files]
  end

  # What init prints in the project at WORK/app, as update does.
  def init(*argv, app:) = update(*argv, app:)

  def update(*argv, app:)
    argv += ["-C", "#{WORK}/app"] unless argv.include?("-C")
    out = StringIO.new
    err = StringIO.new
    status = CrossLint::CLI.new(argv, out:, err:, env: {}, spec: shipped_spec, app:).run
    [out.string, err.string, status]
  end

  # Standard output on a terminal.
  class Terminal < StringIO
    def tty? = true
  end

  def run_cli(*argv, spec: fixture_spec, env: {}, app: nil)
    out = StringIO.new
    err = StringIO.new
    status = CrossLint::CLI.new(argv, out:, err:, env:, spec:, app:).run
    [out.string, err.string, status]
  end

  # What crosslint prints for help with the words in argv, in the project
  # the app holds, which -C names before the words, since --help ends the
  # reading of the line.
  def helping(*argv, app:) = check("-C", "#{WORK}/app", *argv, app:)

  def check(*argv, app: nil, tty: false, env: {}, err_tty: false)
    argv += ["-C", "#{WORK}/app"] if app && !argv.include?("-C") && !argv.include?("--project")
    out = tty ? Terminal.new : StringIO.new
    err = err_tty ? Terminal.new : StringIO.new
    status = CrossLint::CLI.new(argv, out:, err:, env:, spec: shipped_spec, app:).run
    [out.string, err.string, status]
  end

  SHARED = "https://example.com/OWNER/signatures"

  # The manifests of the built-in plugins in CrossLint's plugins folder:
  # debt has a step and its command update, and angular has neither.
  def built_in_manifests(flags = nil)
    core = CrossLint::Core
    step = core::StepDeclaration.new(name: "track-debt", line: 1)
    update = core::CommandDeclaration.new(name: "update", help: "Rewrite the debt file to list the current violations", line: 2,
      flags: flags || [core::CommandFlag.new(short: "n", long: "dry-run", value: nil, help: "List the entries update would add and remove, and write nothing", line: 3)])
    {File.join(CrossLint::App::PLUGINS, "debt") => core::Manifest.new(file: "debt/plugin.kdl", artifacts: [], policies: [], rules: [], helpers: [],
      step_policies: [core::StepPolicy.new(name: "has-debt", line: 3)], steps: [step], commands: [update]),
     File.join(CrossLint::App::PLUGINS, "angular") => core::Manifest.new(file: "angular/plugin.kdl", artifacts: [], policies: [], rules: [], helpers: [])}
  end

  # A rule that raises.
  RAISES_SOURCE = "class Raises < CrossLint::Rule; def check(_) = raise('boom'); end"

  RAISES = ->(namespace) { namespace.module_eval(RAISES_SOURCE, "raises.rb", 1) }

  # A project with the plugin tests: every lib/{path}.rb has a test at
  # test/{path}_test.rb, and only lib/a.rb has one.
  #
  # With debt, the project also lists the built-in debt plugin, and with
  # shared, a shared plugin that isn't fetched.
  def app(files: ["lib/a.rb", "lib/b.rb", "test/a_test.rb"], severity: nil, unused: false, warnings: nil, verbosity: nil, broken: nil, raises: false,
    debt: false, shared: false, fetch_log: StringIO.new, debt_flags: nil)
    core = CrossLint::Core
    listed = [core::ListedPlugin.new(name: "./.config/tests", ref: nil, settings: [], line: 1)]
    listed.unshift(core::ListedPlugin.new(name: "debt", ref: nil, settings: [], line: 2)) if debt
    listed << core::ListedPlugin.new(name: SHARED, ref: "v1.0.0", settings: [], line: 3) if shared
    rules = unused ? [core::RuleDeclaration.new(name: "unused", ruby: "unused.rb", line: 3)] : []
    rules << core::RuleDeclaration.new(name: "raises", ruby: "raises.rb", line: 4) if raises
    artifact = core::ArtifactDeclaration.new(name: "ruby-file", primary: core::PathPattern.new(source: "lib/{path}.rb"), line: 1,
      pieces: [core::PieceDeclaration.new(name: "test", pattern: core::PathPattern.new(source: "test/{path}_test.rb"), line: 2)])
    policy = core::Policy.new(name: "has-test", applies_to: core::AppliesTo.new(artifact: "ruby-file", line: 6), condition: nil, line: 5,
      rules: [core::PolicyRule.new(name: "piece-exists", arguments: {"piece" => "test"}, severity:, line: 7)] +
        (raises ? [core::PolicyRule.new(name: "raises", arguments: {}, severity: nil, line: 8)] : []))
    manifest = core::Manifest.new(file: ".config/tests/plugin.kdl", artifacts: [artifact], policies: [policy], rules:, helpers: [])
    configuration = core::Configuration.new(file: ".config/crosslint/config.kdl", plugins: listed, policies: [], warnings:, verbosity:)
    CrossLint::App.new(configuration: CrossLint::Adapters::MemoryConfiguration.new({"#{WORK}/app" => broken || configuration}),
      manifests: CrossLint::Adapters::MemoryPluginManifests.new({"#{WORK}/app/.config/tests" => manifest}.merge(built_in_manifests(debt_flags))),
      debt_files: CrossLint::Adapters::MemoryDebtFiles.new,
      shared_plugins: CrossLint::Adapters::MemorySharedPlugins.new({}, err: fetch_log),
      project_files: CrossLint::Adapters::MemoryProjectFiles.new({"#{WORK}/app" => files}),
      crosslint_ruby: CrossLint::Adapters::MemoryCrossLintRuby.new({"#{WORK}/app/.config/tests/raises.rb" => RAISES}))
  end
end
