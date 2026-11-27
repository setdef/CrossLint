# frozen_string_literal: true

# The AGENTS.md at the project's root and each one in a folder are two
# artifacts, since no path pattern matches both. Either may match nothing:
# a project can keep its AGENTS.md at its root alone, or only in folders.
class Artifacts < CrossLint::Artifacts
  def declare(_settings)
    [artifact("agents-md", primary: "AGENTS.md", pieces: {"claude" => "CLAUDE.md"}, optional: true),
      artifact("nested-agents-md", primary: "{path}/AGENTS.md", pieces: {"claude" => "{path}/CLAUDE.md"}, optional: true)]
  end
end
