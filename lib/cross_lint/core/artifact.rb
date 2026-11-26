# frozen_string_literal: true

module CrossLint
  module Core
    class Companion < Data.define(:name, :path, :exists)
      def exist? = exists
    end

    class Artifact < Data.define(:plugin, :role, :path, :match, :companions)
      def companion(name)
        companions.find { |companion| companion.name == name } || raise(KeyError, "artifact #{role.dump} has no companion #{name.dump}")
      end
    end

    class Violation < Data.define(:plugin, :policy, :artifact, :role, :message, :severity, :detail); end
  end
end
