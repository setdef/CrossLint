# frozen_string_literal: true

require_relative "manifest"
require_relative "mistake"
require_relative "fault"
require_relative "path_pattern"

module CrossLint
  # The file of a helper that declares a plugin's artifacts names this
  # class CrossLint::Artifacts, as a Ruby rule's file names CrossLint::Rule,
  # so it is outside Core though core/ defines it.
  class Artifacts
    def declare(_settings)
      raise Core::PluginError, "has no declare method"
    end

    def artifact(name, primary:, pieces: {}, key: nil, optional: false, dotfiles: true)
      raise Core::PluginError, "declared an artifact named #{name.inspect}, which is no string" unless name.is_a?(String)
      raise Core::PluginError, "declared artifact #{name.dump} with pieces #{pieces.inspect}, which is no hash" unless pieces.is_a?(Hash)
      raise Core::PluginError, "declared artifact #{name.dump} with optional: #{optional.inspect}, which is neither true nor false" unless [true, false].include?(optional)

      raise Core::PluginError, "declared artifact #{name.dump} with dotfiles: #{dotfiles.inspect}, which is neither true nor false" unless [true, false].include?(dotfiles)

      declared = pieces.map do |piece, pattern|
        unless piece.is_a?(String)
          raise Core::PluginError, "declared artifact #{name.dump} with a piece named #{piece.inspect}, which is no string"
        end

        Core::PieceDeclaration.new(name: piece, pattern: Core::PathPattern.declared(name, pattern), line: @crosslint_line)
      end
      Core::ArtifactDeclaration.new(name:, primary: Core::PathPattern.declared(name, primary), pieces: declared, line: @crosslint_line,
        key: key && Core::PathPattern.declared(name, key), optional:, dotfiles:)
    end

    def mistake(message, setting) = Core::Mistake.new(message, file: @crosslint_configuration, line: setting.line)
  end
end
