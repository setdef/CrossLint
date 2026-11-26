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
    assert_raises(CrossLint::Core::PluginError) { CrossLint::Adapters::JobObject.new(0) }
  end
end
