# frozen_string_literal: true

require "test_helper"
require "open3"
require "rbconfig"

# The crosslint program, run as a person runs it. These are the only tests
# that start a process.
class ExeTest < Minitest::Test
  EXE = File.join(ROOT, "exe", "crosslint")

  def test_prints_the_version_and_exits_with_0
    assert_equal ["crosslint #{shipped_spec.version}\n", "", 0], crosslint("--version")
  end

  def test_prints_the_help_the_spec_gives
    assert_equal [CrossLint::Help.new(shipped_spec).render, "", 0], crosslint("--help")
  end

  def test_exits_with_2_at_a_mistake
    assert_equal ["", "crosslint: crosslint has no flag --quite; did you mean --quiet?\n", 2], crosslint("--quite")
  end

  private

  def crosslint(*argv)
    out, err, status = Open3.capture3(RbConfig.ruby, EXE, *argv, stdin_data: "")
    [out, err, status.exitstatus]
  end
end
