# frozen_string_literal: true

require_relative "artifact"
require_relative "check_result"
require_relative "ruby_rule"

module CrossLint
  module Core
    class Check
      def initialize(project_files:, plugin_ruby:, helpers:)
        @project_files = project_files
        @plugin_ruby = plugin_ruby
        @helpers = helpers
      end

      def call(project, warnings: nil, verbosity: nil, all: false)
        warnings ||= project.configuration.warnings
        verbosity ||= project.configuration.verbosity || :normal
        policies = enabled_policies(project)
        files = @project_files.files(project.root)
        kinds = project.plugins.to_h do |plugin|
          [plugin.name, plugin.manifest.artifacts.to_h { |declaration| [declaration.name, find(project, plugin, declaration, files)] }]
        end
        helpers = @helpers.start(project.root, project.plugins)
        begin
          violations, faults = run_plugins(project, policies, kinds, helpers)
        rescue Interrupt
          # Before stop, which waits for each helper to finish.
          helpers.kill
          raise
        ensure
          helpers.stop
        end
        report(project, kinds, checked_kinds(project, policies), violations, faults, warnings:, verbosity:, all:)
      end

      private

      def enabled_policies(project)
        project.plugins.flat_map do |plugin|
          plugin.manifest.policies.filter_map do |policy|
            [plugin, policy] unless setting(project, plugin, policy)&.enabled == false
          end
        end
      end

      def setting(project, plugin, policy)
        project.configuration.policies.find { |setting| setting.name == "#{plugin.name}/#{policy.name}" }
      end

      def run_plugins(project, policies, kinds, helpers)
        rules, faults = load_rules(policies, helpers)
        read = ->(path) { @project_files.read(project.root, path) }
        stopped = faults.map(&:plugin)
        violations = project.plugins.reject { |plugin| stopped.include?(plugin.name) }.flat_map do |plugin|
          policies.select { |owner, _| owner == plugin }.flat_map { |_, policy| run(project, plugin, policy, kinds, rules, read) }
        rescue RubyRule::Stopped => error
          faults << error.fault
          []
        end
        [violations, faults]
      end

      # Each plugin's files run in a namespace of the plugin's own, and a
      # plugin stops at its first fault.
      def load_rules(policies, helpers)
        loaded = {} #: Hash[[String, String], RubyRule]
        faults = [] #: Array[Fault]
        policies.group_by(&:first).each do |plugin, owned|
          namespace = Module.new
          declarations = plugin.manifest.rules.to_h { |rule| [rule.name, rule] }
          names = owned.flat_map { |_, policy| policy.rules.map(&:name) }.uniq.reject { |name| BuiltInRule.named(name) }
          call = ->(name, input) { call_helper(helpers, plugin, name, input) }
          names.each { |name| loaded[[plugin.name, name]] = RubyRule.load(@plugin_ruby, plugin, declarations.fetch(name), namespace, call) }
        rescue RubyRule::Stopped => error
          faults << error.fault
        end
        [loaded, faults]
      end

      def call_helper(helpers, plugin, name, input)
        unless plugin.manifest.helpers.any? { |helper| helper.name == name }
          raise PluginError, "called helper #{name.inspect}, which plugin #{plugin.name} doesn't declare"
        end

        helpers.call(plugin, name, input)
      end

      def find(project, plugin, declaration, files)
        files.filter_map do |path|
          match = declaration.files.match(path)
          next unless match

          companions = declaration.companions.map do |companion|
            companion_path = companion.pattern.expand(match)
            Companion.new(name: companion.name, path: companion_path, exists: @project_files.exist?(project.root, companion_path))
          end
          Artifact.new(plugin: plugin.name, role: declaration.name, path:, match:, companions:)
        end
      end

      # The artifact a policy applies to, as [plugin, artifact], by the
      # names LoadProject has checked.
      def target(plugin, policy)
        owner, slash, name = policy.applies_to.artifact.partition("/")
        slash.empty? ? [plugin.name, owner] : [owner, name]
      end

      def checked_kinds(project, policies)
        targets = policies.map { |plugin, policy| target(plugin, policy) }
        kinds = project.plugins.flat_map do |plugin|
          plugin.manifest.artifacts.map do |declaration|
            [plugin.name, declaration.name] #: [String, String]
          end
        end
        kinds.select { |kind| targets.include?(kind) }
      end

      def run(project, plugin, policy, kinds, rules, read)
        owner, name = target(plugin, policy)
        override = setting(project, plugin, policy)&.severity
        kinds.fetch(owner).fetch(name).flat_map do |artifact|
          next [] unless policy.condition.nil? || policy.condition.holds?(artifact)

          policy.rules.flat_map do |rule|
            checker = BuiltInRule.named(rule.name) || rules.fetch([plugin.name, rule.name])
            checker.results(artifact, rule.arguments, read).map do |result|
              Violation.new(plugin: plugin.name, policy: policy.name, artifact: result.path, role: result.role, message: result.message,
                severity: override || rule.severity || checker.severity, detail: result.detail)
            end
          end
        end
      end

      def report(project, kinds, checked, violations, faults, warnings:, verbosity:, all:)
        hidden = warnings == :none
        shown = violations.select { |violation| !hidden || violation.severity == :error }
        notices = notices(project, kinds)
        fails = ->(violation) { violation.severity == :error || warnings == :error }
        failed = shown.any?(&fails) || (warnings == :error && !notices.empty?)
        findings = (verbosity == :quiet) ? shown.select(&fails) : shown
        findings += passed(kinds, checked, violations) if all && verbosity == :normal
        # Every notice is a warning, so --quiet reports one only when it
        # fails the check.
        shows_notices = !hidden && (verbosity == :normal || (verbosity == :quiet && warnings == :error))
        CheckResult.new(notices: notices.select { shows_notices }, findings: sort(findings.reject { verbosity == :silent }),
          summary: summary(kinds, checked, shown, hidden, faults.size), verbosity:, failed:, faults:)
      end

      def notices(project, kinds)
        project.unused_rules.map do |plugin, rule|
          Notice.new(file: plugin.manifest.file, line: rule.line, message: "no policy runs rule #{rule.name.dump}, so CrossLint doesn't load it")
        end + project.plugins.flat_map do |plugin|
          plugin.manifest.artifacts.select { |declaration| kinds.fetch(plugin.name).fetch(declaration.name).empty? }.map do |declaration|
            Notice.new(file: plugin.manifest.file, line: declaration.line,
              message: "no file matches #{declaration.files.source.dump}, the files of artifact #{declaration.name.dump}")
          end
        end
      end

      def passed(kinds, checked, violations)
        failed = violations.map { |violation| [violation.artifact, violation.role] }
        checked.flat_map { |owner, name| kinds.fetch(owner).fetch(name) }.reject { |artifact| failed.include?([artifact.path, artifact.role]) }
      end

      def summary(kinds, checked, shown, hidden, faults)
        names = checked.map(&:last)
        counted = checked.map do |owner, name|
          [(names.count(name) > 1) ? "#{owner}/#{name}" : name, kinds.fetch(owner).fetch(name).size] #: [String, Integer]
        end
        Summary.new(kinds: counted, faults:, errors: shown.count { |violation| violation.severity == :error },
          warnings: shown.count { |violation| violation.severity == :warning }, warnings_shown: !hidden)
      end

      def sort(findings)
        findings.sort_by do |finding|
          case finding
          when Violation then [finding.artifact, finding.plugin, finding.policy, finding.message]
          else [finding.path, finding.plugin, "", finding.role]
          end
        end
      end
    end
  end
end
