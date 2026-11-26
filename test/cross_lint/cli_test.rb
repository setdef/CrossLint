# frozen_string_literal: true

require "test_helper"

class CLITest < Minitest::Test
  cover "CrossLint::CLI*"

  # A spec that raises +error+ when CrossLint reads its flags.
  class BrokenSpec
    def initialize(error) = @error = error
    def flags = raise(@error)
  end

  def test_prints_the_version
    assert_equal ["tool 1.2.3\n", "", 0], run_cli("--version")
  end

  def test_prints_the_help
    help = CrossLint::Help.new(fixture_spec)

    assert_equal [help.render, "", 0], run_cli("--help")
    assert_equal [help.render, "", 0], run_cli
    assert_equal [help.render(fixture_spec.commands.first), "", 0], run_cli("run", "--help")
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
      crosslint: please report it at https://github.com/setdef/CrossLint/issues, with the command you ran and what crosslint --version prints
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
    assert_equal "crosslint: please report it at https://github.com/setdef/CrossLint/issues, with the command you ran and what crosslint --version prints", lines[1]
    assert_match(/\Acrosslint:   from .*cli_test\.rb:\d+:in 'CLITest::BrokenSpec#flags'\z/, lines[2])
    assert_operator lines.size, :>, 3
    assert(lines.drop(2).all? { |line| line.start_with?("crosslint:   from ") })
  end

  def test_shows_where_a_bug_stopped_it_when_debug_is_set
    _, err, = run_cli(spec: BrokenSpec.new(RuntimeError.new("boom")), env: {"DEBUG" => "1"})

    assert_match(/\Acrosslint:   from /, err.lines[2])
    _, err, = run_cli(spec: BrokenSpec.new(RuntimeError.new("boom")), env: {"DEBUG" => ""})

    assert_equal "crosslint: run it again with --debug to see where it stopped\n", err.lines[2]
  end

  def test_writes_only_ascii_to_standard_error
    _, err, = run_cli(spec: BrokenSpec.new(RuntimeError.new("bôom \xFF".b.force_encoding("UTF-8"))))

    assert_equal "crosslint: stopped on a bug in CrossLint: RuntimeError: b?om ?\n", err.lines.first
  end

  private

  def run_cli(*argv, spec: fixture_spec, env: {})
    out = StringIO.new
    err = StringIO.new
    status = CrossLint::CLI.new(argv, out:, err:, env:, spec:).run
    [out.string, err.string, status]
  end
end
