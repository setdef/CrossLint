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

          hint = "; a name PATTERN tells them apart" unless declaration.name_pattern
          raise Stopped, fault(plugin, declaration, "has two artifacts named #{name}, #{same.first.location} and #{same.fetch(1).location}#{hint}")
        end
        found
      end

      def find(plugin, declaration)
        @files.flat_map do |path|
          match = declaration.primary.match(path)
          next [] unless match
          next [] if !declaration.dotfiles && match.values.any? { |value| value.split("/").any? { |segment| segment.start_with?(".") } }

          primary_matches(plugin, declaration, path, match).map do |values, line|
            pieces = declaration.pieces.map { |piece| piece(plugin, declaration, piece, values) }
            Artifact.new(plugin: plugin.name, role: declaration.name, path:, match: values, pieces:, key: declaration.key&.expand(values),
              name: declaration.name_pattern&.expand(values) || path, line:)
          end
        end
      end

      # What each artifact in the primary piece's file at `path` matched,
      # with the line where its regex matched: one artifact with no line,
      # for a primary with no regex.
      def primary_matches(plugin, declaration, path, match)
        regex = declaration.regex
        return [[match, nil]] unless regex

        text = text(path)
        return [] unless text

        search(plugin, declaration, "its primary", path, regex) { regex.matches(text, match) }.map do |captures, line|
          # An empty value would make a piece's path or regex match what
          # the author never meant, such as `def \b`.
          empty = declaration.used_captures.find { |name| captures[name].to_s.empty? }
          raise Stopped, fault(plugin, declaration, "captured nothing for {#{empty}} at #{path}:#{line}") if empty

          [match.merge(captures.compact), line] #: [Hash[String, String], Integer?]
        end
      end

      # A piece with a regex exists when its file has a match, so a piece
      # whose file can't be read, a folder or a link out of the project,
      # doesn't, and says so.
      def piece(plugin, declaration, piece, match)
        path = piece.pattern.expand(match)
        exists = inside?(path) && @project_files.exist?(@root, path)
        regex = piece.regex
        return Piece.new(name: piece.name, path:, exists:) unless regex

        text = exists ? text(path) : nil
        return Piece.new(name: piece.name, path:, exists: false, readable: false) unless text

        line = search(plugin, declaration, "piece #{piece.name.dump}", path, regex) { regex.first_line(text, match) }
        Piece.new(name: piece.name, path:, exists: !line.nil?, line:, readable: true)
      end

      # A capture's value comes from a file's text, so it can hold `..`.
      def inside?(path) = path.split("/", -1).none? { |segment| segment.empty? || %w[. ..].include?(segment) }

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
