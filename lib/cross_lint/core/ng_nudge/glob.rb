# frozen_string_literal: true

module CrossLint
  module Core
    module NgNudge
      # A node-glob pattern from ng-nudge's rc.json, as the path pattern that
      # finds the same files. A pattern is converted only in the forms
      # whose matches were compared with node-glob 11 and are the same:
      # anything else raises Unsupported, saying why.
      class Glob
        class Unsupported < ArgumentError; end

        # A character that makes a segment more than a name: a wildcard, a
        # class, a brace list, an extglob or a negation, or an escape.
        SPECIAL = /[*?\[\]{}()!\\]/

        def self.convert(source) = new(source).converted

        def initialize(source)
          @source = source
        end

        def converted
          refuse("starts at the root; write it relative to srcDir") if @source.start_with?("/") || @source.match?(/\A[A-Za-z]:/)
          refuse("ends with /, so it finds folders, and an artifact is a file") if @source.end_with?("/")

          segments = cleaned
          tail, names = tail(segments.pop || refuse("is empty"), segments)
          folders = segments.map { |segment| folder(segment) }
          refuse("has * in two places that CrossLint writes as {name}, which would have to match one text twice") if names + folders.count("{name}") > 1
          [*folders, tail].join("/")
        end

        private

        def refuse(message) = raise(Unsupported, message)

        # The segments with each ./ and // and `x/..` taken out.
        def cleaned
          @source.split("/").each_with_object([]) do |segment, kept|
            next if segment.empty? || segment == "."
            next kept << segment unless segment == ".."

            before = kept.last
            refuse("has .. that doesn't follow a folder name; write the path without it") if before.nil? || before.match?(SPECIAL)
            kept.pop
          end
        end

        # The path pattern for the last segment, and how many {name} it
        # has: a file name stays, `**/*S` is {path}S, and `*S` is {name}S,
        # for a suffix S that starts with . and ends with .ts. A `**` before
        # it is taken out of `segments`.
        def tail(last, segments)
          refuse("ends with **; write the files it finds, as in **/*.store.ts") if last == "**"
          unless last.include?("*")
            refuse("has ** before a file name; CrossLint reads ** only before *SUFFIX, as in **/*.store.ts") if segments.last == "**"
            reject_special(last)
            refuse("doesn't end in .ts") unless last.end_with?(".ts")
            return [last, 0]
          end

          refuse("has * in a file name; CrossLint reads * only at the start of the last segment, and as a whole folder name") unless last.start_with?("*")
          suffix = last.delete_prefix("*")
          reject_special(suffix)
          refuse("has a suffix, #{suffix.dump}, that doesn't start with .") unless suffix.start_with?(".")
          refuse("has a suffix, #{suffix.dump}, that doesn't end with .ts") unless suffix.end_with?(".ts")
          return ["{name}#{suffix}", 1] unless segments.last == "**"

          segments.pop
          ["{path}#{suffix}", 0]
        end

        # A folder: its name, or {name} for a whole name that is *.
        def folder(segment)
          return "{name}" if segment == "*"

          refuse("has ** that isn't right before a last segment of the form *SUFFIX, as in **/*.store.ts") if segment == "**"
          reject_special(segment)
          segment
        end

        def reject_special(segment)
          found = segment[SPECIAL]
          return unless found

          refuse("has a brace list; CrossLint's path patterns have none, so list a role for each file name") if ["{", "}"].include?(found)
          refuse("has #{found}, which CrossLint's path patterns don't have")
        end
      end
    end
  end
end
