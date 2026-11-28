# frozen_string_literal: true

require_relative "artifact"
require_relative "debt_file"
require_relative "mistake"
require_relative "spelling"
require_relative "step"

module CrossLint
  module Core
    class TrackDebt
      class Report < Data.define(:commented, :matching); end

      class Settings < Data.define(:file, :report); end

      # A violation's identity, by which an entry matches it.
      class Identity < Data.define(:plugin, :policy, :artifact, :role, :detail, :key, :built_in)
        def self.of(violation) = new(plugin: violation.plugin, policy: violation.policy, artifact: violation.artifact,
          role: violation.role, detail: violation.detail.to_s, key: violation.key, built_in: violation.built_in)

        def rule = "#{plugin}/#{policy}"

        # What an entry's Artifact column can hold for it: its name or its
        # key, such as the base path ng-nudge writes, each alone or with
        # its role.
        def artifacts = [artifact, key].compact.flat_map { |name| [name, "#{name}.#{role}"] }
      end

      FILE = ".config/crosslint/debt.tsv"

      POLICY = "has-debt"

      COMMAND = "update"

      DRY_RUN = "dry-run"

      SEVERITIES = %w[error warning none].freeze

      REPORT = %w[commented matching].freeze

      def self.settings(settings, file)
        found = {} #: Hash[String, Setting]
        settings.each do |setting|
          fail_at = ->(message) { raise Mistake.new(message, file:, line: setting.line) }
          first = found[setting.name]
          fail_at.call("#{setting.name} is set twice; the first is on line #{first.line}") if first
          fail_at.call("#{setting.name} takes no settings inside it") unless setting.children.empty?
          found[setting.name] = setting
        end
        Settings.new(file: found["file"]&.then { |setting| debt_file(setting, file) } || FILE,
          report: found["report-entries"]&.then { |setting| report(setting, file) })
      end

      def self.debt_file(setting, file)
        path = setting.arguments.first
        unless setting.arguments.size == 1 && path.is_a?(String) && setting.properties.empty?
          raise Mistake.new("file takes one path and nothing else, as in file #{FILE.dump}", file:, line: setting.line)
        end
        return path unless path.empty? || path.match?(%r{\A(?:[/\\]|[A-Za-z]:)}) || path.split(%r{[/\\]}).include?("..")

        raise Mistake.new("file takes a path relative to the project's root, not #{path.dump}", file:, line: setting.line)
      end

      def self.report(setting, file)
        fail_at = ->(message) { raise Mistake.new(message, file:, line: setting.line) }
        fail_at.call("report-entries takes no arguments, only commented= and matching=") unless setting.arguments.empty?
        unknown = setting.properties.keys - REPORT
        fail_at.call(Spelling.unknown("property", unknown.fetch(0), REPORT) + " for report-entries") unless unknown.empty?
        commented = setting.properties["commented"]
        unless commented.nil? || SEVERITIES.include?(commented)
          fail_at.call("commented= takes #{Spelling.list(SEVERITIES.map(&:dump))}, not #{commented.inspect}")
        end
        matching = setting.properties["matching"]
        fail_at.call("matching= takes a regular expression, as a string") unless matching.nil? || matching.is_a?(String)
        Report.new(commented: commented&.to_sym, matching: matching && Regexp.new(matching))
      rescue RegexpError => error
        raise Mistake.new("matching= isn't a regular expression CrossLint reads: #{error}", file:, line: setting.line)
      end

      def initialize(debt_files:, debug: nil)
        @debt_files = debt_files
        @debug = debug
      end

      def policies = [POLICY]

      def check_settings(settings, file)
        self.class.settings(settings, file)
      end

      def call(input)
        project = input.project
        settings = self.class.settings(input.plugin.listing.settings, project.configuration.file)
        debt = @debt_files.read(project.root, settings.file)
        debt = debt.with(entries: debt.entries.map { |entry| slashed(entry) })
        identities = input.violations.map { |violation| Identity.of(violation) }.uniq
        wrote = [] #: Array[String]
        if input.command == COMMAND
          dry_run = input.flags.key?(DRY_RUN)
          wrote.concat(update(project, input, settings, debt, identities, dry_run:))
          debt = @debt_files.read(project.root, settings.file) unless dry_run
        end
        state(project, input, settings, debt, identities, wrote)
      end

      private

      # Keys use / on every system, so an entry written on Windows with \
      # matches elsewhere, and is written back with /.
      def slashed(entry) = entry.artifact.include?("\\") ? entry.with(artifact: entry.artifact.tr("\\", "/"), source: nil) : entry

      def state(project, input, settings, debt, identities, wrote)
        excused = [] #: Array[Identity]
        paid_off = [] #: Array[PaidOffEntry]
        notices = [] #: Array[Notice]
        named = identities_named(project, input, debt, identities)
        debt.entries.each do |entry|
          rule = resolve(project, input, debt, entry)
          matched = rule ? matches(entry, rule, identities, named) : [] #: Array[Identity]
          said(debt, entry, rule, matched)
          next unless rule

          excused.concat(matched)
          line = entry.line #: Integer
          if matched.empty?
            paid_off << PaidOffEntry.new(plugin: rule.first, policy: rule.last, artifact: entry.artifact, file: debt.file, line:,
              message: "the debt entry at #{debt.file}:#{entry.line} is paid off, since no violation matches it; crosslint debt update removes it")
          end
          warning = coarse(entry, rule, matched)
          notices << Notice.new(file: debt.file, line:, message: warning) if warning
        end
        accepted = input.violations.select { |violation| excused.include?(Identity.of(violation)) }
        StepResult.new(excused: accepted, violations: report_entries(project, input, settings, debt), paid_off:, notices:, wrote:,
          summary: accepted.empty? ? [] : ["#{accepted.size} accepted as debt"])
      end

      def said(debt, entry, rule, matched)
        @debug&.write("debt") do
          found = if rule.nil?
            "left alone, since CrossLint doesn't check that policy: its plugin isn't listed or stopped at a fault, or it is off"
          elsif matched.empty?
            "matches no violation, so it is paid off"
          else
            "matches #{Spelling.count(matched.size, "violation")}, accepted as debt"
          end
          "#{debt.file}:#{entry.line}, #{described(entry)}: #{found}"
        end
      end

      # The plugin and policy an entry is for, or nil when CrossLint
      # doesn't check it: its plugin isn't listed or stopped at a fault, or
      # its policy is disabled.
      def resolve(project, input, debt, entry)
        rule = entry.rule
        name, slash, policy = rule.partition("/")
        if slash.empty?
          owners = project.plugins.select { |plugin| plugin.manifest.policies.any? { |each| each.name == rule } }
          if owners.size > 1
            raise Mistake.new("has an entry for #{rule.dump}, a policy of #{Spelling.list(owners.map(&:name), "and")}; " \
              "write it as PLUGIN/POLICY", file: debt.file, line: entry.line)
          end
          owner = owners.first
          return unless owner

          name = owner.name
          policy = rule
        end
        listed = project.plugins.any? { |plugin| plugin.name == name }
        disabled = project.configuration.policies.any? { |setting| setting.name == "#{name}/#{policy}" && setting.enabled == false }
        [name, policy] if listed && !disabled && !input.faulted.include?(name)
      end

      # The identities an entry matches. An entry with no detail matches
      # every detail of a violation a built-in rule reported, which gave
      # none before it did, unless an entry has its detail; one ng-nudge
      # wrote, with a policy's name alone, matches every detail of any
      # violation.
      def matches(entry, rule, identities, named)
        legacy = !entry.rule.include?("/") && entry.detail.nil?
        undetailed = entry.detail.nil?
        identities.select do |identity|
          [identity.plugin, identity.policy] == rule && identity.artifacts.include?(entry.artifact) &&
            (legacy || (undetailed && identity.built_in && !named.include?(identity)) || identity.detail == entry.detail.to_s)
        end
      end

      # The identities an entry with a detail matches.
      def identities_named(project, input, debt, identities)
        debt.entries.reject { |entry| entry.detail.nil? }.flat_map do |entry|
          rule = resolve(project, input, debt, entry)
          rule ? matches(entry, rule, identities, []) : []
        end
      end

      # The warning for an entry that matches more than one artifact, or
      # every detail on its artifact, or nil.
      def coarse(entry, rule, matched)
        artifacts = matched.map { |identity| [identity.artifact, identity.role] }.uniq
        name = rule.join("/")
        if artifacts.size > 1
          "the entry for #{name} on #{entry.artifact} matches the violations of #{artifacts.size} artifacts, " \
            "#{Spelling.list(artifacts.map { |artifact, role| "#{artifact} as #{role}" }, "and")}; " \
            "crosslint debt update writes one entry for each"
        elsif !matched.all? { |identity| identity.detail == entry.detail.to_s }
          "the entry for #{name} on #{entry.artifact} has no detail, so it matches every violation of #{name} on it; " \
            "crosslint debt update writes one entry for each, with its detail"
        end
      end

      # Writes the debt file, or with dry_run only lists what it would
      # change, in the order it writes it; and returns the lines that say so,
      # the last of them the counts.
      def update(project, input, settings, debt, identities, dry_run:)
        covered = [] #: Array[Identity]
        written = [] #: Array[DebtEntry]
        changes = [] #: Array[String]
        removed = 0
        rewritten = 0
        named = identities_named(project, input, debt, identities)
        debt.entries.each do |entry|
          rule = resolve(project, input, debt, entry)
          unless rule
            written << entry
            unless entry.source
              rewritten += 1
              changes.concat(rewrite(entry))
            end
            next
          end

          matched = matches(entry, rule, identities, named)
          left = matched - covered
          covered.concat(left)
          if coarse(entry, rule, matched)
            rewritten += 1
            replacements = left.sort_by(&:deconstruct).map { |identity| fresh(identity, identities, entry.comment) }
            changes << "replace #{described(entry)}, line #{entry.line}"
            changes.concat(replacements.map { |replacement| "add #{described(replacement)}" })
            written.concat(replacements)
          elsif left.empty?
            removed += 1
            changes << "remove #{described(entry)}, line #{entry.line}"
          else
            unless entry.source
              rewritten += 1
              changes.concat(rewrite(entry))
            end
            written << entry
          end
        end
        added = (identities - covered).sort_by(&:deconstruct).map { |identity| fresh(identity, identities, "") }
        changes.concat(added.map { |entry| "add #{described(entry)}" })
        @debt_files.write(project.root, settings.file, debt.with(entries: written + added)) unless dry_run
        counts = ["#{added.size} #{(added.size == 1) ? "entry" : "entries"} added", "#{removed} removed"]
        counts << "#{rewritten} rewritten" unless rewritten.zero?
        return ["wrote #{debt.file}: #{counts.join(", ")}"] unless dry_run

        changes.map { |change| "would #{change}" } + ["would write #{debt.file}: #{counts.join(", ")}"]
      end

      # The lines that say an entry is written again as it now is.
      def rewrite(entry) = ["replace #{described(entry)}, line #{entry.line}", "add #{described(entry)}"]

      # An entry as a person reads it: its policy, its artifact, and its
      # detail when it has one.
      def described(entry)
        detail = entry.detail.to_s
        "#{entry.rule} on #{entry.artifact}#{" (#{detail})" unless detail.empty?}"
      end

      # An entry for one identity, keyed by its artifact, or by its
      # artifact and role when another artifact of the policy has that key.
      def fresh(identity, identities, comment)
        roles = identities.select { |other| [other.plugin, other.policy, other.artifact] == [identity.plugin, identity.policy, identity.artifact] }
          .map(&:role).uniq
        DebtEntry.fresh(rule: identity.rule, artifact: (roles.size > 1) ? "#{identity.artifact}.#{identity.role}" : identity.artifact, comment:,
          detail: (identity.detail unless identity.detail.empty?))
      end

      def report_entries(project, input, settings, debt)
        report = settings.report
        name = "#{input.plugin.name}/#{POLICY}"
        policy = project.configuration.policies.find { |setting| setting.name == name }
        return [] if report.nil? || policy&.enabled == false

        severity = policy&.severity || :error
        debt.entries.filter_map do |entry|
          next unless resolve(project, input, debt, entry)

          comment = entry.comment
          commented = !comment.empty? && (report.matching.nil? || report.matching.match?(comment))
          level = commented ? (report.commented || severity) : severity
          next if level == :none

          said = comment.empty? ? ", with no comment" : ": #{comment}"
          Violation.new(plugin: input.plugin.name, policy: POLICY, artifact: debt.file, role: "debt-file", severity: level,
            message: "line #{entry.line} lists #{entry.rule} on #{entry.artifact} as debt#{said}", detail: entry.line.to_s)
        end
      end
    end
  end
end
