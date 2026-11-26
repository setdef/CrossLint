# frozen_string_literal: true

require_relative "kdl_document"
require_relative "replace_file"

module CrossLint
  module Adapters
    class KDLConfiguration
      FILE = ".config/crosslint/config.kdl"

      NODES = %w[plugin policy warnings verbosity].freeze

      WARNINGS = %w[all none error].freeze

      VERBOSITIES = %w[normal quiet silent].freeze

      SEVERITIES = %w[error warning].freeze

      # Where a line ends, as KDL says.
      NEWLINE = /\r\n|[\n\r\u0085\u000B\u000C\u2028\u2029]/

      # A string at the position it is matched from, plain or raw: its
      # text is the second group.
      STRING = /\G(#*)"(.*?)"\1/m

      def file = FILE

      def find_root(start)
        raise Core::Mistake, "no folder #{start}" unless File.directory?(start)

        folder = File.expand_path(start)
        until File.file?(File.join(folder, FILE))
          parent = File.dirname(folder)
          return if parent == folder

          folder = parent
        end
        folder
      end

      def read(root)
        path = File.join(root, FILE)
        raise Core::Mistake.new("doesn't exist", file: FILE) unless File.file?(path)

        document = KDLDocument.load(path, FILE)
        document.nodes.each do |node|
          next if NODES.include?(node.name)

          raise document.mistake(Core::Spelling.unknown("node", node.name, NODES), node)
        end
        Core::Configuration.new(file: FILE, plugins: nodes(document, "plugin").map { |node| plugin(document, node) },
          policies: nodes(document, "policy").map { |node| policy(document, node) },
          warnings: mode(document, "warnings", WARNINGS), verbosity: mode(document, "verbosity", VERBOSITIES))
      end

      def set_refs(root, refs)
        path = File.join(root, FILE)
        raise Core::Mistake.new("doesn't exist", file: FILE) unless File.file?(path)

        source = File.binread(path).force_encoding(Encoding::UTF_8)
        document = KDLDocument.new(source, FILE)
        plugins = document.nodes.select { |node| node.name == "plugin" && refs.key?(node.arguments.first) }
        # Last first, so that a change doesn't move the ones before it.
        plugins.map { |node| change(source, node, refs.fetch(node.arguments.first)) }.reverse_each do |at, size, text|
          source[at, size] = text
        end
        ReplaceFile.call(path, source) unless plugins.empty?
      rescue Errno::EACCES
        raise Core::Mistake.new("couldn't be replaced, since permission was denied; close any program that has it open, and run again", file: FILE)
      end

      private

      # Where the text of the ref of `node` is in `source`, how long it is,
      # and `ref` to put there. Only the text between the quotes changes.
      def change(source, node, ref)
        word = node.properties["ref"]
        unless word.respond_to?(:column)
          raise Core::Mistake.new("plugin #{node.arguments.first.dump} has no ref= with a string to rewrite", file: FILE, line: node.line)
        end

        position = 0
        (word.line - 1).times do
          ending = source.match(NEWLINE, position) #: MatchData
          position = ending.end(0)
        end
        found = STRING.match(source, position + word.column - 1)
        # A string with an escape, or on several lines, has text other than its
        # value, and isn't rewritten.
        unless found && found[2] == word
          raise Core::Mistake.new("can't rewrite ref=#{word.dump}, which isn't written as plain text between quotes on one line; " \
            "write it as ref=#{word.dump}", file: FILE, line: word.line)
        end

        start = found.begin(2) #: Integer
        [start, word.size, ref]
      end

      def nodes(document, name) = document.nodes.select { |node| node.name == name }

      def plugin(document, node)
        name = document.string(node, "plugin NAME { ... }")
        document.properties(node, ["ref"])
        Core::ListedPlugin.new(name:, ref: document.string_property(node, "ref"),
          settings: node.children.map { |child| setting(child) }, line: node.line)
      end

      def setting(node)
        Core::Setting.new(name: node.name, arguments: node.arguments, properties: node.properties,
          children: node.children.map { |child| setting(child) }, line: node.line)
      end

      def policy(document, node)
        name = document.string(node, "policy PLUGIN/POLICY enabled=#false")
        document.properties(node, %w[enabled severity])
        document.children(node, [])
        enabled = document.boolean_property(node, "enabled")
        severity = document.string_property(node, "severity")
        if enabled.nil? && severity.nil?
          raise document.mistake("policy #{name.dump} changes nothing; give it enabled=#false or severity=", node)
        end

        Core::PolicySetting.new(name:, enabled:, severity: severity && document.choice(node, "severity", severity, SEVERITIES),
          line: node.line)
      end

      def mode(document, name, choices)
        found = nodes(document, name)
        again = found.at(1)
        raise document.mistake("#{name} is set twice; the first is on line #{found.fetch(0).line}", again) if again

        node = found.first
        return unless node

        value = document.string(node, "#{name} MODE")
        document.properties(node, [])
        document.children(node, [])
        document.choice(node, name, value, choices)
      end
    end
  end
end
