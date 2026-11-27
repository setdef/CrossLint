# frozen_string_literal: true

# What the plugin's rules read in Markdown, with Ruby's standard library
# alone, since a plugin can load no gem CrossLint wasn't built with: the
# text GitHub renders, and the links in it. The rules require this file,
# which Ruby loads once, at the top level, so its module has a name no
# other plugin's file is likely to have.
module DecisionLogMarkdown
  FILL = "\u{F00FF}"

  # A character escaped with a backslash, while the text is read, as a
  # character of a private-use plane that no syntax matches.
  ESCAPED = 0xF0000

  FENCE = /\A {0,3}(`{3,}|~{3,})/

  CODE = /(`+)(?!`).+?(?<!`)\1(?!`)/m

  INLINE = /!?\[[^\[\]]*\]\(\s*(<[^<>\n]*>|(?:[^\s()]|\([^\s()]*\))*)(?:\s+(?:"[^"]*"|'[^']*'|\([^()]*\)))?\s*\)/

  DEFINITION = /^ {0,3}\[([^\]^][^\]]*)\]:[ \t]*\n?[ \t]*(<[^<>\n]*>|\S+)/

  TAG = /<[A-Za-z][^<>]*>/

  # The text, with each character of what GitHub renders as no text of
  # its own, front matter, HTML comments, fenced code, and code spans,
  # replaced with FILL, and each escaped character with a private one.
  # Lines keep their places, so an offset's line is the source's.
  def self.prose(text)
    text = text.scrub.delete_prefix("\uFEFF").gsub("\r\n", "\n")
    text = mask(mask(text, /\A---\n.*?^(?:---|\.\.\.)$/m), /<!--.*?-->/m)
    text = unfenced(text.split("\n", -1)).join("\n")
    mask(text.gsub(/\\([!-\/:-@\[-`{-~])/) { (ESCAPED + Regexp.last_match(1).ord).chr(Encoding::UTF_8) }, CODE)
  end

  # Each link's destination as written, with the line it is on: inline
  # links and images, reference definitions, and href and src in HTML.
  def self.links(text)
    text = prose(text)
    found = text.to_enum(:scan, DEFINITION).map { [Regexp.last_match(2), line(text, Regexp.last_match.begin(0))] }
    text.to_enum(:scan, TAG).each do
      start = Regexp.last_match.begin(0)
      Regexp.last_match(0).scan(/\s(?:href|src)\s*=\s*(?:"([^"]*)"|'([^']*)')/) { found << [$1 || $2, line(text, start)] }
    end
    while (match = INLINE.match(text))
      found << [match[1], line(text, match.begin(0))]
      text = text[0...match.begin(0)] + mask(match[0], /[^\n]+/) + text[match.end(0)..]
    end
    found.map { |written, at| [restore(written.delete_prefix("<").delete_suffix(">")), at] }.reject { |written, _| written.empty? }
  end

  def self.line(text, offset) = text[0...offset].count("\n") + 1

  def self.mask(text, pattern) = text.gsub(pattern) { it.gsub(/[^\n]/, FILL) }

  def self.restore(text) = text.gsub(/[\u{F0021}-\u{F007E}]/) { (it.ord - ESCAPED).chr }

  # The lines, with each line of fenced code empty. A fence that is never
  # closed runs to the end, as CommonMark has it.
  def self.unfenced(lines)
    fence = nil
    lines.map do |line|
      if fence
        fence = nil if line.match?(/\A {0,3}#{Regexp.escape(fence[0])}{#{fence.size},}[ \t]*\z/)
        next ""
      end
      fence = line[FENCE, 1]
      fence ? "" : line
    end
  end
end
