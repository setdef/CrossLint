# frozen_string_literal: true

module CrossLint
  module Core
    class Plugin < Data.define(:name, :folder, :listing, :manifest)
      # Without applies-to, every artifact of the plugin's own that has each
      # companion the policy names.
      def targets(policy)
        applies_to = policy.applies_to
        unless applies_to
          named = policy.companions
          return manifest.artifacts.select { |artifact| named.all? { |companion| artifact.companion(companion) } }.map { |artifact| [name, artifact.name] }
        end

        owner, slash, artifact = applies_to.artifact.partition("/")
        [slash.empty? ? [name, owner] : [owner, artifact]]
      end
    end

    class PluginListing < Data.define(:file, :plugins, :unfetched); end

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
