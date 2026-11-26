# frozen_string_literal: true

require_relative "mistake"

module CrossLint
  module Core
    # Every mistake found in one pass, for a command that lists them all
    # before it stops.
    class Mistakes < Mistake
      attr_reader :all

      # The one mistake when there is one, else all of them as Mistakes.
      def self.of(mistakes) = mistakes.one? ? mistakes.fetch(0) : new(mistakes)

      def initialize(all)
        super("#{all.size} mistakes: " + all.map { |mistake| [mistake.location, mistake.message].reject(&:empty?).join(": ") }.join("; "))
        @all = all
      end
    end
  end
end
