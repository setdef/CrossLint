# frozen_string_literal: true

require "json"
require_relative "../configuration"
require_relative "../mistake"
require_relative "../mistakes"
require_relative "../spelling"
require_relative "files"
require_relative "glob"
require_relative "expression"

module CrossLint
  module Core
    module NgNudge
      # The JavaScript expression of `withComment.matching`, and the Ruby
      # expression CrossLint translated it to.
      class Matching < Data.define(:key, :source, :translated); end

      # An rc.json as the configuration CrossLint reads: what each key of
      # it becomes, the changes to say, and the expression of
      # `withComment.matching` when one counts. A key or a value that isn't
      # carried raises a Mistake naming the file and the key, and the fix.
      class Rc
        # The configuration, the changes to list, the `matching`, or nil,
        # the folder the Angular plugin looks in, and each role it finds
        # files for.
        class Result < Data.define(:configuration, :changes, :matching, :src_dir, :roles); end

        # A role, the node-glob pattern ng-nudge finds its files with, and
        # the path pattern that stands for it.
        class Role < Data.define(:name, :glob, :files); end

        # A `report-entries` setting, and the matching it holds, or nil.
        class Report < Data.define(:setting, :matching); end

        FILE = ".config/crosslint/config.kdl"

        # The roles ng-nudge has, each found by **/*.ROLE.ts.
        BUILT_IN = %w[component directive pipe service guard resolver interceptor].freeze

        KEYS = %w[$schema srcDir tsConfig artifacts rules options].freeze

        RULES = %w[spec-exists stub-exists interface-exists stub-matches-component interface-matches-component prefer-css-over-scss].freeze

        DEBT_RULE = "has-debt"

        SEVERITIES = %w[error warning].freeze

        CEILINGS = %w[none warning error].freeze

        OPTIONS = { "warnings" => %w[all none error], "verbosity" => %w[normal quiet silent] }.freeze

        ROLE = /\A[A-Za-z0-9_-]+\z/

        # The lists an `expects` can be, as the Angular plugin reads them.
        EXPECTS = [[], ["spec"]].freeze # steep:ignore UnannotatedEmptyCollection

        # What the debt file and the configuration have for a line number:
        # none, since a configuration CrossLint writes has no lines yet.
        LINE = 0

        # For a key that isn't there.
        NONE = {}.freeze # steep:ignore UnannotatedEmptyCollection

        def initialize(text, file: SETTINGS_FILE)
          @text = text
          @file = file
          @changes = [] #: Array[String]
          @globs = {} #: Hash[String, String]
          @problems = [] #: Array[Mistake]
        end

        def call
          data = parse
          case data
          when Hash then convert(data)
          else raise Mistake.new("holds #{JSON.generate(data)}, and it takes one object in braces", file: @file)
          end
        end

        private

        def convert(data)
          refuse_unknown(data, KEYS, "ng-nudge reads only these keys")
          @changes << "drop $schema, which CrossLint doesn't read" if data.key?("$schema")
          src_dir = attempt { location(data, "srcDir", "src-dir", "src") } || "src"
          tsconfig = attempt { location(data, "tsConfig", "tsconfig", "tsconfig.json") } || "tsconfig.json"
          angular = [folder("src-dir", src_dir, "src"), folder("tsconfig", tsconfig, "tsconfig.json"), *roles(data)].compact
          policies, report = rules(data)
          options = options(data)
          raise Mistakes.of(@problems) unless @problems.empty?

          plugins = [plugin("angular", angular), plugin("debt", [report&.setting].compact)]
          Result.new(configuration: Configuration.new(file: FILE, plugins:, policies:, warnings: options["warnings"]&.to_sym, verbosity: options["verbosity"]&.to_sym),
            changes: @changes, matching: report&.matching, src_dir:, roles: found_roles)
        end

        def mistake(key, message) = Mistake.new("#{key}: #{message}", file: @file)

        def refuse(key, message) = raise(mistake(key, message))

        # Keeps a mistake to list with the others, and goes on.
        def problem(key, message) = @problems << mistake(key, message)

        # What the block gives, or nil after keeping the Mistake it
        # raised, so that every mistake in the file is found before the
        # conversion stops.
        def attempt
          yield
        rescue Mistake => mistake
          @problems << mistake
          nil
        end

        def parse
          JSON.parse(@text)
        rescue JSON::ParserError => error
          raise Mistake.new("isn't valid JSON; fix it, as ng-nudge's schema says: #{error.message}", file: @file)
        end

        # Keeps a mistake for each key of `given` that isn't one of
        # `known`, with the nearest spelling.
        def refuse_unknown(given, known, why, within: nil)
          (given.keys - known).each do |key|
            problem([within, key].compact.join("."), "#{Spelling.unknown('key', key, known)}; #{why}, so remove it")
          end
        end

        def object(value, key)
          case value
          when Hash then value
          else refuse(key, "is #{JSON.generate(value)}, and it takes an object in braces")
          end
        end

        def string(value, key, what)
          case value
          when String then value
          else refuse(key, "is #{JSON.generate(value)}, and it takes #{what}")
          end
        end

        def plugin(name, settings) = ListedPlugin.new(name:, ref: nil, settings:, line: LINE)

        def setting(name, arguments, properties = {}, children = []) = Setting.new(name:, arguments:, properties:, children:, line: LINE)

        # srcDir or tsConfig: a path in the project, cleaned up, as src-dir
        # or tsconfig, and left out when it is the default. ng-nudge reads
        # an empty one as the default.
        def location(data, key, name, default)
          path = string(data.fetch(key, ""), key, "a path as a string, such as #{default.dump}")
          return default if path.empty?

          outside = "is #{path.dump}, which is outside the project; write a path inside it, relative to the project's root"
          refuse(key, "is #{path.dump}, which has a \\ or a brace; CrossLint reads neither, so write / between folders and no brace") if path.match?(/[\\{}]/)
          refuse(key, outside) if path.start_with?("/") || path.match?(/\A[A-Za-z]:/)

          cleaned = clean(path) || refuse(key, outside)
          refuse(key, "is #{path.dump}, which is no file; write the path of the tsconfig.json to read") if cleaned.empty? && name == "tsconfig"
          @changes << "convert #{key} #{path.dump} to #{name} #{cleaned.dump}" unless cleaned == path || cleaned == default
          cleaned
        end

        # The setting for a folder, or nil when it is the default.
        def folder(name, location, default) = (setting(name, [location]) unless location == default)

        # `path` with each ./, //, trailing /, and x/.. taken out, or nil
        # when a .. leaves the folder the path starts in.
        def clean(path)
          kept = [] #: Array[String]
          inside = path.split("/").all? do |segment|
            case segment
            when "", "." then true
            when ".." then kept.pop
            else kept << segment
            end
          end
          kept.join("/") if inside
        end

        def roles(data)
          given = attempt { object(data.fetch("artifacts", NONE), "artifacts") } || NONE
          given.filter_map { |name, entry| role(name, entry) }
        end

        def role(name, entry)
          key = "artifacts.#{name}"
          given = attempt { object(entry, key) }
          return unless given

          problem(key, "has a role name with a character other than a letter, digit, - or _, which a CrossLint role can't have; rename it") unless name.match?(ROLE)
          refuse_unknown(given, %w[pattern expects], "ng-nudge reads only these", within: key)
          pattern = attempt { string(given.fetch("pattern", ""), "#{key}.pattern", "a glob pattern as a string") } || ""
          properties = {} #: Hash[String, untyped]
          converted = attempt { files("#{key}.pattern", pattern) } unless pattern.empty?
          properties["files"] = converted if converted
          @globs[name] = pattern.empty? ? "**/*.#{name}.ts" : pattern
          setting("role", [name], properties, given.slice("expects").filter_map { |_, value| attempt { expects("#{key}.expects", value) } })
        end

        # Each built-in role and each role the configuration adds or changes.
        def found_roles
          BUILT_IN.to_h { |role| [role, "**/*.#{role}.ts"] }.merge(@globs).map { |name, glob| Role.new(name:, glob:, files: Glob.convert(glob)) }
        end

        def files(key, pattern)
          converted = Glob.convert(pattern)
          @changes << "convert #{key} #{pattern.dump} to files #{converted.dump}" unless converted == pattern
          converted
        rescue Glob::Unsupported => error
          refuse(key, "is #{pattern.dump}, which " + error.message)
        end

        def expects(key, given)
          unless EXPECTS.include?(given)
            refuse(key, "is #{JSON.generate(given)}, and CrossLint's Angular plugin takes [] or [\"spec\"] only; in ng-nudge 0.3.0 any expects list turned the role's " \
              "checks off, so the setting never did what it says. Remove it, or write one of those")
          end
          setting("expects", given)
        end

        # The policy lines of the rules, and the report-entries setting the
        # debt rule's withComment gives.
        def rules(data)
          given = attempt { object(data.fetch("rules", NONE), "rules") } || NONE
          known = RULES + [DEBT_RULE]
          (given.keys - known).each { |unknown| problem("rules.#{unknown}", "#{Spelling.unknown('rule', unknown, known)}; ng-nudge has no other, so remove it") }
          report = nil #: Report?
          policies = given.filter_map do |name, rule|
            key = "rules.#{name}"
            next unless known.include?(name)

            body = attempt { object(rule, key) } || next
            body.slice("withComment").each_value do |with_comment|
              if name == DEBT_RULE
                report = attempt { report_entries("#{key}.withComment", with_comment) }
              else
                problem("#{key}.withComment", "is a setting of #{DEBT_RULE} only; remove it")
              end
            end
            policy(key, name, body)
          end
          [policies, report]
        end

        # The policy line for a rule's enabled and severity, or nil when it
        # changes nothing.
        def policy(key, name, body)
          refuse_unknown(body, %w[enabled severity withComment], "ng-nudge reads only these", within: key)
          enabled = body.fetch("enabled", true)
          enabled_ok = [true, false].include?(enabled)
          problem("#{key}.enabled", "is #{JSON.generate(enabled)}, and it takes true or false") unless enabled_ok
          severity = body.fetch("severity", nil)
          severity_ok = [nil, *SEVERITIES].include?(severity)
          problem("#{key}.severity", "is #{JSON.generate(severity)}, and it takes \"error\" or \"warning\"") unless severity_ok
          return if !enabled_ok || !severity_ok || (enabled && severity.nil?)

          PolicySetting.new(name: "#{(name == DEBT_RULE) ? 'debt' : 'angular'}/#{name}", enabled: (false unless enabled), severity: severity&.to_sym, line: LINE)
        end

        # What withComment says, as report-entries: ng-nudge reads it as a
        # ceiling on the severity of an entry that has a comment. Reporting
        # entries at all is the first thing it does, and a ceiling of
        # "error" changes no severity.
        def report_entries(key, given)
          case given
          when true then report("warning")
          when false then report("error")
          when String then report(ceiling(key, given))
          when Hash
            refuse_unknown(given, %w[maxSeverity matching], "ng-nudge reads only these", within: key)
            maximum = attempt do
              ceiling("#{key}.maxSeverity", given.fetch("maxSeverity") do
                refuse("#{key}.maxSeverity", "is missing, and withComment as an object takes it, as \"none\", \"warning\", or \"error\"")
              end)
            end
            expression = attempt { string(given.fetch("matching", ""), "#{key}.matching", "a JavaScript regular expression as a string") } || ""
            report(maximum || "error", attempt { matching_of(maximum, "#{key}.matching", expression) })
          else
            refuse(key, "is #{JSON.generate(given)}, and it takes true, false, \"none\", \"warning\", \"error\", or an object with maxSeverity and matching")
          end
        end

        def ceiling(key, given)
          return given if CEILINGS.include?(given)

          refuse(key, "is #{JSON.generate(given)}, and it takes \"none\", \"warning\", or \"error\"")
        end

        # The report-entries setting for a ceiling, with the translation of
        # the expression, which `key` names, as its matching= unless the
        # ceiling is "error", which any expression leaves as it is.
        def report(ceiling, matching = nil)
          properties = {} #: Hash[String, String]
          properties["commented"] = ceiling unless ceiling == "error"
          properties["matching"] = matching.translated if matching
          Report.new(setting: setting("report-entries", [], properties), matching:)
        end

        # The translation of the expression, which `key` names, or nil when
        # there is none, or the ceiling is "error", which any expression
        # leaves as it is.
        def matching_of(ceiling, key, expression)
          return if expression.empty?

          if ceiling == "error"
            @changes << "drop #{key}, which changes nothing with a maxSeverity of \"error\""
            return
          end
          translate(key, expression)
        end

        def translate(key, expression)
          translated = Expression.translate(expression)
          @changes << "convert #{key} #{expression.dump} to matching #{translated.dump}" unless translated == expression
          Matching.new(key:, source: expression, translated:)
        rescue Expression::Unsupported => error
          refuse(key, "is #{expression.dump}, which #{error.message}; write it another way, or remove it")
        end

        def options(data)
          options = attempt { object(data.fetch("options", NONE), "options") } || NONE
          refuse_unknown(options, OPTIONS.keys, "ng-nudge reads only these", within: "options")
          options.slice(*OPTIONS.keys).each do |name, value|
            choices = OPTIONS.fetch(name)
            problem("options.#{name}", "is #{JSON.generate(value)}, and it takes #{Spelling.list(choices.map(&:dump))}") unless choices.include?(value)
          end
        end
      end
    end
  end
end
