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
    # Every `sleep` outlasts EVENT_LIMIT, so that a process still running
    # when a test gives up waiting for it is one nobody ended.
    "hangs.sh" => "sleep 60 &\necho $! > hangs.pid\nwait\n",
    "garbage.sh" => "while read -r line; do echo 'not json, and a line longer than the eighty characters a message shows of it, cut off here'; done\n",
    "signals.sh" => "kill -9 $$\n",
    "short.sh" => "read -r line\necho nope\n",
    "once.sh" => "read -r line\necho '{}'\n",
    "quits.sh" => "exit 0\n",
    "talks.sh" => "while read -r line; do echo heard >&2; echo '{}'; done\n",
    "leaves.sh" => "read -r line\nsleep 60 &\necho $! > leaves.pid\necho '{}'\n",
    # Says when its input has closed, and then waits to be ended.
    "stays.sh" => "read -r line\nsleep 60 &\necho $! > stays.pid\necho '{}'\ncat > /dev/null\necho closed > stays.closed\nwait\n",
    "dumps.sh" => "env > env.txt\nread -r line\necho '{}'\n",
    "lingers.sh" => "read -r line\necho $$ > lingers.pid\necho '{}'\nexec 0<&-\nwhile :; do sleep 1; done\n",
    # Says when its input has closed, in a file every helper of the test shares.
    "listens.sh" => "read -r line\necho '{}'\ncat > /dev/null\necho closed >> listened.txt\nwhile :; do sleep 1; done\n",
    "escapes.sh" => "read -r line\necho '{}'\n" \
      "ruby -e 'File.write(\"escaped.pid\", Process.spawn(RbConfig.ruby, \"-e\", \"sleep 60\", pgroup: true))'\n",
    # Exits only once the test lets it, after its input has closed, and
    # gives up if the test is over and its folder gone.
    "finishes.sh" => "while read -r line; do echo '{}'; done\necho eof > finishing.txt\n" \
      "while [ -f finishing.txt ] && [ ! -f proceed.txt ]; do sleep 0.05; done\necho bye > finished.txt\n"
  }.freeze

  # The longest any test waits for an event, in seconds. A test that waits
  # for one fails when it hasn't come by then, and nothing else decides how
  # long a test takes.
  EVENT_LIMIT = 30

  def setup
    @base = Dir.mktmpdir("crosslint")
    SCRIPTS.each { |name, script| write(@base, "tests/#{name}", script) }
  end

  def teardown
    FileUtils.rm_rf(@base)
  end

  def helpers_port = CrossLint::Adapters::ProcessHelpers.new

  def helper_root = @base

  def test_waits_a_minute_for_each_answer_and_two_seconds_for_each_exit_unless_told_otherwise
    other = CrossLint::Adapters::ProcessHelpers.new(time_limit: 0.5, stop_limit: 0.25)

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

  # The helper starts the process it hangs on before it reads anything, so
  # this limit, which starts when the request is written, is the room a
  # loaded computer has to run two lines of sh.
  def test_ends_a_helper_that_doesnt_answer_with_everything_it_started
    running = start("hangs", time_limit: 2)
    error = assert_raises(CrossLint::Core::PluginError) { running.call(plugin_of("hangs"), "hangs", {}) }

    assert_equal "called helper hangs, which didn't answer within 2 seconds, so CrossLint ended it and everything it started", error.message
    assert_gone(File.read(wait_for_file(File.join(@base, "hangs.pid"))).strip)
  end

  def test_ends_a_helper_that_reads_nothing_however_much_it_is_asked
    running = start("hangs", time_limit: 0.5)
    error = Timeout.timeout(EVENT_LIMIT) { assert_raises(CrossLint::Core::PluginError) { running.call(plugin_of("hangs"), "hangs", {"big" => "x" * 1_000_000}) } }

    assert_equal "called helper hangs, which didn't answer within 0.5 seconds, so CrossLint ended it and everything it started", error.message
  end

  # The process that left the tree outlives EVENT_LIMIT, so a stop that
  # waits for it doesn't return in time.
  def test_doesnt_wait_for_a_process_that_left_the_helpers_tree_to_close_standard_error
    skip "Windows has no process groups to leave, and ends every process a helper started" if CrossLint::Adapters::ProcessHelpers::WINDOWS

    running = start("escapes", time_limit: 3)
    running.call(plugin_of("escapes"), "escapes", {})
    wait_for_file(File.join(@base, "escaped.pid"))
    stopping = stop_in_a_thread(running)

    assert stopping.join(EVENT_LIMIT), "stop is still waiting for a process that left the tree"
  ensure
    end_escaped
  end

  def test_reads_a_helpers_standard_error_whatever_becomes_of_crosslints
    closed = StringIO.new.tap(&:close)
    error = assert_raises(CrossLint::Core::PluginError) { start("fails", err: closed, debug: true).call(plugin_of("fails"), "fails", {}) }
    running = start("talks", err: closed, debug: true)
    answers = [running.call(plugin_of("talks"), "talks", 1), running.call(plugin_of("talks"), "talks", 2)]
    running.stop

    assert_equal ["called helper fails, which exited with status 3 before it answered, and wrote:\nnope", [{}, {}]], [error.message, answers]
  end

  # CrossLint's standard error holds its line back until the helper has
  # exited and been ended, and stop is waiting for the line: a stop that
  # doesn't wait has returned by then.
  def test_writes_everything_a_helper_wrote_to_standard_error_by_the_time_it_stops
    allowed = Queue.new
    err = StringIO.new
    err.define_singleton_method(:write) do |line|
      allowed.pop
      super(line)
    end
    kills = []
    running = start("talks", err:, debug: true, stop_limit: 100, tree: killing_tree(kills))
    running.call(plugin_of("talks"), "talks", {})
    stopping = stop_in_a_thread(running)
    wait_until("stop to have ended the helper and to wait") { kills.any? && stopping.stop? }

    assert stopping.alive?, "stop returned before CrossLint wrote the helper's standard error"
    allowed << true
    stopping.join(EVENT_LIMIT)

    assert_equal "crosslint: debug: helper tests/talks wrote to standard error: heard\n", err.string
  end

  def test_shows_a_short_answer_that_isnt_json_whole
    error = assert_raises(CrossLint::Core::PluginError) { start("short").call(plugin_of("short"), "short", {}) }

    assert_equal %(called helper short, which answered with a line that isn't JSON: "nope"), error.message
  end

  # A command of several words, such as bundle exec ruby, runs with its
  # words between the program and the helper's file.
  def test_starts_a_helper_with_the_words_its_command_has_before_its_file
    write(@base, "tests/wraps.sh", %(read -r line; printf '{"wrapped":"%s"}\\n' "$1"\n))
    helper = CrossLint::Core::HelperDeclaration.new(name: "echo", command: "sh", arguments: [File.join(@base, "tests", "wraps.sh")],
      file: "echo.sh", line: 4)
    plugin = helper_plugin.then { |given| given.with(manifest: given.manifest.with(helpers: [helper])) }
    running = helpers_port.start(helper_root, [plugin])

    assert_equal({"wrapped" => File.join(@base, "tests", "echo.sh")}, running.call(plugin, "echo", 1))
  ensure
    running&.stop
  end

  def test_finds_no_command_with_no_path
    assert_nil CrossLint::Adapters::ProcessHelpers.new(env: {}).find("sh")
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

    assert_equal ["", "crosslint: debug: helper tests/talks wrote to standard error: heard\n"], [quiet, debugged]
  end

  def test_ends_what_a_helper_left_running_when_the_check_ends
    running = start("leaves")
    running.call(plugin_of("leaves"), "leaves", {})
    running.stop

    assert_gone(File.read(File.join(@base, "leaves.pid")).strip)
  end

  # The helper exits when the test lets it, and a stop that ends it
  # instead has killed it by the time stop is waiting.
  def test_lets_a_helper_finish_once_its_input_closes
    kills = []
    running = start("finishes", stop_limit: 100, tree: killing_tree(kills))
    running.call(plugin_of("finishes"), "finishes", {})
    stopping = stop_in_a_thread(running)
    wait_for_file(File.join(@base, "finishing.txt"))
    wait_until("stop to wait for the helper") { stopping.stop? }

    assert_empty kills, "stop ended the helper before it had a chance to exit"
    write(@base, "proceed.txt", "")
    stopping.join(EVENT_LIMIT)

    assert_equal "bye\n", File.read(File.join(@base, "finished.txt"))
  ensure
    running&.kill
  end

  def test_ends_a_helper_that_doesnt_exit_once_its_input_closes
    running = start("lingers", stop_limit: 0.5)
    running.call(plugin_of("lingers"), "lingers", {})
    stopping = stop_in_a_thread(running)

    assert stopping.join(EVENT_LIMIT), "stop is still waiting for the helper to exit"
    assert_gone(File.read(File.join(@base, "lingers.pid")).strip)
  end

  # Every helper's input closes while the first is still being waited for,
  # which no helper's limit can be over for, so one after another can't.
  def test_gives_every_helper_its_time_to_exit_at_once_not_one_after_another
    helpers = %w[one two three].map { |name| CrossLint::Core::HelperDeclaration.new(name:, command: "sh", file: "listens.sh", line: 4) }
    plugin = helper_plugin.then { |tests| tests.with(manifest: tests.manifest.with(helpers:)) }
    running = CrossLint::Adapters::ProcessHelpers.new(stop_limit: 100).start(@base, [plugin])
    helpers.each { |helper| running.call(plugin, helper.name, {}) }
    stopping = stop_in_a_thread(running)
    listened = File.join(@base, "listened.txt")
    closed = -> { File.exist?(listened) ? File.read(listened).lines(chomp: true) : [] }
    wait_until("every helper's input to close") { !stopping.alive? || closed.call.size == 3 }

    assert_equal %w[closed] * 3, closed.call
  ensure
    running&.kill
    stopping&.join(EVENT_LIMIT)
  end

  def test_ends_every_helper_at_once_when_killed_and_waits_for_none_to_exit
    running = start("stays", stop_limit: 100)
    running.call(plugin_of("stays"), "stays", {})
    running.kill

    assert_gone(File.read(File.join(@base, "stays.pid")).strip)
    stopping = stop_in_a_thread(running)

    assert stopping.join(EVENT_LIMIT), "stop is waiting for a helper that has been ended"
  end

  # The process that left the tree outlives EVENT_LIMIT, as does the
  # limit, so a stop that waits for its standard error doesn't return.
  def test_doesnt_wait_for_standard_error_once_killed
    skip "Windows has no process groups to leave, and ends every process a helper started" if CrossLint::Adapters::ProcessHelpers::WINDOWS

    running = start("escapes", time_limit: 100)
    running.call(plugin_of("escapes"), "escapes", {})
    wait_for_file(File.join(@base, "escaped.pid"))
    running.kill
    stopping = stop_in_a_thread(running)

    assert stopping.join(EVENT_LIMIT), "stop is waiting for the standard error of a helper that has been ended"
  ensure
    end_escaped
  end

  # The thread's own end is what the test checks, so that Ctrl-C has
  # nowhere to go but the thread: the helper has seen its input close, and
  # only the ending of its tree is left to wait for.
  def test_ends_every_helper_at_once_when_ctrl_c_comes_while_waiting_for_them_to_exit
    running = start("stays", stop_limit: 100)
    running.call(plugin_of("stays"), "stays", {})
    stopping = Thread.new do
      running.stop
    rescue Interrupt => interrupt
      interrupt
    end
    stopping.report_on_exception = false
    wait_until("the helper's input to close") { File.exist?(File.join(@base, "stays.closed")) || !stopping.alive? }
    stopping.raise(Interrupt)

    assert_instance_of Interrupt, stopping.value
    assert_gone(File.read(File.join(@base, "stays.pid")).strip)
  end

  def test_ends_a_helper_it_cant_put_in_a_process_tree_and_fails_it
    started = []
    running = start("stays", tree: unholding_tree(started) { |_pid| })
    error = assert_raises(CrossLint::Core::PluginError) { running.call(plugin_of("stays"), "stays", {}) }
    *pipes, waiter = started

    assert_equal "called helper stays, which couldn't be put in a tree, so CrossLint ended it", error.message
    assert_equal [true, true, true, false], [*pipes.map(&:closed?), waiter.alive?]
  end

  def test_ends_a_helper_it_cant_put_in_a_process_tree_that_has_exited_already
    started = []
    tree = unholding_tree(started) do |pid|
      wait_until("the helper to exit") { !process_exists?(pid) }
    end
    error = assert_raises(CrossLint::Core::PluginError) { start("quits", tree:).call(plugin_of("quits"), "quits", {}) }

    assert_equal "called helper quits, which couldn't be put in a tree, so CrossLint ended it", error.message
  end

  # A helper that has exited and been reaped before it is put in a tree has
  # nothing to hold, and ended as any helper that exits does. Windows
  # answers error 87 to a process that is gone.
  def test_reads_how_a_helper_ended_that_exited_before_it_was_put_in_a_tree
    started = []
    tree = Class.new(CrossLint::Adapters::ProcessHelpers::TREE) do
      define_singleton_method(:popen3) { |*arguments| super(*arguments, &nil).tap { |by_it| started.concat(by_it) } }
      define_method(:initialize) do |pid|
        # The waiter ends once Ruby has reaped the process.
        started.last.join
        sleep 0.3
        super(pid)
      end
    end
    error = assert_raises(CrossLint::Core::PluginError) { start("quits", tree:).call(plugin_of("quits"), "quits", {}) }

    assert_equal "called helper quits, which exited with status 0 before it answered", error.message
  end

  def test_fails_a_helper_that_isnt_in_a_process_group_of_its_own
    skip "Windows has job objects, not process groups" if CrossLint::Adapters::ProcessHelpers::WINDOWS

    pid = Process.spawn("sleep", "30")
    error = assert_raises(CrossLint::Core::PluginError) { CrossLint::Adapters::ProcessGroup.new(pid) }

    assert_equal "wasn't put in a process group of its own", error.message
  ensure
    Process.kill("KILL", pid) if pid
    Process.wait(pid) if pid
  end

  def test_has_nothing_to_hold_of_a_helper_that_has_exited
    skip "Windows has job objects, not process groups" if CrossLint::Adapters::ProcessHelpers::WINDOWS

    pid = Process.spawn("true")
    Process.wait(pid)

    assert_instance_of CrossLint::Adapters::ProcessGroup, CrossLint::Adapters::ProcessGroup.new(pid)
  end

  def test_starts_a_helper_with_the_environment_the_launcher_saved_not_the_one_it_set
    unset = CrossLint::Adapters::HelperEnvironment::UNSET
    ENV["CROSSLINT_TEST_SET"] = "by the launcher"
    env = ENV.to_h.merge("RUBYOPT" => "-rbundler/setup -W0", "BUNDLER_ORIG_RUBYOPT" => "-W0", "BUNDLER_ORIG_CROSSLINT_TEST_SET" => unset)
    running = CrossLint::Adapters::ProcessHelpers.new(env:).start(@base, [plugin_of("dumps")])
    running.call(plugin_of("dumps"), "dumps", {})
    running.stop
    seen = File.read(File.join(@base, "env.txt")).lines(chomp: true).map { |line| line.split("=", 2) }.to_h

    assert_equal ["-W0", nil, []], [seen["RUBYOPT"], seen["CROSSLINT_TEST_SET"], seen.keys.grep(/\ABUNDLER_ORIG_/)]
  ensure
    ENV.delete("CROSSLINT_TEST_SET")
  end

  def test_finds_a_command_on_the_path_the_launcher_saved
    write(@base, "saved/tool.exe", "")
    File.chmod(0o755, File.join(@base, "saved/tool.exe"))
    env = {"PATH" => File.join(@base, "other"), "BUNDLER_ORIG_PATH" => File.join(@base, "saved")}

    assert_equal File.join(@base, "saved/tool.exe"), CrossLint::Adapters::ProcessHelpers.new(env:).find("tool.exe")
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

  # A tree class that holds nothing: it pushes the pipes and waiter of
  # each helper it starts to `started`, runs the block with the helper's
  # pid, and raises that it couldn't hold the helper.
  def unholding_tree(started, &before)
    Class.new(CrossLint::Adapters::ProcessHelpers::TREE) do
      define_singleton_method(:popen3) { |*arguments| super(*arguments, &nil).tap { |started_by_it| started.concat(started_by_it) } }
      define_method(:initialize) do |pid|
        before.call(pid)
        raise CrossLint::Core::PluginError, "couldn't be put in a tree"
      end
    end
  end

  def process_exists?(pid)
    Process.kill(0, pid)
    true
  rescue Errno::ESRCH
    false
  end

  # The plugin "tests" with the one helper `name`, in `name`.sh.
  def plugin_of(name)
    plugin = helper_plugin
    helper = CrossLint::Core::HelperDeclaration.new(name:, command: "sh", file: "#{name}.sh", line: 4)
    plugin.with(manifest: plugin.manifest.with(helpers: [helper]))
  end

  # The helper `name` started, saying what it writes to standard error
  # on `err` as debug output when `debug` is true.
  def start(name, err: StringIO.new, debug: false, **options)
    CrossLint::Adapters::ProcessHelpers.new(debug: (CrossLint::Adapters::TextDebugOutput.new(err) if debug), **options).start(@base, [plugin_of(name)])
  end

  # A port whose PATH is `folders`, and whose PATHEXT is `pathext`.
  def port_finding(folders, pathext: nil)
    env = {"PATH" => folders.join(File::PATH_SEPARATOR), "PATHEXT" => pathext}.compact
    CrossLint::Adapters::ProcessHelpers.new(env:)
  end

  # Ruby warns at every change of Encoding.default_external.
  def quietly
    verbose = $VERBOSE
    $VERBOSE = nil
    yield
  ensure
    $VERBOSE = verbose
  end

  # Waits for what the block says has happened, which a test waits for by
  # an event and never by a time, and fails after EVENT_LIMIT seconds,
  # which is far longer than a loaded computer takes.
  def wait_until(what)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + EVENT_LIMIT
    sleep 0.01 until (done = yield) || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

    assert done, "gave up waiting #{EVENT_LIMIT} seconds for #{what}"
  end

  # The path of `file` once it exists, which a helper's script writes a
  # moment after CrossLint has what it asked for.
  def wait_for_file(file)
    wait_until("#{File.basename(file)} to exist") { File.exist?(file) }

    file
  end

  # Asks sh, since on Windows `pid` is MSYS2's number for the process.
  def assert_gone(pid)
    wait_until("process #{pid} to end") { !system("sh", "-c", "kill -0 #{pid} 2>/dev/null") }
  end

  # Runs `running.stop` in a thread, whose exception, if it has one, is
  # the one `join` raises.
  def stop_in_a_thread(running)
    Thread.new do
      Thread.current.report_on_exception = false
      running.stop
    end
  end

  # A tree class that adds to `kills` each time it has ended a tree.
  def killing_tree(kills)
    Class.new(CrossLint::Adapters::ProcessHelpers::TREE) do
      define_method(:kill) do
        super()
        kills << true
      end
    end
  end

  # Ends the process the escaping helper left outside its tree, which
  # nothing else does.
  def end_escaped
    file = File.join(@base, "escaped.pid")
    pid = File.exist?(file) ? File.read(file).to_i : 0
    Process.kill("KILL", pid) if pid.positive?
  rescue SystemCallError
    nil
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
