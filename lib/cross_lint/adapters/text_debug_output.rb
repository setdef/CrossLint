# frozen_string_literal: true

module CrossLint
  module Adapters
    class TextDebugOutput
      PREFIX = "crosslint: debug: "

      def initialize(err)
        @err = err
      end

      # One write for each line, since a helper's standard error is
      # written from a thread of its own, and puts may write the line and
      # its newline apart.
      def write(topic)
        yield.each_line(chomp: true) { |line| @err.write("#{PREFIX}#{topic} #{line}\n") }
      end
    end
  end
end
