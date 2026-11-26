# frozen_string_literal: true

require "json"
require_relative "../configuration"
require_relative "../mistake"
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
        # The configuration, the changes to list, and the `matching`, or
        # nil.
        class Result < Data.define(:configuration, :changes, :matching); end

        # A `report-entries` setting, and the matching it holds, or nil.
        class Report < Data.define(:setting, :matching); end

        FILE = ".config/crosslint/config.kdl"

        KEYS = %w[$schema srcDir tsConfig artifacts rules options].freeze

        RULES = %w[spec-exists stub-exists interface-exists stub-matches-component interface-matches-component prefer-css-over-scss].freeze

        DEBT_RULE = "has-debt"

        SEVERITIES = %w[error warning].freeze

        CEILINGS = %w[none warning error].freeze

        OPTIONS = {"warnings" => %w[all none error], "verbosity" => %w[normal quiet silent]}.freeze

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
          angular = [folder(data, "srcDir", "src-dir", "src"), folder(data, "tsConfig", "tsconfig", "tsconfig.json"), *roles(data)].compact
          policies, report = rules(data)
          options = options(data)
          plugins = [plugin("angular", angular), plugin("debt", [report&.setting].compact)]
          Result.new(configuration: Configuration.new(file: FILE, plugins:, policies:, warnings: options["warnings"]&.to_sym, verbosity: options["verbosity"]&.to_sym),
            changes: @changes, matching: report&.matching)
        end

        def refuse(key, message) = raise(Mistake.new("#{key}: #{message}", file: @file))

        def parse
          JSON.parse(@text)
        rescue JSON::ParserError => error
          raise Mistake.new("isn't valid JSON; fix it, as ng-nudge's schema says: " + error.message, file: @file)
        end

        # Refuses the first key of `given` that isn't one of `known`, with
        # the nearest spelling.
        def refuse_unknown(given, known, why, within: nil)
          key = (given.keys - known).first
          return unless key

          refuse([within, key].compact.join("."), "#{Spelling.unknown("key", key, known)}; #{why}, so remove it")
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
        def folder(data, key, name, default)
          path = string(data.fetch(key, ""), key, "a path as a string, such as #{default.dump}")
          return if path.empty?

          outside = "is #{path.dump}, which is outside the project; write a path inside it, relative to the project's root"
          refuse(key, "is #{path.dump}, which has a \\ or a brace; CrossLint reads neither, so write / between folders and no brace") if path.match?(/[\\{}]/)
          refuse(key, outside) if path.start_with?("/") || path.match?(/\A[A-Za-z]:/)

          cleaned = clean(path) || refuse(key, outside)
          refuse(key, "is #{path.dump}, which is no file; write the path of the tsconfig.json to read") if cleaned.empty? && name == "tsconfig"
          return if cleaned == default

          @changes << "convert #{key} #{path.dump} to #{name} #{cleaned.dump}" unless cleaned == path
          setting(name, [cleaned])
        end

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
          object(data.fetch("artifacts", NONE), "artifacts").map { |name, given| role(name, object(given, "artifacts.#{name}")) }
        end

        def role(name, given)
          key = "artifacts.#{name}"
          refuse(key, "has a role name with a character other than a letter, digit, - or _, which a CrossLint role can't have; rename it") unless name.match?(ROLE)
          refuse_unknown(given, %w[pattern expects], "ng-nudge reads only these", within: key)
          pattern = string(given.fetch("pattern", ""), "#{key}.pattern", "a glob pattern as a string")
          properties = pattern.empty? ? {} : {"files" => files("#{key}.pattern", pattern)} #: Hash[String, untyped]
          setting("role", [name], properties, given.slice("expects").map { |_, value| expects("#{key}.expects", value) })
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
          given = object(data.fetch("rules", NONE), "rules")
          unknown = (given.keys - RULES - [DEBT_RULE]).first
          refuse("rules.#{unknown}", "#{Spelling.unknown("rule", unknown, RULES + [DEBT_RULE])}; ng-nudge has no other, so remove it") if unknown
          report = nil #: Report?
          policies = given.filter_map do |name, rule|
            key = "rules.#{name}"
            body = object(rule, key)
            body.slice("withComment").each_value do |with_comment|
              refuse("#{key}.withComment", "is a setting of #{DEBT_RULE} only; remove it") unless name == DEBT_RULE
              report = report_entries("#{key}.withComment", with_comment)
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
          refuse("#{key}.enabled", "is #{JSON.generate(enabled)}, and it takes true or false") unless [true, false].include?(enabled)
          severity = body.fetch("severity", nil)
          refuse("#{key}.severity", "is #{JSON.generate(severity)}, and it takes \"error\" or \"warning\"") unless [nil, *SEVERITIES].include?(severity)
          return if enabled && severity.nil?

          PolicySetting.new(name: "#{(name == DEBT_RULE) ? "debt" : "angular"}/#{name}", enabled: (false unless enabled), severity: severity&.to_sym, line: LINE)
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
            maximum = given.fetch("maxSeverity") { refuse("#{key}.maxSeverity", "is missing, and withComment as an object takes it, as \"none\", \"warning\", or \"error\"") }
            expression = string(given.fetch("matching", ""), "#{key}.matching", "a JavaScript regular expression as a string")
            maximum = ceiling("#{key}.maxSeverity", maximum)
            report(maximum, matching_of(maximum, "#{key}.matching", expression))
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
          refuse(key, "is #{expression.dump}, which " + error.message + "; write it another way, or remove it")
        end

        def options(data)
          options = object(data.fetch("options", NONE), "options")
          refuse_unknown(options, OPTIONS.keys, "ng-nudge reads only these", within: "options")
          options.each do |name, value|
            choices = OPTIONS.fetch(name)
            refuse("options.#{name}", "is #{JSON.generate(value)}, and it takes #{Spelling.list(choices.map(&:dump))}") unless choices.include?(value)
          end
        end
      end
    end
  end
end
