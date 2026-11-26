# frozen_string_literal: true

require "test_helper"

# What the debt-files contract can't say of TSVDebtFiles#move: the bytes it
# moves, and what it does when the system denies a rename or a deletion.
class TSVDebtFilesMoveTest < Minitest::Test
  cover "CrossLint::Adapters::TSVDebtFiles*"

  Core = CrossLint::Core

  # Denies each File.rename in this thread while :crosslint_move_rename_denied
  # is set, as Windows denies one over a file another program has open.
  module DeniedRenames
    def rename(from, to)
      raise Errno::EACCES, "#{from}, #{to}" if Thread.current[:crosslint_move_rename_denied]

      super
    end
  end
  File.singleton_class.prepend(DeniedRenames)

  # Denies each File.delete in this thread while :crosslint_move_delete_denied
  # is set.
  module DeniedDeletes
    def delete(*files)
      raise Errno::EACCES, files.join(", ") if Thread.current[:crosslint_move_delete_denied]

      super
    end
  end
  File.singleton_class.prepend(DeniedDeletes)

  def setup
    @root = Dir.mktmpdir("crosslint")
  end

  def teardown
    FileUtils.rm_rf(@root)
  end

  def port = CrossLint::Adapters::TSVDebtFiles.new

  def test_moves_the_bytes_of_a_file_as_they_are_even_when_they_are_no_debt_file
    bytes = "Rule\tArtifact\r\n\"a\"\"\"\tb\r\nno final newline \xE9".b
    File.binwrite(File.join(@root, "old.tsv"), bytes)
    port.move(@root, "old.tsv", "new/debt.tsv")

    assert_equal [bytes, ["new"]], [File.binread(File.join(@root, "new/debt.tsv")), Dir.children(@root)]
    assert_equal ["debt.tsv"], Dir.children(File.join(@root, "new"))
  end

  def test_keeps_the_file_it_moves_over_when_the_rename_is_denied
    write(@root, "old.tsv", "Rule\tArtifact\tComment\nr\ta\tnew\n")
    write(@root, "debt.tsv", "Rule\tArtifact\tComment\nr\ta\told\n")
    Thread.current[:crosslint_move_rename_denied] = true
    mistake = assert_raises(Core::Mistake) { port.move(@root, "old.tsv", "debt.tsv") }

    assert_equal ["debt.tsv", "couldn't be replaced, since permission was denied; close any program that has it open, and run again"],
      [mistake.location, mistake.message]
    assert_equal ["Rule\tArtifact\tComment\nr\ta\told\n", "Rule\tArtifact\tComment\nr\ta\tnew\n", ["debt.tsv", "old.tsv"]],
      [File.binread(File.join(@root, "debt.tsv")), File.binread(File.join(@root, "old.tsv")), Dir.children(@root).sort]
  ensure
    Thread.current[:crosslint_move_rename_denied] = nil
  end

  def test_says_what_the_system_said_when_it_cannot_remove_the_file_it_moved
    write(@root, "old.tsv", "Rule\tArtifact\tComment\n")
    mistake = begin
      Thread.current[:crosslint_move_delete_denied] = true
      assert_raises(Core::Mistake) { port.move(@root, "old.tsv", "debt.tsv") }
    ensure
      Thread.current[:crosslint_move_delete_denied] = nil
    end

    assert_equal "old.tsv", mistake.file
    assert_match(/\Acouldn't be removed once it was written to debt.tsv: .*old\.tsv/, mistake.message)
  end
end
