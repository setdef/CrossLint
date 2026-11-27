# frozen_string_literal: true

module CrossLint
  module Core
    class Piece < Data.define(:name, :path, :exists)
      def exist? = exists
    end

    class Artifact < Data.define(:plugin, :role, :path, :match, :pieces, :key, :name)
      def initialize(path:, key: nil, name: path, **fields) = super

      def piece(name)
        pieces.find { |piece| piece.name == name } || raise(KeyError, "artifact #{role.dump} has no piece #{name.dump}")
      end
    end

    class Violation < Data.define(:plugin, :policy, :artifact, :role, :message, :severity, :detail, :key, :path)
      def initialize(artifact:, key: nil, path: artifact, **fields) = super
    end

    class RuleResult < Data.define(:path, :role, :message, :detail); end
  end
end
