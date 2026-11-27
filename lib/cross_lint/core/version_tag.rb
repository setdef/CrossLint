# frozen_string_literal: true

module CrossLint
  module Core
    class VersionTag < Data.define(:text, :version)
      PATTERN = /\Av?(\d+)\.(\d+)\.(\d+)\z/

      def self.parse(text)
        found = PATTERN.match(text)
        new(text:, version: Version.new(numbers: found.captures.map(&:to_i))) if found
      end

      # A tag pairs its text with the version that text names, so only parse makes one.
      private_class_method :new, :[]
      private :with

      def v? = text.start_with?("v")
    end
  end
end
