# frozen_string_literal: true

module CrossLint
  module Core
    class PathPattern < Data.define(:source)
      PLACEHOLDERS = %w[path name].freeze

      PLACEHOLDER = /\{([^{}]*)\}/

      class Invalid < ArgumentError; end

      def self.problem(source)
        return "path pattern #{source.dump} is empty" if source.empty?
        return "path pattern #{source.dump} has \\; write / between folders on every system" if source.include?("\\")

        unknown = source.scan(PLACEHOLDER).flatten.find { |placeholder| !PLACEHOLDERS.include?(placeholder) }
        if unknown
          return "path pattern #{source.dump} has #{Spelling.unknown("placeholder", "{#{unknown}}", PLACEHOLDERS.map { |known| "{#{known}}" })}"
        end

        brace = source.gsub(PLACEHOLDER, "")[/[{}]/]
        "path pattern #{source.dump} has a #{brace} that pairs with nothing" if brace
      end

      def initialize(source:)
        problem = PathPattern.problem(source)
        raise Invalid, problem if problem

        super
      end

      def placeholders = source.scan(PLACEHOLDER).flatten.uniq
    end
  end
end
