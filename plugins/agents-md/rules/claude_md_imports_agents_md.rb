# frozen_string_literal: true

# A byte order mark, and spaces, tabs, or the \r of a CRLF line ending after
# @AGENTS.md, are no part of the first line, since an editor that writes
# them shows the line as @AGENTS.md.
class ClaudeMdImportsAgentsMd < CrossLint::Rule
  IMPORT = "@AGENTS.md"

  def check(artifact)
    claude = artifact.piece("claude")
    first = claude.read.delete_prefix("\uFEFF")[/\A[^\n]*/].rstrip
    return [] if first == IMPORT

    [violation(artifact, "#{claude.path} starts with #{first.empty? ? 'a blank line' : first.dump}; its first line should be #{IMPORT}")]
  end
end
