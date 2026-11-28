# frozen_string_literal: true

require "json"
require_relative "text_report"

module CrossLint
  module Adapters
    class JSONReport < TextReport
      def initialize(out:, err:, crosslint:, debug: false)
        super(out:, err:, debug:)
        @crosslint = crosslint
      end

      def write(result)
        return write_faults(result) if result.verbosity == :silent

        super
      end

      private

      def write_findings(result)
        summary = result.summary
        @out.puts JSON.generate({
          "crosslint_version" => @crosslint,
          "findings" => result.violations.map do |violation|
            {
"path" => violation.path,
"message" => violation.message,
"plugin" => violation.plugin,
"policy" => violation.policy,
"artifact" => violation.artifact,
"role" => violation.role,
"severity" => violation.severity,
"detail" => violation.detail,
"line" => violation.line,
}
          end,
          "paid_off" => result.paid_off.map do |paid_off|
            {
"file" => paid_off.file,
"line" => paid_off.line,
"plugin" => paid_off.plugin,
"policy" => paid_off.policy,
"artifact" => paid_off.artifact,
"message" => paid_off.message,
}
          end,
          "summary" => { "artifacts" => summary.artifacts, "errors" => summary.errors, "warnings" => summary.warnings, "paid_off" => summary.paid_off, "debt" => summary.excused },
        }, ascii_only: true)
      end
    end
  end
end
