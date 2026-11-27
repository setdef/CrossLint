# frozen_string_literal: true

# The index and every Markdown file, each with the folder of records as its
# piece "folder", since a rule gets no settings and learns the folder
# from its artifact.
class Artifacts < CrossLint::Artifacts
  def declare(settings)
    found = {}
    settings.each do |setting|
      first = found[setting.name]
      raise mistake("#{setting.name} is set twice; the first is on line #{first.line}", setting) if first

      found[setting.name] = setting
    end
    folder = path(found["folder"], "docs/decisions")
    index = path(found["index"], "#{folder}/README.md")
    [artifact("index", primary: index, pieces: {"folder" => folder}),
      artifact("document", primary: "{path}.md", pieces: {"folder" => folder})]
  end

  private

  # The path a setting gives, relative to the project's root, with no ./
  # or trailing /, or the default when the setting isn't given.
  def path(setting, default)
    return default unless setting

    given = setting.arguments.first
    unless setting.arguments.size == 1 && given.is_a?(String) && setting.properties.empty? && setting.children.empty?
      raise mistake("#{setting.name} takes one path and nothing else, as in #{setting.name} #{default.dump}", setting)
    end

    parts = given.split("/").reject { ["", "."].include?(it) }
    if parts.empty? || given.start_with?("/") || given.match?(/\A[A-Za-z]:|[\\{}]/) || parts.include?("..")
      raise mistake("#{setting.name} takes a path inside the project, relative to its root, with / between folders, not #{given.dump}", setting)
    end

    parts.join("/")
  end
end
