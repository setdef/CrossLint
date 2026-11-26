# frozen_string_literal: true

require_relative "../core"

module CrossLint
  module Adapters
    class MemoryDebtFiles
      HEADER = "Rule\tArtifact\tComment"

      def initialize(files = {})
        @files = files
      end

      def read(root, path)
        held = @files.fetch(File.join(root, path)) { Core::DebtFile.new(file: path, entries: [], header: nil) }
        raise held if held.instance_of?(Core::Mistake)

        held
      end

      def exist?(root, path) = @files.key?(File.join(root, path))

      def move(root, from, to)
        held = @files.delete(File.join(root, from)) || raise(Core::Mistake.new("doesn't exist", file: from))
        # A file that can't be read moves as it is, as bytes do.
        @files[File.join(root, to)] = held.instance_of?(Core::Mistake) ? held : held.with(file: to)
      end

      # Holds each entry as the file would have it once read: on the line
      # it would start on, with a source.
      def write(root, path, debt)
        entries = debt.entries.each_with_index.map do |entry, index|
          entry.with(line: index + 2, source: entry.source || [entry.rule, entry.artifact, entry.comment, entry.detail].join("\t"))
        end
        @files[File.join(root, path)] = debt.with(file: path, entries:, header: debt.header || HEADER)
      end
    end
  end
end
