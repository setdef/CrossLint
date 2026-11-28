# frozen_string_literal: true

require_relative "artifact"
require_relative "fault"
require_relative "ruby_rule"

module CrossLint
  module Core
    class HelperRule
      def initialize(plugin:, name:, helper:, call:)
        @plugin = plugin
        @name = name
        @helper = helper
        @call = call
      end

      def severity = :error

      def results(artifact, _arguments, _read)
        answer = @call.call(@helper, {"rule" => @name, "artifact" => HelperRule.described(artifact)})
        raise PluginError, "failed in helper #{@helper.dump}: #{answer.fetch("error")}" if answer.is_a?(Hash) && answer["error"].is_a?(String)

        found = answer.is_a?(Hash) && answer["violations"]
        raise PluginError, %(got an answer from helper #{@helper.dump} that isn't {"violations": [...]}) unless found.is_a?(Array)

        found.map { |violation| result(artifact, violation) }
      rescue PluginError => error
        raise RubyRule::Stopped, Fault.of(error, plugin: @plugin, rule: @name, artifact: artifact.location)
      end

      def self.described(artifact)
        {"path" => artifact.path, "name" => artifact.name, "role" => artifact.role, "line" => artifact.line, "match" => artifact.match,
         "key" => artifact.key, "pieces" => artifact.pieces.to_h { |piece| [piece.name, {"path" => piece.path, "exists" => piece.exists}] }}
      end

      private

      def result(artifact, violation)
        message = violation["message"] if violation.is_a?(Hash)
        detail = violation["detail"] if violation.is_a?(Hash)
        given = message.is_a?(String) && (detail.nil? || detail.is_a?(String))
        raise PluginError, %(got a violation from helper #{@helper.dump} that isn't {"message": TEXT, "detail": TEXT}) unless given

        RuleResult.new(path: artifact.path, role: artifact.role, message:, detail:)
      end
    end
  end
end
