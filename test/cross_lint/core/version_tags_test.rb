# frozen_string_literal: true

require "test_helper"

class VersionTagsTest < Minitest::Test
  cover "CrossLint::Core::VersionTags*"

  VersionTag = CrossLint::Core::VersionTag
  VersionTags = CrossLint::Core::VersionTags

  def tags(*texts) = VersionTags.parse(texts)

  def tag(text) = VersionTag.parse(text)

  def test_picks_the_tag_with_the_highest_version_by_number_not_by_text
    assert_equal "v1.10.0", tags(*%w[v1.2.0 v1.10.0 v1.9.9 v0.99.99]).newest.text
    assert_equal "2.0.0", tags(*%w[v1.10.0 2.0.0 v1.99.99]).newest.text
    assert_equal "v1.2.10", tags(*%w[v1.2.9 v1.2.10 v1.1.99]).newest.text
    assert_equal "v10.0.0", tags(*%w[v9.9.9 v10.0.0]).newest.text
  end

  def test_leaves_out_a_tag_that_isnt_three_integers
    others = %w[v3.0.0-rc.1 3.0.0-rc.1 v3.0 v3 3.0.0.1 v3.0.0+build vv3.0.0 V3.0.0 latest stable v3.0.0-1 v1.0.x x9.9.9 release-9.9.9]

    assert_nil tags(*others).newest
    assert_equal "v1.0.0", tags(*others, "v1.0.0").newest.text
    assert_equal "v1.0.0", tags("v1.0.0", "9.9.9\n", " 9.9.9", "9.9.9 ").newest.text
    assert_nil tags.newest
  end

  def test_picks_the_tag_the_project_has_among_the_tags_of_the_highest_version
    all = tags("1.2.0", "v1.2.0", "v1.1.0")

    assert_equal %w[v1.2.0 1.2.0], [all.newest(keep: tag("v1.2.0")).text, all.newest(keep: tag("1.2.0")).text]
    assert_equal "1.2.0", tags("v1.2.0", "1.2.0", "v1.1.0").newest.text
    assert_equal "1.2.0", all.newest(keep: nil).text
  end

  def test_moves_to_the_tag_with_the_form_of_the_ref_it_replaces_when_two_tags_tie
    all = tags("1.2.0", "v1.2.0", "v1.1.0", "1.1.0")

    assert_equal %w[v1.2.0 1.2.0], [all.newest(keep: tag("v1.1.0")).text, all.newest(keep: tag("1.1.0")).text]
    assert_equal "v1.2.0", tags("v1.2.0").newest(keep: tag("1.1.0")).text
  end

  # v1.2.0 and v1.02.0 are one version in two spellings of the same form.
  def test_keeps_the_tag_the_project_has_or_else_the_first_by_name_among_tags_of_one_version_and_form
    forward = tags("v1.2.0", "v1.02.0")
    backward = tags("v1.02.0", "v1.2.0")
    kept = tag("v1.2.0")
    lower = tag("v1.1.0")

    assert_equal %w[v1.2.0 v1.2.0 v1.02.0 v1.02.0 v1.02.0],
      [forward.newest(keep: kept).text, backward.newest(keep: kept).text, forward.newest(keep: lower).text, backward.newest(keep: lower).text, backward.newest.text]
  end

  def test_never_moves_to_a_lower_version_than_the_one_the_project_has
    assert_equal %w[v2.0.0 2.1.0 v1.10.0 v1.2.0],
      [tags("v1.9.0", "v1.10.0").newest(keep: tag("v2.0.0")), tags("v1.9.0").newest(keep: tag("2.1.0")),
        tags("v1.9.0", "v1.10.0").newest(keep: tag("v1.1.0")), tags("v1.2.0").newest(keep: tag("v1.2.0"))].map(&:text)
    assert_nil tags("latest").newest(keep: tag("v9.0.0"))
  end

  def test_keeps_the_tags_compatible_with_a_version
    all = tags(*%w[v1.0.0 v1.9.0 1.10.0 v2.0.0 v0.9.0 v0.3.1 v0.3.9 v0.4.0 v0.0.3 v0.0.4 v1.0.0-rc.1 latest])

    assert_equal %w[v1.0.0 v1.9.0 1.10.0], all.compatible_with(tag("v1.4.0")).tags.map(&:text)
    assert_equal %w[v0.3.1 v0.3.9], all.compatible_with(tag("0.3.0")).tags.map(&:text)
    assert_equal %w[v0.0.3], all.compatible_with(tag("v0.0.3")).tags.map(&:text)
  end

  def test_names_the_highest_tag_of_each_newer_incompatible_group_lowest_first
    all = tags(*%w[v1.4.0 v1.5.0 v2.0.0 v2.3.1 v2.3.0 3.0.0 v3.0.0 v0.9.0 v3.1.0-rc.1])

    assert_equal %w[v2.3.1 v3.0.0], all.newer_incompatible(tag("v1.4.0")).map(&:text)
    assert_equal %w[v1.5.0 v2.3.1 v3.0.0], all.newer_incompatible(tag("v0.9.0")).map(&:text)
    assert_empty all.newer_incompatible(tag("v3.0.0"))
    assert_equal %w[v0.0.5 v0.3.2 v0.4.0], tags(*%w[v0.3.0 v0.3.2 v0.4.0 v0.0.5 v0.0.2]).newer_incompatible(tag("v0.0.4")).map(&:text)
  end

  def test_names_the_tag_in_the_form_of_the_ref_when_two_tags_tie
    assert_equal %w[2.0.0], tags("v2.0.0", "2.0.0").newer_incompatible(tag("1.0.0")).map(&:text)
    assert_equal %w[v2.0.0], tags("v2.0.0", "2.0.0").newer_incompatible(tag("v1.0.0")).map(&:text)
  end
end
