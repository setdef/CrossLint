# frozen_string_literal: true

require "test_helper"
require_relative "../../tasks/doctest"

class DoctestTest < Minitest::Test
  def test_finds_the_ruby_blocks_in_markdown_with_the_line_their_code_starts_on
    text = "# Title\n\n```ruby\n1 + 1 # => 2\n```\n\n```console\n$ ls\n```\n"

    assert_equal [Doctest::Example.new(file: "a.md", line: 4, code: "1 + 1 # => 2\n")], Doctest.blocks("a.md", text)
  end

  def test_finds_the_ruby_blocks_in_a_signatures_comments
    source = "# Adds.\n#\n# ```ruby\n# 1 + 1 # => 2\n# ```\nclass A\nend\n"

    assert_equal [Doctest::Example.new(file: "a.rbs", line: 4, code: "1 + 1 # => 2\n")],
      Doctest.blocks("a.rbs", Doctest.comments(source))
  end

  def test_refuses_a_block_with_no_closing_fence
    error = assert_raises(Doctest::Failure) { Doctest.blocks("a.md", "```ruby\n1\n") }

    assert_equal "a.md:1: a ruby block with no closing fence", error.message
  end

  def test_passes_an_example_whose_results_match
    assert_nil Doctest.run(example("x = [1, 2]\nx.sum # => 3\nx.map { _1 * 2 } # => [2, 4]\n"))
  end

  def test_fails_an_example_whose_result_differs
    error = assert_raises(Doctest::Failure) { Doctest.run(example("x = 1\nx + 1 # => 3\n")) }

    assert_equal "a.md:11: shows 3, and the code returns 2", error.message
  end

  def test_fails_an_example_that_raises
    error = assert_raises(Doctest::Failure) { Doctest.run(example("Nothing.here\n")) }

    assert_match(/\Aa\.md:10: raised NameError: uninitialized constant Nothing/, error.message)
  end

  def test_runs_an_example_that_shows_no_result
    assert_nil Doctest.run(example("class DoctestRan; end\n"))
    assert defined?(DoctestRan)
  end

  def test_skips_an_example_that_uses_a_part_not_built_yet
    stub_const_pending({ "CrossLint::NotYet" => "#99" }) do
      assert_equal "uses CrossLint::NotYet, which #99 builds", Doctest.run(example("CrossLint::NotYet.new\n"))
    end
  end

  def test_fails_once_a_pending_part_exists
    stub_const_pending({ "CrossLint::CLI" => "#99" }) do
      error = assert_raises(Doctest::Failure) { Doctest.run(example("CrossLint::CLI\n")) }

      assert_equal "a.md:10: CrossLint::CLI exists, so remove it from Doctest::PENDING", error.message
    end
  end

  private

  def example(code) = Doctest::Example.new(file: "a.md", line: 10, code:)

  def stub_const_pending(pending)
    original = Doctest::PENDING
    Doctest.send(:remove_const, :PENDING)
    Doctest.const_set(:PENDING, pending)
    yield
  ensure
    Doctest.send(:remove_const, :PENDING)
    Doctest.const_set(:PENDING, original)
  end
end
