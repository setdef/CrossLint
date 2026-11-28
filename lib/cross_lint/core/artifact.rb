# frozen_string_literal: true

module CrossLint
  module Core
    class Piece < Data.define(:name, :path, :exists, :line, :readable)
      PRIMARY = "primary"

      def initialize(line: nil, readable: nil, **fields) = super

      def exist? = exists

      def explanation
        return %(piece #{name.dump} at #{[path, line].compact.join(":")} exists) if exists
        return %(piece #{name.dump} at #{path} is missing) if readable.nil?

        %(piece #{name.dump} is missing, since #{path} #{readable ? "has no match of its regex" : "isn't a file"})
      end
    end

    class Artifact < Data.define(:plugin, :role, :path, :match, :pieces, :key, :name, :line)
      def initialize(path:, key: nil, name: path, line: nil, **fields) = super

      def location = line ? "#{path}:#{line}" : path

      def reference = (name == path) ? location : "#{name} at #{location}"

      def explanation
        named = ", named #{name}" unless name == path
        keyed = ", with key #{key}" if key
        "#{plugin}/#{role} #{location}#{named}#{keyed}: #{pieces.empty? ? "no piece but its primary" : pieces.map(&:explanation).join("; ")}"
      end

      def piece(name)
        pieces.find { |piece| piece.name == name } || raise(KeyError, "artifact #{role.dump} has no piece #{name.dump}")
      end
    end

    class Violation < Data.define(:plugin, :policy, :artifact, :role, :message, :severity, :detail, :key, :path, :line, :built_in)
      def initialize(artifact:, key: nil, path: artifact, line: nil, built_in: false, **fields) = super

      def explanation = "#{severity}: #{message}#{detail&.then { |text| ", with detail #{text.dump}" }}"
    end

    class RuleResult < Data.define(:path, :role, :message, :detail); end
  end
end
