# frozen_string_literal: true

require "test_helper"

class SharedPluginTest < Minitest::Test
  cover "CrossLint::Core::SharedPlugin*"
  cover "CrossLint::Core::FetchError*"

  SharedPlugin = CrossLint::Core::SharedPlugin

  def test_names_a_plugin_for_the_last_part_of_its_repositorys_url
    urls = ["https://github.com/OWNER/signatures", "https://github.com/OWNER/signatures.git", "https://github.com/OWNER/signatures/",
      "https://github.com/OWNER/signatures.git//", "file:///tmp/a.b_c-d"]

    assert_equal %w[signatures signatures signatures signatures a.b_c-d], urls.map { |url| SharedPlugin.plugin_name(url) }
  end

  def test_names_no_plugin_for_a_last_part_that_isnt_letters_digits_and_dot_underscore_dash
    urls = ["https://example.com/OWNER/a b", "https://example.com/OWNER/café", "https://example.com/OWNER/a:b", "https://example.com/OWNER/..",
      "https://example.com/OWNER/.", "https://example.com/OWNER/.git", "https://example.com/OWNER/a\nb", ""]

    assert_equal [nil] * urls.size, urls.map { |url| SharedPlugin.plugin_name(url) }
  end

  def test_takes_a_tag_name_or_a_full_sha_as_a_ref
    refs = ["v1.2.0", "1.2.0", "release/2026.1", "v1.0.0+build.5", "2.0.0-rc.1", "a" * 40, "A1" * 20, "a" * 39, "#{"a" * 41}g"]

    assert_equal [true] * refs.size, refs.map { |ref| SharedPlugin.ref?(ref) }
  end

  def test_takes_no_ref_with_a_character_git_reads_as_part_of_a_refspec
    refs = ["", "-v1", ".v1", "a:b", "a*", "a?", "a[", "a^", "a~", "a b", "a\\b", "a\nb", "v1\n", "café"]

    assert_equal [false] * refs.size, refs.map { |ref| SharedPlugin.ref?(ref) }
  end

  def test_knows_a_full_sha_from_a_tag_that_looks_like_one
    assert_equal [true, true, false, false, false], ["a" * 40, "0123456789ABCDEFabcdef0123456789ABCDEFab", "a" * 39, "a" * 41, "#{"a" * 39}g"]
      .map { |ref| SharedPlugin.sha?(ref) }
    assert_equal [false], ["#{"a" * 40}\n"].map { |ref| SharedPlugin.sha?(ref) }
  end

  def test_knows_a_plain_version_tag_from_every_other_ref
    versions = %w[v1.2.3 1.2.3 v0.0.0 v10.20.30]
    others = ["v1.2.3-rc.1", "1.2", "v1", "v1.2.3.4", "v1.2.3+b", "latest", "a" * 40, "v1.2.3\n", " 1.2.3", "V1.2.3"]

    assert_equal [[true] * versions.size, [false] * others.size], [versions, others].map { |refs| refs.map { |ref| SharedPlugin.version?(ref) } }
  end

  def test_knows_a_url_with_a_user_name_or_password_by_what_comes_before_the_first_slash_after_the_scheme
    with = %w[https://u:p@example.com/o/r https://u@example.com/o/r https://:p@example.com/o/r https://u:p@example.com ssh://git@example.com/o/r x://u@h HTTPS://u:p@h https://@h/o]
    without = %w[https://example.com/o/r https://example.com/o/a@b https://example.com/?a=b@c https://example.com#a@b https://example.com:8080/o/r file:///tmp/a@b]

    assert_equal [[true] * with.size, [false] * without.size], [with, without].map { |urls| urls.map { |url| SharedPlugin.credentials?(url) } }
  end

  def test_refuses_the_first_plugin_whose_name_is_a_url_with_a_user_name_or_password_and_no_other
    listing = ->(name, line, ref = nil) { CrossLint::Core::ListedPlugin.new(name:, ref:, settings: [], line:) }
    plugins = [listing.call("./a@b", 1), listing.call("https://example.com/o/ok", 2, "v1"), listing.call("http://u:p@h/o", 3, "v1"),
      listing.call("https://u:p@h/o/r", 4, "v1"), listing.call("https://v@h/o/r", 5, "v1")]
    configuration = CrossLint::Core::Configuration.new(file: "c.kdl", plugins:, policies: [], warnings: nil, verbosity: nil)
    mistake = assert_raises(CrossLint::Core::Mistake) { SharedPlugin.refuse_credentials(configuration) }

    assert_equal ["c.kdl", 3], [mistake.file, mistake.line]
    SharedPlugin.refuse_credentials(configuration.with(plugins: plugins.first(2)))
    assert_equal 4, assert_raises(CrossLint::Core::Mistake) { SharedPlugin.refuse_credentials(configuration.with(plugins: plugins.drop(3))) }.line
    SharedPlugin.refuse_credentials(configuration.with(plugins: []))
  end

  def test_picks_the_tag_with_the_highest_version_by_number_not_by_text
    assert_equal "v1.10.0", SharedPlugin.newest_tag(%w[v1.2.0 v1.10.0 v1.9.9 v0.99.99])
    assert_equal "2.0.0", SharedPlugin.newest_tag(%w[v1.10.0 2.0.0 v1.99.99])
    assert_equal "v1.2.10", SharedPlugin.newest_tag(%w[v1.2.9 v1.2.10 v1.1.99])
    assert_equal "v10.0.0", SharedPlugin.newest_tag(%w[v9.9.9 v10.0.0])
  end

  def test_leaves_out_a_tag_that_isnt_three_integers
    tags = %w[v3.0.0-rc.1 3.0.0-rc.1 v3.0 v3 3.0.0.1 v3.0.0+build vv3.0.0 V3.0.0 latest stable v3.0.0-1 v1.0.x]

    assert_nil SharedPlugin.newest_tag(tags)
    assert_equal "v1.0.0", SharedPlugin.newest_tag(tags + ["v1.0.0"])
    assert_nil SharedPlugin.newest_tag([])
  end

  def test_leaves_out_a_tag_with_text_around_a_version
    assert_equal "v1.0.0", SharedPlugin.newest_tag(["v1.0.0", "x9.9.9", "9.9.9\n", "release-9.9.9", " 9.9.9", "9.9.9 "])
  end

  def test_picks_the_tag_the_project_has_among_the_tags_of_the_highest_version
    tags = %w[1.2.0 v1.2.0 v1.1.0]

    assert_equal ["v1.2.0", "1.2.0"], [SharedPlugin.newest_tag(tags, keep: "v1.2.0"), SharedPlugin.newest_tag(tags, keep: "1.2.0")]
    assert_equal "1.2.0", SharedPlugin.newest_tag(tags.reverse)
    assert_equal "1.2.0", SharedPlugin.newest_tag(tags, keep: nil)
  end

  def test_moves_to_the_tag_with_the_form_of_the_ref_it_replaces_when_two_tags_tie
    tags = %w[1.2.0 v1.2.0 v1.1.0 1.1.0]

    assert_equal ["v1.2.0", "1.2.0", "1.2.0"], [SharedPlugin.newest_tag(tags, keep: "v1.1.0"), SharedPlugin.newest_tag(tags, keep: "1.1.0"),
      SharedPlugin.newest_tag(%w[1.2.0 v1.2.0], keep: "release-1.1.0")]
    assert_equal "v1.2.0", SharedPlugin.newest_tag(%w[v1.2.0], keep: "1.1.0")
  end

  # v1.2.0 and v1.02.0 are one version in two spellings of the same form.
  def test_keeps_the_tag_the_project_has_or_else_the_first_by_name_among_tags_of_one_version_and_form
    tags = %w[v1.2.0 v1.02.0]

    assert_equal ["v1.2.0", "v1.2.0", "v1.02.0", "v1.02.0", "v1.02.0"], [SharedPlugin.newest_tag(tags, keep: "v1.2.0"), SharedPlugin.newest_tag(tags.reverse, keep: "v1.2.0"),
      SharedPlugin.newest_tag(tags, keep: "v1.1.0"), SharedPlugin.newest_tag(tags.reverse, keep: "v1.1.0"), SharedPlugin.newest_tag(tags.reverse)]
  end

  def test_never_moves_to_a_lower_version_than_the_one_the_project_has
    assert_equal ["v2.0.0", "2.1.0", "v1.10.0", "v1.2.0"], [SharedPlugin.newest_tag(%w[v1.9.0 v1.10.0], keep: "v2.0.0"), SharedPlugin.newest_tag(%w[v1.9.0], keep: "2.1.0"),
      SharedPlugin.newest_tag(%w[v1.9.0 v1.10.0], keep: "v1.1.0"), SharedPlugin.newest_tag(%w[v1.2.0], keep: "v1.2.0")]
    assert_equal "v1.0.0", SharedPlugin.newest_tag(%w[v1.0.0], keep: "release-9.9.9")
    assert_nil SharedPlugin.newest_tag(%w[latest], keep: "v9.0.0")
  end

  def test_says_what_is_wrong_with_a_ref
    assert_equal "ext::x doesn't start with https:// or file://", CrossLint::Core::FetchError.scheme("ext::x", ["https://", "file://"]).message
    errors = [CrossLint::Core::FetchError.bad_ref("a:b"), CrossLint::Core::FetchError.branch("main"), CrossLint::Core::FetchError.no_tag("v9"),
      CrossLint::Core::FetchError.no_commit("abc")]

    assert_equal ['"a:b" is neither a tag name nor a full 40-character commit SHA', "main is a branch, and a ref is a tag or a full 40-character commit SHA",
      "the repository has no tag v9, and a ref is a tag or a full 40-character commit SHA", "the repository has no commit abc"], errors.map(&:message)
    assert(errors.all? { |error| error.is_a?(StandardError) })
  end
end
