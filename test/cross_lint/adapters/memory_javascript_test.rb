# frozen_string_literal: true

require "test_helper"
require "rbconfig"

class MemoryJavaScriptTest < Minitest::Test
  cover "CrossLint::Adapters::MemoryJavaScript*"

  include CrossLint::Testing::JavaScriptContract

  def javascript_port
    CrossLint::Adapters::MemoryJavaScript.new({
      "b" => -> (text) { text.include?("b") },
      "^a" => -> (text) { text.start_with?("a") },
      "é" => -> (text) { text.include?("é") },
      "(" => CrossLint::Core::InvalidExpression.new("Invalid regular expression: /(/: Unterminated group"),
    })
  end

  def glob_port(installed)
    CrossLint::Adapters::MemoryJavaScript.new({}, globs: ({ "**/*.a.ts" => ["app/x.a.ts"], "echo" => ["src", "true"] } if installed))
  end

  def glob_root = "/app"

  def test_raises_for_an_expression_it_does_not_hold
    error = assert_raises(CrossLint::Core::InvalidExpression) { CrossLint::Adapters::MemoryJavaScript.new.matches("x", ["x"]) }

    assert_equal "Invalid regular expression: x", error.message
  end

  def test_raises_the_error_it_holds_for_a_glob_and_gives_no_files_when_it_holds_none
    error = CrossLint::Core::JavaScriptError.new("glob failed")

    assert_same error, assert_raises(CrossLint::Core::JavaScriptError) { CrossLint::Adapters::MemoryJavaScript.new({}, globs: error).glob("/app", "src", ["a"], [""]) }
    assert_nil CrossLint::Adapters::MemoryJavaScript.new.glob("/app", "src", ["a"], [""])
  end
end
