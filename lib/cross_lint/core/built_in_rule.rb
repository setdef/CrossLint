# frozen_string_literal: true

require_relative "artifact"

module CrossLint
  module Core
    class BuiltInRule < Data.define(:name, :arguments, :severity)
      ALL = [
        new(name: "piece-exists", arguments: ["piece"], severity: :error),
        new(name: "piece-absent", arguments: ["piece"], severity: :error)
      ].freeze

      def self.named(name) = ALL.find { |rule| rule.name == name }

      def results(artifact, arguments, _read)
        messages(artifact, arguments).map { |message| RuleResult.new(path: artifact.path, role: artifact.role, message:, detail: nil) }
      end

      def messages(artifact, arguments)
        piece = artifact.piece(arguments.fetch("piece"))
        return (piece.exist? ? [] : ["no #{piece.name} file at #{piece.path}"]) if name == "piece-exists"

        piece.exist? ? ["#{piece.name} file exists at #{piece.path}"] : []
      end
    end
  end
end
