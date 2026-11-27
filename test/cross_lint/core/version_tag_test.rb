# frozen_string_literal: true

require "test_helper"

class VersionTagTest < Minitest::Test
  cover "CrossLint::Core::VersionTag*"

  VersionTag = CrossLint::Core::VersionTag

  def test_reads_a_plain_version_tag_with_or_without_a_v_and_no_other_ref
    versions = %w[v1.2.3 1.2.3 v0.0.0 v10.20.30]
    others = ["v1.2.3-rc.1", "1.2", "v1", "v1.2.3.4", "v1.2.3+b", "latest", "a" * 40, "v1.2.3\n", " 1.2.3", "V1.2.3", "vv1.2.3", "x9.9.9", "9.9.9 "]

    assert_equal [versions, []], [versions.select { |ref| VersionTag.parse(ref) }, others.select { |ref| VersionTag.parse(ref) }]
  end

  def test_keeps_the_text_as_written_and_its_three_numbers
    tag = VersionTag.parse("v1.02.30")

    assert_equal ["v1.02.30", [1, 2, 30], true], [tag.text, tag.numbers, tag.v?]
    assert_equal ["1.2.3", false], [VersionTag.parse("1.2.3").text, VersionTag.parse("1.2.3").v?]
  end

  def test_orders_by_number_not_by_text
    tags = %w[v1.10.0 v1.2.0 v1.9.9 v0.99.99 v10.0.0 v1.2.10].map { |text| VersionTag.parse(text) }

    assert_equal %w[v0.99.99 v1.2.0 v1.2.10 v1.9.9 v1.10.0 v10.0.0], tags.sort.map(&:text)
    assert_equal "v10.0.0", tags.max.text
  end

  def test_one_version_in_two_forms_ties_but_the_two_tags_are_not_equal
    with_v = VersionTag.parse("v1.2.0")
    plain = VersionTag.parse("1.2.0")

    assert_equal [0, false, true], [with_v <=> plain, with_v == plain, with_v == VersionTag.parse("v1.2.0")]
    refute_equal with_v, "v1.2.0"
  end

  # The caret rule of Cargo and npm: the leftmost number that isn't zero
  # stays, and the ones before it are all zeros.
  def test_is_compatible_with_the_versions_that_share_its_leftmost_number_that_isnt_zero
    one = VersionTag.parse("v1.4.0")
    results = %w[v1.0.0 v1.9.0 1.10.0 v2.0.0 v0.9.0].map { |text| one.compatible_with?(VersionTag.parse(text)) }

    assert_equal [true, true, true, false, false], results
  end

  def test_is_compatible_at_zero_y_z_with_the_same_zero_y_only
    zero = VersionTag.parse("0.3.0")
    results = %w[v0.3.1 v0.3.9 v0.4.0 v0.0.3 v1.3.0].map { |text| zero.compatible_with?(VersionTag.parse(text)) }

    assert_equal [true, true, false, false, false], results
  end

  def test_is_compatible_at_zero_zero_z_with_that_version_only
    triple_zero = VersionTag.parse("v0.0.3")
    results = %w[v0.0.3 0.0.3 v0.0.4 v0.0.2 v0.1.3 v1.0.3].map { |text| triple_zero.compatible_with?(VersionTag.parse(text)) }

    assert_equal [true, true, false, false, false, false], results
  end

  def test_groups_the_versions_that_are_compatible
    groups = %w[v1.0.0 1.9.9 v2.0.0 v0.3.0 v0.3.9 v0.0.3 v0.0.4].map { |text| VersionTag.parse(text).group }

    assert_equal [[1], [1], [2], [0, 3], [0, 3], [0, 0, 3], [0, 0, 4]], groups
  end
end
