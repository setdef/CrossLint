# frozen_string_literal: true

require_relative "../core"

module CrossLint
  module Adapters
    class MemoryJavaScript
      # What glob finds for a pattern the port holds no files for.
      NONE = [].freeze # steep:ignore UnannotatedEmptyCollection

      def initialize(expressions = {}, globs: nil)
        @expressions = expressions
        @globs = globs
      end

      def matches(source, texts)
        held = @expressions.fetch(source) { raise Core::JavaScriptError, "Invalid regular expression: #{source}" }
        case held
        when Core::JavaScriptError then raise held
        else texts.map { |text| held.call(text) }
        end
      end

      def glob(_root, _cwd, patterns, _packages)
        held = @globs
        case held
        when Core::JavaScriptError then raise held
        when Hash then patterns.to_h { |pattern| [pattern, held.fetch(pattern, NONE)] }
        end
      end
    end
  end
end
