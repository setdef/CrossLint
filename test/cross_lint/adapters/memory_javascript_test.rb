# frozen_string_literal: true

require "test_helper"
require "rbconfig"

class MemoryJavaScriptTest < Minitest::Test
  cover "CrossLint::Adapters::MemoryJavaScript*"

  include CrossLint::Testing::JavaScriptContract

  def javascript_port
    CrossLint::Adapters::MemoryJavaScript.new({
      "b" => ->(text) { text.include?("b") },
      "^a" => ->(text) { text.start_with?("a") },
      "é" => ->(text) { text.include?("é") },
      "(" => CrossLint::Core::JavaScriptError.new("Invalid regular expression: /(/: Unterminated group")
    })
  end

  def test_raises_for_an_expression_it_does_not_hold
    error = assert_raises(CrossLint::Core::JavaScriptError) { CrossLint::Adapters::MemoryJavaScript.new.matches("x", ["x"]) }

    assert_equal "Invalid regular expression: x", error.message
  end
end
