# frozen_string_literal: true

require_relative "../core"

module CrossLint
  module Adapters
    class MemoryReport
      attr_reader :results

      def initialize
        @results = []
      end

      def write(result)
        @results << result
      end
    end
  end
end
