# frozen_string_literal: true

require "test_helper"

class VersionTest < Minitest::Test
  cover "CrossLint::Core::Version*"

  Version = CrossLint::Core::Version

  def version(text) = Version.new(numbers: text.split(".").map(&:to_i))

  def test_orders_by_number_not_by_text
    versions = %w[1.10.0 1.2.0 1.9.9 0.99.99 10.0.0 1.2.10].map { |text| version(text) }

    assert_equal %w[0.99.99 1.2.0 1.2.10 1.9.9 1.10.0 10.0.0], versions.sort.map { |each| each.numbers.join(".") }
    assert_equal [10, 0, 0], versions.max.numbers
  end

  def test_compares_with_nothing_but_a_version
    assert_nil version("1.2.0") <=> "1.2.0"
    assert_nil version("1.2.0") <=> nil
    assert_raises(ArgumentError) { version("1.2.0") < "1.2.0" }
    refute_equal version("1.2.0"), "1.2.0"
  end

  def test_equal_versions_are_equal_eql_and_hash_alike
    one = version("1.2.0")
    other = version("1.2.0")

    assert_equal [0, true, true, true], [one <=> other, one == other, one.eql?(other), one.hash == other.hash]
    assert_equal [one], [one, other].uniq
    refute_equal one, version("1.2.1")
  end

  # The caret rule of Cargo and npm: the leftmost number that isn't zero
  # stays, and the ones before it are all zeros.
  def test_is_compatible_with_the_versions_that_share_its_leftmost_number_that_isnt_zero
    one = version("1.4.0")
    results = %w[1.0.0 1.9.0 1.10.0 2.0.0 0.9.0].map { |text| one.compatible_with?(version(text)) }

    assert_equal [true, true, true, false, false], results
  end

  def test_is_compatible_at_zero_y_z_with_the_same_zero_y_only
    zero = version("0.3.0")
    results = %w[0.3.1 0.3.9 0.4.0 0.0.3 1.3.0].map { |text| zero.compatible_with?(version(text)) }

    assert_equal [true, true, false, false, false], results
  end

  def test_is_compatible_at_zero_zero_z_with_that_version_only
    triple_zero = version("0.0.3")
    results = %w[0.0.3 0.0.4 0.0.2 0.1.3 1.0.3].map { |text| triple_zero.compatible_with?(version(text)) }

    assert_equal [true, false, false, false, false], results
  end

  def test_groups_the_versions_that_are_compatible
    groups = %w[1.0.0 1.9.9 2.0.0 0.3.0 0.3.9 0.0.3 0.0.4].map { |text| version(text).group }

    assert_equal [[1], [1], [2], [0, 3], [0, 3], [0, 0, 3], [0, 0, 4]], groups
  end
end
