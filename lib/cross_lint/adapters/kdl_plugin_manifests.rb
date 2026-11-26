# frozen_string_literal: true

require_relative "kdl_document"

module CrossLint
  module Adapters
    class KDLPluginManifests
      FILE = "plugin.kdl"

      NODES = %w[artifact artifacts policy rule helper setting command step].freeze

      CONDITIONS = %w[companion-exists not all any].freeze

      SEVERITIES = %w[error warning].freeze

      FLAG_MISTAKE = "flag isn't a node CrossLint reads: a plugin adds commands under its own name, as in command NAME help=TEXT, " \
        "and no flag to crosslint check"

      def file = FILE

      def read(root, folder)
        path = File.join(root, folder, FILE)
        return unless File.file?(path)

        document = KDLDocument.load(path, folder.empty? ? FILE : "#{folder}/#{FILE}")
        document.nodes.each do |node|
          next if NODES.include?(node.name)
          raise document.mistake(FLAG_MISTAKE, node) if node.name == "flag"

          raise document.mistake(Core::Spelling.unknown("node", node.name, NODES), node)
        end
        blockless, policies = document.nodes.select { |node| node.name == "policy" }.partition { |node| node.children.empty? }
        Core::Manifest.new(file: document.file, artifacts: nodes(document, "artifact") { |node| artifact(document, node) },
          policies: policies.map { |node| policy(document, node) },
          rules: nodes(document, "rule") { |node| rule(document, node) },
          helpers: nodes(document, "helper") { |node| helper(document, node) },
          step_policies: blockless.map { |node| Core::StepPolicy.new(name: named(document, node, "policy NAME { ... }"), line: node.line) },
          settings: named_nodes(document, "setting") { |name, line| Core::SettingDeclaration.new(name:, line:) },
          commands: nodes(document, "command") { |node| command(document, node) },
          steps: named_nodes(document, "step") { |name, line| Core::StepDeclaration.new(name:, line:) },
          artifacts_ruby: artifacts_ruby(document))
      end

      private

      def nodes(document, name, &read) = document.nodes.select { |node| node.name == name }.map(&read)

      def named_nodes(document, name)
        nodes(document, name) { |node| yield named(document, node, "#{name} NAME"), node.line }
      end

      # The name of a node that takes nothing else.
      def named(document, node, usage)
        name = document.string(node, usage)
        no_more(document, node)
        name
      end

      def artifact(document, node)
        name = document.string(node, "artifact NAME { ... }")
        document.properties(node, [])
        document.children(node, %w[files companion])
        files = document.required_child(node, "files")
        files_pattern = pattern(document, files, document.string(files, "files PATTERN"))
        no_more(document, files)
        companions = node.children.select { |child| child.name == "companion" }.map do |child|
          words = document.strings(child, "companion NAME PATTERN", 2)
          no_more(document, child)
          Core::CompanionDeclaration.new(name: words.first, pattern: pattern(document, child, words.last), line: child.line)
        end
        Core::ArtifactDeclaration.new(name:, files: files_pattern, companions:, line: node.line)
      end

      def pattern(document, node, source)
        problem = Core::PathPattern.problem(source)
        raise document.mistake(problem, node) if problem

        Core::PathPattern.new(source:)
      end

      def policy(document, node)
        name = document.string(node, "policy NAME { ... }")
        document.properties(node, [])
        document.children(node, %w[applies-to when rule])
        applies_to = document.optional_child(node, "applies-to")&.then do |child|
          artifact = document.string(child, "applies-to ARTIFACT")
          no_more(document, child)
          Core::AppliesTo.new(artifact:, line: child.line)
        end
        condition = document.optional_child(node, "when")
        rules = node.children.select { |child| child.name == "rule" }
        raise document.mistake("policy #{name.dump} has no rule", node) if rules.empty?

        Core::Policy.new(name:, applies_to:,
          condition: condition && when_condition(document, condition), rules: rules.map { |rule| policy_rule(document, rule) },
          line: node.line)
      end

      def when_condition(document, node)
        kind, *rest = node.arguments
        raise document.mistake("when has no condition; write it as when companion-exists COMPANION", node) unless kind

        condition(document, KDLDocument::Node.new(name: kind.to_s, line: node.line, arguments: rest,
          properties: node.properties, children: node.children))
      end

      def condition(document, node)
        document.properties(node, [])
        case node.name
        when "companion-exists"
          companion = document.string(node, "companion-exists COMPANION")
          document.children(node, [])
          Core::Condition::CompanionExists.new(companion:, line: node.line)
        when "not"
          inner = conditions(document, node, "not { CONDITION }")
          raise document.mistake("not has #{inner.size} conditions; write it as not { CONDITION }", node) unless inner.size == 1

          Core::Condition::Not.new(condition: inner.first, line: node.line)
        when "all"
          Core::Condition::All.new(conditions: conditions(document, node, "all { CONDITION ... }", nonempty: true), line: node.line)
        when "any"
          Core::Condition::Any.new(conditions: conditions(document, node, "any { CONDITION ... }", nonempty: true), line: node.line)
        else
          raise document.mistake(Core::Spelling.unknown("condition", node.name, CONDITIONS), node)
        end
      end

      def conditions(document, node, usage, nonempty: false)
        document.arguments(node, usage, 0)
        raise document.mistake("#{node.name} has no condition; write it as #{usage}", node) if nonempty && node.children.empty?

        node.children.map { |child| condition(document, child) }
      end

      def policy_rule(document, node)
        name = document.string(node, "rule RULE")
        no_children(document, node)
        severity = document.string_property(node, "severity")
        Core::PolicyRule.new(name:, arguments: node.properties.except("severity"),
          severity: severity && document.choice(node, "severity", severity, SEVERITIES), line: node.line)
      end

      def rule(document, node)
        name = document.string(node, "rule NAME ruby=FILE")
        document.properties(node, ["ruby"])
        no_children(document, node)
        ruby = document.string_property(node, "ruby")
        raise document.mistake("rule #{name.dump} has no ruby=, the file its code is in", node) unless ruby

        Core::RuleDeclaration.new(name:, ruby:, line: node.line)
      end

      def artifacts_ruby(document)
        first, again = document.nodes.select { |node| node.name == "artifacts" }
        return unless first
        raise document.mistake("artifacts is declared twice; the first is on line #{first.line}", again) if again

        document.arguments(first, "artifacts ruby=FILE", 0)
        document.properties(first, ["ruby"])
        no_children(document, first)
        ruby = document.string_property(first, "ruby")
        raise document.mistake("artifacts has no ruby=, the file that declares them", first) unless ruby

        Core::ArtifactsRuby.new(ruby:, line: first.line)
      end

      def command(document, node)
        name = document.string(node, "command NAME help=TEXT")
        document.properties(node, ["help"])
        no_children(document, node)
        help = document.string_property(node, "help")
        raise document.mistake("command #{name.dump} has no help=, its line in --help", node) if help.nil? || help.strip.empty?

        Core::CommandDeclaration.new(name:, help:, line: node.line)
      end

      def helper(document, node)
        name = document.string(node, "helper NAME command=COMMAND file=FILE")
        document.properties(node, %w[command file])
        no_children(document, node)
        command = document.string_property(node, "command")
        file = document.string_property(node, "file")
        raise document.mistake("helper #{name.dump} has no command=, the program it runs on", node) unless command
        raise document.mistake("helper #{name.dump} has no file=, the program's file in the plugin", node) unless file

        Core::HelperDeclaration.new(name:, command:, file:, line: node.line)
      end

      def no_more(document, node)
        document.properties(node, [])
        no_children(document, node)
      end

      def no_children(document, node) = document.children(node, [])
    end
  end
end
