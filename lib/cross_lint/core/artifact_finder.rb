# frozen_string_literal: true

require_relative "artifact"

module CrossLint
  module Core
    class ArtifactFinder
      def initialize(project_files:, root:, files:)
        @project_files = project_files
        @root = root
        @files = files
      end

      def artifacts(plugin) = plugin.manifest.artifacts.to_h { |declaration| [declaration.name, find(plugin, declaration)] }

      private

      def find(plugin, declaration)
        @files.filter_map do |path|
          match = declaration.primary.match(path)
          next unless match
          next if !declaration.dotfiles && match.values.any? { |value| value.split("/").any? { |segment| segment.start_with?(".") } }

          pieces = declaration.pieces.map do |piece|
            piece_path = piece.pattern.expand(match)
            Piece.new(name: piece.name, path: piece_path, exists: @project_files.exist?(@root, piece_path))
          end
          Artifact.new(plugin: plugin.name, role: declaration.name, path:, match:, pieces:, key: declaration.key&.expand(match))
        end
      end
    end
  end
end
