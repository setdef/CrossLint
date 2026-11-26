# frozen_string_literal: true

require "test_helper"

# What a test of a helpers adapter shares: the plugin the contract
# describes.
module HelpersTestHelper
  def helper_plugin(command: nil)
    command ||= "sh"
    helpers = [CrossLint::Core::HelperDeclaration.new(name: "echo", command:, file: "echo.sh", line: 4),
      CrossLint::Core::HelperDeclaration.new(name: "fails", command:, file: "fails.sh", line: 5)]
    manifest = CrossLint::Core::Manifest.new(file: "tests/plugin.kdl", artifacts: [], policies: [], rules: [], helpers:)
    CrossLint::Core::Plugin.new(name: "tests", folder: File.join(helper_root, "tests"), manifest:,
      listing: CrossLint::Core::ListedPlugin.new(name: "./tests", ref: nil, settings: [], line: 1))
  end
end

# The helpers port as processes. A helper here is a shell script, run by
# sh, which the CI jobs and Git for Windows have.
class ProcessHelpersTest < Minitest::Test
  cover "CrossLint::Adapters::ProcessHelpers*"
  cover "CrossLint::Adapters::ProcessGroup*"

  include CrossLint::Testing::HelpersContract
  include HelpersTestHelper

  SCRIPTS = {
    "echo.sh" => %(while IFS= read -r line; do printf '{"echo":%s}\\n' "$line"; done\n),
    "fails.sh" => "printf '\\n nope\\n\\n' >&2\nexit 3\n",
    "hangs.sh" => "sleep 30 &\necho $! > hangs.pid\nwait\n",
    "garbage.sh" => "while read -r line; do echo 'not json, and a line longer than the eighty characters a message shows of it, cut off here'; done\n",
    "signals.sh" => "kill -9 $$\n",
    "short.sh" => "read -r line\necho nope\n",
    "once.sh" => "read -r line\necho '{}'\n",
    "quits.sh" => "exit 0\n",
    "talks.sh" => "while read -r line; do echo heard >&2; echo '{}'; done\n",
    "leaves.sh" => "read -r line\nsleep 30 &\necho $! > leaves.pid\necho '{}'\n",
    "stays.sh" => "read -r line\nsleep 30 &\necho $! > stays.pid\necho '{}'\nwait\n",
    "lingers.sh" => "read -r line\necho '{}'\nexec 0<&-\nwhile :; do sleep 1; done\n",
    "escapes.sh" => %(ruby -e 'Process.spawn(RbConfig.ruby, "-e", "sleep 8", pgroup: true)'\nread -r line\necho '{}'\n),
    "finishes.sh" => "while read -r line; do echo '{}'; done\nsleep 0.3\necho bye > finished.txt\n"
  }.freeze

  def setup
    @base = Dir.mktmpdir("crosslint")
    SCRIPTS.each { |name, script| write(@base, "tests/#{name}", script) }
  end

  def teardown
    FileUtils.rm_rf(@base)
  end

  def helpers_port = CrossLint::Adapters::ProcessHelpers.new(err: StringIO.new, debug: false)

  def helper_root = @base

  def test_waits_a_minute_for_each_answer_and_two_seconds_for_each_exit_unless_told_otherwise
    other = CrossLint::Adapters::ProcessHelpers.new(err: $stderr, debug: false, time_limit: 0.5, stop_limit: 0.25)

    assert_equal [[60, 2], [0.5, 0.25]], [helpers_port, other].map { |port| [port.time_limit, port.stop_limit] }
  end

  def test_reads_an_answer_as_utf_8_whatever_the_locale
    external = Encoding.default_external
    quietly { Encoding.default_external = Encoding::US_ASCII }
    running = start("echo")

    assert_equal({"echo" => "café"}, running.call(plugin_of("echo"), "echo", "café"))
    running.stop
  ensure
    quietly { Encoding.default_external = external }
  end

  def test_says_which_signal_ended_a_helper
    skip "Windows ends a process with a status, not a signal" if CrossLint::Adapters::ProcessHelpers::WINDOWS

    error = assert_raises(CrossLint::Core::PluginError) { start("signals").call(plugin_of("signals"), "signals", {}) }

    assert_equal "called helper signals, which exited with signal 9 before it answered", error.message
  end

  def test_ends_a_helper_that_doesnt_answer_with_everything_it_started
    running = start("hangs", time_limit: 0.5)
    error = assert_raises(CrossLint::Core::PluginError) { running.call(plugin_of("hangs"), "hangs", {}) }

    assert_equal "called helper hangs, which didn't answer within 0.5 seconds, so CrossLint ended it and everything it started", error.message
    assert_gone(File.read(wait_for_file(File.join(@base, "hangs.pid"))).strip)
  end

  def test_ends_a_helper_that_reads_nothing_however_much_it_is_asked
    running = start("hangs", time_limit: 0.5)
    error = Timeout.timeout(5) { assert_raises(CrossLint::Core::PluginError) { running.call(plugin_of("hangs"), "hangs", {"big" => "x" * 1_000_000}) } }

    assert_equal "called helper hangs, which didn't answer within 0.5 seconds, so CrossLint ended it and everything it started", error.message
  end

  def test_doesnt_wait_for_a_process_that_left_the_helpers_tree_to_close_standard_error
    running = start("escapes", time_limit: 0.5)
    running.call(plugin_of("escapes"), "escapes", {})
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    running.stop

    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 6
  end

  def test_reads_a_helpers_standard_error_whatever_becomes_of_crosslints
    closed = StringIO.new.tap(&:close)
    error = assert_raises(CrossLint::Core::PluginError) { start("fails", err: closed, debug: true).call(plugin_of("fails"), "fails", {}) }
    running = start("talks", err: closed, debug: true)
    answers = [running.call(plugin_of("talks"), "talks", 1), running.call(plugin_of("talks"), "talks", 2)]
    running.stop

    assert_equal ["called helper fails, which exited with status 3 before it answered, and wrote:\nnope", [{}, {}]], [error.message, answers]
  end

  def test_writes_everything_a_helper_wrote_to_standard_error_by_the_time_it_stops
    err = StringIO.new
    err.define_singleton_method(:puts) do |line|
      sleep 0.3
      super(line)
    end
    running = start("talks", err:, debug: true)
    running.call(plugin_of("talks"), "talks", {})
    running.stop

    assert_equal "crosslint: helper talks: heard\n", err.string
  end

  def test_shows_a_short_answer_that_isnt_json_whole
    error = assert_raises(CrossLint::Core::PluginError) { start("short").call(plugin_of("short"), "short", {}) }

    assert_equal %(called helper short, which answered with a line that isn't JSON: "nope"), error.message
  end

  def test_finds_no_command_with_no_path
    assert_nil CrossLint::Adapters::ProcessHelpers.new(err: StringIO.new, debug: false, env: {}).find("sh")
  end

  def test_fails_a_helper_that_answers_with_what_isnt_json
    error = assert_raises(CrossLint::Core::PluginError) { start("garbage").call(plugin_of("garbage"), "garbage", {}) }

    assert_equal %(called helper garbage, which answered with a line that isn't JSON: "not json, and a line longer than the eighty characters a message shows of it, cu"),
      error.message
  end

  def test_fails_a_helper_that_exits_and_every_call_after
    running = start("once")

    assert_equal({}, running.call(plugin_of("once"), "once", 1))
    first = assert_raises(CrossLint::Core::PluginError) { running.call(plugin_of("once"), "once", 2) }
    again = assert_raises(CrossLint::Core::PluginError) { running.call(plugin_of("once"), "once", 3) }

    assert_equal ["called helper once, which exited with status 0 before it answered"] * 2, [first.message, again.message]
    running.stop
  end

  def test_fails_a_helper_that_exits_before_it_reads
    error = assert_raises(CrossLint::Core::PluginError) { start("quits").call(plugin_of("quits"), "quits", {"big" => "x" * 100_000}) }

    assert_equal "called helper quits, which exited with status 0 before it answered", error.message
  end

  def test_writes_what_a_helper_writes_to_standard_error_only_with_debug
    quiet, debugged = [false, true].map do |debug|
      err = StringIO.new
      running = start("talks", err:, debug:)
      running.call(plugin_of("talks"), "talks", {})
      running.stop
      err.string
    end

    assert_equal ["", "crosslint: helper talks: heard\n"], [quiet, debugged]
  end

  def test_ends_what_a_helper_left_running_when_the_check_ends
    running = start("leaves")
    running.call(plugin_of("leaves"), "leaves", {})
    running.stop

    assert_gone(File.read(File.join(@base, "leaves.pid")).strip)
  end

  def test_lets_a_helper_finish_once_its_input_closes
    running = start("finishes")
    running.call(plugin_of("finishes"), "finishes", {})
    running.stop

    assert_equal "bye\n", File.read(File.join(@base, "finished.txt"))
  end

  def test_ends_a_helper_that_doesnt_exit_once_its_input_closes
    running = start("lingers", stop_limit: 0.5)
    running.call(plugin_of("lingers"), "lingers", {})
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    running.stop

    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 5
  end

  def test_gives_every_helper_its_time_to_exit_at_once_not_one_after_another
    helpers = %w[one two three].map { |name| CrossLint::Core::HelperDeclaration.new(name:, command: "sh", file: "lingers.sh", line: 4) }
    plugin = helper_plugin.then { |tests| tests.with(manifest: tests.manifest.with(helpers:)) }
    running = CrossLint::Adapters::ProcessHelpers.new(err: StringIO.new, debug: false, stop_limit: 1).start(@base, [plugin])
    helpers.each { |helper| running.call(plugin, helper.name, {}) }
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    running.stop

    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 2.5
  end

  def test_ends_every_helper_at_once_when_killed_and_waits_for_none_to_exit
    running = start("stays", stop_limit: 30)
    running.call(plugin_of("stays"), "stays", {})
    running.kill

    assert_gone(File.read(File.join(@base, "stays.pid")).strip)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    running.stop

    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 5
  end

  def test_doesnt_wait_for_standard_error_once_killed
    running = start("escapes", time_limit: 5)
    running.call(plugin_of("escapes"), "escapes", {})
    running.kill
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    running.stop

    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 3
  end

  def test_ends_every_helper_at_once_when_ctrl_c_comes_while_waiting_for_them_to_exit
    running = start("stays", stop_limit: 30)
    running.call(plugin_of("stays"), "stays", {})
    stopping = Thread.new { running.stop }
    stopping.report_on_exception = false
    Thread.pass until stopping.stop?
    stopping.raise(Interrupt)

    assert_raises(Interrupt) { stopping.join }
    assert_gone(File.read(File.join(@base, "stays.pid")).strip)
  end

  def test_stops_at_a_helper_file_the_plugins_folder_lacks
    plugin = plugin_of("missing")
    mistake = assert_raises(CrossLint::Core::Mistake) { helpers_port.start(@base, [plugin]) }

    assert_equal ["tests/plugin.kdl:4", %(no file "missing.sh" in the plugin's folder)], [mistake.location, mistake.message]
  end

  def test_finds_a_command_by_its_name_alone_on_the_path_but_not_in_the_current_folder
    %w[tool.exe bin/one/tool.exe bin/two/tool.exe].each { |file| File.chmod(0o755, write(@base, file, "")) }
    FileUtils.mkdir_p(File.join(@base, "bin/zero/tool.exe"))
    port = port_finding(["", "bin/zero", "bin/one", "bin/two"])
    found, expected = Dir.chdir(@base) { [[port.find("tool.exe"), port.find("tool")], File.expand_path("bin/one/tool.exe")] }

    assert_equal [expected, nil], found
  end

  def test_finds_only_a_file_it_can_run
    skip "Windows counts a file as one it can run by its extension" if CrossLint::Adapters::ProcessHelpers::WINDOWS

    File.chmod(0o644, write(@base, "bin/zero/tool", ""))
    File.chmod(0o755, write(@base, "bin/one/tool", ""))

    assert_equal File.join(@base, "bin/one/tool"), port_finding(["#{@base}/bin/zero", "#{@base}/bin/one"]).find("tool")
  end

  def test_finds_a_command_with_each_extension_in_pathext_before_its_name_alone
    bare = write(@base, "bin/tool.exe", "")
    cmd = write(@base, "bin/tool.exe.CMD", "")
    [bare, cmd].each { |file| File.chmod(0o755, file) }
    find = ->(pathext) { port_finding([File.join(@base, "bin")], pathext:).find("tool.exe") }

    assert_equal [cmd, bare, bare], [find.call(".EXE;;.CMD"), find.call(nil), find.call(".BAT")]
  end

  private

  # The plugin "tests" with the one helper `name`, in `name`.sh.
  def plugin_of(name)
    plugin = helper_plugin
    helper = CrossLint::Core::HelperDeclaration.new(name:, command: "sh", file: "#{name}.sh", line: 4)
    plugin.with(manifest: plugin.manifest.with(helpers: [helper]))
  end

  def start(name, err: StringIO.new, debug: false, **options)
    CrossLint::Adapters::ProcessHelpers.new(err:, debug:, **options).start(@base, [plugin_of(name)])
  end

  # A port whose PATH is `folders`, and whose PATHEXT is `pathext`.
  def port_finding(folders, pathext: nil)
    env = {"PATH" => folders.join(File::PATH_SEPARATOR), "PATHEXT" => pathext}.compact
    CrossLint::Adapters::ProcessHelpers.new(err: StringIO.new, debug: false, env:)
  end

  # Ruby warns at every change of Encoding.default_external.
  def quietly
    verbose = $VERBOSE
    $VERBOSE = nil
    yield
  ensure
    $VERBOSE = verbose
  end

  # The path of `file` once it exists, which a helper's script writes a
  # moment after CrossLint has what it asked for.
  def wait_for_file(file)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
    sleep 0.05 until File.exist?(file) || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

    file
  end

  # Asks sh, since on Windows `pid` is MSYS2's number for the process.
  def assert_gone(pid)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
    alive = system("sh", "-c", "kill -0 #{pid} 2>/dev/null") while alive != false && Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline

    refute alive, "process #{pid} is still running"
  end
end

class MemoryHelpersTest < Minitest::Test
  cover "CrossLint::Adapters::MemoryHelpers*"
  cover "CrossLint::Core::HelperDeclaration*"

  include CrossLint::Testing::HelpersContract
  include HelpersTestHelper

  FAILS = ->(_) { raise CrossLint::Core::PluginError, "called helper fails, which exited with status 3 before it answered, and wrote:\nnope" }

  def helpers_port = CrossLint::Adapters::MemoryHelpers.new({"tests/echo" => ->(input) { {"echo" => input} }, "tests/fails" => FAILS}, commands: ["sh"])

  def helper_root = "/memory/app"

  def test_says_whether_the_check_stopped_or_killed_it
    running = helpers_port.start(helper_root, [helper_plugin])

    assert_equal [false, false, helper_root], [running.stopped, running.killed, running.root]
    running.stop

    assert_equal [true, false], [running.stopped, running.killed]
    running.kill

    assert_equal [true, true], [running.stopped, running.killed]
  end

  def test_holds_no_helper_unless_it_is_given_some
    running = CrossLint::Adapters::MemoryHelpers.new(commands: ["sh"]).start(helper_root, [helper_plugin])

    assert_raises(KeyError) { running.call(helper_plugin, "echo", 1) }
  end

  def test_finds_no_command_unless_it_is_given_some
    assert_raises(CrossLint::Core::Mistake) { CrossLint::Adapters::MemoryHelpers.new.start(helper_root, [helper_plugin]) }
  end
end
