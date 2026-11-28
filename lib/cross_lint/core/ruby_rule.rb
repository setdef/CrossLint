# frozen_string_literal: true

require "timeout"

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

      TIME_LIMIT = 60

      # An Exception, not a StandardError, so that a rule's own
      # `rescue => error` doesn't swallow it and run on.
      class Overran < Exception
      end

      FAULTS = [StandardError, ScriptError, SystemExit, SystemStackError].freeze

      CLASS_NAME = /\A[A-Z][A-Za-z0-9_]*\z/

      def self.class_name(name) = name.split(/[-_]/).map { |part| part.sub(/\A[a-z]/, &:upcase) }.join

      # SystemExit too, since a rule that calls exit would otherwise end
      # the check with a status that says nothing of the rule, and
      # SystemStackError, which a rule that recurses without end raises
      # and which is no StandardError.
      def self.load(crosslint_ruby, plugin, declaration, namespace, helpers, files, read)
        file = declaration.ruby #: String
        crosslint_ruby.load(plugin, file, declaration.line, namespace)
        new(plugin:, name: declaration.name, rule: make(find(declaration, namespace), helpers, files, read))
      rescue Mistake
        raise
      rescue *FAULTS => error
        raise Stopped, Fault.of(error, plugin:, rule: declaration.name)
      end

      # A rule's class may define initialize, and helper, project_files and
      # read work there too, so the instance has them before initialize runs.
      def self.make(rule_class, helpers, files, read)
        rule = rule_class.allocate
        rule.instance_variable_set(:@crosslint_helpers, helpers)
        rule.instance_variable_set(:@crosslint_files, files)
        rule.instance_variable_set(:@crosslint_read, read)
        rule.__send__(:initialize)
        rule
      end

      def self.find(declaration, namespace)
        name = class_name(declaration.name)
        found = namespace.const_get(name) if name.match?(CLASS_NAME) && namespace.const_defined?(name, false)
        raise PluginError, "defines no class #{name} in #{declaration.ruby}" unless found.instance_of?(Class)
        raise PluginError, "has a class #{name} that doesn't inherit from CrossLint::Rule" unless found < Rule

        found
      end

      def initialize(plugin:, name:, rule:, time_limit: TIME_LIMIT)
        @time_limit = time_limit
        @plugin = plugin
        @name = name
        @rule = rule
      end

      def severity = :error

      def results(artifact, _arguments, read)
        results = Timeout.timeout(@time_limit, Overran) { @rule.check(Rule::Artifact.new(artifact, read)) }
        raise PluginError, "returned #{results.class} from check, where check returns an array of violations" unless results.instance_of?(Array)

        results.each do |result|
          raise PluginError, "returned an array holding #{result.class}, where check returns violations" unless result.instance_of?(RuleResult)
          next if [result.path, result.role] == [artifact.path, artifact.role]

          raise PluginError, "returned a violation of #{result.path}, which isn't the artifact it checked"
        end
      rescue Overran
        error = PluginError.new("didn't finish within #{@time_limit} seconds, so CrossLint stopped it")
        raise Stopped, Fault.of(error, plugin: @plugin, rule: @name, artifact: artifact.location)
      rescue *FAULTS => error
        raise Stopped, Fault.of(error, plugin: @plugin, rule: @name, artifact: artifact.location)
      end
    end
  end
end
