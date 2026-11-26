# frozen_string_literal: true

require_relative "manifest"
require_relative "mistake"
require_relative "fault"
require_relative "path_pattern"

module CrossLint
  # A plugin's artifacts file names this class CrossLint::Artifacts, as
  # its rule files name CrossLint::Rule, so it is outside Core though
  # core/ defines it.
  class Artifacts
    def declare(_settings)
      raise Core::PluginError, "has no declare method"
    end

    def artifact(name, files:, companions: {}, key: nil, optional: false, hidden: true)
      raise Core::PluginError, "declared an artifact named #{name.inspect}, which is no string" unless name.is_a?(String)
      raise Core::PluginError, "declared artifact #{name.dump} with companions #{companions.inspect}, which is no hash" unless companions.is_a?(Hash)
      raise Core::PluginError, "declared artifact #{name.dump} with optional: #{optional.inspect}, which is neither true nor false" unless [true, false].include?(optional)

      raise Core::PluginError, "declared artifact #{name.dump} with hidden: #{hidden.inspect}, which is neither true nor false" unless [true, false].include?(hidden)

      declared = companions.map do |companion, pattern|
        unless companion.is_a?(String)
          raise Core::PluginError, "declared artifact #{name.dump} with a companion named #{companion.inspect}, which is no string"
        end

        Core::CompanionDeclaration.new(name: companion, pattern: pattern(name, pattern), line: @crosslint_line)
      end
      Core::ArtifactDeclaration.new(name:, files: pattern(name, files), companions: declared, line: @crosslint_line,
        key: key && pattern(name, key), optional:, hidden:)
    end

    def mistake(message, setting) = Core::Mistake.new(message, file: @crosslint_configuration, line: setting.line)

    private

    def pattern(name, source)
      raise Core::PluginError, "declared artifact #{name.dump} with the pattern #{source.inspect}, which is no string" unless source.is_a?(String)

      problem = Core::PathPattern.problem(source)
      raise Core::PluginError, "declared artifact #{name.dump} with a #{problem}" if problem

      Core::PathPattern.new(source:)
    end
  end
end
