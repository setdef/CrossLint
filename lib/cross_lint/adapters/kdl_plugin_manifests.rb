# frozen_string_literal: true

require_relative "../usage_spec"
require_relative "kdl_document"

module CrossLint
  module Adapters
    class KDLPluginManifests
      FILE = "plugin.kdl"

      NODES = %w[artifact artifacts policy rule helper setting command step].freeze

      CONDITIONS = %w[piece-exists not all any].freeze

      SEVERITIES = %w[error warning].freeze

      # The one type annotation a manifest reads: a helper's command=,
      # written (crosslint)"ruby", runs the helper on CrossLint's
      # Ruby, where no project command could ever be found.
      TYPED = {"helper" => {"command" => ["crosslint"]}}.freeze

      # What a helper's command=(crosslint) may name: the runtimes
      # CrossLint carries.
      CARRIED = ["ruby"].freeze

      HELPER = "helper NAME command=COMMAND file=FILE"

      GONE = "ruby= is gone; declare the file as a helper on the Ruby CrossLint carries, " \
        "helper NAME command=(crosslint)\"ruby\" file=FILE, and write %s helper=NAME"

      FLAG_MISTAKE = "flag isn't a node CrossLint reads outside a command: a plugin adds commands under its own name, " \
        "as in command NAME help=TEXT, and flags only to its commands, as in flag \"-n --name\" help=TEXT inside one; it adds no flag to crosslint check"

      def file = FILE

      def read(root, folder)
        path = File.join(root, folder, FILE)
        return unless File.file?(path)

        document = KDLDocument.load(path, folder.empty? ? FILE : "#{folder}/#{FILE}", typed: TYPED)
        document.nodes.each do |node|
          next if NODES.include?(node.name)
          raise document.mistake(FLAG_MISTAKE, node) if node.name == "flag"

          raise document.mistake(Core::Spelling.unknown("node", node.name, NODES), node)
        end
        blockless, policies = document.nodes.select { |node| node.name == "policy" }.partition { |node| node.children.empty? }
        all = nodes(document, "helper") { |node| helper(document, node) }
        once(document, all)
        carried = [] #: Array[Carried]
        helpers = [] #: Array[Core::HelperDeclaration]
        all.each { |helper| helper.is_a?(Carried) ? carried << helper : helpers << helper }
        Core::Manifest.new(file: document.file, artifacts: nodes(document, "artifact") { |node| artifact(document, node) },
          policies: policies.map { |node| policy(document, node) },
          rules: nodes(document, "rule") { |node| rule(document, node, carried) },
          helpers:,
          step_policies: blockless.map { |node| Core::StepPolicy.new(name: named(document, node, "policy NAME { ... }"), line: node.line) },
          settings: named_nodes(document, "setting") { |name, line| Core::SettingDeclaration.new(name:, line:) },
          commands: nodes(document, "command") { |node| command(document, node) },
          steps: named_nodes(document, "step") { |name, line| Core::StepDeclaration.new(name:, line:) },
          **artifacts(document, carried))
      end

      private

      # A helper on CrossLint's Ruby: its file runs in CrossLint,
      # as the Ruby of the rules and the artifacts that name it.
      class Carried < Data.define(:name, :file, :line); end

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
        document.children(node, %w[primary name piece])
        primary = document.required_child(node, "primary")
        primary_pattern = pattern(document, primary, document.string(primary, "primary PATTERN"))
        document.properties(primary, ["regex"])
        no_children(document, primary)
        declared = Core::ArtifactDeclaration.new(name:, primary: primary_pattern, pieces: [], line: node.line,
          regex: primary_regex(document, primary, primary_pattern))
        name_pattern = document.optional_child(node, "name")&.then { |child| name_pattern(document, child, declared) }
        declared.with(name_pattern:, pieces: node.children.select { |child| child.name == "piece" }.map { |child| piece(document, child, declared) })
      end

      def primary_regex(document, node, primary)
        regex = regex(document, node, primary.placeholders)
        taken = regex&.captures.to_a & Core::PathPattern::PLACEHOLDERS
        raise document.mistake("regex captures (?<#{taken.first}>...), which has the name of a placeholder; name it otherwise", node) if taken.any?

        regex
      end

      def piece(document, node, declared)
        words = document.strings(node, "piece NAME PATTERN", 2)
        document.properties(node, ["regex"])
        no_children(document, node)
        Core::PieceDeclaration.new(name: words.first, pattern: pattern(document, node, words.last, declared.captures), line: node.line,
          regex: regex(document, node, declared.placeholders))
      end

      def name_pattern(document, node, declared)
        named = pattern(document, node, document.string(node, "name PATTERN"), declared.captures)
        no_more(document, node)
        extra = named.placeholders - declared.placeholders
        return named if extra.empty?

        raise document.mistake("name #{named.source.dump} #{declared.lacking(extra.first)}", node)
      end

      # The regex= of `node`, which may use the placeholders in `known`,
      # or nil when it has none.
      def regex(document, node, known)
        source = document.string_property(node, "regex")
        return unless source

        problem = Core::Regex.problem(source, known)
        raise document.mistake(problem, node) if problem

        Core::Regex.new(source:)
      end

      def pattern(document, node, source, captures = [])
        problem = Core::PathPattern.problem(source, Core::PathPattern::PLACEHOLDERS + captures)
        raise document.mistake(problem, node) if problem

        Core::PathPattern.new(source:, captures:)
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
        raise document.mistake("when has no condition; write it as when piece-exists PIECE", node) unless kind

        condition(document, KDLDocument::Node.new(name: kind.to_s, line: node.line, arguments: rest,
          properties: node.properties, children: node.children))
      end

      def condition(document, node)
        document.properties(node, [])
        case node.name
        when "piece-exists"
          piece = document.string(node, "piece-exists PIECE")
          document.children(node, [])
          Core::Condition::PieceExists.new(piece:, line: node.line)
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

      def rule(document, node, carried)
        name = document.string(node, "rule NAME helper=HELPER")
        raise document.mistake(format(GONE, "rule #{name.dump}"), node) if node.properties.key?("ruby")

        document.properties(node, %w[helper])
        no_children(document, node)
        helper = document.string_property(node, "helper")
        raise document.mistake("rule #{name.dump} has no helper=, the helper that runs it", node) unless helper

        ruby = carried.find { |each| each.name == helper }&.file
        ruby ? Core::RuleDeclaration.new(name:, ruby:, line: node.line) : Core::RuleDeclaration.new(name:, helper:, line: node.line)
      end

      # The artifacts line, if there is one: the helper that declares
      # the artifacts, which may be a file of Ruby CrossLint runs.
      def artifacts(document, carried)
        first, again = document.nodes.select { |node| node.name == "artifacts" }
        return {} unless first
        raise document.mistake("artifacts is declared twice; the first is on line #{first.line}", again) if again
        raise document.mistake(format(GONE, "artifacts"), first) if first.properties.key?("ruby")

        document.arguments(first, "artifacts helper=HELPER", 0)
        document.properties(first, %w[helper])
        no_children(document, first)
        helper = document.string_property(first, "helper")
        raise document.mistake("artifacts has no helper=, the helper that declares them", first) unless helper

        ruby = carried.find { |each| each.name == helper }&.file
        return {artifacts_ruby: Core::ArtifactsRuby.new(ruby:, line: first.line)} if ruby

        {artifacts_helper: Core::ArtifactsHelper.new(helper:, line: first.line)}
      end

      def command(document, node)
        name = document.string(node, "command NAME help=TEXT")
        document.properties(node, ["help"])
        document.children(node, ["flag"])
        help = document.string_property(node, "help")
        raise document.mistake("command #{name.dump} has no help=, its line in --help", node) if help.nil? || help.empty?

        flags = node.children.map { |child| command_flag(document, child) }
        Core::CommandDeclaration.new(name:, help:, line: node.line, flags:)
      end

      # A flag in the usage spec's syntax: its names, then help=TEXT.
      def command_flag(document, node)
        usage = "flag NAMES help=TEXT"
        words = document.string(node, usage)
        document.properties(node, ["help"])
        no_children(document, node)
        help = document.string_property(node, "help")
        raise document.mistake("flag #{words.dump} has no help=, its line in --help", node) if help.nil? || help.empty?

        short, long, value = UsageSpec.flag_names(words, failing: ->(message) { raise document.mistake(message, node) })
        Core::CommandFlag.new(short:, long:, value:, help:, line: node.line)
      end

      # A helper: a command and a file. The command is a program on the
      # PATH, written command=PROGRAM, or a program and the words after it,
      # written as a command node in the helper's block, or a runtime
      # CrossLint carries, written command=(crosslint)"ruby".
      def helper(document, node)
        name = document.string(node, HELPER)
        document.properties(node, %w[command file])
        document.children(node, %w[command])
        file = document.string_property(node, "file")
        raise document.mistake("helper #{name.dump} has no file=, the program's file in the plugin", node) unless file

        given = node.properties["command"]
        block = document.optional_child(node, "command")
        raise document.mistake("helper #{name.dump} has both command= and a command node; write one", node) if given && block
        return carried(document, node, name, given, file) if given.is_a?(KDLDocument::Typed)

        words = block ? command_words(document, block) : [given].compact
        program, *arguments = words.map { |word| word.is_a?(String) ? word : raise(document.mistake("command= takes a string, not #{word.inspect}", node)) }
        raise document.mistake("helper #{name.dump} has no command=, the program it runs on", node) unless program

        Core::HelperDeclaration.new(name:, command: program, arguments:, file:, line: node.line)
      end

      def carried(document, node, name, given, file)
        unless CARRIED.include?(given.value)
          raise document.mistake("command=(crosslint) names a runtime CrossLint carries, and it carries #{CARRIED.map(&:dump).join(" and ")}, " \
            "not #{given.value.inspect}", node)
        end

        Carried.new(name:, file:, line: node.line)
      end

      # The words of a helper's command node: the program, then its
      # arguments, each a string.
      def command_words(document, node)
        no_more(document, node)
        words = node.arguments
        raise document.mistake("command has no words; write it as command PROGRAM ARGUMENT ...", node) if words.empty?
        raise document.mistake("command takes strings, as in command \"bundle\" \"exec\" \"ruby\"", node) unless words.all?(String)

        words
      end

      # Checks that no two helpers have one name, as a rule or the
      # artifacts line names a helper by it.
      def once(document, helpers)
        helpers.each_with_index do |helper, index|
          first = helpers.take(index).find { |other| other.name == helper.name }
          next unless first

          raise Core::Mistake.new("helper #{helper.name.dump} is declared twice; the first is on line #{first.line}", file: document.file, line: helper.line)
        end
      end

      def no_more(document, node)
        document.properties(node, [])
        no_children(document, node)
      end

      def no_children(document, node) = document.children(node, [])
    end
  end
end
