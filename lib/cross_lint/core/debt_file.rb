# frozen_string_literal: true

module CrossLint
  module Core
    class DebtEntry < Data.define(:rule, :artifact, :comment, :detail, :line, :source)
      def self.fresh(rule:, artifact:, comment: "", detail: nil) = new(rule:, artifact:, comment:, detail:, line: nil, source: nil)
    end

    class DebtFile < Data.define(:file, :entries, :header); end
  end
end
