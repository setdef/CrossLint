# frozen_string_literal: true

require_relative "mistake"

module CrossLint
  module Core
    class PieceDeclaration < Data.define(:name, :pattern, :line, :regex)
      def initialize(regex: nil, **declared) = super
    end

    class ArtifactDeclaration < Data.define(:name, :primary, :pieces, :line, :key, :optional, :dotfiles, :name_pattern, :regex)
      def initialize(key: nil, optional: false, dotfiles: true, name_pattern: nil, regex: nil, **fields) = super

      def placeholders = primary.placeholders + captures

      def captures = regex&.captures.to_a

      # Why a piece's pattern, a regex, or the name can't use `placeholder`.
      def lacking(placeholder)
        return "uses {#{placeholder}}, which the primary pattern #{primary.source.dump} doesn't have" unless regex

        "uses {#{placeholder}}, which neither the primary pattern #{primary.source.dump} has nor its regex captures"
      end

      # The captures of the primary's regex that the name, a piece's path,
      # or a piece's regex uses.
      def used_captures
        used = ([name_pattern] + pieces.map(&:pattern)).compact.flat_map(&:placeholders) + pieces.filter_map(&:regex).flat_map(&:placeholders)
        captures & used
      end

      def piece(name) = pieces.find { |piece| piece.name == name }
    end

    class AppliesTo < Data.define(:artifact, :line); end

    class PolicyRule < Data.define(:name, :arguments, :severity, :line); end

    class Policy < Data.define(:name, :applies_to, :condition, :rules, :line)
      # Only a built-in rule takes arguments, and piece= is its only one.
      def pieces = ((condition&.piece_conditions || []).map(&:piece) + rules.filter_map { |rule| rule.arguments["piece"] }).uniq
    end

    # A rule a plugin declares, which a helper runs: `ruby` is the file of
    # a helper on CrossLint's Ruby, `helper` the name of any
    # other.
    class RuleDeclaration < Data.define(:name, :ruby, :helper, :line)
      def initialize(ruby: nil, helper: nil, **declared) = super
    end

    class HelperDeclaration < Data.define(:name, :command, :file, :line, :arguments)
      def initialize(arguments: [], **declared) = super

      def missing_command(plugin)
        Mistake.new("plugin #{plugin.name} needs #{command} on the PATH for its helper #{name.dump}, and there is none",
          file: plugin.manifest.file, line:)
      end
    end

    class StepPolicy < Data.define(:name, :line); end

    class SettingDeclaration < Data.define(:name, :line); end

    # A flag a command declares, in the usage spec's flag syntax: it has
    # no long help, choices, or default unless given.
    class CommandFlag < Data.define(:short, :long, :value, :help, :line, :long_help, :choices, :default)
      def initialize(long_help: nil, choices: nil, default: nil, **given) = super

      def usage = value ? "--#{long} <#{value}>" : "--#{long}"

      # Every spelling the flag takes, as written on a command line.
      def names = ["--#{long}", ("-#{short}" if short)].compact
    end

    class CommandDeclaration < Data.define(:name, :help, :line, :flags)
      def initialize(flags: [], **declared) = super
    end

    class StepDeclaration < Data.define(:name, :line); end

    class ArtifactsRuby < Data.define(:ruby, :line); end

    class ArtifactsHelper < Data.define(:helper, :line); end

    class Manifest < Data.define(:file, :artifacts, :policies, :rules, :helpers, :step_policies, :settings, :commands, :steps, :artifacts_ruby,
      :artifacts_helper)
      def initialize(step_policies: [], settings: [], commands: [], steps: [], artifacts_ruby: nil, artifacts_helper: nil, **declared) = super
    end
  end
end
