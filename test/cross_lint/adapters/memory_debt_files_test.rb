# frozen_string_literal: true

require "test_helper"

# What the debt-files contract can't say of MemoryDebtFiles#move.
class MemoryDebtFilesMoveTest < Minitest::Test
  cover "CrossLint::Adapters::MemoryDebtFiles*"

  ROOT = File.expand_path("/app")

  def test_moves_a_file_it_cannot_read_as_it_is
    mistake = CrossLint::Core::Mistake.new("has an entry with no rule", file: "old.tsv", line: 3)
    port = CrossLint::Adapters::MemoryDebtFiles.new({File.join(ROOT, "old.tsv") => mistake})
    port.move(ROOT, "old.tsv", "debt.tsv")

    assert_same mistake, assert_raises(CrossLint::Core::Mistake) { port.read(ROOT, "debt.tsv") }
    refute port.exist?(ROOT, "old.tsv")
  end
end
