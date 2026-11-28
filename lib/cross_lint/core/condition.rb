# frozen_string_literal: true

module CrossLint
  module Core
    module Condition
      class PieceExists < Data.define(:piece, :line)
        def piece_conditions = [self]

        def holds?(artifact) = artifact.piece(piece).exist?

        def explanation(artifact) = %(piece-exists #{piece.dump} (#{holds?(artifact) ? "exists" : "missing"}))
      end

      class Not < Data.define(:condition, :line)
        def piece_conditions = condition.piece_conditions

        def holds?(artifact) = !condition.holds?(artifact)

        def explanation(artifact) = "not { #{condition.explanation(artifact)} }"
      end

      class All < Data.define(:conditions, :line)
        def piece_conditions = conditions.flat_map(&:piece_conditions)

        def holds?(artifact) = conditions.all? { |condition| condition.holds?(artifact) }

        def explanation(artifact) = "all { #{conditions.map { |condition| condition.explanation(artifact) }.join(" ")} }"
      end

      class Any < Data.define(:conditions, :line)
        def piece_conditions = conditions.flat_map(&:piece_conditions)

        def holds?(artifact) = conditions.any? { |condition| condition.holds?(artifact) }

        def explanation(artifact) = "any { #{conditions.map { |condition| condition.explanation(artifact) }.join(" ")} }"
      end
    end
  end
end
