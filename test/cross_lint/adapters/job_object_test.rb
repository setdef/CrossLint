# frozen_string_literal: true

require "test_helper"

# A helper's process tree on Windows. ProcessHelpersTest runs helpers in
# it there; these are the cases no helper reaches.
class JobObjectTest < Minitest::Test
  def setup
    skip "only Windows has job objects" unless CrossLint::Adapters::ProcessHelpers::WINDOWS
    @base = Dir.mktmpdir("crosslint")
  end

  def teardown
    FileUtils.rm_rf(@base) if @base
  end

  def test_ends_its_processes_once
    script = write(@base, "sleeps.sh", "sleep 30\n")
    _, _, _, wait = CrossLint::Adapters::JobObject.popen3(["sh", script], @base, {})
    job = CrossLint::Adapters::JobObject.new(wait.pid)
    job.kill
    job.kill

    refute_nil wait.join(5)
  end

  def test_stops_at_a_process_it_cant_hold
    error = assert_raises(CrossLint::Core::PluginError) { CrossLint::Adapters::JobObject.new(0) }

    assert_match(/\Acouldn't be put in a job object: OpenProcess failed with Windows error \d+\z/, error.message)
  end

  # Windows answers error 87, invalid parameter, to the pid of a process
  # that has exited and been reaped.
  def test_has_nothing_to_hold_of_a_process_that_has_exited
    _, _, _, wait = CrossLint::Adapters::JobObject.popen3(["sh", "-c", "exit 0"], @base, {})
    wait.join
    sleep 0.3
    job = CrossLint::Adapters::JobObject.new(wait.pid)
    job.kill

    assert_equal 0, wait.value.exitstatus
  end

  # Ruby keeps the handle of a process until it is reaped, so Windows
  # opens one that has exited, and refuses to put it in a job with error 5.
  def test_has_nothing_to_hold_of_a_process_that_has_exited_and_has_not_been_reaped
    pid = Process.spawn("sh", "-c", "exit 0")
    sleep 1
    job = CrossLint::Adapters::JobObject.new(pid)
    job.kill
  ensure
    Process.wait(pid) if pid
  end

  # A reaped child's pid is free, and another process can take it. The job
  # then has to leave that process alone: it was created after the child
  # was started, which here is a minute ago.
  def test_leaves_a_process_alone_that_was_created_after_the_child_was_started
    pid = Process.spawn("sh", "-c", "sleep 30")
    waiter = Process.detach(pid)
    job = CrossLint::Adapters::JobObject.new(pid, spawned: Time.now - 60)
    job.kill

    assert_nil waiter.join(2)
  ensure
    Process.kill("KILL", pid) if pid
    waiter&.join(5)
  end

  # What popen3 records is the time of the spawn, which the child was
  # created at or before.
  def test_holds_a_process_that_was_created_by_the_time_of_the_spawn
    script = write(@base, "sleeps.sh", "sleep 30\n")
    _, _, _, wait = CrossLint::Adapters::JobObject.popen3(["sh", script], @base, {})
    sleep 0.3
    CrossLint::Adapters::JobObject.new(wait.pid).kill

    refute_nil wait.join(5)
  end

  # Windows refuses a process that is exiting, with error 5, a moment
  # before it signals that it has exited, so one wait of no time at all
  # takes it for a running process.
  def test_waits_for_a_process_windows_refuses_to_signal_that_it_has_exited
    script = write(@base, "sleeps.sh", "sleep 30\n")
    _, _, _, wait = CrossLint::Adapters::JobObject.popen3(["sh", script], @base, {})
    waited = []
    refusing = Class.new(CrossLint::Adapters::JobObject) do
      define_method(:call) do |name, arguments, result, *values|
        waited << values.last if name == "WaitForSingleObject"
        (name == "AssignProcessToJobObject") ? 0 : super(name, arguments, result, *values)
      end
    end
    error = assert_raises(CrossLint::Core::PluginError) { refusing.new(wait.pid) }

    assert_match(/AssignProcessToJobObject failed/, error.message)
    assert_equal [CrossLint::Adapters::JobObject::EXIT_WAIT], waited
    assert_operator CrossLint::Adapters::JobObject::EXIT_WAIT, :>, 0
    CrossLint::Adapters::JobObject.new(wait.pid).kill
  end

  def test_stops_at_each_call_windows_refuses_and_closes_what_it_made
    script = write(@base, "sleeps.sh", "sleep 30\n")
    _, _, _, wait = CrossLint::Adapters::JobObject.popen3(["sh", script], @base, {})
    %w[CreateJobObjectW SetInformationJobObject AssignProcessToJobObject].each do |refused|
      called = []
      refusing = Class.new(CrossLint::Adapters::JobObject) do
        define_method(:call) do |name, *rest|
          called << name
          (name == refused) ? 0 : super(name, *rest)
        end
      end
      error = assert_raises(CrossLint::Core::PluginError, refused) { refusing.new(wait.pid) }

      assert_match(/\Acouldn't be put in a job object: #{refused} failed with Windows error \d+\z/, error.message)
      assert_equal (refused == "CreateJobObjectW") ? 0 : 1, called.count("TerminateJobObject"), refused
    end
    CrossLint::Adapters::JobObject.new(wait.pid).kill
  end
end
