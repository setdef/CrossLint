# frozen_string_literal: true

require_relative "../path_pattern"

module CrossLint
  module Core
    module NgNudge
      # What node-glob finds for a role's pattern, and what the Angular
      # plugin finds with the path pattern it was converted to, compared:
      # each file only one of them finds is a line to say. node-glob and
      # CrossLint differ in ways that aren't about the pattern: node-glob
      # ignores case on macOS and Windows, returns folders, finds files
      # Git ignores, and follows a symlinked folder.
      class Differences
        # The paths, relative to `src_dir`, of the `files` of the project
        # the Angular plugin finds for the path pattern `pattern`, which is
        # relative to `src_dir`: a file below a folder or a name that starts
        # with a dot is skipped where a placeholder matches it.
        def self.found(files, src_dir, pattern)
          prefix = src_dir.empty? ? "" : "#{src_dir}/"
          path_pattern = PathPattern.new(source: pattern)
          files.filter_map do |file|
            next unless file.start_with?(prefix)

            relative = file.delete_prefix(prefix)
            captured = path_pattern.match(relative)
            next unless captured
            next if captured.values.any? { |value| value.split("/").any? { |segment| segment.start_with?(".") } }

            relative
          end
        end

        def initialize(role:, src_dir:)
          @role = role
          @src_dir = src_dir
        end

        # A line for each file only one of the two finds, node-glob's first,
        # each in the order of its path.
        def lines(glob_found, crosslint_found)
          (glob_found - crosslint_found).sort.map { |path| "node-glob finds #{named(path)} as a #{@role}, and CrossLint doesn't" } +
            (crosslint_found - glob_found).sort.map { |path| "CrossLint finds #{named(path)} as a #{@role}, and node-glob doesn't" }
        end

        private

        # The path, relative to the project's root.
        def named(path) = [@src_dir, path].reject(&:empty?).join("/")
      end
    end
  end
end
