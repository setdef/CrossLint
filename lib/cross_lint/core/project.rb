# frozen_string_literal: true

module CrossLint
  module Core
    class Plugin < Data.define(:name, :folder, :listing, :manifest); end

    class Project < Data.define(:root, :configuration, :plugins)
      def unused_rules
        plugins.flat_map do |plugin|
          used = plugin.manifest.policies.flat_map(&:rules).map(&:name)
          plugin.manifest.rules.reject { |rule| used.include?(rule.name) }.map { |rule| [plugin, rule] }
        end
      end
    end
  end
end
