# frozen_string_literal: true

require "test_helper"
require "json"
require "open3"

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
    assert_equal ["", "crosslint: tool has no command runn; did you mean run?\n", 2], run_cli("help", "runn")
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

  # docs/design/checking.md: a line within 100 ms on a terminal, so a
  # large project never sits silent while a rule reads its files.
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

  def test_check_hands_a_flag_it_doesnt_read_to_the_plugins
    assert_equal ["", "crosslint: .config/crosslint/config.kdl: lists no plugin that takes --update-debt\n", 2],
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

  def test_check_writes_what_a_helper_writes_to_standard_error_with_debug
    Dir.mktmpdir("crosslint") do |project|
      write(project, ".config/crosslint/config.kdl", %(plugin "."\n))
      write(project, "plugin.kdl", %(artifact "a" {\n  files "{path}.md"\n}\nrule "asks" ruby="asks.rb"\nhelper "h" command="sh" file="h.sh"\n) +
        %(policy "p" {\n  applies-to "a"\n  rule "asks"\n}\n))
      write(project, "asks.rb", %(class Asks < CrossLint::Rule\n  def check(artifact) = (helper("h").call(1) && [])\nend\n))
      write(project, "h.sh", %(while read -r line; do echo said >&2; echo 1; done\n))
      write(project, "a.md", "")
      Open3.capture3("git", "init", "-q", chdir: project)

      assert_equal ["", "crosslint: checked 1 a artifact: no violations\n", 0], check("check", "-C", project)
      assert_equal "crosslint: helper h: said\n", check("check", "-C", project, "--debug")[1].lines.first
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

  def test_update_builds_the_app_it_needs_which_fetches_over_https_only_and_works_from_the_current_folder
    Dir.mktmpdir do |base|
      url = "https://example.test/#{SecureRandom.hex(8)}/signatures"
      origin = repository_at(File.join(base, "origin", "signatures"), {"plugin.kdl" => ""}, tags: %w[v1.0.0 v1.2.0])
      config = write(base, "project/.config/crosslint/config.kdl", %(plugin "#{url}" ref="v1.0.0"\n))
      out, err, status = rewriting(url, origin) { Dir.chdir(File.join(base, "project")) { run_cli("update", spec: shipped_spec) } }

      assert_equal ["", 2], [out, status]
      assert_operator err, :start_with?, "crosslint: listing the tags of #{url}\n"
      assert_match(%r{^crosslint: \.config/crosslint/config\.kdl:1: couldn't list the tags of shared plugin #{Regexp.escape(url)}: .*transport 'file' not allowed}m, err)
      assert_equal %(plugin "#{url}" ref="v1.0.0"\n), File.binread(config)
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
  def update_app(missing: false)
    core = CrossLint::Core
    plugins = [core::ListedPlugin.new(name: ONE, ref: "v1.0.0", settings: [], line: 1), core::ListedPlugin.new(name: TWO, ref: "v3.0.0", settings: [], line: 2)]
    configuration = CrossLint::Adapters::MemoryConfiguration.new({"#{WORK}/app" => core::Configuration.new(file: ".config/crosslint/config.kdl", plugins:,
      policies: [], warnings: nil, verbosity: nil)})
    tags = ->(names) { CrossLint::Adapters::MemorySharedPlugins::Repository.new(tags: names.to_h { |name| [name, "/cache/#{name}"] }, branches: [], commits: {}) }
    repositories = {ONE => tags.call(%w[v1.0.0 v1.2.0])}
    repositories[TWO] = tags.call(%w[v3.0.0]) unless missing
    shared_plugins = CrossLint::Adapters::MemorySharedPlugins.new(repositories, err: StringIO.new)
    [CrossLint::App.new(configuration:, shared_plugins:), configuration]
  end

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

  def run_cli(*argv, spec: fixture_spec, env: {})
    out = StringIO.new
    err = StringIO.new
    status = CrossLint::CLI.new(argv, out:, err:, env:, spec:).run
    [out.string, err.string, status]
  end

  def check(*argv, app: nil, tty: false, env: {}, err_tty: false)
    argv += ["-C", "#{WORK}/app"] if app && !argv.include?("-C") && !argv.include?("--project")
    out = tty ? Terminal.new : StringIO.new
    err = err_tty ? Terminal.new : StringIO.new
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
