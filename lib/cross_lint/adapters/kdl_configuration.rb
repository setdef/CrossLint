# frozen_string_literal: true

require_relative "kdl_document"

module CrossLint
  module Adapters
    class KDLConfiguration
      FILE = ".config/crosslint.kdl"

      NODES = %w[plugin policy warnings verbosity].freeze

      WARNINGS = %w[all none error].freeze

      VERBOSITIES = %w[normal quiet silent].freeze

      SEVERITIES = %w[error warning].freeze

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

      private

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
