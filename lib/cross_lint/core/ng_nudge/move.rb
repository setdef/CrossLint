# frozen_string_literal: true

require_relative "../javascript_error"
require_relative "../mistake"
require_relative "../mistakes"
require_relative "../track_debt"
require_relative "differences"
require_relative "files"
require_relative "rc"

module CrossLint
  module Core
    module NgNudge
      # What `crosslint init --from-ng-nudge` did, or would do: each change,
      # as a verb and what it acts on, and each note: a file that node-glob
      # and CrossLint would find differently, or why they weren't compared.
      class MoveResult < Data.define(:changes, :notes, :dry_run); end

      # Moves a project from ng-nudge: writes the configuration its rc.json
      # converts to, and moves its debt file. Every key is checked, and each
      # change listed to `planned`, before the first one is made.
      class Move
        # The folders, relative to the project's root, that the glob
        # package ng-nudge finds its files with is looked for from: ng-nudge's
        # own, and then the project's.
        PACKAGES = ["node_modules/@overthetopmarketing/ng-nudge", ""].freeze

        # What a project with no rc.json is moved as if it held.
        EMPTY = "{}"

        # What node-glob does that CrossLint doesn't, which is why a file
        # can be found by one and not the other.
        WHY = "node-glob also returns folders, ignores case on macOS and Windows, finds files Git ignores, and follows a symlinked folder, which CrossLint doesn't"

        def initialize(configuration:, ng_nudge:, debt_files:, javascript:, project_files:, debug: nil)
          @debug = debug
          @configuration = configuration
          @ng_nudge = ng_nudge
          @debt_files = debt_files
          @javascript = javascript
          @project_files = project_files
        end

        def call(root, force: false, dry_run: false, planned: nil)
          problems = [] #: Array[Mistake]
          replaced = @configuration.exist?(root)
          attempt(problems) { refuse_existing(@configuration.file, "the configuration") } if replaced && !force
          text = @ng_nudge.settings(root)
          found = attempt(problems) { Rc.new(text || EMPTY).call }
          paths = @ng_nudge.extensions(root)
          problems.concat(code_files(paths))
          read = attempt(problems) { @debt_files.read(root, DEBT_FILE) }
          moves = @debt_files.exist?(root, DEBT_FILE)
          replaces = moves && @debt_files.exist?(root, TrackDebt::FILE)
          attempt(problems) { refuse_existing(TrackDebt::FILE, "the debt file") } if replaces && !force
          matching = found&.matching
          attempt(problems) { agree(matching, read) } if matching
          @debug&.write("read") { [settings_read(text, paths), debt_read(read, moves, replaces), existence(@configuration.file, replaced)].join("\n") }
          raise Mistakes.of(problems) unless problems.empty?

          converted = found #: Rc::Result
          debt = read #: DebtFile
          files = moved(replaced, converted, moves, debt, replaces)
          carried = settings(converted.configuration)
          said(converted, files, carried, dry_run)
          changes = [*assumed(text), *files, *converted.changes, *carried, *paths.map { |path| "leave #{path}, which ng-nudge never ran" }]
          notes = compare(root, converted)
          planned&.call(changes, notes)
          unless dry_run
            @configuration.write(root, converted.configuration)
            @debt_files.move(root, DEBT_FILE, TrackDebt::FILE) if moves
          end
          MoveResult.new(changes:, notes:, dry_run:)
        end

        private

        # What the debug output says of each setting the converted
        # configuration carries, and of each file it writes or moves.
        def said(converted, files, carried, dry_run)
          tense = dry_run ? "would" : "will"
          @debug&.write("setting") do
            [*converted.changes.map { |change| "from #{SETTINGS_FILE}: #{change}" }, *carried.map { |line| "into #{@configuration.file}: #{line}" }].join("\n")
          end
          @debug&.write("write") { files.map { |line| "#{tense} #{line}" }.join("\n") }
        end

        def settings_read(text, paths)
          rc = text ? existence(SETTINGS_FILE, true) : "#{SETTINGS_FILE}: isn't there, so it is read as #{EMPTY}"
          [rc, *paths.map { |path| "#{path}: is a file ng-nudge loads" }].join("\n")
        end

        def debt_read(debt, moves, replaces)
          lines = [moves ? "#{existence(DEBT_FILE, true)}#{", with #{entries(debt)}" if debt}" : existence(DEBT_FILE, false)]
          lines << existence(TrackDebt::FILE, true) if replaces
          lines.join("\n")
        end

        def existence(file, there) = "#{file}: #{there ? 'is there' : "isn't there"}"

        def entries(debt) = "#{debt.entries.size} #{(debt.entries.size == 1) ? 'entry' : 'entries'}"

        # The line that says a project with no rc.json is moved as if it
        # held {}, or none when it has one.
        def assumed(text)
          return [] if text

          ["treat #{SETTINGS_FILE}, which isn't there, as #{EMPTY}, since ng-nudge then runs on its defaults"]
        end

        # The files the project's own glob finds for each role's pattern,
        # and the files CrossLint finds for the pattern it was converted
        # to, compared: a line for each file only one of them finds. It
        # refuses nothing: it says why when it can't compare.
        def compare(root, converted)
          src_dir = converted.src_dir
          found = @javascript.glob(root, src_dir, converted.roles.map(&:glob).uniq, PACKAGES)
          return ["couldn't compare the files node-glob finds with the files CrossLint finds, since the project has no glob package"] unless found

          files = @project_files.files(root)
          lines = converted.roles.flat_map do |role|
            Differences.new(role: role.name, src_dir:).lines(found.fetch(role.glob), Differences.found(files, src_dir, role.files))
          end
          lines.empty? ? lines : [*lines, WHY]
        rescue JavaScriptError, Mistake => error
          ["couldn't compare the files node-glob finds with the files CrossLint finds: #{error.message}"]
        end

        def refuse_existing(file, what)
          raise Mistake.new("already exists, and crosslint init --from-ng-nudge changes nothing in #{what}; crosslint init --from-ng-nudge --force replaces it", file:)
        end

        # What the block gives, or nil after adding the Mistake or Mistakes
        # it raised to `problems`, so that every problem is found before the
        # move stops.
        def attempt(problems)
          yield
        rescue Mistakes => mistakes
          problems.concat(mistakes.all)
          nil
        rescue Mistake => mistake
          problems << mistake
          nil
        end

        # A mistake for each file of artifacts or policies, which ng-nudge
        # loads to change what it checks, and CrossLint carries no code of
        # ng-nudge's.
        def code_files(paths)
          paths.reject { |each| each.include?("/rules/") }.map do |path|
            Mistake.new("is a file ng-nudge loads to change what it checks, which CrossLint can't run; declare the same check in a local plugin " \
              "(docs/reference/plugin.md), then move the file out of .config/ng-nudge", file: path)
          end
        end

        # A line for each setting the configuration holds, in the order the
        # file holds them: the settings of each plugin, and of a role in it,
        # then the policy lines, then the modes.
        def settings(configuration)
          plugins = configuration.plugins.flat_map { |plugin| plugin.settings.flat_map { |each| setting_lines(each, "the #{plugin.name} plugin") } }
          policies = configuration.policies.map do |policy|
            properties = { "enabled" => policy.enabled, "severity" => policy.severity&.to_s }.compact
            ["set policy #{policy.name.dump}", *properties.map { |name, value| "#{name}=#{kdl(value)}" }].join(" ")
          end
          modes = { "warnings" => configuration.warnings, "verbosity" => configuration.verbosity }.filter_map { |name, mode| "set #{name} #{mode.to_s.dump}" if mode }
          [*plugins, *policies, *modes]
        end

        # The line for a setting, and for each setting inside it, saying
        # where it is.
        def setting_lines(setting, within)
          words = [setting.name, *setting.arguments.map { |each| kdl(each) }, *setting.properties.map { |name, value| "#{name}=#{kdl(value)}" }]
          inside = "#{setting.name} #{kdl(setting.arguments.first)} of #{within}"
          ["set #{words.join(' ')} in #{within}", *setting.children.flat_map { |child| setting_lines(child, inside) }]
        end

        # A value as KDL writes it: the only boolean the configuration
        # gets is #false.
        def kdl(value) = (value == false) ? "#false" : value.to_s.dump

        def moved(replaced, converted, moves, debt, replaces)
          plugins = converted.configuration.plugins.map(&:name)
          lines = ["#{replaced ? 'replace' : 'write'} #{@configuration.file}, with the plugins #{plugins.join(' and ')}"]
          return lines unless moves

          lines << "move #{DEBT_FILE} to #{TrackDebt::FILE}, byte for byte, with #{entries(debt)}#{', and replace the debt file that is there' if replaces}"
        end

        # ng-nudge compiles `withComment.matching` with JavaScript, which
        # can refuse what the translation reads, and tests it on each
        # comment with JavaScript, and CrossLint with the translation, so
        # the two are tested on each comment the debt file has, if it has
        # one: the translation is trusted only where they agree.
        def agree(matching, debt)
          entries = (debt&.entries || []).reject { |entry| entry.comment.empty? }.uniq(&:comment)
          ruby = Regexp.new(matching.translated)
          answers = @javascript.matches(matching.source, entries.map(&:comment))
          entry, javascript = entries.zip(answers).reject { |each, answer| ruby.match?(each.comment) == answer }.first
          return unless entry

          raise Mistake.new("#{matching.key}: JavaScript #{javascript ? 'matches' : "doesn't match"} the comment #{entry.comment.dump} " \
            "of line #{entry.line} of the debt file, and its translation, #{matching.translated.dump}, #{javascript ? "doesn't" : 'does'}; " \
            "write the expression another way, or remove it", file: SETTINGS_FILE)
        rescue InvalidExpression => error
          raise Mistake.new("#{matching.key}: is #{matching.source.dump}, which JavaScript refuses: #{error.message}; write it another way, or remove it", file: SETTINGS_FILE)
        rescue JavaScriptError => error
          raise Mistake.new("#{matching.key}: CrossLint tests the expression, #{matching.source.dump}, with JavaScript on each comment of the debt file, " \
            "and " + error.message, file: SETTINGS_FILE)
        end
      end
    end
  end
end
