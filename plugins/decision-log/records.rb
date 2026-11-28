# frozen_string_literal: true

# The records of a decision log, and where a link from one of its files
# leads. The rules require this file, which Ruby loads once, at the top
# level, so its module has a name no other plugin's file is likely to
# have.
module DecisionLogRecords
  # A record is a Markdown file whose name starts with its number, as in
  # 0001-use-postgres.md or 20240131-use-postgres.md.
  RECORD = %r{\A(\d+)[^/]*\.md\z}

  # A link with a scheme, such as https:, or one that starts with //,
  # leaves the repository.
  ABSOLUTE = %r{\A(?:[A-Za-z][A-Za-z0-9+.-]*:|//)}

  def self.record?(path) = File.basename(path).match?(RECORD)

  # Each record directly in `folder`, by its path, with its number.
  def self.in(files, folder)
    files.select { File.dirname(it) == folder && record?(it) }.to_h { [it, File.basename(it)[RECORD, 1].to_i] }
  end

  # The path from the project's root that the link `written` in the file
  # `from` leads to, without its anchor or query, or nil for a link that
  # leaves the repository or the project.
  def self.resolve(from, written)
    return if written.match?(ABSOLUTE)

    path = written.partition("#").first.partition("?").first
    path = path.b.gsub(/%(\h\h)/n) { Regexp.last_match(1).hex.chr }.force_encoding(Encoding::UTF_8)
    parts = path.start_with?("/") ? [] : from.split("/")[0...-1]
    path.split("/").each do |part|
      next if ["", "."].include?(part)
      return nil if part == ".." && parts.empty?

      (part == "..") ? parts.pop : parts << part
    end
    parts.join("/")
  end

  # The names, as in "a and b" or "a, b, and c".
  def self.list(names) = (names.size == 2) ? names.join(" and ") : "#{names[0...-1].join(', ')}, and #{names.last}"
end
