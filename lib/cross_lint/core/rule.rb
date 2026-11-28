# frozen_string_literal: true

require_relative "artifact"
require_relative "fault"

module CrossLint
  # A rule file names this class CrossLint::Rule, as the plugin
  # reference does, so it is outside Core though core/ defines it.
  class Rule
    # Rule files run in CrossLint's process, where Bundler is loaded, and
    # bundler/inline would install gems into CrossLint's folder. Ruby
    # finds the bundler/inline in this folder first, which refuses.
    REFUSED = File.expand_path("refused", File.dirname(__FILE__))
    $LOAD_PATH.unshift(REFUSED)

    class Piece
      attr_reader :name, :path

      def initialize(piece, read)
        @name = piece.name
        @path = piece.path
        @exists = piece.exist?
        @read = read
      end

      def exist? = @exists

      def read = @read.call(path)
    end

    class Artifact
      attr_reader :role, :path, :match, :name, :line, :key, :primary

      def initialize(artifact, read)
        @role = artifact.role
        @path = artifact.path
        @name = artifact.name
        @line = artifact.line
        @key = artifact.key
        @match = artifact.match.freeze
        @primary = Piece.new(Core::Piece.new(name: Core::Piece::PRIMARY, path: artifact.path, exists: true), read)
        @pieces = artifact.pieces.map { |piece| Piece.new(piece, read) }
        @read = read
      end

      def piece(name)
        return primary if name == Core::Piece::PRIMARY

        @pieces.find { |piece| piece.name == name } || raise(KeyError, "artifact #{role.dump} has no piece #{name.dump}")
      end

      def read = @read.call(path)
    end

    def check(_artifact)
      raise Core::PluginError, "has no check method"
    end

    def helper(name) = ->(input) { @crosslint_helpers.call(name, input) }

    def project_files = @crosslint_files

    def read(path)
      raise Errno::ENOENT, path unless crosslint_inside?(path)

      @crosslint_read.call(path)
    end

    def violation(artifact, message, detail: nil)
      raise Core::PluginError, "made a violation of #{artifact.inspect}, which is no artifact it was given" unless artifact.instance_of?(Artifact)
      raise Core::PluginError, "made a violation whose message is #{message.inspect}, which is no string" unless message.instance_of?(String)
      raise Core::PluginError, "made a violation whose detail is #{detail.inspect}, which is no string" unless detail.nil? || detail.instance_of?(String)

      Core::RuleResult.new(path: artifact.path, role: artifact.role, message:, detail:)
    end

    private

    # Whether `path`, followed through . and .., stays in the project's
    # root, which an absolute path doesn't.
    def crosslint_inside?(path)
      return false if path.start_with?("/")

      depth = 0
      path.split("/").all? do |part|
        depth += {"" => 0, "." => 0, ".." => -1}.fetch(part, 1)
        depth >= 0
      end
    end
  end
end
