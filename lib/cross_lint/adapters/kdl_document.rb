# frozen_string_literal: true

require "kdl"
require_relative "../core"

module CrossLint
  module Adapters
    class KDLDocument
      class Node < Data.define(:name, :line, :arguments, :properties, :children); end

      # The kdl gem's nodes and values carry no line, so this parser hands
      # each name and string to the gem as a String that knows its line.
      class Parser < ::KDL::Parser
        class Word < String
          attr_reader :line

          def initialize(text, line)
            super(text)
            @line = line
          end
        end

        # The parser reads only these of a name's or string's token.
        class WordToken < Data.define(:value, :line, :column); end

        WORDS = %i[IDENT STRING RAWSTRING].freeze

        private

        def next_token
          type, token = super
          return [type, token] unless WORDS.include?(type)

          [type, WordToken.new(value: Word.new(token.value, token.line), line: token.line, column: token.column)]
        end
      end

      attr_reader :file, :nodes

      # Read as bytes and taken as UTF-8, so a file reads the same whatever
      # the system's default encoding.
      def self.load(path, file) = new(File.binread(path).force_encoding(Encoding::UTF_8), file)

      def initialize(source, file)
        @file = file
        raise Core::Mistake.new("isn't valid UTF-8", file:) unless source.valid_encoding?

        @nodes = Parser.new(parse_types: false).parse(source).map { |node| convert(node) }
      rescue KDL::Error => error
        raise Core::Mistake.new("isn't valid KDL: #{error.message.sub(/ \(\d+:\d+\)\z/, "")}", file:, line: error.line)
      end

      def mistake(message, node) = Core::Mistake.new(message, file:, line: node.line)

      def arguments(node, usage, count)
        values = node.arguments
        return values if values.size == count

        raise mistake("#{node.name} has #{values.size} #{(values.size == 1) ? "argument" : "arguments"}; write it as #{usage}", node)
      end

      def strings(node, usage, count)
        arguments(node, usage, count).each do |value|
          raise mistake("#{node.name} has #{value.inspect} where a string goes; write it as #{usage}", node) unless value.is_a?(String)
        end
      end

      def string(node, usage)
        strings(node, usage, 1)
        node.arguments.first
      end

      def properties(node, allowed)
        unknown = node.properties.keys - allowed
        return node.properties if unknown.empty?

        raise mistake(Core::Spelling.unknown("property", unknown.first, allowed, none: "#{node.name} takes none"), node)
      end

      def children(node, allowed)
        node.children.each do |child|
          next if allowed.include?(child.name)

          raise mistake(Core::Spelling.unknown("node", child.name, allowed, none: "#{node.name} takes no children"), child)
        end
      end

      def string_property(node, name)
        return unless node.properties.key?(name)

        value = node.properties.fetch(name)
        return value if value.is_a?(String)

        raise mistake("#{name}= takes a string, not #{value.inspect}", node)
      end

      def boolean_property(node, name)
        return unless node.properties.key?(name)

        value = node.properties.fetch(name)
        return value if [true, false].include?(value)

        raise mistake("#{name}= takes #true or #false, not #{value.inspect}", node)
      end

      def choice(node, name, value, choices)
        return value.to_sym if choices.include?(value)

        raise mistake(Core::Spelling.unknown(name, value, choices), node)
      end

      def optional_child(node, name)
        found = node.children.select { |child| child.name == name }
        again = found.at(1)
        raise mistake("#{node.name} has #{name} twice; the first is on line #{found.fetch(0).line}", again) if again

        found.first
      end

      def required_child(node, name)
        optional_child(node, name) || raise(mistake("#{node.name} #{node.arguments.first.dump} has no #{name}", node))
      end

      private

      def convert(node)
        line = node.name.line
        [node, *node.arguments, *node.properties.values].each do |typed|
          next unless typed.type

          raise Core::Mistake.new("#{node.name} has the type annotation (#{typed.type}), which CrossLint doesn't read", file:, line:)
        end
        Node.new(name: node.name, line:, arguments: node.arguments.map(&:value),
          properties: node.properties.transform_values(&:value), children: node.map { |child| convert(child) })
      end
    end
  end
end
