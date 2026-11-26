# frozen_string_literal: true

require "test_helper"

class MemoryDebtFilesTest < Minitest::Test
  cover "CrossLint::Adapters::MemoryDebtFiles*"
  cover "CrossLint::Core::DebtEntry*"

  include CrossLint::Testing::DebtFilesContract

  def debt_root = File.expand_path("/app")

  def debt_files_port(broken: nil)
    held = {} #: Hash[String, CrossLint::Core::DebtFile | CrossLint::Core::Mistake]
    held[File.join(debt_root, broken)] = CrossLint::Core::Mistake.new("has an entry with no rule", file: broken, line: 3) if broken
    CrossLint::Adapters::MemoryDebtFiles.new(held)
  end

  def test_keeps_the_header_and_sources_it_is_given
    port = debt_files_port
    entry = CrossLint::Core::DebtEntry.new(rule: "r", artifact: "a", comment: "", detail: nil, line: 9, source: "as read")
    port.write(debt_root, "debt.tsv", CrossLint::Core::DebtFile.new(file: "other.tsv", entries: [entry], header: "kept"))
    read = port.read(debt_root, "debt.tsv")

    assert_equal ["debt.tsv", "kept", [[2, "as read"]]], [read.file, read.header, read.entries.map { |each| [each.line, each.source] }]
  end

  def test_gives_a_new_entry_the_fields_as_its_source
    port = CrossLint::Adapters::MemoryDebtFiles.new
    entry = CrossLint::Core::DebtEntry.fresh(rule: "r", artifact: "a", comment: "c", detail: "d")
    port.write(debt_root, "debt.tsv", CrossLint::Core::DebtFile.new(file: "debt.tsv", entries: [entry], header: nil))

    assert_equal [entry.with(line: 2, source: "r\ta\tc\td")], port.read(debt_root, "debt.tsv").entries
    assert_equal ["", nil, nil], CrossLint::Core::DebtEntry.fresh(rule: "r", artifact: "a").then { |fresh| [fresh.comment, fresh.line, fresh.source] }
  end
end

# The format is ng-nudge's: what ng-nudge 0.3.0's DebtFile and d3-dsv 3
# read and write (lib/config/debt-file.js), with the defects
# docs/design/debt.md lists left out.
class TSVDebtFilesTest < Minitest::Test
  cover "CrossLint::Adapters::TSVDebtFiles*"

  include CrossLint::Testing::DebtFilesContract

  Core = CrossLint::Core

  WINDOWS = RbConfig::CONFIG.fetch("host_os").match?(/mswin|mingw/)

  def setup
    @root = Dir.mktmpdir("crosslint")
  end

  def teardown
    FileUtils.rm_rf(@root)
  end

  def debt_root = @root

  def debt_files_port(broken: nil)
    write(@root, broken, "Rule\tArtifact\tComment\nok\ta\t\n\ta\t\n") if broken
    CrossLint::Adapters::TSVDebtFiles.new
  end

  def port = CrossLint::Adapters::TSVDebtFiles.new

  def file(text)
    write(@root, "debt.tsv", text)
    port.read(@root, "debt.tsv")
  end

  def fields(debt) = debt.entries.map { |entry| [entry.rule, entry.artifact, entry.comment, entry.detail, entry.line] }

  def rewrite(debt, added = [])
    port.write(@root, "debt.tsv", debt.with(entries: debt.entries + added))
    File.binread(File.join(@root, "debt.tsv"))
  end

  def fresh(artifact, **fields) = Core::DebtEntry.fresh(rule: "tests/has-test", artifact:, **fields)

  # Records each File.rename while the block runs, and renames as usual.
  # With :crosslint_rename_denied set, each rename is denied as Windows
  # denies one over a file another program has open.
  module Renames
    def rename(from, to)
      Thread.current[:crosslint_renames]&.push([from, to])
      raise Errno::EACCES, "#{from}, #{to}" if Thread.current[:crosslint_rename_denied]

      super
    end
  end
  File.singleton_class.prepend(Renames)

  def renamed
    Thread.current[:crosslint_renames] = []
    yield
    Thread.current[:crosslint_renames]
  ensure
    Thread.current[:crosslint_renames] = nil
  end

  def test_reads_a_file_ng_nudge_wrote
    debt = file("Rule\tArtifact\tComment\nspec-exists\tapp/card\tlegacy\nstub-exists\tapp/list\t\n")

    assert_equal [["spec-exists", "app/card", "legacy", nil, 2], ["stub-exists", "app/list", "", nil, 3]], fields(debt)
    assert_equal ["Rule\tArtifact\tComment\n", "spec-exists\tapp/card\tlegacy\n"], [debt.header, debt.entries.first.source]
  end

  def test_reads_quoted_fields_as_d3_dsv_does
    debt = file(%(Rule\tArtifact\tComment\tDetail\n"r"\t"a ""b"""\t"two\nlines\tand a tab"\t""\nr\ta\t\t"d"\n))

    assert_equal [["r", %(a "b"), "two\nlines\tand a tab", nil, 2], ["r", "a", "", "d", 4]], fields(debt)
  end

  def test_reads_crlf_line_endings_and_a_last_line_with_no_ending
    debt = file("Rule\tArtifact\tComment\r\nr\ta\tc\r\nr\tb\t\"x\"\r\nr\tc")

    assert_equal [["r", "a", "c", nil, 2], ["r", "b", "x", nil, 3], ["r", "c", "", nil, 4]], fields(debt)
    assert_equal ["r\ta\tc\r\n", "r\tc"], [debt.entries.first.source, debt.entries.last.source]
  end

  def test_reads_and_writes_a_carriage_return_alone_as_a_line_ending
    debt = file("Rule\tArtifact\tComment\rr\ta\tc\rr\tb")

    assert_equal [["r", "a", "c", nil, 2], ["r", "b", "", nil, 3]], fields(debt)
    assert_equal "Rule\tArtifact\tComment\rr\ta\tc\rr\tb\rtests/has-test\tlib/a.rb\t\r", rewrite(debt, [fresh("lib/a.rb")])
  end

  def test_reads_an_empty_file_and_the_single_newline_ng_nudge_writes_for_one_as_having_no_header
    ["", "\n", "\r\n"].each do |text|
      assert_equal ["debt.tsv", [], nil], file(text).then { |debt| [debt.file, debt.entries, debt.header] }, text.dump
    end
  end

  def test_reads_text_that_isnt_ascii_in_every_kind_of_field
    debt = file(%(Rule\tArtifact\tComment\n"ré"\taé\t"cé"\nr\ta\tcafé))

    assert_equal [["ré", "aé", "cé", nil, 2], ["r", "a", "café", nil, 3]], fields(debt)
    assert_equal %("ré"\taé\t"cé"\n), debt.entries.first.source
  end

  def test_keeps_a_header_whose_columns_are_quoted
    debt = file(%("Rule"\tArtifact\tComment\nr\ta\t\n))

    assert_equal %("Rule"\tArtifact\tComment\nr\ta\t\ntests/has-test\tlib/a.rb\t\n), rewrite(debt, [fresh("lib/a.rb")])
    assert_equal "Rule\tArtifact\tComment\tDetail\nr\ta\t\ntests/has-test\tlib/a.rb\t\td\n", rewrite(debt, [fresh("lib/a.rb", detail: "d")])
    assert_equal %("Rule"\tArtifact\tComment\t"Detail"\ntests/has-test\tlib/a.rb\t\td\n),
      rewrite(file(%("Rule"\tArtifact\tComment\t"Detail"\n)), [fresh("lib/a.rb", detail: "d")])
  end

  def test_reads_a_quoted_field_at_the_very_end
    assert_equal [["r", "a", "é", nil, 2]], fields(file(%(Rule\tArtifact\tComment\nr\ta\t"é")))
  end

  def test_stops_at_an_empty_line_before_the_last_line_ending
    mistake = assert_raises(Core::Mistake) { file("Rule\tArtifact\tComment\nr\ta\t\n\n") }

    assert_equal ["debt.tsv:3", "has an entry with no rule"], [mistake.location, mistake.message]
  end

  def test_writes_beside_the_file_and_renames_it_into_place
    renames = renamed { port.write(@root, "debt.tsv", Core::DebtFile.new(file: "debt.tsv", entries: [], header: nil)) }

    assert_equal [File.join(@root, "debt.tsv")], renames.map(&:last)
    assert_equal [@root], renames.map { |from, _| File.dirname(from) }
    refute_equal "debt.tsv", File.basename(renames.first.first)
  end

  def test_reads_a_file_with_only_its_header
    debt = file("Rule\tArtifact\tComment")

    assert_equal [[], "Rule\tArtifact\tComment"], [debt.entries, debt.header]
  end

  def test_reads_a_short_row_with_empty_fields_for_the_rest
    assert_equal [["r", "a", "", nil, 2]], fields(file("Rule\tArtifact\tComment\tDetail\nr\ta\n"))
  end

  def test_reads_a_key_with_backslashes_as_it_is
    assert_equal ["app\\card"], file("Rule\tArtifact\tComment\nr\tapp\\card\t\n").entries.map(&:artifact)
  end

  def test_stops_at_an_entry_with_no_rule_or_no_artifact_naming_the_file_and_line
    {"\ta\tc" => "has an entry with no rule", "r\t\tc" => "has an entry with no artifact", "" => "has an entry with no rule",
     "r" => "has an entry with no artifact"}.each do |row, message|
      mistake = assert_raises(Core::Mistake) { file(%(Rule\tArtifact\tComment\n"x\ny"\ta\t\n#{row}\nr\ta\t\n)) }

      assert_equal ["debt.tsv:4", message], [mistake.location, mistake.message], row.dump
    end
  end

  def test_stops_at_a_header_that_isnt_a_debt_files
    ["Rule\tArtifact", "Rule\tArtifact\tComment\tDetail\tMore", "Rule\tArtifact\tCommnet", "﻿Rule\tArtifact\tComment"].each do |header|
      mistake = assert_raises(Core::Mistake) { file("#{header}\nr\ta\t\n") }

      assert_equal "debt.tsv:1", mistake.location, header.dump
      assert_match(/\Ahas the columns .* in its header, where CrossLint reads "Rule", "Artifact", "Comment", and an optional "Detail"\z/,
        mistake.message)
    end
  end

  def test_stops_at_a_row_with_more_fields_than_columns
    mistake = assert_raises(Core::Mistake) { file("Rule\tArtifact\tComment\nr\ta\tc\td\n") }

    assert_equal ["debt.tsv:2", "has 4 fields, where the header has 3 columns"], [mistake.location, mistake.message]
  end

  def test_stops_at_a_quote_that_doesnt_end_or_has_text_after_it
    {%(r\t"a\n) => "has a quote that doesn't end", %(r\t"a"b\tc\n) => "has text after a closing quote"}.each do |row, message|
      mistake = assert_raises(Core::Mistake) { file("Rule\tArtifact\tComment\n#{row}") }

      assert_equal ["debt.tsv:2", message], [mistake.location, mistake.message]
    end
  end

  def test_stops_at_a_file_that_isnt_utf_8
    mistake = assert_raises(Core::Mistake) { file("Rule\tArtifact\tComment\nr\t\xFF\t\n".b) }

    assert_equal ["debt.tsv", "isn't valid UTF-8"], [mistake.location, mistake.message]
  end

  def test_writes_each_entry_it_read_back_byte_for_byte
    text = %(Rule\tArtifact\tComment\r\n"spec-exists"\tapp/card\t"quoted for no reason"\r\nr\ta\tc\nr\tb\t)

    assert_equal "#{text}\r\n", rewrite(file(text))
  end

  def test_writes_new_entries_as_d3_dsv_formats_them_with_the_headers_line_ending
    added = [fresh("lib/a.rb"), fresh("lib/b.rb", comment: %(a "quote"\tand\r\nlines)), fresh("lib/café.rb", comment: "plain")]

    assert_equal "Rule\tArtifact\tComment\r\nr\ta\tc\r\ntests/has-test\tlib/a.rb\t\r\n" \
      "tests/has-test\tlib/b.rb\t\"a \"\"quote\"\"\tand\r\nlines\"\r\ntests/has-test\tlib/café.rb\tplain\r\n",
      rewrite(file("Rule\tArtifact\tComment\r\nr\ta\tc"), added).force_encoding(Encoding::UTF_8)
  end

  # ng-nudge wrote an empty debt file as one newline (lib/config/debt-file.js:76-81).
  def test_writes_a_header_and_a_newline_for_a_file_with_none
    assert_equal "Rule\tArtifact\tComment\n", rewrite(file("\n"))
    assert_equal "Rule\tArtifact\tComment\ntests/has-test\tlib/a.rb\t\n", rewrite(file(""), [fresh("lib/a.rb")])
  end

  def test_keeps_the_header_of_a_file_whose_entries_are_all_removed
    assert_equal "Rule\tArtifact\tComment\tDetail\r\n", rewrite(file("Rule\tArtifact\tComment\tDetail\r\nr\ta\t\t\r\n").with(entries: []))
  end

  def test_adds_the_detail_column_only_for_an_entry_with_a_detail
    debt = file("Rule\tArtifact\tComment\nr\ta\tc\n")

    assert_equal "Rule\tArtifact\tComment\nr\ta\tc\ntests/has-test\tlib/b.rb\t\n", rewrite(debt, [fresh("lib/b.rb")])
    assert_equal "Rule\tArtifact\tComment\tDetail\nr\ta\tc\ntests/has-test\tlib/b.rb\t\tinputs.name\n",
      rewrite(debt, [fresh("lib/b.rb", detail: "inputs.name")])
    assert_equal "Rule\tArtifact\tComment\tDetail\nr\ta\t\t\ntests/has-test\tlib/b.rb\t\t\n",
      rewrite(file("Rule\tArtifact\tComment\tDetail\nr\ta\t\t\n"), [fresh("lib/b.rb")])
  end

  # ng-nudge failed an update when the folder was missing (lib/config/debt-file.js:81);
  # the contract's test_makes_the_folder_of_a_file_it_writes shows CrossLint makes it.
  def test_replaces_the_file_whole_and_leaves_no_file_beside_it
    write(@root, "debt.tsv", "Rule\tArtifact\tComment\n")
    File.chmod(0o640, File.join(@root, "debt.tsv"))
    rewrite(file("Rule\tArtifact\tComment\n"), [fresh("lib/a.rb")])

    assert_equal ["debt.tsv"], Dir.children(@root)
    assert_equal 0o640, File.stat(File.join(@root, "debt.tsv")).mode & 0o777 unless WINDOWS
  end

  def test_leaves_no_file_beside_it_when_the_write_fails
    FileUtils.mkdir_p(File.join(@root, "debt.tsv", "inside"))

    # Windows denies the rename; macOS and Linux find a folder there.
    assert_raises(SystemCallError, Core::Mistake) { port.write(@root, "debt.tsv", Core::DebtFile.new(file: "debt.tsv", entries: [], header: nil)) }
    assert_equal ["debt.tsv"], Dir.children(@root)
    assert_equal ["inside"], Dir.children(File.join(@root, "debt.tsv"))
  end

  def test_stops_naming_the_file_and_leaves_it_when_the_rename_is_denied
    write(@root, "debt.tsv", "Rule\tArtifact\tComment\n")
    Thread.current[:crosslint_rename_denied] = true
    mistake = assert_raises(Core::Mistake) { rewrite(port.read(@root, "debt.tsv"), [fresh("lib/a.rb")]) }

    assert_equal ["debt.tsv", "couldn't be replaced, since permission was denied; close any program that has it open, and run again"],
      [mistake.location, mistake.message]
    assert_equal [["debt.tsv"], "Rule\tArtifact\tComment\n"], [Dir.children(@root), File.binread(File.join(@root, "debt.tsv"))]
  ensure
    Thread.current[:crosslint_rename_denied] = nil
  end

  # Windows denies renaming over a file Ruby has open; macOS and Linux
  # replace it.
  def test_replaces_a_file_another_handle_has_open_for_reading_except_on_windows
    write(@root, "debt.tsv", "Rule\tArtifact\tComment\n")
    File.open(File.join(@root, "debt.tsv"), "rb") do |open|
      if WINDOWS
        assert_raises(Core::Mistake) { rewrite(port.read(@root, "debt.tsv"), [fresh("lib/a.rb")]) }
      else
        rewrite(port.read(@root, "debt.tsv"), [fresh("lib/a.rb")])
      end

      assert_equal "Rule\tArtifact\tComment\n", open.read
    end

    assert_equal ["debt.tsv"], Dir.children(@root)
    assert_equal WINDOWS ? "Rule\tArtifact\tComment\n" : "Rule\tArtifact\tComment\ntests/has-test\tlib/a.rb\t\n",
      File.binread(File.join(@root, "debt.tsv"))
  end
end
