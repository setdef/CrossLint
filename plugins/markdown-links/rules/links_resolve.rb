# frozen_string_literal: true

# A relative link resolves as GitHub resolves it in a repository's
# Markdown: a path from the file's folder, or from the project's root when
# it starts with /, to a file or folder among the project's files, and an
# anchor, when it has one, to a heading or an HTML id or name in the
# Markdown file it points to. A link with ?plain=1 has no anchor to check,
# since its anchor names a line of the source.
class LinksResolve < CrossLint::Rule
  MARKDOWN = /\.(?:md|markdown)\z/

  # A link with a scheme, such as https: or mailto:, or one that starts
  # with //, leaves the repository.
  ABSOLUTE = %r{\A(?:[A-Za-z][A-Za-z0-9+.-]*:|//)}

  def initialize
    @files = project_files.to_h { [it, true] }
    @folders = {"" => true}
    project_files.each do |file|
      parts = file.split("/")
      (1...parts.size).each { |size| @folders[parts.take(size).join("/")] = true }
    end
    @anchors = {}
  end

  def check(artifact)
    Document.new(artifact.read).links.group_by(&:first).filter_map do |written, found|
      problem = problem(artifact.path, written)
      next unless problem

      lines = found.map(&:last).uniq
      violation(artifact, "#{(lines.size == 1) ? "line" : "lines"} #{lines.join(", ")}: #{written} #{problem}", detail: written)
    end
  end

  private

  def problem(from, written)
    return if written.match?(ABSOLUTE)

    path, _, anchor = written.partition("#")
    path, _, query = path.partition("?")
    target = path.empty? ? from : resolve(from, decode(path))
    return "points outside the project" unless target
    return "points to #{target}, which isn't a file or folder of the project" unless @files[target] || @folders[target]
    return if anchor.empty? || !target.match?(MARKDOWN) || !@files[target]
    # With ?plain=1 GitHub shows the file's source, where #L3 is a line.
    return if query.split("&").include?("plain=1")

    "points to #{target}, which has no heading or anchor #{decode(anchor).dump}" unless anchors(target).include?(decode(anchor))
  end

  # The path from the project's root, without . and .., or nil when ..
  # leaves the project.
  def resolve(from, path)
    parts = path.start_with?("/") ? [] : from.split("/")[0...-1]
    path.split("/").each do |part|
      next if ["", "."].include?(part)
      return nil if part == ".." && parts.empty?

      (part == "..") ? parts.pop : parts << part
    end
    parts.join("/")
  end

  def decode(text) = text.b.gsub(/%(\h\h)/n) { Regexp.last_match(1).hex.chr }.force_encoding(Encoding::UTF_8)

  def anchors(path) = @anchors[path] ||= Document.new(read(path)).anchors

  # A Markdown file's links and anchors, read with Ruby's standard library
  # alone, since a plugin can load no gem CrossLint wasn't built with. It
  # reads the CommonMark and GitHub forms a link takes in a repository's
  # documents: inline links and images, reference definitions, and href
  # and src in HTML. It skips what GitHub doesn't render as a link: fenced
  # code, code spans, HTML comments, front matter, and characters escaped
  # with a backslash. An indented code block reads as text, since telling
  # one from a list item's indented lines takes a full parser, and a link
  # missed in a list is worse than one checked in such a block.
  class Document
    # A character escaped with a backslash, while the text is read, as a
    # character of a private-use plane that no syntax matches.
    ESCAPED = 0xF0000

    FILL = "\u{F00FF}"

    FENCE = /\A {0,3}(`{3,}|~{3,})/

    INLINE = /!?\[(?:[^\[\]]|\[[^\[\]]*\](?!\())*\]\(\s*(<[^<>\n]*>|(?:[^\s()]|\([^\s()]*\))*)(?:\s+(?:"[^"]*"|'[^']*'|\([^()]*\)))?\s*\)/

    DEFINITION = /^ {0,3}\[([^\]^][^\]]*)\]:[ \t]*\n?[ \t]*(<[^<>\n]*>|\S+)/

    TAG = /<[A-Za-z][^<>]*>/

    ATX = /\A {0,3}\#{1,6}(?:[ \t]+(.*?))?(?:[ \t]+#+)?[ \t]*\z/

    SETEXT = /\A {0,3}(?:=+|-+)[ \t]*\z/

    # A line a setext underline can't make a heading of: a heading, a
    # quote, a list item, or a table's row.
    NO_PARAGRAPH = /\A {0,3}(?:#|>|[-*+][ \t]|\d+[.)][ \t]|\|)/

    def initialize(text)
      text = text.scrub.delete_prefix("\uFEFF").gsub("\r\n", "\n")
      text = mask(text, /\A---\n.*?^(?:---|\.\.\.)$/m)
      text = mask(text, /<!--.*?-->/m)
      @lines = unfenced(text.split("\n", -1))
      @text = @lines.join("\n").gsub(/\\([!-\/:-@\[-`{-~])/) { (ESCAPED + Regexp.last_match(1).ord).chr(Encoding::UTF_8) }
    end

    # Each link's destination as written, with the line it is on.
    def links
      text = mask(@text, /(`+)(?!`).+?(?<!`)\1(?!`)/m)
      found = text.to_enum(:scan, DEFINITION).map { [Regexp.last_match(2), line(text, Regexp.last_match.begin(0))] }
      text.to_enum(:scan, TAG).each do
        start = Regexp.last_match.begin(0)
        Regexp.last_match(0).scan(/\s(?:href|src)\s*=\s*(?:"([^"]*)"|'([^']*)')/) { found << [$1 || $2, line(text, start)] }
      end
      while (match = INLINE.match(text))
        found << [match[1], line(text, match.begin(0))]
        text = text[0...match.begin(0)] + fill(match[0]) + text[match.end(0)..]
      end
      found.map { |written, at| [restore(written.delete_prefix("<").delete_suffix(">")), at] }.reject { |written, _| written.empty? }
    end

    # The anchor of each heading, as GitHub makes it, and each id and name
    # in HTML.
    def anchors
      seen = Hash.new(0)
      headings.map { slug(it, seen) } + mask(@text, /(`+)(?!`).+?(?<!`)\1(?!`)/m).scan(TAG).flat_map do |tag|
        tag.scan(/\s(?:id|name)\s*=\s*(?:"([^"]*)"|'([^']*)')/).map { |double, single| restore(double || single) }
      end
    end

    private

    def mask(text, pattern) = text.gsub(pattern) { fill(it) }

    def fill(text) = text.gsub(/[^\n]/, FILL)

    def line(text, offset) = text[0...offset].count("\n") + 1

    def restore(text) = text.gsub(/[\u{F0021}-\u{F007E}]/) { (it.ord - ESCAPED).chr }

    # The lines, with each line of fenced code empty. A fence that is
    # never closed runs to the end, as CommonMark has it.
    def unfenced(lines)
      fence = nil
      lines.map do |line|
        opening = line[FENCE, 1]
        if fence
          fence = nil if line.match?(/\A {0,3}#{Regexp.escape(fence[0])}{#{fence.size},}[ \t]*\z/)
          next ""
        end
        next line unless opening

        fence = opening
        ""
      end
    end

    def headings
      lines = @text.split("\n", -1)
      lines.each_with_index.filter_map do |line, index|
        next line[ATX, 1].to_s if line.match?(ATX)

        before = lines[index - 1] if index.positive?
        before.strip if line.match?(SETEXT) && before && !before.strip.empty? && !before.match?(NO_PARAGRAPH) && !before.match?(SETEXT)
      end
    end

    # GitHub's anchor for a heading: its text as it renders, in lower
    # case, with each space a -, and with nothing but letters, marks,
    # digits, _, and - kept; a later heading with the same anchor gets -1,
    # -2, and so on.
    def slug(heading, seen)
      text = restore(heading.gsub(/!\[[^\]]*\]\([^)]*\)/, "").gsub(/\[([^\]]*)\](?:\([^)]*\)|\[[^\]]*\])/, '\1').gsub(%r{</?[A-Za-z][^<>]*>}, ""))
      text = text.gsub(/[`*~]/, "").gsub(/(?<![\p{L}\p{N}])_+|_+(?![\p{L}\p{N}])/, "")
      base = text.downcase.gsub(/[^\p{L}\p{M}\p{N}\p{Pc} -]/, "").tr(" ", "-")
      anchor = base
      anchor = "#{base}-#{seen[base] += 1}" while seen.key?(anchor)
      seen[anchor] = 0
      anchor
    end
  end
end
