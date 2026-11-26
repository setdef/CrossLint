# frozen_string_literal: true

require_relative "../core"

module CrossLint
  module Adapters
    class MemoryReport
      attr_reader :results, :starts

      def initialize
        @results = []
        @starts = []
      end

      def start(kinds)
        @starts << kinds
      end

      def write(result)
        @results << result
      end
    end
  end
end
