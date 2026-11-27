# frozen_string_literal: true

require_relative "artifact"
require_relative "fault"
require_relative "regex"

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
        @texts = {} #: Hash[String, String?]
      end

      def artifacts(plugin) = plugin.manifest.artifacts.to_h { |declaration| [declaration.name, named_once(plugin, declaration)] }

      private

      # A violation's identity is its artifact's name, so two artifacts of
      # one role with one name couldn't be told apart in a debt file.
      def named_once(plugin, declaration)
        found = find(plugin, declaration)
        found.group_by(&:name).each do |name, same|
          next if same.one?

          raise Stopped, fault(plugin, declaration, "has two artifacts named #{name}, #{same.first.path} and #{same.fetch(1).path}")
        end
        found
      end

      def find(plugin, declaration)
        @files.filter_map do |path|
          match = declaration.primary.match(path)
          next unless match
          next if !declaration.dotfiles && match.values.any? { |value| value.split("/").any? { |segment| segment.start_with?(".") } }

          pieces = declaration.pieces.map { |piece| piece(plugin, declaration, piece, match) }
          Artifact.new(plugin: plugin.name, role: declaration.name, path:, match:, pieces:, key: declaration.key&.expand(match),
            name: declaration.name_pattern&.expand(match) || path)
        end
      end

      # A piece with a regex exists when its file has a match, so a piece
      # whose file can't be read, a folder or a link out of the project,
      # doesn't, and says so.
      def piece(plugin, declaration, piece, match)
        path = piece.pattern.expand(match)
        exists = @project_files.exist?(@root, path)
        regex = piece.regex
        return Piece.new(name: piece.name, path:, exists:) unless regex

        text = exists ? text(path) : nil
        return Piece.new(name: piece.name, path:, exists: false, readable: false) unless text

        line = search(plugin, declaration, "piece #{piece.name.dump}", path, regex) { regex.first_line(text, match) }
        Piece.new(name: piece.name, path:, exists: !line.nil?, line:, readable: true)
      end

      def text(path)
        @texts.fetch(path) do
          @texts[path] = begin
            @project_files.read(@root, path)
          rescue SystemCallError
            nil
          end
        end
      end

      def search(plugin, declaration, owner, path, regex)
        yield
      rescue Regexp::TimeoutError
        raise Stopped, fault(plugin, declaration, "ran past the #{regex.time_limit}-second time limit searching #{path} with the regex of #{owner}")
      rescue Regex::NotText
        raise Stopped, fault(plugin, declaration, "can't search #{path} with the regex of #{owner}, since it isn't UTF-8")
      end

      def fault(plugin, declaration, message) = Fault.new(plugin: plugin.name, role: declaration.name, artifact: nil, trace: [], message:)
    end
  end
end
