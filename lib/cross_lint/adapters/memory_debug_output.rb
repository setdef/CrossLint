# frozen_string_literal: true

module CrossLint
  module Adapters
    class MemoryDebugOutput
      attr_reader :lines

      def initialize
        @lines = []
      end

      def write(topic)
        yield.each_line(chomp: true) { |line| @lines << [topic, line] }
      end

      def written(topic) = @lines.filter_map { |each, line| line if each == topic }
    end
  end
end
