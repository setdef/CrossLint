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
    _, _, _, wait = CrossLint::Adapters::JobObject.popen3(["sh", script], @base)
    job = CrossLint::Adapters::JobObject.new(wait.pid)
    job.kill
    job.kill

    refute_nil wait.join(5)
  end

  def test_stops_at_a_process_it_cant_hold
    error = assert_raises(CrossLint::Core::PluginError) { CrossLint::Adapters::JobObject.new(0) }

    assert_match(/\Acouldn't be put in a job object: OpenProcess failed with Windows error \d+\z/, error.message)
  end

  def test_stops_at_each_call_windows_refuses_and_closes_what_it_made
    script = write(@base, "sleeps.sh", "sleep 30\n")
    _, _, _, wait = CrossLint::Adapters::JobObject.popen3(["sh", script], @base)
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
