# frozen_string_literal: true

require "kdl"
require_relative "../core"

module CrossLint
  module Adapters
    class KDLDocument
      class Node < Data.define(:name, :line, :arguments, :properties, :children); end

      # A property's value with the one type annotation its document allows there.
      class Typed < Data.define(:type, :value); end

      # The kdl gem's nodes and values carry no line, so this parser hands
      # each name and string to the gem as a String that knows its line.
      class Parser < ::KDL::Parser
        class Word < String
          attr_reader :line, :column

          def initialize(text, line, column)
            super(text)
            @line = line
            @column = column
          end
        end

        # Stands in for the gem's Token: the grammar reads only a name's or
        # string's value, and an error message reads its line and column.
        class WordToken < Data.define(:value, :line, :column); end

        WORDS = %i[IDENT STRING RAWSTRING].freeze

        private

        def next_token
          type, token = super
          return [type, token] unless WORDS.include?(type)

          [type, WordToken.new(value: Word.new(token.value, token.line, token.column), line: token.line, column: token.column)]
        end
      end

      CROSSLINT = "crosslint"

      CROSSLINT_USAGE = %(crosslint min="1.2")

      attr_reader :file, :nodes

      # Read as bytes and taken as UTF-8, so a file reads the same whatever
      # the system's default encoding.
      def self.source(path) = File.binread(path).force_encoding(Encoding::UTF_8)

      def self.load(path, file, typed: {}) = new(source(path), file, typed:)

      # A newer CrossLint may write KDL that this one can't parse, so when
      # it can't, the fewest lines before the mistake that parse into a
      # node are read alone, for a crosslint line there.
      def self.minimum(source, file, typed: {})
        new(source, file, typed:).minimum
      rescue Core::Mistake => mistake
        before = source.lines.take((mistake.line || 1) - 1)
        first = (1..(before.size)).lazy.filter_map { |count| first_nodes(before.take(count).join, file, typed) }.first
        first&.minimum || raise(mistake)
      end

      def self.first_nodes(source, file, typed)
        document = new(source, file, typed:)
        document unless document.nodes.empty?
      rescue Core::Mistake
        nil
      end
      private_class_method :first_nodes

      def initialize(source, file, typed: {})
        @file = file
        @typed = typed
        raise Core::Mistake.new("isn't valid UTF-8", file:) unless source.valid_encoding?

        @nodes = Parser.new(parse_types: false).parse(source).map { |node| convert(node) }
      rescue KDL::Error => error
        raise Core::Mistake.new("isn't valid KDL: #{error.message.sub(/ \(\d+:\d+\)\z/, '')}", file:, line: error.line)
      end

      def mistake(message, node) = Core::Mistake.new(message, file:, line: node.line)

      # Only the line's min= is read, so that a newer CrossLint can add
      # other properties to the line and still have an older one name the
      # version it needs.
      def minimum
        first, again = nodes.select { |node| node.name == CROSSLINT }
        return unless first
        raise mistake("crosslint is set twice; the first is on line #{first.line}", again) if again

        top = nodes.fetch(0)
        unless top.equal?(first)
          raise mistake("crosslint comes after #{top.name} on line #{top.line}; write it as the first line, so that a CrossLint too old " \
            "for the file says so before it reads any other", first)
        end
        raise mistake("crosslint has no min=; write it as #{CROSSLINT_USAGE}", first) unless first.properties.key?("min")

        text = first.properties.fetch("min")
        found = Core::MinimumVersion.parse(text, file:, line: first.line) if text.is_a?(String)
        found || raise(mistake("crosslint min= takes a version of one to three numbers in a string, with no operator or pre-release part, " \
          "such as min=\"1.2\", not #{text.inspect}", first))
      end

      # The minimum, once the rest of its line is checked too.
      def whole_minimum
        found = minimum
        return unless found

        line = nodes.fetch(0)
        arguments(line, CROSSLINT_USAGE, 0)
        properties(line, ["min"])
        children(line, [])
        found
      end

      def arguments(node, usage, count)
        values = node.arguments
        return values if values.size == count

        raise mistake("#{node.name} has #{values.size} #{(values.size == 1) ? 'argument' : 'arguments'}; write it as #{usage}", node)
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

      def convert(node, top: true)
        line = node.name.line
        none = {} #: Hash[String, Array[String]]
        allowed = top ? @typed.fetch(node.name.to_s, none) : none
        [node, *node.arguments].each do |typed|
          refuse(node, typed.type, line) if typed.type
        end
        properties = node.properties.to_h do |key, value|
          next [key, value.value] unless value.type
          refuse(node, value.type, line) unless allowed.fetch(key, []).include?(value.type)

          [key, Typed.new(type: value.type, value: value.value)]
        end
        Node.new(name: node.name, line:, arguments: node.arguments.map(&:value), properties:,
          children: node.map { |child| convert(child, top: false) })
      end

      def refuse(node, type, line)
        raise Core::Mistake.new("#{node.name} has the type annotation (#{type}), which CrossLint doesn't read", file:, line:)
      end
    end
  end
end
