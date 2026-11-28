# frozen_string_literal: true

require "test_helper"

class SharedPluginTest < Minitest::Test
  cover "CrossLint::Core::SharedPlugin*"
  cover "CrossLint::Core::FetchError*"
  cover "CrossLint::Core::ListedPlugin*"

  SharedPlugin = CrossLint::Core::SharedPlugin

  def test_names_a_plugin_for_the_last_part_of_its_repositorys_url
    urls = [
      "https://github.com/OWNER/signatures",
      "https://github.com/OWNER/signatures.git",
      "https://github.com/OWNER/signatures/",
      "https://github.com/OWNER/signatures.git//",
      "file:///tmp/a.b_c-d",
]

    assert_equal %w[signatures signatures signatures signatures a.b_c-d], urls.map { |url| SharedPlugin.plugin_name(url) }
  end

  def test_names_no_plugin_for_a_last_part_that_isnt_letters_digits_and_dot_underscore_dash
    urls = [
      "https://example.com/OWNER/a b",
      "https://example.com/OWNER/café",
      "https://example.com/OWNER/a:b",
      "https://example.com/OWNER/..",
      "https://example.com/OWNER/.",
      "https://example.com/OWNER/.git",
      "https://example.com/OWNER/a\nb",
      "",
]

    assert_equal [nil] * urls.size, urls.map { |url| SharedPlugin.plugin_name(url) }
  end

  def test_takes_a_tag_name_or_a_full_sha_as_a_ref
    refs = ["v1.2.0", "1.2.0", "release/2026.1", "v1.0.0+build.5", "2.0.0-rc.1", "a" * 40, "A1" * 20, "a" * 39, "#{'a' * 41}g"]

    assert_equal [true] * refs.size, refs.map { |ref| SharedPlugin.ref?(ref) }
  end

  def test_takes_no_ref_with_a_character_git_reads_as_part_of_a_refspec
    refs = ["", "-v1", ".v1", "a:b", "a*", "a?", "a[", "a^", "a~", "a b", "a\\b", "a\nb", "v1\n", "café"]

    assert_equal [false] * refs.size, refs.map { |ref| SharedPlugin.ref?(ref) }
  end

  def test_knows_a_full_sha_from_a_tag_that_looks_like_one
    assert_equal [true, true, false, false, false], ["a" * 40, "0123456789ABCDEFabcdef0123456789ABCDEFab", "a" * 39, "a" * 41, "#{'a' * 39}g"]
      .map { |ref| SharedPlugin.sha?(ref) }
    assert_equal [false], ["#{'a' * 40}\n"].map { |ref| SharedPlugin.sha?(ref) }
  end

  def test_knows_a_url_with_a_user_name_or_password_by_what_comes_before_the_first_slash_after_the_scheme
    with = %w[https://u:p@example.com/o/r https://u@example.com/o/r https://:p@example.com/o/r https://u:p@example.com ssh://git@example.com/o/r x://u@h HTTPS://u:p@h https://@h/o]
    without = %w[https://example.com/o/r https://example.com/o/a@b https://example.com/?a=b@c https://example.com#a@b https://example.com:8080/o/r file:///tmp/a@b]

    assert_equal [[true] * with.size, [false] * without.size], [with, without].map { |urls| urls.map { |url| SharedPlugin.credentials?(url) } }
  end

  def test_knows_a_url_with_a_query_or_a_fragment_by_a_question_mark_or_a_hash_after_the_scheme
    with = %w[
      https://example.com/o/r?token=X
      https://example.com/o/r#frag
      https://example.com/o/r?token=X#frag
      https://example.com?a=b
      https://example.com#a
      https://example.com/o/r.git?
      https://example.com/o/r#
      HTTPS://example.com/o/r?t=1
      http://example.com/o/r?t=1
      file:///tmp/a?b
]
    without = %w[
      https://example.com/o/r
      https://example.com/o/r.git
      https://example.com:8080/o/r
      https://example.com/o/a@b
      https://example.com/o/a=b
      https://example.com/o/a%3Fb
      ./a?b
      plugins/a#b
      debt
]

    assert_equal [[true] * with.size, [false] * without.size], [with, without].map { |urls| urls.map { |url| SharedPlugin.query_or_fragment?(url) } }
  end

  def test_refuses_the_first_plugin_whose_name_is_a_url_with_a_query_or_a_fragment_and_no_other
    listing = -> (name, line) { CrossLint::Core::ListedPlugin.new(name:, ref: "v1", settings: [], line:) }
    plugins = [
      listing.call("https://example.com/o/ok", 1),
      listing.call("./a?b", 2),
      listing.call("https://example.com/o/r?token=SECRET", 3),
      listing.call("https://example.com/o/r#SECRET", 4),
]
    configuration = CrossLint::Core::Configuration.new(file: "c.kdl", plugins:, policies: [], warnings: nil, verbosity: nil)
    mistake = assert_raises(CrossLint::Core::Mistake) { SharedPlugin.refuse_secrets(configuration) }

    assert_equal ["c.kdl", 3], [mistake.file, mistake.line]
    assert_equal 4, assert_raises(CrossLint::Core::Mistake) { SharedPlugin.refuse_secrets(configuration.with(plugins: plugins.drop(3))) }.line
    SharedPlugin.refuse_secrets(configuration.with(plugins: plugins.first(2)))
  end

  def test_refuses_the_first_plugin_whose_name_is_a_url_with_a_user_name_or_password_and_no_other
    listing = -> (name, line, ref = nil) { CrossLint::Core::ListedPlugin.new(name:, ref:, settings: [], line:) }
    plugins = [
      listing.call("./a@b", 1),
      listing.call("https://example.com/o/ok", 2, "v1"),
      listing.call("http://u:p@h/o", 3, "v1"),
      listing.call("https://u:p@h/o/r", 4, "v1"),
      listing.call("https://v@h/o/r", 5, "v1"),
]
    configuration = CrossLint::Core::Configuration.new(file: "c.kdl", plugins:, policies: [], warnings: nil, verbosity: nil)
    mistake = assert_raises(CrossLint::Core::Mistake) { SharedPlugin.refuse_secrets(configuration) }

    assert_equal ["c.kdl", 3], [mistake.file, mistake.line]
    SharedPlugin.refuse_secrets(configuration.with(plugins: plugins.first(2)))
    assert_equal 4, assert_raises(CrossLint::Core::Mistake) { SharedPlugin.refuse_secrets(configuration.with(plugins: plugins.drop(3))) }.line
    SharedPlugin.refuse_secrets(configuration.with(plugins: []))
  end

  def test_takes_a_relative_path_of_folders_joined_by_a_slash
    paths = ["plugins/markdown-links", "a", "a.b/c_d/e-f", "..a/b", "a/b..", "a/.hidden"]

    assert_equal [nil] * paths.size, paths.map { |path| SharedPlugin.path_problem(path) }
  end

  def test_says_what_is_wrong_with_a_path
    problems = {
      "" => "is empty",
      "a\\b" => "has a backslash; write the folders with / between them",
      "/a" => "is absolute; write it relative to the repository's root",
      "C:/a" => "is absolute; write it relative to the repository's root",
      "c:a" => "is absolute; write it relative to the repository's root",
      "a//b" => "has an empty part; write each folder's name, with a single / between them",
      "a/" => "has an empty part; write each folder's name, with a single / between them",
      "a/b/" => "has an empty part; write each folder's name, with a single / between them",
      "a/c:y" => "ends in a folder whose name has other characters than letters, digits, and . _ -; a plugin's name is its folder's name",
      "a/b/." => "has \".\"; write each folder's name, with a single / between them",
      "a/b/.." => "has \"..\"; write each folder's name, with a single / between them",
      "." => "has \".\"; write each folder's name, with a single / between them",
      "a/./b" => "has \".\"; write each folder's name, with a single / between them",
      "../a" => "has \"..\"; write each folder's name, with a single / between them",
      "a/../b" => "has \"..\"; write each folder's name, with a single / between them",
      "a/b c" => "ends in a folder whose name has other characters than letters, digits, and . _ -; a plugin's name is its folder's name",
      "a\nb" => "ends in a folder whose name has other characters than letters, digits, and . _ -; a plugin's name is its folder's name",
    }

    assert_equal problems.values, problems.keys.map { |path| SharedPlugin.path_problem(path) }
  end

  def test_refuses_a_path_naming_the_url_the_ref_the_problem_and_the_path_but_not_a_missing_one_or_a_good_one
    url = "https://example.com/o/repo"

    assert_equal %(shared plugin "#{url}" at v1.2.0 has a path= that has ".."; write each folder's name, with a single / between them: "../x"),
      SharedPlugin.path_refusal(url, "v1.2.0", "../x")
    assert_equal [nil, nil], [SharedPlugin.path_refusal(url, "v1.2.0", nil), SharedPlugin.path_refusal(url, "v1.2.0", "plugins/a")]
  end

  def test_a_listed_plugin_is_named_for_its_path_or_else_its_repository_and_has_no_path_unless_given_one
    listing = -> (path) { CrossLint::Core::ListedPlugin.new(name: "https://example.com/o/repo.git", ref: "v1", path:, settings: [], line: 1) }
    bare = CrossLint::Core::ListedPlugin.new(name: "https://example.com/o/repo.git", ref: "v1", settings: [], line: 1)

    assert_equal %w[markdown-links x repo], [listing.call("plugins/markdown-links").plugin_name, listing.call("x").plugin_name, bare.plugin_name]
    assert_equal [nil, "https://example.com/o/repo.git"], [bare.path, bare.shown]
    assert_equal "https://example.com/o/repo.git (plugins/x)", listing.call("plugins/x").shown
  end

  def test_says_what_is_wrong_with_a_ref
    assert_equal "ext::x doesn't start with https:// or file://", CrossLint::Core::FetchError.scheme("ext::x", ["https://", "file://"]).message
    errors = [
      CrossLint::Core::FetchError.bad_ref("a:b"),
      CrossLint::Core::FetchError.branch("main"),
      CrossLint::Core::FetchError.no_tag("v9"),
      CrossLint::Core::FetchError.no_commit("abc"),
]

    assert_equal [
      '"a:b" is neither a tag name nor a full 40-character commit SHA',
      "main is a branch, and a ref is a tag or a full 40-character commit SHA",
      "the repository has no tag v9, and a ref is a tag or a full 40-character commit SHA",
      "the repository has no commit abc",
], errors.map(&:message)
    assert(errors.all? { |error| error.is_a?(StandardError) })
  end
end
