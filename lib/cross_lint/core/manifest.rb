# frozen_string_literal: true

module CrossLint
  module Core
    class CompanionDeclaration < Data.define(:name, :pattern, :line); end

    class ArtifactDeclaration < Data.define(:name, :files, :companions, :line)
      def companion(name) = companions.find { |companion| companion.name == name }
    end

    class AppliesTo < Data.define(:artifact, :line); end

    class PolicyRule < Data.define(:name, :arguments, :severity, :line); end

    class Policy < Data.define(:name, :applies_to, :condition, :rules, :line); end

    class RuleDeclaration < Data.define(:name, :ruby, :line); end

    class HelperDeclaration < Data.define(:name, :command, :file, :line); end

    class Manifest < Data.define(:file, :artifacts, :policies, :rules, :helpers); end
  end
end
