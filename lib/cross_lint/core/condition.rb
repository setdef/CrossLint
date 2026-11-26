# frozen_string_literal: true

module CrossLint
  module Core
    module Condition
      class CompanionExists < Data.define(:companion, :line)
        def companion_tests = [self]
      end

      class Not < Data.define(:condition, :line)
        def companion_tests = condition.companion_tests
      end

      class All < Data.define(:conditions, :line)
        def companion_tests = conditions.flat_map(&:companion_tests)
      end

      class Any < Data.define(:conditions, :line)
        def companion_tests = conditions.flat_map(&:companion_tests)
      end
    end
  end
end
