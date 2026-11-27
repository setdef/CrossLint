# frozen_string_literal: true

require "json"
require_relative "text_report"

module CrossLint
  module Adapters
    class JSONReport < TextReport
      def write(result)
        return write_faults(result) if result.verbosity == :silent

        super
      end

      private

      def write_findings(result)
        summary = result.summary
        @out.puts JSON.generate({
          "findings" => result.violations.map do |violation|
            {"path" => violation.path, "message" => violation.message, "plugin" => violation.plugin, "policy" => violation.policy,
             "artifact" => violation.artifact, "role" => violation.role, "severity" => violation.severity, "detail" => violation.detail}
          end,
          "stale" => result.stale.map do |stale|
            {"file" => stale.file, "line" => stale.line, "plugin" => stale.plugin, "policy" => stale.policy, "artifact" => stale.artifact,
             "message" => stale.message}
          end,
          "summary" => {"artifacts" => summary.artifacts, "errors" => summary.errors, "warnings" => summary.warnings, "stale" => summary.stale}
        }, ascii_only: true)
      end
    end
  end
end
