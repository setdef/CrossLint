# frozen_string_literal: true

require "test_helper"
require "json"

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

  def test_writes_the_text_of_an_error_as_it_is_to_standard_error
    _, err, = run_cli(spec: BrokenSpec.new(RuntimeError.new("bôom \xFF".b.force_encoding("UTF-8"))))

    assert_equal "crosslint: stopped on a bug in CrossLint: RuntimeError: bôom \xFF\n".b, err.lines.first.b
  end

  def test_check_prints_each_violation_and_the_summary_and_exits_with_1
    assert_equal ["lib/b.rb: no test file at test/b_test.rb (tests/has-test)\n",
      "crosslint: checked 2 ruby-file artifacts: 1 error\n", 1], check("check", app: app)
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

  def test_check_lists_passing_artifacts_with_all
    assert_equal "lib/a.rb: ruby-file passes\nlib/b.rb: no test file at test/b_test.rb (tests/has-test)\n",
      check("check", "-a", app: app)[0]
    assert_equal check("check", "-a", app: app), check("check", "--all", app: app)
  end

  def test_check_prints_json_with_json
    out, err, status = check("check", "--json", app: app)

    assert_equal [{"path" => "lib/b.rb", "message" => "no test file at test/b_test.rb", "plugin" => "tests", "policy" => "has-test",
                   "artifact" => "lib/b.rb", "role" => "ruby-file", "severity" => "error", "detail" => nil}], JSON.parse(out).fetch("findings")
    assert_equal ["crosslint: checked 2 ruby-file artifacts: 1 error\n", 1], [err, status]
  end

  def test_check_refuses_to_update_the_debt
    assert_equal ["", "crosslint: --update-debt needs the debt plugin, which doesn't work yet\n", 2],
      check("check", "--update-debt", app: app)
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

  def test_check_names_the_file_and_line_of_a_mistake
    mistake = CrossLint::Core::Mistake.new(%(unknown node "file", did you mean "files"?), file: ".config/tests/plugin.kdl", line: 2)

    assert_equal ["", %(crosslint: .config/tests/plugin.kdl:2: unknown node "file", did you mean "files"?\n), 2],
      check("check", app: app(broken: mistake))
    assert_equal "crosslint: .config/crosslint/config.kdl: lists nothing\n",
      check("check", app: app(broken: CrossLint::Core::Mistake.new("lists nothing", file: ".config/crosslint/config.kdl")))[1]
  end

  private

  # Standard output on a terminal.
  class Terminal < StringIO
    def tty? = true
  end

  def run_cli(*argv, spec: fixture_spec, env: {})
    out = StringIO.new
    err = StringIO.new
    status = CrossLint::CLI.new(argv, out:, err:, env:, spec:).run
    [out.string, err.string, status]
  end

  def check(*argv, app: nil, tty: false, env: {})
    argv += ["-C", "#{WORK}/app"] if app && !argv.include?("-C") && !argv.include?("--project")
    out = tty ? Terminal.new : StringIO.new
    err = StringIO.new
    status = CrossLint::CLI.new(argv, out:, err:, env:, spec: shipped_spec, app:).run
    [out.string, err.string, status]
  end

  # A rule that raises.
  RAISES_SOURCE = "class Raises < CrossLint::Rule; def check(_) = raise('boom'); end"

  RAISES = ->(namespace) { namespace.module_eval(RAISES_SOURCE, "raises.rb", 1) }

  # A project with the plugin tests: every lib/{path}.rb has a test at
  # test/{path}_test.rb, and only lib/a.rb has one.
  def app(files: ["lib/a.rb", "lib/b.rb", "test/a_test.rb"], severity: nil, unused: false, warnings: nil, verbosity: nil, broken: nil, raises: false)
    core = CrossLint::Core
    listed = [core::ListedPlugin.new(name: "./.config/tests", ref: nil, settings: [], line: 1)]
    rules = unused ? [core::RuleDeclaration.new(name: "unused", ruby: "unused.rb", line: 3)] : []
    rules << core::RuleDeclaration.new(name: "raises", ruby: "raises.rb", line: 4) if raises
    artifact = core::ArtifactDeclaration.new(name: "ruby-file", files: core::PathPattern.new(source: "lib/{path}.rb"), line: 1,
      companions: [core::CompanionDeclaration.new(name: "test", pattern: core::PathPattern.new(source: "test/{path}_test.rb"), line: 2)])
    policy = core::Policy.new(name: "has-test", applies_to: core::AppliesTo.new(artifact: "ruby-file", line: 6), condition: nil, line: 5,
      rules: [core::PolicyRule.new(name: "companion-exists", arguments: {"companion" => "test"}, severity:, line: 7)] +
        (raises ? [core::PolicyRule.new(name: "raises", arguments: {}, severity: nil, line: 8)] : []))
    manifest = core::Manifest.new(file: ".config/tests/plugin.kdl", artifacts: [artifact], policies: [policy], rules:, helpers: [])
    configuration = core::Configuration.new(file: ".config/crosslint/config.kdl", plugins: listed, policies: [], warnings:, verbosity:)
    CrossLint::App.new(configuration: CrossLint::Adapters::MemoryConfiguration.new({"#{WORK}/app" => broken || configuration}),
      manifests: CrossLint::Adapters::MemoryPluginManifests.new({"#{WORK}/app/.config/tests" => manifest}),
      project_files: CrossLint::Adapters::MemoryProjectFiles.new({"#{WORK}/app" => files}),
      plugin_ruby: CrossLint::Adapters::MemoryPluginRuby.new({"#{WORK}/app/.config/tests/raises.rb" => RAISES}))
  end
end
