# frozen_string_literal: true

require "test_helper"

class TextDebugOutputTest < Minitest::Test
  cover "CrossLint::Adapters::TextDebugOutput*"

  include CrossLint::Testing::DebugOutputContract

  def setup
    @err = StringIO.new
  end

  def debug_output_port = CrossLint::Adapters::TextDebugOutput.new(@err)

  def debug_lines = @err.string.lines(chomp: true).map { |line| line.delete_prefix("crosslint: debug: ").split(" ", 2) }

  def test_begins_each_line_with_crosslint_debug_and_the_topic
    debug_output_port.write("file") { "lib/café.rb" }

    assert_equal "crosslint: debug: file lib/café.rb\n", @err.string
  end
end

class MemoryDebugOutputTest < Minitest::Test
  cover "CrossLint::Adapters::MemoryDebugOutput*"

  include CrossLint::Testing::DebugOutputContract

  def debug_output_port = @port ||= CrossLint::Adapters::MemoryDebugOutput.new

  def debug_lines = debug_output_port.lines

  def test_gives_the_lines_of_one_topic
    debug_output_port.write("file") { "lib/a.rb" }
    debug_output_port.write("role") { "tests/ruby-file" }

    assert_equal ["lib/a.rb"], debug_output_port.written("file")
  end
end
