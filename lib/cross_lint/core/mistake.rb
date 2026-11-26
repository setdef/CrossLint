# frozen_string_literal: true

module CrossLint
  module Core
    class Mistake < StandardError
      attr_reader :file, :line

      def initialize(message, file: nil, line: nil)
        super(message)
        @file = file
        @line = line
      end

      def self.no_configuration(file, start)
        new("no #{file} in #{start} or any folder above it; run crosslint init in the project's root to write one")
      end

      def self.credentials(file, line)
        new("a plugin's URL has a user name or password, which would be in the configuration and on standard error; " \
          "remove it, and give Git the credentials with a Git credential helper (git help credentials)", file:, line:)
      end

      def location = [file, line].compact.join(":")
    end
  end
end
