# frozen_string_literal: true

require_relative "../markdown"
require_relative "../records"

# A citation is "ADR" and a number, as in ADR 7, ADR 0007, or ADR-0007,
# in the text GitHub renders; a number in a code span or a fenced block
# is an example. "former ADR 7" is how a dated document mentions a record
# that a later one replaced, so it is no citation.
class CitationsResolve < CrossLint::Rule
  CITATION = /(?<![\p{L}\p{N}_-])((?i:former)\s+)?ADR[ -]?(\d+)(?![\p{L}\p{N}_])/

  def check(artifact)
    folder = artifact.companion("folder").path
    numbers = DecisionLogRecords.in(project_files, folder).values
    text = DecisionLogMarkdown.prose(artifact.read)
    cited = text.to_enum(:scan, CITATION).filter_map do
      match = Regexp.last_match
      [match[0], match[2].to_i, DecisionLogMarkdown.line(text, match.begin(0))] unless match[1]
    end
    cited.reject { numbers.include?(it[1]) }.group_by(&:first).map do |written, found|
      lines = found.map(&:last).uniq
      violation(artifact, "#{(lines.size == 1) ? "line" : "lines"} #{lines.join(", ")}: #{written} matches no record in #{folder}", detail: written)
    end
  end
end
