# frozen_string_literal: true

require_relative "spelling"

module CrossLint
  module Core
    class Notice < Data.define(:file, :line, :message); end

    class Summary < Data.define(:kinds, :errors, :warnings, :warnings_shown)
      def artifacts = kinds.sum(&:last)

      def line
        counted = kinds.map { |name, count| "#{count} #{name}" }
        checked = counted.empty? ? "0" : Spelling.list(counted, "and")
        "checked #{checked} #{(artifacts == 1) ? "artifact" : "artifacts"}: #{found}"
      end

      private

      def found
        counts = {"error" => errors, "warning" => warnings}.reject { |_, count| count.zero? }
          .map { |word, count| "#{count} #{word}#{"s" unless count == 1}" }
        return counts.join(", ") unless counts.empty?

        warnings_shown ? "no violations" : "no errors"
      end
    end

    class CheckResult < Data.define(:notices, :findings, :summary, :verbosity, :failed)
      def violations
        findings.filter_map do |finding|
          case finding
          when Violation then finding
          end
        end
      end
    end
  end
end
