# frozen_string_literal: true

require "json"
require_relative "text_report"

module CrossLint
  module Adapters
    class JSONReport < TextReport
      def write(result)
        super unless result.verbosity == :silent
      end

      private

      def write_findings(result)
        summary = result.summary
        @out.puts JSON.generate({
          "findings" => result.violations.map do |violation|
            {"path" => violation.artifact, "message" => violation.message, "plugin" => violation.plugin, "policy" => violation.policy,
             "artifact" => violation.artifact, "role" => violation.role, "severity" => violation.severity, "detail" => violation.detail}
          end,
          "summary" => {"artifacts" => summary.artifacts, "errors" => summary.errors, "warnings" => summary.warnings}
        }, ascii_only: true)
      end
    end
  end
end
