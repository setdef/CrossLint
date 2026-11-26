# frozen_string_literal: true

require "pathname"

module CrossLint
  module Core
    class LoadProject
      def initialize(configuration:, manifests:, built_in: {}, steps: {})
        @configuration = configuration
        @manifests = manifests
        @built_in = built_in
        @steps = steps
      end

      def call(start)
        root = @configuration.find_root(start)
        unless root
          raise Mistake, "no #{@configuration.file} in #{start} or any folder above it; " \
            "run crosslint init in the project's root to write one"
        end

        configuration = @configuration.read(root)
        raise Mistake.new("lists no plugin, so no check would run; list one with plugin NAME", file: configuration.file) if configuration.plugins.empty?

        plugins = configuration.plugins.each_with_index.with_object([]) do |(listing, index), loaded|
          loaded << plugin(root, configuration, index, loaded)
        end
        plugins.each do |plugin|
          check_manifest(plugin, plugins)
          check_settings(plugin, configuration.file)
        end
        check_policy_settings(configuration, plugins)
        Project.new(root:, configuration:, plugins:)
      end

      private

      def plugin(root, configuration, index, loaded)
        listing = configuration.plugins.fetch(index)
        fail_at = ->(message, line = listing.line) { raise Mistake.new(message, file: configuration.file, line:) }
        first = configuration.plugins.take(index).find { |other| other.name == listing.name }
        fail_at.call("plugin #{listing.name.dump} is listed twice; the first is on line #{first.line}") if first

        base, folder = place(root, listing, fail_at)
        manifest = @manifests.read(base, folder) || fail_at.call("no #{@manifests.file} in #{folder.empty? ? "the project's root" : folder}")
        name = File.basename(File.expand_path(folder, base))
        same = loaded.find { |plugin| plugin.name == name }
        if same
          fail_at.call("plugins #{same.listing.name.dump} and #{listing.name.dump} are both named #{name.dump}, " \
            "since a plugin's name is its folder's name")
        end
        Plugin.new(name:, folder: File.expand_path(folder, base), listing:, manifest:)
      end

      def place(root, listing, fail_at)
        case listing.kind
        when :shared
          fail_at.call("shared plugin #{listing.name.dump} needs ref=, a tag or a full commit SHA") unless listing.ref
          fail_at.call("CrossLint can't fetch shared plugins yet")
        when :local
          fail_at.call("only a shared plugin takes ref=") if listing.ref
          [root, clean(listing.name)]
        else
          fail_at.call("only a shared plugin takes ref=") if listing.ref
          folder = @built_in.fetch(listing.name) do
            fail_at.call(Spelling.unknown("built-in plugin", listing.name, @built_in.keys, none: "this CrossLint has none"))
          end
          [File.dirname(folder), File.basename(folder)]
        end
      end

      # A name that starts with / is relative to the root too, as the
      # configuration reference says of every local plugin.
      def clean(name)
        cleaned = Pathname.new(name.sub(%r{\A/+}, "")).cleanpath.to_s
        (cleaned == ".") ? "" : cleaned
      end

      def check_manifest(plugin, plugins)
        manifest = plugin.manifest
        once(manifest.artifacts, "artifact", manifest.file)
        manifest.artifacts.each { |artifact| check_artifact(artifact, manifest.file) }
        once(manifest.rules, "rule", manifest.file)
        manifest.rules.each do |rule|
          next unless BuiltInRule.named(rule.name)

          raise Mistake.new("rule #{rule.name.dump} has the name of a built-in rule; name it something else",
            file: manifest.file, line: rule.line)
        end
        once(manifest.helpers, "helper", manifest.file)
        once(manifest.policies + manifest.step_policies, "policy", manifest.file)
        manifest.policies.each { |policy| check_policy(plugin, policy, plugins) }
        %i[settings flags steps].each { |kind| once(manifest.public_send(kind), kind.to_s.chomp("s"), manifest.file) }
        check_steps(manifest)
      end

      # Each step is one CrossLint has, and reports exactly the policies
      # the manifest declares with no block.
      def check_steps(manifest)
        reported = manifest.steps.flat_map do |declaration|
          step = @steps.fetch(declaration.name) do
            raise Mistake.new(Spelling.unknown("step", declaration.name, @steps.keys, none: "this CrossLint has none"),
              file: manifest.file, line: declaration.line)
          end
          step.policies.each do |name|
            next if manifest.step_policies.any? { |policy| policy.name == name }

            raise Mistake.new("step #{declaration.name.dump} reports policy #{name.dump}; declare it as policy #{name.dump}, with no block",
              file: manifest.file, line: declaration.line)
          end
        end
        manifest.step_policies.each do |policy|
          next if reported.include?(policy.name)

          raise Mistake.new("policy #{policy.name.dump} has no applies-to, and no step of the plugin reports it",
            file: manifest.file, line: policy.line)
        end
      end

      # Each setting in the plugin's block is one its manifest declares,
      # and each step reads what it takes.
      def check_settings(plugin, file)
        settings = plugin.listing.settings
        declared = plugin.manifest.settings.map(&:name)
        settings.each do |setting|
          next if declared.include?(setting.name)

          raise Mistake.new(Spelling.unknown("setting", setting.name, declared, none: "plugin #{plugin.name} takes none"), file:,
            line: setting.line)
        end
        plugin.manifest.steps.each { |declaration| @steps.fetch(declaration.name).check_settings(settings, file) }
      end

      def check_artifact(artifact, file)
        once(artifact.companions, "companion", file)
        artifact.companions.each do |companion|
          extra = companion.pattern.placeholders - artifact.files.placeholders
          next if extra.empty?

          raise Mistake.new("companion #{companion.name.dump} uses {#{extra.first}}, which the files pattern " \
            "#{artifact.files.source.dump} doesn't have", file:, line: companion.line)
        end
      end

      def once(declarations, kind, file)
        declarations.each_with_index do |declaration, index|
          first = declarations.take(index).find { |other| other.name == declaration.name }
          next unless first

          raise Mistake.new("#{kind} #{declaration.name.dump} is declared twice; the first is on line #{first.line}",
            file:, line: declaration.line)
        end
      end

      def check_policy(plugin, policy, plugins)
        file = plugin.manifest.file
        artifact = target(plugin, policy.applies_to, plugins)
        policy.condition&.companion_tests&.each { |test| companion(artifact, test.companion, file, test.line) }
        policy.rules.each { |rule| check_rule(plugin, artifact, rule) }
      end

      def target(plugin, applies_to, plugins)
        fail_at = ->(message) { raise Mistake.new(message, file: plugin.manifest.file, line: applies_to.line) }
        before, slash, after = applies_to.artifact.partition("/")
        owner_name, name = slash.empty? ? [plugin.name, before] : [before, after]
        owner = plugins.find { |listed| listed.name == owner_name }
        fail_at.call(Spelling.unknown("plugin", owner_name, plugins.map(&:name))) unless owner
        artifacts = owner.manifest.artifacts
        artifacts.find { |artifact| artifact.name == name } ||
          fail_at.call(Spelling.unknown("artifact", name, artifacts.map(&:name), none: "#{owner.name} declares none"))
      end

      def check_rule(plugin, artifact, rule)
        fail_at = ->(message) { raise Mistake.new(message, file: plugin.manifest.file, line: rule.line) }
        built_in = BuiltInRule.named(rule.name)
        unless built_in
          declared = plugin.manifest.rules.map(&:name)
          fail_at.call(Spelling.unknown("rule", rule.name, BuiltInRule::ALL.map(&:name) + declared)) unless declared.include?(rule.name)
          return if rule.arguments.empty?

          fail_at.call("rule #{rule.name.dump} is written in Ruby, and takes no #{rule.arguments.keys.first}=")
        end

        unknown = rule.arguments.keys - built_in.arguments
        fail_at.call(Spelling.unknown("argument", unknown.first, built_in.arguments) + " for rule #{rule.name.dump}") unless unknown.empty?
        missing = built_in.arguments - rule.arguments.keys
        fail_at.call("rule #{rule.name.dump} needs #{missing.first}=NAME") unless missing.empty?
        name = rule.arguments.fetch("companion")
        fail_at.call("companion= takes the name of a companion, as a string") unless name.is_a?(String)
        companion(artifact, name, plugin.manifest.file, rule.line)
      end

      def companion(artifact, name, file, line)
        return if artifact.companion(name)

        raise Mistake.new(Spelling.unknown("companion", name, artifact.companions.map(&:name),
          none: "artifact #{artifact.name.dump} declares none"), file:, line:)
      end

      def check_policy_settings(configuration, plugins)
        configuration.policies.each_with_index do |setting, index|
          fail_at = ->(message) { raise Mistake.new(message, file: configuration.file, line: setting.line) }
          first = configuration.policies.take(index).find { |other| other.name == setting.name }
          fail_at.call("policy #{setting.name.dump} is set twice; the first is on line #{first.line}") if first

          owner_name, _, name = setting.name.partition("/")
          if [owner_name, name].any?(&:empty?)
            fail_at.call("policy #{setting.name.dump} names no plugin; write it as PLUGIN/POLICY")
          end
          owner = plugins.find { |plugin| plugin.name == owner_name }
          fail_at.call(Spelling.unknown("plugin", owner_name, plugins.map(&:name))) unless owner
          policies = (owner.manifest.policies + owner.manifest.step_policies).map(&:name)
          fail_at.call(Spelling.unknown("policy", name, policies, none: "#{owner.name} declares none")) unless policies.include?(name)
        end
      end
    end
  end
end
