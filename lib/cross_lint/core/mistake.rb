# frozen_string_literal: true

module CrossLint
  module Core
    class Mistake < StandardError
      attr_reader :file, :line

      def initialize(message, file: nil, line: nil)
        super(message)
        @file = file
        @line = line
      end

      def location = [file, line].compact.join(":")
    end
  end
end
