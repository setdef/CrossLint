# frozen_string_literal: true

module CrossLint
  module Core
    module Condition
      class CompanionExists < Data.define(:companion, :line)
        def companion_conditions = [self]

        def holds?(artifact) = artifact.companion(companion).exist?
      end

      class Not < Data.define(:condition, :line)
        def companion_conditions = condition.companion_conditions

        def holds?(artifact) = !condition.holds?(artifact)
      end

      class All < Data.define(:conditions, :line)
        def companion_conditions = conditions.flat_map(&:companion_conditions)

        def holds?(artifact) = conditions.all? { |condition| condition.holds?(artifact) }
      end

      class Any < Data.define(:conditions, :line)
        def companion_conditions = conditions.flat_map(&:companion_conditions)

        def holds?(artifact) = conditions.any? { |condition| condition.holds?(artifact) }
      end
    end
  end
end
