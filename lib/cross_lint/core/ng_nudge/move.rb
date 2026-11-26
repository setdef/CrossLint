# frozen_string_literal: true

require_relative "../javascript_error"
require_relative "../mistake"
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

        # What node-glob does that CrossLint doesn't, which is why a file
        # can be found by one and not the other.
        WHY = "node-glob also returns folders, ignores case on macOS and Windows, finds files Git ignores, and follows a symlinked folder, which CrossLint doesn't"

        def initialize(configuration:, ng_nudge:, debt_files:, javascript:, project_files:)
          @configuration = configuration
          @ng_nudge = ng_nudge
          @debt_files = debt_files
          @javascript = javascript
          @project_files = project_files
        end

        def call(root, force: false, dry_run: false, planned: nil)
          replaced = @configuration.exist?(root)
          refuse_existing(@configuration.file, "the configuration") if replaced && !force
          text = @ng_nudge.settings(root) || raise(Mistake.new("doesn't exist; crosslint init --from-ng-nudge moves a project that has it, " \
            "and crosslint init writes a configuration for any other", file: SETTINGS_FILE))
          converted = Rc.new(text).call
          paths = @ng_nudge.extensions(root)
          refuse_code(paths)
          debt = @debt_files.read(root, DEBT_FILE)
          moves = @debt_files.exist?(root, DEBT_FILE)
          refuse_existing(TrackDebt::FILE, "the debt file") if moves && !force && @debt_files.exist?(root, TrackDebt::FILE)
          agree(converted.matching, debt) if converted.matching
          changes = [*moved(replaced, converted, moves, debt), *converted.changes, *paths.map { |path| "leave #{path}, which ng-nudge never ran" }]
          notes = compare(root, converted)
          planned&.call(changes, notes)
          unless dry_run
            @configuration.write(root, converted.configuration)
            @debt_files.move(root, DEBT_FILE, TrackDebt::FILE) if moves
          end
          MoveResult.new(changes:, notes:, dry_run:)
        end

        private

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
          ["couldn't compare the files node-glob finds with the files CrossLint finds: " + error.message]
        end

        def refuse_existing(file, what)
          raise Mistake.new("already exists, and crosslint init --from-ng-nudge changes nothing in #{what}; crosslint init --from-ng-nudge --force replaces it", file:)
        end

        # A file of artifacts or policies is loaded by ng-nudge to change what it checks, and
        # CrossLint carries no code of ng-nudge's.
        def refuse_code(paths)
          path = paths.find { |each| !each.include?("/rules/") }
          return unless path

          raise Mistake.new("is a file ng-nudge loads to change what it checks, which CrossLint can't run; declare the same check in a local plugin " \
            "(docs/reference/plugin.md), then move the file out of .config/ng-nudge", file: path)
        end

        def moved(replaced, converted, moves, debt)
          plugins = converted.configuration.plugins.map(&:name)
          lines = ["#{replaced ? "replace" : "write"} #{@configuration.file}, with the plugins #{plugins.join(" and ")}"]
          return lines unless moves

          entries = debt.entries.size
          lines << "move #{DEBT_FILE} to #{TrackDebt::FILE}, byte for byte, with #{entries} #{(entries == 1) ? "entry" : "entries"}"
        end

        # ng-nudge tests `withComment.matching` on each comment with
        # JavaScript, and CrossLint with the translation, so the two are
        # tested on each comment the debt file has: the translation is
        # trusted only where they agree.
        def agree(matching, debt)
          entries = debt.entries.reject { |entry| entry.comment.empty? }.uniq(&:comment)
          return if entries.empty?

          ruby = Regexp.new(matching.translated)
          answers = @javascript.matches(matching.source, entries.map(&:comment))
          entry, javascript = entries.zip(answers).reject { |each, answer| ruby.match?(each.comment) == answer }.first
          return unless entry

          raise Mistake.new("#{matching.key}: JavaScript #{javascript ? "matches" : "doesn't match"} the comment #{entry.comment.dump} " \
            "of line #{entry.line} of the debt file, and its translation, #{matching.translated.dump}, #{javascript ? "doesn't" : "does"}; " \
            "write the expression another way, or remove it", file: SETTINGS_FILE)
        rescue JavaScriptError => error
          raise Mistake.new("#{matching.key}: CrossLint tests the expression, #{matching.source.dump}, with JavaScript on each comment of the debt file, " \
            "and " + error.message, file: SETTINGS_FILE)
        end
      end
    end
  end
end
