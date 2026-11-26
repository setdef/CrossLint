# frozen_string_literal: true

require_relative "spelling"

module CrossLint
  module Core
    class Notice < Data.define(:file, :line, :message); end

    class Summary < Data.define(:kinds, :faults, :errors, :warnings, :warnings_shown, :stale, :steps)
      def initialize(stale: 0, steps: [], **counts) = super

      def artifacts = kinds.sum(&:last)

      def line
        counted = kinds.map { |name, count| "#{count} #{name}" }
        checked = counted.empty? ? "0" : Spelling.list(counted, "and")
        "checked #{checked} #{(artifacts == 1) ? "artifact" : "artifacts"}: #{found}"
      end

      private

      def found
        counts = {"fault" => faults, "error" => errors, "warning" => warnings}.reject { |_, count| count.zero? }
          .map { |word, count| "#{count} #{word}#{"s" unless count == 1}" }
        counts << "#{stale} stale #{(stale == 1) ? "entry" : "entries"}" unless stale.zero?
        counts.concat(steps)
        return counts.join(", ") unless counts.empty?

        warnings_shown ? "no violations" : "no errors"
      end
    end

    class CheckResult < Data.define(:notices, :findings, :summary, :verbosity, :failed, :faults, :wrote)
      def initialize(wrote: [], **fields) = super

      def violations
        findings.filter_map do |finding|
          case finding
          when Violation then finding
          end
        end
      end

      def stale
        findings.filter_map do |finding|
          case finding
          when Stale then finding
          end
        end
      end
    end
  end
end
