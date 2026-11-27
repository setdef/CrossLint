# frozen_string_literal: true

require_relative "../records"

# Two records with one number, as when two people each take the next
# number at once, make every citation of that number ambiguous.
class NumbersUnique < CrossLint::Rule
  def check(artifact)
    folder = artifact.piece("folder").path
    DecisionLogRecords.in(project_files, folder).group_by(&:last).sort.filter_map do |number, records|
      next if records.size == 1

      names = records.map { File.basename(it.first) }.sort
      violation(artifact, "#{DecisionLogRecords.list(names)} in #{folder} have the same number, #{number}", detail: number.to_s)
    end
  end
end
