# frozen_string_literal: true

require "test_helper"

class MinimumVersionTest < Minitest::Test
  cover "CrossLint::Core::MinimumVersion*"

  Core = CrossLint::Core

  def minimum(text) = Core::MinimumVersion.parse(text, file: "plugin.kdl", line: 1)

  def version(text) = Core::Version.parse(text)

  def test_keeps_the_text_the_file_has_and_reads_its_version
    found = minimum("1.2")

    assert_equal ["1.2", [1, 2, 0], "plugin.kdl", 1], [found.text, found.version.numbers, found.file, found.line]
  end

  def test_reads_nothing_from_a_version_that_isnt_bare_numbers
    assert_nil minimum(">=1.2")
  end

  def test_is_met_by_its_version_and_every_later_one
    met = %w[1.1.9 1.2.0 1.2.1 2.0.0].map { |text| minimum("1.2").met_by?(version(text)) }

    assert_equal [false, true, true, true], met
  end

  def test_names_both_versions_and_says_to_upgrade_when_crosslint_is_older
    mistake = assert_raises(Core::Mistake) { minimum("1.2").check(version("1.1.9")) }

    assert_equal ["plugin.kdl", 1, "needs CrossLint 1.2 or later, and this is CrossLint 1.1.9; upgrade CrossLint"],
      [mistake.file, mistake.line, mistake.message]
  end

  def test_names_what_needs_the_newer_crosslint_when_it_is_told
    mistake = assert_raises(Core::Mistake) { minimum("2").check(version("1.4.0"), of: "plugin links") }

    assert_equal "plugin links needs CrossLint 2 or later, and this is CrossLint 1.4.0; upgrade CrossLint", mistake.message
  end

  def test_says_nothing_when_crosslint_is_as_new
    assert_nil minimum("1.2").check(version("1.2.0"))
  end
end
