# frozen_string_literal: true

require_relative "fault"

module CrossLint
  module Core
    class PathPattern < Data.define(:source, :captures)
      PLACEHOLDERS = %w[path name].freeze

      PLACEHOLDER = /\{([^{}]*)\}/

      MATCHES = { "path" => "[^/]+(?:/[^/]+)*", "name" => "[^/]+" }.freeze

      class Invalid < ArgumentError; end

      def self.problem(source, known = PLACEHOLDERS)
        return "path pattern #{source.dump} is empty" if source.empty?
        return "path pattern #{source.dump} has \\; write / between folders on every system" if source.include?("\\")

        unknown = source.scan(PLACEHOLDER).flatten.find { |placeholder| !known.include?(placeholder) }
        if unknown
          return "path pattern #{source.dump} has #{Spelling.unknown('placeholder', "{#{unknown}}", known.map { |each| "{#{each}}" })}"
        end

        brace = source.gsub(PLACEHOLDER, "")[/[{}]/]
        "path pattern #{source.dump} has a #{brace} that pairs with nothing" if brace
      end

      # Lives here, not in CrossLint::Artifacts, so no name a plugin's
      # subclass defines can replace it.
      def self.declared(artifact, source)
        raise PluginError, "declared artifact #{artifact.dump} with the pattern #{source.inspect}, which is no string" unless source.is_a?(String)

        problem = problem(source)
        raise PluginError, "declared artifact #{artifact.dump} with a #{problem}" if problem

        new(source:)
      end

      def initialize(source:, captures: [])
        problem = PathPattern.problem(source, PLACEHOLDERS + captures)
        raise Invalid, problem if problem

        super
      end

      def placeholders = source.scan(PLACEHOLDER).flatten.uniq

      # No group in regexp is optional, so every value is a string.
      def match(path) = regexp.match(path)&.named_captures #: Hash[String, String]?

      def expand(values) = source.gsub(PLACEHOLDER) { |placeholder| values.fetch(placeholder.delete_prefix("{").delete_suffix("}")) }

      private

      # A placeholder that appears twice matches the same text both times.
      def regexp
        seen = [] #: Array[String]
        body = source.gsub(/#{PLACEHOLDER}|[^{]+/o) do |part|
          name = Regexp.last_match(1)
          next Regexp.escape(part) unless name

          pattern = seen.include?(name) ? "\\k<#{name}>" : "(?<#{name}>#{MATCHES.fetch(name)})"
          seen << name
          pattern
        end
        Regexp.new("\\A#{body}\\z")
      end
    end
  end
end
