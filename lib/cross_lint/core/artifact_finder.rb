# frozen_string_literal: true

require_relative "artifact"

module CrossLint
  module Core
    class ArtifactFinder
      class Stopped < StandardError
        attr_reader :fault

        def initialize(fault)
          @fault = fault
          super(fault.line)
        end
      end

      def initialize(project_files:, root:, files:)
        @project_files = project_files
        @root = root
        @files = files
      end

      def artifacts(plugin) = plugin.manifest.artifacts.to_h { |declaration| [declaration.name, named_once(plugin, declaration)] }

      private

      # A violation's identity is its artifact's name, so two artifacts of
      # one role with one name couldn't be told apart in a debt file.
      def named_once(plugin, declaration)
        found = find(plugin, declaration)
        found.group_by(&:name).each do |name, same|
          next if same.one?

          raise Stopped, Fault.new(plugin: plugin.name, role: declaration.name, artifact: nil, trace: [],
            message: "has two artifacts named #{name}, #{same.first.path} and #{same.fetch(1).path}")
        end
        found
      end

      def find(plugin, declaration)
        @files.filter_map do |path|
          match = declaration.primary.match(path)
          next unless match
          next if !declaration.dotfiles && match.values.any? { |value| value.split("/").any? { |segment| segment.start_with?(".") } }

          pieces = declaration.pieces.map do |piece|
            piece_path = piece.pattern.expand(match)
            Piece.new(name: piece.name, path: piece_path, exists: @project_files.exist?(@root, piece_path))
          end
          Artifact.new(plugin: plugin.name, role: declaration.name, path:, match:, pieces:, key: declaration.key&.expand(match),
            name: declaration.name_pattern&.expand(match) || path)
        end
      end
    end
  end
end
