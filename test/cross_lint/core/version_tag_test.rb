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

  def test_keeps_the_text_as_written_and_its_version
    tag = VersionTag.parse("v1.02.30")

    assert_equal ["v1.02.30", [1, 2, 30], true], [tag.text, tag.version.numbers, tag.v?]
    assert_equal ["1.2.3", false], [VersionTag.parse("1.2.3").text, VersionTag.parse("1.2.3").v?]
  end

  def test_two_tags_of_one_version_are_not_equal
    with_v = VersionTag.parse("v1.2.0")
    plain = VersionTag.parse("1.2.0")
    same = VersionTag.parse("v1.2.0")

    assert_equal [false, false, true, true], [with_v == plain, with_v.eql?(plain), with_v == same, with_v.eql?(same)]
    assert_equal [with_v, plain], [with_v, plain, same].uniq
    assert_equal [with_v, plain], { with_v => 1, plain => 2, same => 3 }.keys
    refute_equal with_v, "v1.2.0"
  end

  def test_two_tags_of_one_version_share_it
    assert_equal VersionTag.parse("v1.2.0").version, VersionTag.parse("1.2.0").version
    refute_equal VersionTag.parse("v1.2.0").version, VersionTag.parse("v1.2.1").version
  end

  def test_only_parse_makes_a_tag
    tag = VersionTag.parse("v1.2.0")

    assert_raises(NoMethodError) { VersionTag.new(text: "v1", version: tag.version) }
    assert_raises(NoMethodError) { VersionTag[text: "v1", version: tag.version] }
    assert_raises(NoMethodError) { tag.with(text: "v9.9.9") }
  end
end
