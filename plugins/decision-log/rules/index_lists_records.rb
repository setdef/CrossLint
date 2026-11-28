# frozen_string_literal: true

require_relative "../markdown"
require_relative "../records"

# The index lists a record by a link to it, resolved from the index's
# folder, in any form a link takes: a table's row, a list's item, or a
# reference definition.
class IndexListsRecords < CrossLint::Rule
  def check(artifact)
    folder = artifact.piece("folder").path
    records = DecisionLogRecords.in(project_files, folder)
    linked = DecisionLogMarkdown.links(artifact.read).filter_map do |written, line|
      path = DecisionLogRecords.resolve(artifact.path, written)
      [path, line] if path && File.dirname(path) == folder && DecisionLogRecords.record?(path)
    end
    unlisted = (records.keys - linked.map(&:first)).sort.map do |record|
      name = File.basename(record)
      violation(artifact, "#{name} is a record in #{folder}, and the index has no link to it", detail: name)
    end
    unlisted + linked.reject { records.key?(it.first) }.group_by(&:first).map do |path, found|
      lines = found.map(&:last).uniq
      name = File.basename(path)
      violation(artifact, "#{(lines.size == 1) ? 'line' : 'lines'} #{lines.join(', ')}: links to #{name}, which isn't a record in #{folder}", detail: name)
    end
  end
end
