# frozen_string_literal: true

require_relative "mistake"

module CrossLint
  module Core
    class CompanionDeclaration < Data.define(:name, :pattern, :line); end

    class ArtifactDeclaration < Data.define(:name, :files, :companions, :line, :key, :optional, :hidden)
      def initialize(key: nil, optional: false, hidden: true, **fields) = super

      def companion(name) = companions.find { |companion| companion.name == name }
    end

    class AppliesTo < Data.define(:artifact, :line); end

    class PolicyRule < Data.define(:name, :arguments, :severity, :line); end

    class Policy < Data.define(:name, :applies_to, :condition, :rules, :line)
      # Only a built-in rule takes arguments, and companion= is its only one.
      def companions = ((condition&.companion_conditions || []).map(&:companion) + rules.filter_map { |rule| rule.arguments["companion"] }).uniq
    end

    class RuleDeclaration < Data.define(:name, :ruby, :line); end

    class HelperDeclaration < Data.define(:name, :command, :file, :line)
      def missing_command(plugin)
        Mistake.new("plugin #{plugin.name} needs #{command} on the PATH for its helper #{name.dump}, and there is none",
          file: plugin.manifest.file, line:)
      end
    end

    class StepPolicy < Data.define(:name, :line); end

    class SettingDeclaration < Data.define(:name, :line); end

    class CommandDeclaration < Data.define(:name, :help, :line); end

    class StepDeclaration < Data.define(:name, :line); end

    class ArtifactsRuby < Data.define(:ruby, :line); end

    class Manifest < Data.define(:file, :artifacts, :policies, :rules, :helpers, :step_policies, :settings, :commands, :steps, :artifacts_ruby)
      def initialize(step_policies: [], settings: [], commands: [], steps: [], artifacts_ruby: nil, **declared) = super
    end
  end
end
