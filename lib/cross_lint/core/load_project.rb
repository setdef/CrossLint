# frozen_string_literal: true

require_relative "artifacts"
require_relative "ruby_rule"

module CrossLint
  module Core
    class LoadProject
      DECLARER = :Artifacts

      # What a helper that declares artifacts answers when its answer is
      # neither, and when an artifact in it isn't one.
      ANSWER = %(answered neither {"artifacts": [...]} nor {"mistake": {"message": TEXT, "line": LINE}})
      ARTIFACT = %(declared an artifact that isn't {"name": NAME, "primary": PATTERN, ...})

      # The fields an artifact a helper declares can have.
      FIELDS = %w[name primary pieces key optional dotfiles].freeze

      # What a command of a plugin is called: lowercase letters, digits, and -.
      COMMAND = /\A[a-z0-9-]+\z/

      # The names CrossLint keeps for commands it may add, as well as the
      # names of the commands it has: no plugin that adds commands has one,
      # so adding the command breaks no plugin.
      RESERVED = %w[version completion config plugin plugins list cache doctor explain fix self].freeze

      def initialize(configuration:, manifests:, plugin_ruby:, shared_plugins:, helpers:, built_in: {}, steps: {}, reserved: [], reserved_flags: [])
        @configuration = configuration
        @manifests = manifests
        @plugin_ruby = plugin_ruby
        @helpers = helpers
        @shared_plugins = shared_plugins
        @built_in = built_in
        @steps = steps
        @reserved = reserved
        @reserved_flags = reserved_flags
      end

      # The plugins whose manifests are on disk, for a person who asks what
      # commands the project's plugins add: nothing is fetched, a shared
      # plugin not fetched yet is only listed, and no helper runs.
      def listed(start)
        root = @configuration.find_root(start)
        raise Mistake.no_configuration(@configuration.file, start) unless root

        configuration = @configuration.read(root)
        loaded = [] #: Array[Plugin]
        unfetched = [] #: Array[ListedPlugin]
        configuration.plugins.each_index do |index|
          found = plugin(root, configuration, index, loaded, fetching: false)
          found ? loaded << found : unfetched << configuration.plugins.fetch(index)
        end
        # A command that no run could take is not listed.
        loaded.each do |found|
          once(found.manifest.commands, "command", found.manifest.file)
          check_commands(found)
        end
        PluginListing.new(file: configuration.file, plugins: loaded, unfetched:)
      end

      def call(start)
        root = @configuration.find_root(start)
        raise Mistake.no_configuration(@configuration.file, start) unless root

        configuration = @configuration.read(root)
        raise Mistake.new("lists no plugin, so no check would run; list one with plugin NAME", file: configuration.file) if configuration.plugins.empty?

        SharedPlugin.refuse_credentials(configuration)
        plugins = configuration.plugins.each_with_index.with_object([]) do |(listing, index), loaded|
          loaded << plugin(root, configuration, index, loaded)
        end
        # Every plugin's artifacts before any policy is checked, since a
        # policy can apply to another plugin's.
        plugins = plugins.map do |plugin|
          check_setting_names(plugin, configuration.file)
          declare(root, plugin, configuration.file)
        end
        plugins.each do |plugin|
          check_manifest(plugin, plugins)
          check_settings(plugin, configuration.file)
        end
        check_policy_settings(configuration, plugins)
        Project.new(root:, configuration:, plugins:)
      end

      # A setting as the helper that declares a plugin's artifacts is sent it.
      def self.described(setting)
        {"name" => setting.name, "arguments" => setting.arguments, "properties" => setting.properties,
         "children" => setting.children.map { |child| described(child) }, "line" => setting.line}
      end

      private

      def plugin(root, configuration, index, loaded, fetching: true)
        listing = configuration.plugins.fetch(index)
        fail_at = ->(message, line = listing.line) { raise Mistake.new(message, file: configuration.file, line:) }
        first = configuration.plugins.take(index).find { |other| other.name == listing.name && other.path == listing.path }
        fail_at.call("plugin #{listing.shown.dump} is listed twice; the first is on line #{first.line}") if first

        placed = place(root, listing, fail_at, fetching)
        return unless placed

        base, folder = placed
        manifest = @manifests.read(base, folder) || fail_at.call("no #{@manifests.file} in #{where(listing, folder)}")
        name = File.basename(File.expand_path(folder, base))
        if (listing.kind == :local || listing.shared?(@shared_plugins)) && @built_in.key?(name)
          fail_at.call("plugin #{listing.shown.dump} is named #{name.dump}, the name of a built-in plugin, which no local or shared plugin " \
            "can have; rename the plugin's folder, since a plugin's name is its folder's name")
        end
        same = loaded.find { |plugin| plugin.name == name }
        if same
          fail_at.call("plugins #{same.listing.shown.dump} and #{listing.shown.dump} are both named #{name.dump}, " \
            "since a plugin's name is its folder's name")
        end
        Plugin.new(name:, folder: File.expand_path(folder, base), listing:, manifest:)
      end

      def where(listing, folder)
        if listing.shared?(@shared_plugins)
          return listing.path ? "folder #{listing.path.dump} of #{listing.name} at #{listing.ref}" : "the root of #{listing.name} at #{listing.ref}"
        end

        folder.empty? ? "the project's root" : folder
      end

      def place(root, listing, fail_at, fetching)
        return fetch(listing, fail_at, fetching) if listing.shared?(@shared_plugins)

        fail_at.call("only a shared plugin takes ref=") if listing.ref
        fail_at.call("only a shared plugin takes path=") if listing.path
        return [root, clean(listing.name)] if listing.kind == :local

        folder = @built_in.fetch(listing.name) do
          fail_at.call(Spelling.unknown("built-in plugin", listing.name, @built_in.keys, none: "this CrossLint has none"))
        end
        [File.dirname(folder), File.basename(folder)]
      end

      # The shared plugin's folder in the user's cache is the base, so that
      # the plugin's name is the name of that folder, as for any plugin.
      def fetch(listing, fail_at, fetching)
        url = listing.name
        ref = listing.ref || fail_at.call("shared plugin #{url.dump} needs ref=, a tag or a full commit SHA")
        path = listing.path
        if path && (problem = SharedPlugin.path_problem(path))
          fail_at.call("shared plugin #{url.dump} at #{ref} has a path= that #{problem}: #{path.dump}")
        end
        SharedPlugin.plugin_name(url) || fail_at.call("can't name a plugin from #{url.dump}, whose last path segment has other characters " \
          "than letters, digits, and . _ -; a plugin's name is its repository's name")

        folder = begin
          fetching ? @shared_plugins.fetch(url, ref) : @shared_plugins.cached(url, ref)
        rescue FetchError => error
          fail_at.call("couldn't fetch shared plugin #{listing.plugin_name} from #{url} at #{ref}: " + error.message)
        end
        [folder, listing.path || ""] if folder
      end

      # A name that starts with / is relative to the root too, as the
      # configuration reference says of every local plugin.
      def clean(name)
        cleaned = Pathname.new(name.sub(%r{\A/+}, "")).cleanpath.to_s
        (cleaned == ".") ? "" : cleaned
      end

      # The plugin with the artifacts its helper declares from its settings
      # added to its manifest's. Whatever a Ruby helper raises but a mistake
      # stops CrossLint the same way, since no check can run without the
      # plugin's artifacts.
      def declare(root, plugin, file)
        ruby = plugin.manifest.artifacts_ruby
        helper = plugin.manifest.artifacts_helper
        return declare_in_ruby(plugin, ruby, file) if ruby
        return declare_by_helper(root, plugin, helper, file) if helper

        plugin
      end

      # The plugin with the artifacts its helper declares from its settings
      # added to its manifest's, the helper started for this alone and
      # stopped after it answers.
      def declare_by_helper(root, plugin, declaration, file)
        manifest = plugin.manifest
        name = declaration.helper
        unless manifest.helpers.any? { |helper| helper.name == name }
          raise Mistake.new("artifacts are declared by helper #{name.dump}, which plugin #{plugin.name} doesn't declare", file: manifest.file, line: declaration.line)
        end

        running = @helpers.start(root, [plugin])
        answer = begin
          running.call(plugin, name, {"settings" => plugin.listing.settings.map { |setting| LoadProject.described(setting) }})
        ensure
          running.stop
        end
        plugin.with(manifest: manifest.with(artifacts: manifest.artifacts + declared(answer, name, file, declaration.line)))
      rescue PluginError => error
        raise Mistake.new("fault in plugin #{plugin.name}: #{error.message}", file: plugin.manifest.file, line: declaration.line)
      end

      # The artifacts a helper's answer declares, or the mistake it found
      # in a setting, raised.
      def declared(answer, name, file, line)
        raise PluginError, "helper #{name.dump} failed: #{answer.fetch("error")}" if answer.is_a?(Hash) && answer["error"].is_a?(String)

        mistake = answer["mistake"] if answer.is_a?(Hash)
        if mistake.is_a?(Hash) && mistake["message"].is_a?(String) && mistake["line"].is_a?(Integer)
          raise Mistake.new(mistake.fetch("message"), file:, line: mistake.fetch("line"))
        end

        found = answer["artifacts"] if answer.is_a?(Hash)
        raise PluginError, "helper #{name.dump} #{ANSWER}" unless found.is_a?(Array)

        declarer = Artifacts.allocate
        declarer.instance_variable_set(:@crosslint_line, line)
        found.map do |artifact|
          raise PluginError, "helper #{name.dump} #{ARTIFACT}" unless artifact.is_a?(Hash) && (artifact.keys - FIELDS).empty?

          none = {} #: Hash[String, untyped]
          begin
            declarer.artifact(artifact["name"], primary: artifact["primary"], pieces: artifact.fetch("pieces", none), key: artifact["key"],
              optional: artifact.fetch("optional", false), dotfiles: artifact.fetch("dotfiles", true))
          rescue PluginError => error
            raise PluginError, "helper #{name.dump} #{error.message}"
          end
        end
      end

      def declare_in_ruby(plugin, ruby, file)
        manifest = plugin.manifest
        namespace = Module.new
        @plugin_ruby.load(plugin, ruby.ruby, ruby.line, namespace)
        found = namespace.const_get(DECLARER) if namespace.const_defined?(DECLARER, false)
        raise PluginError, "defines no class Artifacts" unless found.instance_of?(Class)
        raise PluginError, "has a class Artifacts that doesn't inherit from CrossLint::Artifacts" unless found < Artifacts

        declarer = found.allocate
        declarer.instance_variable_set(:@crosslint_configuration, file)
        declarer.instance_variable_set(:@crosslint_line, ruby.line)
        declarer.__send__(:initialize)
        declared = declarer.declare(plugin.listing.settings)
        unless declared.instance_of?(Array) && declared.all?(ArtifactDeclaration)
          raise PluginError, "returned #{declared.class} from declare, where declare returns an array of artifacts"
        end

        plugin.with(manifest: manifest.with(artifacts: manifest.artifacts + declared))
      rescue Mistake
        raise
      rescue *RubyRule::FAULTS => error
        raise Mistake.new("fault in plugin #{plugin.name}: #{ruby.ruby} #{Fault.describe(error, plugin.folder)}", file: plugin.manifest.file, line: ruby.line)
      end

      def check_manifest(plugin, plugins)
        manifest = plugin.manifest
        once(manifest.artifacts, "artifact", manifest.file)
        manifest.artifacts.each { |artifact| check_artifact(artifact, manifest.file) }
        once(manifest.rules, "rule", manifest.file)
        manifest.rules.each do |rule|
          if BuiltInRule.named(rule.name)
            raise Mistake.new("rule #{rule.name.dump} has the name of a built-in rule; name it something else",
              file: manifest.file, line: rule.line)
          end
          next if rule.helper.nil? || manifest.helpers.any? { |helper| helper.name == rule.helper }

          raise Mistake.new("rule #{rule.name.dump} is run by helper #{rule.helper.dump}, which plugin #{plugin.name} doesn't declare",
            file: manifest.file, line: rule.line)
        end
        once(manifest.helpers, "helper", manifest.file)
        once(manifest.policies + manifest.step_policies, "policy", manifest.file)
        manifest.policies.each { |policy| check_policy(plugin, policy, plugins) }
        %i[settings commands steps].each { |kind| once(manifest.public_send(kind), kind.to_s.chomp("s"), manifest.file) }
        check_steps(manifest)
        check_commands(plugin)
      end

      # crosslint PLUGIN COMMAND must never be read two ways, so a command
      # can't be named as CrossLint's words are, nor a plugin that adds
      # commands as CrossLint's commands are; and a command with no step
      # to tell its name to would do nothing.
      def check_commands(plugin)
        manifest = plugin.manifest
        first = manifest.commands.first
        return unless first

        manifest.commands.each do |command|
          check_command(command, manifest.file)
          check_flags(plugin, command)
        end
        if (@reserved + RESERVED).include?(plugin.name)
          raise Mistake.new("plugin #{plugin.name} in #{plugin.folder} adds commands, and #{plugin.name} is reserved, as a command of CrossLint " \
            "or a name CrossLint keeps for one; rename the plugin's folder, since a plugin's name is its folder's name",
            file: manifest.file, line: first.line)
        end
        return unless manifest.steps.empty?

        raise Mistake.new("command #{first.name.dump} has no step to do its work, and the plugin declares none; declare one with step NAME",
          file: manifest.file, line: first.line)
      end

      def check_command(command, file)
        unless command.name.match?(COMMAND)
          raise Mistake.new("command #{command.name.dump} has other characters than lowercase letters, digits, and -", file:, line: command.line)
        end
        return unless command.name == "help"

        raise Mistake.new("command \"help\" is the name of CrossLint's command help, which a plugin can't take; name the command something else",
          file:, line: command.line)
      end

      # A flag of a command takes no name a global flag has, --help's, or
      # another flag of the command's, so a name always means one thing.
      def check_flags(plugin, command)
        taken = {} #: Hash[String, String]
        @reserved_flags.each { |name| taken[name] = "a global flag of CrossLint" }
        taken["-h"] = taken["--help"] = "the flag that prints help"
        command.flags.each do |flag|
          flag.names.each do |name|
            next unless taken.key?(name)

            raise Mistake.new("plugin #{plugin.name} in #{plugin.folder} gives command #{command.name.dump} the flag #{name}, which is " \
              "#{taken.fetch(name)}; name the flag another way", file: plugin.manifest.file, line: flag.line)
          end
          flag.names.each { |name| taken[name] = "the name of another flag of the command" }
        end
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
      def check_setting_names(plugin, file)
        declared = plugin.manifest.settings.map(&:name)
        plugin.listing.settings.each do |setting|
          next if declared.include?(setting.name)

          raise Mistake.new(Spelling.unknown("setting", setting.name, declared, none: "plugin #{plugin.name} takes none"), file:,
            line: setting.line)
        end
      end

      def check_settings(plugin, file)
        plugin.manifest.steps.each { |declaration| @steps.fetch(declaration.name).check_settings(plugin.listing.settings, file) }
      end

      def check_artifact(artifact, file)
        once(artifact.pieces, "piece", file)
        artifact.pieces.each do |piece|
          extra = piece.pattern.placeholders - artifact.placeholders
          next if extra.empty?

          raise Mistake.new("piece #{piece.name.dump} #{artifact.lacking(extra.first)}", file:, line: piece.line)
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
        applies_to = policy.applies_to
        unless applies_to
          policy.rules.each { |rule| check_rule(plugin, nil, rule) }
          # Artifacts declared in Ruby depend on the settings, which can
          # leave a policy nothing to apply to.
          return unless plugin.targets(policy).empty? && !plugin.manifest.artifacts_ruby

          named = policy.pieces.map(&:dump)
          having = named.empty? ? "declares no artifact" : "has no artifact with #{Spelling.list(named, "and")}, the pieces it names"
          raise Mistake.new("policy #{policy.name.dump} has no applies-to, and plugin #{plugin.name} #{having}", file:, line: policy.line)
        end

        artifact = target(plugin, applies_to, plugins)
        policy.condition&.piece_conditions&.each { |exists| piece(artifact, exists.piece, file, exists.line) }
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

          fail_at.call("rule #{rule.name.dump} is run by a helper, and takes no #{rule.arguments.keys.first}=")
        end

        unknown = rule.arguments.keys - built_in.arguments
        fail_at.call(Spelling.unknown("argument", unknown.first, built_in.arguments) + " for rule #{rule.name.dump}") unless unknown.empty?
        missing = built_in.arguments - rule.arguments.keys
        fail_at.call("rule #{rule.name.dump} needs #{missing.first}=NAME") unless missing.empty?
        name = rule.arguments.fetch("piece")
        fail_at.call("piece= takes the name of a piece, as a string") unless name.is_a?(String)
        piece(artifact, name, plugin.manifest.file, rule.line) if artifact
      end

      def piece(artifact, name, file, line)
        return if artifact.piece(name)

        raise Mistake.new(Spelling.unknown("piece", name, artifact.pieces.map(&:name),
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
