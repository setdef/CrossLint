# frozen_string_literal: true

require "test_helper"

class CLITest < Minitest::Test
  cover "CrossLint::CLI*"

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

  def test_writes_only_ascii_to_standard_error
    _, err, = run_cli(spec: BrokenSpec.new(RuntimeError.new("bôom \xFF".b.force_encoding("UTF-8"))))

    assert_equal "crosslint: stopped on a bug in CrossLint: RuntimeError: b?om ?\n", err.lines.first
  end

  def test_check_reads_the_project_and_says_checking_files_does_not_work_yet
    assert_equal ["", "crosslint: read .config/crosslint.kdl and 1 plugin; checking files doesn't work yet\n", 2],
      check("check", app: app(plugins: ["tests"]))
    assert_equal "crosslint: read .config/crosslint.kdl and 2 plugins; checking files doesn't work yet\n",
      check("check", app: app(plugins: ["tests", "other"]))[1]
  end

  def test_check_finds_the_project_from_the_project_flag
    read = "crosslint: read .config/crosslint.kdl and 1 plugin; checking files doesn't work yet\n"

    assert_equal read, check("check", "-C", "#{WORK}/app/lib", app: app)[1]
    assert_equal read, check("check", "--project", "#{WORK}/app", app: app)[1]
    assert_match(/\Acrosslint: no \.config\/crosslint\.kdl in .*elsewhere or any folder above it/,
      check("check", "-C", "#{TOP}elsewhere", app: app)[1])
  end

  def test_check_warns_of_each_ruby_rule_no_policy_runs
    warning = %(crosslint: .config/tests/plugin.kdl:3: warning: no policy runs rule "unused", so CrossLint doesn't load it\n)

    assert_equal warning, check("check", app: app(unused: true))[1].lines.first
    assert_equal warning, check("check", app: app(unused: true, verbosity: :normal))[1].lines.first
    [["-q"], ["--silent"]].each { |flags| assert_equal 1, check("check", *flags, app: app(unused: true))[1].lines.size }
    %i[quiet silent].each { |verbosity| assert_equal 1, check("check", app: app(unused: true, verbosity:))[1].lines.size }
  end

  def test_check_reads_the_project_in_the_folder_it_runs_in_or_a_folder_relative_to_it
    Dir.mktmpdir("crosslint") do |folder|
      write(folder, "app/.config/crosslint.kdl", %(plugin "."\n))
      write(folder, "app/plugin.kdl", %(helper "h" command="node" file="h.mjs"\n))
      FileUtils.mkdir_p(File.join(folder, "app/lib"))
      read = ["", "crosslint: read .config/crosslint.kdl and 1 plugin; checking files doesn't work yet\n", 2]

      assert_equal read, Dir.chdir(File.join(folder, "app/lib")) { check("check") }
      assert_equal read, Dir.chdir(folder) { check("check", "-C", "app/lib") }
    end
  end

  def test_check_names_the_file_and_line_of_a_mistake
    mistake = CrossLint::Core::Mistake.new(%(unknown node "file", did you mean "files"?), file: ".config/tests/plugin.kdl", line: 2)

    assert_equal ["", %(crosslint: .config/tests/plugin.kdl:2: unknown node "file", did you mean "files"?\n), 2],
      check("check", app: app(broken: mistake))
    assert_equal "crosslint: .config/crosslint.kdl: lists nothing\n",
      check("check", app: app(broken: CrossLint::Core::Mistake.new("lists nothing", file: ".config/crosslint.kdl")))[1]
  end

  private

  def run_cli(*argv, spec: fixture_spec, env: {})
    out = StringIO.new
    err = StringIO.new
    status = CrossLint::CLI.new(argv, out:, err:, env:, spec:).run
    [out.string, err.string, status]
  end

  def check(*argv, app: nil)
    argv += ["-C", "#{WORK}/app"] if app && !argv.include?("-C") && !argv.include?("--project")
    out = StringIO.new
    err = StringIO.new
    status = CrossLint::CLI.new(argv, out:, err:, env: {}, spec: shipped_spec, app:).run
    [out.string, err.string, status]
  end

  def app(plugins: ["tests"], unused: false, verbosity: nil, broken: nil)
    core = CrossLint::Core
    listed = plugins.each_with_index.map { |name, index| core::ListedPlugin.new(name: "./.config/#{name}", ref: nil, settings: [], line: index + 1) }
    rules = unused ? [core::RuleDeclaration.new(name: "unused", ruby: "unused.rb", line: 3)] : []
    manifests = plugins.to_h do |name|
      ["#{WORK}/app/.config/#{name}", core::Manifest.new(file: ".config/#{name}/plugin.kdl", artifacts: [], policies: [], rules:, helpers: [])]
    end
    configuration = core::Configuration.new(file: ".config/crosslint.kdl", plugins: listed, policies: [], warnings: nil, verbosity:)
    CrossLint::App.new(configuration: CrossLint::Adapters::MemoryConfiguration.new({"#{WORK}/app" => broken || configuration}),
      manifests: CrossLint::Adapters::MemoryPluginManifests.new(manifests))
  end
end
