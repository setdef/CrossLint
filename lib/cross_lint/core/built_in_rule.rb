# frozen_string_literal: true

require_relative "artifact"

module CrossLint
  module Core
    class BuiltInRule < Data.define(:name, :arguments, :severity)
      ALL = [
        new(name: "companion-exists", arguments: ["companion"], severity: :error),
        new(name: "companion-absent", arguments: ["companion"], severity: :error)
      ].freeze

      def self.named(name) = ALL.find { |rule| rule.name == name }

      def results(artifact, arguments, _read)
        messages(artifact, arguments).map { |message| RuleResult.new(path: artifact.path, role: artifact.role, message:, detail: nil) }
      end

      def messages(artifact, arguments)
        companion = artifact.companion(arguments.fetch("companion"))
        return (companion.exist? ? [] : ["no #{companion.name} file at #{companion.path}"]) if name == "companion-exists"

        companion.exist? ? ["#{companion.name} file exists at #{companion.path}"] : []
      end
    end
  end
end
