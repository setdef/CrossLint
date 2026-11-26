# frozen_string_literal: true

require_relative "../core"

module CrossLint
  module Adapters
    class MemoryJavaScript
      def initialize(expressions = {})
        @expressions = expressions
      end

      def matches(source, texts)
        held = @expressions.fetch(source) { raise Core::JavaScriptError, "Invalid regular expression: #{source}" }
        case held
        when Core::JavaScriptError then raise held
        else texts.map { |text| held.call(text) }
        end
      end
    end
  end
end
