# frozen_string_literal: true

module CrossLint
  module Core
    class MinimumVersion < Data.define(:text, :version, :file, :line)
      def self.parse(text, file:, line:)
        version = Version.parse(text)
        new(text:, version:, file:, line:) if version
      end

      # A minimum pairs its text with the version that text names, so only parse makes one.
      private_class_method :new, :[]
      private :with

      def met_by?(running) = running >= version

      def requirement = "needs CrossLint #{text} or later"

      def check(running, of: nil)
        return if met_by?(running)

        raise Mistake.new([of, requirement].compact.join(" ") + ", and this is CrossLint #{running}; upgrade CrossLint", file:, line:)
      end
    end
  end
end
