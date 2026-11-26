# frozen_string_literal: true

require_relative "spelling"

module CrossLint
  module Core
    class Notice < Data.define(:file, :line, :message); end

    class Summary < Data.define(:kinds, :faults, :errors, :warnings, :warnings_shown, :stale, :steps)
      def initialize(stale: 0, steps: [], **counts) = super

      # A kind with no artifact is left out when another has some, as the
      # Angular plugin's pipes are in a project with none.
      def self.count(kinds)
        found = kinds.reject { |_, count| count.zero? }
        each = (found.empty? ? kinds : found).map { |name, count| "#{count} #{name}" }
        "#{each.empty? ? "0" : Spelling.list(each, "and")} #{(kinds.sum(&:last) == 1) ? "artifact" : "artifacts"}"
      end

      def artifacts = kinds.sum(&:last)

      def line = "checked #{Summary.count(kinds)}: #{found}"

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
