# frozen_string_literal: true

module CrossLint
  module Core
    class Piece < Data.define(:name, :path, :exists, :line, :readable)
      def initialize(line: nil, readable: nil, **fields) = super

      def exist? = exists
    end

    class Artifact < Data.define(:plugin, :role, :path, :match, :pieces, :key, :name, :line)
      def initialize(path:, key: nil, name: path, line: nil, **fields) = super

      def location = line ? "#{path}:#{line}" : path

      def piece(name)
        pieces.find { |piece| piece.name == name } || raise(KeyError, "artifact #{role.dump} has no piece #{name.dump}")
      end
    end

    class Violation < Data.define(:plugin, :policy, :artifact, :role, :message, :severity, :detail, :key, :path, :line)
      def initialize(artifact:, key: nil, path: artifact, line: nil, **fields) = super
    end

    class RuleResult < Data.define(:path, :role, :message, :detail); end
  end
end
