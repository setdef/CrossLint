# frozen_string_literal: true

require_relative "artifact"
require_relative "artifact_finder"
require_relative "check_result"
require_relative "ruby_rule"
require_relative "helper_rule"
require_relative "step"

module CrossLint
  module Core
    class Check
      def initialize(project_files:, plugin_ruby:, helpers:, steps:)
        @project_files = project_files
        @plugin_ruby = plugin_ruby
        @helpers = helpers
        @steps = steps
      end

      def call(project, warnings: nil, verbosity: nil, all: false, command: nil, flags: {}, started: nil)
        warnings ||= project.configuration.warnings
        verbosity ||= project.configuration.verbosity || :normal
        policies = enabled_policies(project)
        files = @project_files.files(project.root)
        finder = ArtifactFinder.new(project_files: @project_files, root: project.root, files:)
        stopped = [] #: Array[Fault]
        kinds = project.plugins.to_h do |plugin|
          [plugin.name, finder.artifacts(plugin)]
        rescue ArtifactFinder::Stopped => error
          stopped << error.fault
          [plugin.name, plugin.manifest.artifacts.to_h { |declaration| [declaration.name, []] }]
        end
        # Before any rule runs, since a rule that asks a helper to read a
        # language's files can keep a large project silent for a while.
        started&.call(counts(kinds, checked_kinds(project, policies))) if verbosity == :normal
        helpers = @helpers.start(project.root, project.plugins)
        begin
          running = policies.reject { |plugin, _| stopped.any? { |fault| fault.plugin == plugin.name } }
          violations, faults = run_plugins(project, running, kinds, helpers, files.map { -it }.freeze)
          faults = stopped + faults
        rescue Interrupt
          # Before stop, which waits for each helper to finish.
          helpers.kill
          raise
        ensure
          helpers.stop
        end
        steps = run_steps(project, violations, faults, command, flags)
        report(project, kinds, checked_kinds(project, policies), violations, faults, steps, warnings:, verbosity:, all:, command:)
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

      def run_plugins(project, policies, kinds, helpers, files)
        read = ->(path) { @project_files.read(project.root, path) }
        rules, faults = load_rules(policies, helpers, files, read)
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
      def load_rules(policies, helpers, files, read)
        loaded = {} #: Hash[[String, String], RubyRule | HelperRule]
        faults = [] #: Array[Fault]
        policies.group_by(&:first).each do |plugin, owned|
          namespace = Module.new
          declarations = plugin.manifest.rules.to_h { |rule| [rule.name, rule] }
          names = owned.flat_map { |_, policy| policy.rules.map(&:name) }.uniq.reject { |name| BuiltInRule.named(name) }
          call = ->(name, input) { call_helper(helpers, plugin, name, input) }
          names.each do |name|
            declaration = declarations.fetch(name)
            loaded[[plugin.name, name]] = if declaration.helper
              HelperRule.new(plugin:, name:, helper: declaration.helper, call:)
            else
              RubyRule.load(@plugin_ruby, plugin, declaration, namespace, call, files, read)
            end
          end
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

      def checked_kinds(project, policies)
        targets = policies.flat_map { |plugin, policy| plugin.targets(policy) }
        kinds = project.plugins.flat_map do |plugin|
          plugin.manifest.artifacts.map do |declaration|
            [plugin.name, declaration.name] #: [String, String]
          end
        end
        kinds.select { |kind| targets.include?(kind) }
      end

      def run(project, plugin, policy, kinds, rules, read)
        override = setting(project, plugin, policy)&.severity
        plugin.targets(policy).flat_map { |owner, name| kinds.fetch(owner).fetch(name) }.flat_map do |artifact|
          next [] unless policy.condition.nil? || policy.condition.holds?(artifact)

          policy.rules.flat_map do |rule|
            checker = BuiltInRule.named(rule.name) || rules.fetch([plugin.name, rule.name])
            checker.results(artifact, rule.arguments, read).map do |result|
              Violation.new(plugin: plugin.name, policy: policy.name, artifact: artifact.name, path: result.path, role: result.role,
                message: result.message, severity: override || rule.severity || checker.severity, detail: result.detail, key: artifact.key,
                line: artifact.line)
            end
          end
        end
      end

      # Each step of each plugin that didn't stop, run on every violation.
      def run_steps(project, violations, faults, command, flags)
        faulted = faults.map(&:plugin)
        owner, name = command
        project.plugins.reject { |plugin| faulted.include?(plugin.name) }.flat_map do |plugin|
          given = (name if owner == plugin.name)
          plugin.manifest.steps.map do |declaration|
            @steps.fetch(declaration.name).call(StepInput.new(project:, plugin:, violations:, faulted:, command: given, flags: (given ? flags : {})))
          end
        end
      end

      def report(project, kinds, checked, violations, faults, steps, warnings:, verbosity:, all:, command:)
        hidden = warnings == :none
        excused = steps.flat_map(&:excused)
        left = violations.reject { |violation| excused.include?(violation) }
        added = steps.flat_map(&:violations).reject { |violation| disabled?(project, violation) }
        shown = (left + added).select { |violation| !hidden || violation.severity == :error }
        paid_off = steps.flat_map(&:paid_off)
        notices = notices(project, kinds)
        fails = ->(violation) { violation.severity == :error || warnings == :error }
        wrote = steps.flat_map(&:wrote)
        # A command is not a judgment of the check: it did what it was asked.
        failed = command.nil? && (shown.any?(&fails) || !paid_off.empty? || (warnings == :error && !notices.empty?))
        findings = (verbosity == :quiet) ? shown.select(&fails) : shown
        findings += passed(kinds, checked, left) if all && verbosity == :normal
        # Every notice is a warning, so --quiet reports one only when it
        # fails the check. A step's warnings never fail it.
        shows_notices = !hidden && (verbosity == :normal || (verbosity == :quiet && warnings == :error))
        notices = notices.select { shows_notices } + steps.flat_map(&:notices).select { !hidden && verbosity == :normal }
        summary = summary(kinds, checked, shown, hidden, faults.size).with(paid_off: paid_off.size, steps: steps.flat_map(&:summary))
        CheckResult.new(notices:, findings: sort((findings + paid_off).reject { verbosity == :silent }), summary:, verbosity:, failed:,
          faults:, wrote: wrote.reject { verbosity == :silent })
      end

      def disabled?(project, violation)
        project.configuration.policies.any? { |setting| setting.name == "#{violation.plugin}/#{violation.policy}" && setting.enabled == false }
      end

      def notices(project, kinds)
        project.unused_rules.map do |plugin, rule|
          Notice.new(file: plugin.manifest.file, line: rule.line, message: "no policy runs rule #{rule.name.dump}, so CrossLint doesn't load it")
        end + project.plugins.sum([]) { |plugin| unmatched(plugin, kinds.fetch(plugin.name)) }
      end

      # An optional artifact is one a project may well not have, so its
      # pattern is reported only when no artifact of its plugin matches a
      # file, as when a setting names the wrong folder.
      def unmatched(plugin, found)
        declarations = plugin.manifest.artifacts
        empty = declarations.select { |declaration| found.fetch(declaration.name).empty? }
        optional = empty.find(&:optional)
        if optional && empty.size == declarations.size
          return [Notice.new(file: plugin.manifest.file, line: optional.line,
            message: "no file matches the primary of any artifact of plugin #{plugin.name}, such as #{optional.primary.source.dump}")]
        end

        empty.reject(&:optional).map do |declaration|
          found = declaration.regex ? "no file that #{declaration.primary.source.dump} matches has a match of its regex" : "no file matches #{declaration.primary.source.dump}"
          Notice.new(file: plugin.manifest.file, line: declaration.line, message: "#{found}, the primary of artifact #{declaration.name.dump}")
        end
      end

      def passed(kinds, checked, violations)
        failed = violations.map { |violation| [violation.artifact, violation.role] }
        checked.flat_map { |owner, name| kinds.fetch(owner).fetch(name) }.reject { |artifact| failed.include?([artifact.name, artifact.role]) }
      end

      def counts(kinds, checked)
        names = checked.map(&:last)
        checked.map do |owner, name|
          [(names.count(name) > 1) ? "#{owner}/#{name}" : name, kinds.fetch(owner).fetch(name).size] #: [String, Integer]
        end
      end

      def summary(kinds, checked, shown, hidden, faults)
        Summary.new(kinds: counts(kinds, checked), faults:, errors: shown.count { |violation| violation.severity == :error },
          warnings: shown.count { |violation| violation.severity == :warning }, warnings_shown: !hidden)
      end

      def sort(findings)
        findings.sort_by do |finding|
          case finding
          when Violation then [finding.path, finding.line || 0, finding.artifact, finding.plugin, finding.policy, finding.message, finding.severity]
          when PaidOffEntry then [finding.artifact, 0, finding.artifact, finding.plugin, finding.policy, finding.message]
          else [finding.path, finding.line || 0, finding.name, finding.plugin, "", finding.role]
          end
        end
      end
    end
  end
end
