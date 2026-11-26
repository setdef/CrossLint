# frozen_string_literal: true

require_relative "artifact"
require_relative "fault"
require_relative "rule"
require_relative "mistake"

module CrossLint
  module Core
    class RubyRule
      class Stopped < StandardError
        attr_reader :fault

        def initialize(fault)
          @fault = fault
          super(fault.line)
        end
      end

      CLASS_NAME = /\A[A-Z][A-Za-z0-9_]*\z/

      def self.class_name(name) = name.split(/[-_]/).map { |part| part.sub(/\A[a-z]/, &:upcase) }.join

      # SystemExit too, since a rule that calls exit would otherwise end
      # the check with a status that says nothing of the rule.
      def self.load(plugin_ruby, plugin, declaration, namespace)
        plugin_ruby.load(plugin, declaration.ruby, declaration.line, namespace)
        new(plugin:, name: declaration.name, rule: find(declaration, namespace).new)
      rescue Mistake
        raise
      rescue StandardError, ScriptError, SystemExit => error
        raise Stopped, Fault.of(error, plugin:, rule: declaration.name)
      end

      def self.find(declaration, namespace)
        name = class_name(declaration.name)
        found = namespace.const_get(name) if name.match?(CLASS_NAME) && namespace.const_defined?(name, false)
        raise PluginError, "defines no class #{name} in #{declaration.ruby}" unless found.instance_of?(Class)
        raise PluginError, "has a class #{name} that doesn't inherit from CrossLint::Rule" unless found < Rule

        found
      end

      def initialize(plugin:, name:, rule:)
        @plugin = plugin
        @name = name
        @rule = rule
      end

      def severity = :error

      def results(artifact, _arguments, read)
        results = @rule.check(Rule::Artifact.new(artifact, read))
        raise PluginError, "returned #{results.class} from check, where check returns an array of violations" unless results.instance_of?(Array)

        results.each do |result|
          raise PluginError, "returned an array holding #{result.class}, where check returns violations" unless result.instance_of?(RuleResult)
          next if [result.path, result.role] == [artifact.path, artifact.role]

          raise PluginError, "returned a violation of #{result.path}, which isn't the artifact it checked"
        end
      rescue StandardError, ScriptError, SystemExit => error
        raise Stopped, Fault.of(error, plugin: @plugin, rule: @name, artifact: artifact.path)
      end
    end
  end
end
