# frozen_string_literal: true

require_relative "../core"

module CrossLint
  module Adapters
    class TextReport
      PREFIX = "crosslint: "

      COLORS = { error: "\e[31m", warning: "\e[33m" }.freeze

      RESET = "\e[0m"

      def initialize(out:, err:, color: false, debug: false)
        @out = out
        @err = err
        @color = color
        @debug = debug
      end

      # Only on a terminal, where someone waits; a log or a script gets the
      # summary at the end.
      def start(kinds)
        say("checking #{Core::Summary.count(kinds)}") if @err.tty?
      end

      def write(result)
        result.notices.each { |notice| say("#{notice.file}:#{notice.line}: warning: #{notice.message}") }
        write_findings(result)
        # Ruby holds standard output to a pipe until it exits, so where
        # both streams go to one log, as in CI, the summary would come
        # before the findings.
        @out.flush
        write_faults(result)
        result.wrote.each { |line| say(line) } unless result.verbosity == :silent
        say(result.summary.line) if result.verbosity == :normal
      end

      private

      def write_faults(result)
        result.faults.each do |fault|
          fault.line.each_line { |line| say(line) }
          fault.trace.each { |line| say("  from #{line}") } if @debug
        end
        return if @debug || result.verbosity == :silent || result.faults.all? { |fault| fault.trace.empty? }

        say("run it again with --debug to see where each fault was raised")
      end

      def write_findings(result)
        result.findings.each do |finding|
          case finding
          when Core::Violation
            message = (finding.severity == :warning) ? "warning: #{finding.message}" : finding.message
            message = "#{COLORS.fetch(finding.severity)}#{message}#{RESET}" if @color
            @out.puts "#{where(finding.path, finding.line, finding.artifact)}#{message} (#{finding.plugin}/#{finding.policy})"
          when Core::PaidOffEntry
            @out.puts "#{finding.artifact}: #{finding.message} (#{finding.plugin}/#{finding.policy})"
          else
            @out.puts "#{where(finding.path, finding.line, finding.name)}#{finding.role} passes"
          end
        end
      end

      def where(path, line, name) = "#{path}#{":#{line}" if line}: #{"#{name}: " unless name == path}"

      def say(line) = @err.puts("#{PREFIX}#{line}")
    end
  end
end
