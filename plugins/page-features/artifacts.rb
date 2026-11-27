# frozen_string_literal: true

# The page components, found by the path pattern of the setting page, each
# with the feature file the setting feature gives as its companion. A
# placeholder of feature that page lacks would have no value for a page,
# so it is a mistake here rather than a fault at the first page.
class Artifacts < CrossLint::Artifacts
  DEFAULTS = {"page" => "src/pages/{path}.tsx", "feature" => "features/{path}.feature"}.freeze

  def declare(settings)
    found = {}
    settings.each do |setting|
      first = found[setting.name]
      raise mistake("#{setting.name} is set twice; the first is on line #{first.line}", setting) if first

      found[setting.name] = setting
    end
    page, feature = DEFAULTS.map { |name, default| setting_pattern(found[name], name, default) }
    lacking = feature.scan(/\{[^{}]*\}/).uniq - page.scan(/\{[^{}]*\}/)
    raise mistake("feature has #{lacking.first}, which page #{page.dump} doesn't, so a page gives it no value", found["feature"] || found["page"]) if lacking.any?

    [artifact("page", files: page, companions: {"feature" => feature})]
  end

  private

  def setting_pattern(setting, name, default)
    return default unless setting

    given = setting.arguments.first
    unless setting.arguments.size == 1 && given.is_a?(String) && setting.properties.empty? && setting.children.empty?
      raise mistake("#{name} takes one path pattern and nothing else, as in #{name} #{default.dump}", setting)
    end

    if given.empty? || given.start_with?("/") || given.match?(/\A[A-Za-z]:/) || given.split("/").include?("..")
      raise mistake("#{name} takes a path pattern inside the project, relative to its root, not #{given.dump}", setting)
    end
    problem = CrossLint::Core::PathPattern.problem(given)
    raise mistake("#{name} takes a path pattern, and #{problem}", setting) if problem

    given.split("/").reject { it == "." }.join("/")
  end
end
