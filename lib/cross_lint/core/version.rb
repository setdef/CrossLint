# frozen_string_literal: true

module CrossLint
  module Core
    class Version < Data.define(:numbers)
      include Comparable

      def <=>(other) = (numbers <=> other.numbers if other.is_a?(Version))

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
    end
  end
end
