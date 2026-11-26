# frozen_string_literal: true

module CrossLint
  module Core
    class BuiltInRule < Data.define(:name, :arguments, :severity)
      ALL = [
        new(name: "companion-exists", arguments: ["companion"], severity: :error),
        new(name: "companion-absent", arguments: ["companion"], severity: :error)
      ].freeze

      def self.named(name) = ALL.find { |rule| rule.name == name }
    end
  end
end
