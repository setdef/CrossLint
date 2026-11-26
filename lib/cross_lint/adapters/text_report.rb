# frozen_string_literal: true

require_relative "../core"

module CrossLint
  module Adapters
    class TextReport
      PREFIX = "crosslint: "

      COLORS = {error: "\e[31m", warning: "\e[33m"}.freeze

      RESET = "\e[0m"

      def initialize(out:, err:, color: false)
        @out = out
        @err = err
        @color = color
      end

      def write(result)
        result.notices.each { |notice| say("#{notice.file}:#{notice.line}: warning: #{notice.message}") }
        write_findings(result)
        # Ruby holds standard output to a pipe until it exits, so where
        # both streams go to one log, as in CI, the summary would come
        # before the findings.
        @out.flush
        say(result.summary.line) if result.verbosity == :normal
      end

      private

      def write_findings(result)
        result.findings.each do |finding|
          case finding
          when Core::Violation
            message = (finding.severity == :warning) ? "warning: #{finding.message}" : finding.message
            message = "#{COLORS.fetch(finding.severity)}#{message}#{RESET}" if @color
            @out.puts "#{finding.artifact}: #{message} (#{finding.plugin}/#{finding.policy})"
          else
            @out.puts "#{finding.path}: #{finding.role} passes"
          end
        end
      end

      def say(line) = @err.puts("#{PREFIX}#{line}")
    end
  end
end
