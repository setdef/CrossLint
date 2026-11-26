# frozen_string_literal: true

# The Angular plugin's artifacts: ng-nudge's seven roles, each found by
# {path}.ROLE.ts inside src-dir, and each role the configuration's role
# settings change or add. Each artifact's key is ng-nudge's base path, its
# primary file's path relative to src-dir without .ROLE.ts, so that an
# entry of a debt file moved from ng-nudge names it.
class Artifacts < CrossLint::Artifacts
  ROLES = %w[component directive pipe service guard resolver interceptor].freeze

  # Where a component's other companions are: its file, with .ts
  # replaced. ng-nudge reads the stylesheets too.
  COMPONENT = {"stub" => ".stub.ts", "interface" => ".i.d.ts", "css" => ".css", "scss" => ".scss"}.freeze

  # A role can expect only a spec: ng-nudge checks no other companion of
  # every artifact of a role.
  EXPECTED = %w[spec].freeze

  def declare(settings)
    found = once(settings)
    src = folder(found["src-dir"], "src-dir", "src")
    tsconfig = folder(found["tsconfig"], "tsconfig", "tsconfig.json")
    roles = ROLES.to_h { |role| [role, {files: "{path}.#{role}.ts", expects: EXPECTED, optional: true}] }
    settings.select { |setting| setting.name == "role" }.each { |setting| role(roles, setting) }
    roles.map do |role, given|
      files = given.fetch(:files)
      within = ->(pattern) { src.empty? ? pattern : "#{src}/#{pattern}" }
      stem = files.delete_suffix(".ts")
      companions = given.fetch(:expects).to_h { |name| [name, within.call("#{stem}.spec.ts")] }
      companions.merge!(COMPONENT.transform_values { |suffix| within.call(stem + suffix) }, "tsconfig" => tsconfig) if role == "component"
      # node-glob, which ng-nudge's patterns were, skips what starts with a dot.
      artifact(role, files: within.call(files), companions:, key: files.delete_suffix(".#{role}.ts"), optional: given.fetch(:optional), dotfiles: false)
    end
  end

  private

  # The settings that are given once, by name.
  def once(settings)
    settings.reject { |setting| setting.name == "role" }.each_with_object({}) do |setting, found|
      first = found[setting.name]
      raise mistake("#{setting.name} is set twice; the first is on line #{first.line}", setting) if first

      found[setting.name] = setting
    end
  end

  # The path a setting gives, relative to the project's root, with no
  # ./ or trailing /, or the default when the setting isn't given.
  def folder(setting, name, default)
    return default unless setting

    path = setting.arguments.first
    unless setting.arguments.size == 1 && path.is_a?(String) && setting.properties.empty? && setting.children.empty?
      raise mistake("#{name} takes one path and nothing else, as in #{name} #{default.dump}", setting)
    end

    segments = path.split("/").reject { |segment| ["", "."].include?(segment) }
    if path.start_with?("/") || path.match?(/\A[A-Za-z]:/) || segments.include?("..") || path.include?("\\") || path.match?(/[{}]/)
      raise mistake("#{name} takes a path inside the project, relative to its root, with / between folders, not #{path.dump}", setting)
    end
    raise mistake("#{name} takes a file's path, not #{path.dump}", setting) if segments.empty? && name == "tsconfig"

    segments.join("/")
  end

  def role(roles, setting)
    name = setting.arguments.first
    unless setting.arguments.size == 1 && name.is_a?(String) && name.match?(/\A[A-Za-z0-9_-]+\z/)
      raise mistake("role takes one name of letters, digits, - and _, as in role \"store\" files=\"{path}.store.ts\"", setting)
    end
    first = roles.dig(name, :line)
    raise mistake("role #{name.dump} is set twice; the first is on line #{first}", setting) if first

    unknown = setting.properties.keys - ["files"]
    raise mistake("role takes files= and nothing else, not #{unknown.first}=", setting) unless unknown.empty?

    files = setting.properties["files"]
    raise mistake("role #{name.dump} takes files= as a path pattern ending in .ts, relative to src-dir", setting) unless files.nil? || pattern?(files)

    roles[name] = {files: files || "{path}.#{name}.ts", expects: expects(name, setting),
                   optional: files.nil? && roles.key?(name), line: setting.line}
  end

  def pattern?(files)
    files.is_a?(String) && files.end_with?(".ts") && !files.start_with?("/") && !files.split("/").include?("..") &&
      CrossLint::Core::PathPattern.problem(files).nil?
  end

  # The companions a role's block says it expects, or a spec when it has
  # no block.
  def expects(name, setting)
    children = setting.children
    return EXPECTED if children.empty?

    child = children.first
    unless children.size == 1 && child.name == "expects" && child.properties.empty? && child.children.empty?
      raise mistake("role #{name.dump} takes one thing in its block, expects COMPANION ...", children.reject { |each| each.name == "expects" }.first || children.last)
    end

    unknown = child.arguments.find { |companion| !EXPECTED.include?(companion) }
    raise mistake("role #{name.dump} expects #{unknown.inspect}, and a role can expect only \"spec\"", child) if unknown

    child.arguments
  end
end
