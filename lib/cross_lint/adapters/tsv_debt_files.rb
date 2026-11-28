# frozen_string_literal: true

require "fileutils"
require_relative "replace_file"
require_relative "../core"

module CrossLint
  module Adapters
    class TSVDebtFiles
      COLUMNS = %w[Rule Artifact Comment].freeze

      DETAIL = "Detail"

      QUOTE = 34

      NEWLINE = 10

      RETURN = 13

      TAB = 9

      # Each of these makes d3-dsv quote a field when it writes one.
      QUOTED = /["\t\n\r]/

      def read(root, path)
        full = File.join(root, path)
        return empty(path) unless File.file?(full)

        data = File.binread(full)
        raise Core::Mistake.new("isn't valid UTF-8", file: path) unless data.dup.force_encoding(Encoding::UTF_8).valid_encoding?

        records = records(data, path)
        # An empty file, and the single newline ng-nudge writes for one,
        # read as one empty field.
        return empty(path) if records == [[[""], 0, 1]]

        columns = header_columns(records.first, path)
        ends = records.drop(1).map { |record| record.fetch(1) } + [data.bytesize]
        entries = records.drop(1).each_with_index.map do |(fields, start, line), index|
          entry(fields, columns, line, slice(data, start, ends.fetch(index + 1)), path)
        end
        Core::DebtFile.new(file: path, entries:, header: slice(data, 0, ends.fetch(0)))
      end

      def write(root, path, debt)
        full = File.join(root, path)
        FileUtils.mkdir_p(File.dirname(full))
        replace(full, path, contents(debt))
      end

      def exist?(root, path) = File.file?(File.join(root, path))

      def move(root, from, to)
        source = File.join(root, from)
        raise Core::Mistake.new("doesn't exist", file: from) unless File.file?(source)

        target = File.join(root, to)
        FileUtils.mkdir_p(File.dirname(target))
        replace(target, to, File.binread(source))
        File.delete(source)
      rescue SystemCallError => error
        raise Core::Mistake.new("couldn't be removed once it was written to #{to}: " + error.message, file: from)
      end

      private

      def empty(path) = Core::DebtFile.new(file: path, entries: [], header: nil)

      # Every header read has the columns COLUMNS has, with Detail after
      # them or not.
      def contents(debt)
        header = debt.header
        detail = debt.entries.any?(&:detail) || header.to_s.include?(DETAIL)
        ending = (header && ending(header)) || "\n"
        header = (detail ? COLUMNS + [DETAIL] : COLUMNS).join("\t") if header.nil? || (detail && !header.include?(DETAIL))
        rows = debt.entries.map do |entry|
          source = entry.source
          next ended(source, ending) if source

          fields = [entry.rule, entry.artifact, entry.comment] #: Array[String]
          fields << entry.detail.to_s if detail
          fields.map { |field| field.match?(QUOTED) ? %("#{field.gsub('"', '""')}") : field }.join("\t") + ending
        end
        ended(header, ending) + rows.join
      end

      def ending(line) = ["\r\n", "\n", "\r"].find { |each| line.end_with?(each) }

      def ended(line, ending) = ending(line) ? line : line + ending

      # Windows refuses to rename over a file another program has open, and
      # the file is left as it was.
      def replace(full, path, contents)
        ReplaceFile.call(full, contents)
      rescue Errno::EACCES
        raise Core::Mistake.new("couldn't be replaced, since permission was denied; close any program that has it open, and run again",
          file: path)
      end

      def header_columns(record, path)
        columns = record.first
        return columns if [COLUMNS, [*COLUMNS, DETAIL]].include?(columns)

        raise Core::Mistake.new("has the columns #{columns.map(&:dump).join(', ')} in its header, " \
          "where CrossLint reads \"Rule\", \"Artifact\", \"Comment\", and an optional \"Detail\"", file: path, line: 1)
      end

      def entry(fields, columns, line, source, path)
        if fields.size > columns.size
          raise Core::Mistake.new("has #{fields.size} fields, where the header has #{columns.size} columns", file: path, line:)
        end

        rule = fields.fetch(0)
        artifact = fields.fetch(1, "")
        detail = fields.fetch(3, "")
        raise Core::Mistake.new("has an entry with no rule", file: path, line:) if rule.empty?
        raise Core::Mistake.new("has an entry with no artifact", file: path, line:) if artifact.empty?

        Core::DebtEntry.new(rule:, artifact:, comment: fields.fetch(2, ""), detail: (detail unless detail.empty?), line:, source:)
      end

      def slice(data, from, to)
        bytes = data.byteslice(from, to - from) #: String
        bytes.force_encoding(Encoding::UTF_8)
      end

      # The records of `data`, read as d3-dsv reads tab-separated values:
      # each as its fields, the offset it starts at, and the line it starts
      # on. Fields end at a tab, and records at "\n", "\r\n", or "\r"; a
      # field that starts with a quote ends at the next quote not doubled,
      # and holds what is between, with each doubled quote as one. One line
      # ending at the end is no record, and empty data is one empty field.
      #
      # From `stop` on, the data holds only the line ending removed from its
      # end, so no tab or quote is found there, and a field that ends at
      # `stop` ends the data.
      def records(data, path)
        stop = data.bytesize
        stop -= 1 if data.getbyte(stop - 1) == NEWLINE
        stop -= 1 if data.getbyte(stop - 1) == RETURN
        records = [] #: Array[[Array[String], Integer, Integer]]
        at = 0
        line = 1
        loop do
          start = at
          fields = [] #: Array[String]
          loop do
            value, at = field(data, at, stop, path, line)
            fields << value
            break unless data.getbyte(at) == TAB

            at += 1
          end
          records << [fields, start, line]
          break if at == stop

          at += (data.getbyte(at) == RETURN && data.getbyte(at + 1) == NEWLINE) ? 2 : 1
          line += breaks(slice(data, start, at))
        end
        records
      end

      def breaks(bytes) = bytes.count("\n") + bytes.count("\r") - bytes.scan("\r\n").size

      # The field at `at`, and where the tab or line ending after it is, or
      # `stop`.
      def field(data, at, stop, path, line)
        return quoted(data, at, stop, path, line) if data.getbyte(at) == QUOTE

        found = data.index(/[\t\n\r]/n, at) || stop
        [slice(data, at, found), found]
      end

      def quoted(data, at, stop, path, line)
        close = at
        loop do
          close = data.index('"', close + 1) || raise(Core::Mistake.new("has a quote that doesn't end", file: path, line:))
          break unless data.getbyte(close + 1) == QUOTE

          close += 1
        end
        unless close + 1 == stop || [TAB, NEWLINE, RETURN].include?(data.getbyte(close + 1))
          raise Core::Mistake.new("has text after a closing quote", file: path, line:)
        end

        [slice(data, at + 1, close).gsub('""', '"'), close + 1]
      end
    end
  end
end
