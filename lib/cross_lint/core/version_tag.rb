# frozen_string_literal: true

module CrossLint
  module Core
    class VersionTag < Data.define(:text, :numbers)
      include Comparable

      PATTERN = /\Av?(\d+)\.(\d+)\.(\d+)\z/

      def self.parse(text)
        found = PATTERN.match(text)
        new(text:, numbers: found.captures.map(&:to_i)) if found
      end

      def <=>(other) = numbers <=> other.numbers

      # Comparable's == would call v1.2.0 and 1.2.0 equal; they are two tags.
      def ==(other) = other.is_a?(VersionTag) && text == other.text

      def compatible_with?(other) = group == other.group

      def group
        if numbers.fetch(0).positive?
          numbers.first(1)
        elsif numbers.fetch(1).positive?
          numbers.first(2)
        else
          numbers
        end
      end

      def v? = text.start_with?("v")
    end
  end
end
