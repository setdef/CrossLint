# frozen_string_literal: true

require "test_helper"

# Core::NgNudge::Differences: the files the Angular plugin finds for a
# pattern, and the lines for those only node-glob or only CrossLint finds.
class NgNudgeDifferencesTest < Minitest::Test
  cover "CrossLint::Core::NgNudge::Differences*"

  Differences = CrossLint::Core::NgNudge::Differences

  def test_finds_the_files_below_src_dir_that_the_pattern_matches_relative_to_it
    files = ["src/app/a.store.ts", "src/b.store.ts", "src/app/a.service.ts", "lib/c.store.ts", "srcx/d.store.ts", "src/app/deep/e.store.ts"]

    assert_equal ["app/a.store.ts", "b.store.ts", "app/deep/e.store.ts"], Differences.found(files, "src", "{path}.store.ts")
    assert_equal ["b.store.ts"], Differences.found(files, "src", "{name}.store.ts")
    assert_equal ["app/a.store.ts"], Differences.found(files, "src", "app/{name}.store.ts")
  end

  def test_finds_the_files_of_the_whole_project_for_an_empty_src_dir
    assert_equal ["src/a.store.ts", "b.store.ts"], Differences.found(["src/a.store.ts", "b.store.ts", "c.service.ts"], "", "{path}.store.ts")
  end

  def test_skips_a_file_whose_placeholder_matches_a_folder_or_name_that_starts_with_a_dot
    files = ["src/.hidden/a.store.ts", "src/app/.b.store.ts", "src/app/c.store.ts", "src/x.y/d.store.ts"]

    assert_equal ["app/c.store.ts", "x.y/d.store.ts"], Differences.found(files, "src", "{path}.store.ts")
  end

  def test_skips_a_file_when_any_one_of_the_placeholders_matches_a_name_that_starts_with_a_dot
    files = ["src/a/b.x.ts", "src/a/.h/b.x.ts", "src/.a/c.x.ts", "src/a/d/.e.x.ts"]

    assert_equal ["a/b.x.ts"], Differences.found(files, "src", "{name}/{path}.x.ts")
  end

  def test_finds_a_file_in_a_folder_the_pattern_names_though_the_folder_starts_with_a_dot
    assert_equal [".storybook/x.story.ts"], Differences.found(["src/.storybook/x.story.ts", "src/y.story.ts"], "src", ".storybook/{name}.story.ts")
  end

  def test_says_each_file_only_node_glob_finds_and_then_each_file_only_crosslint_finds_in_the_order_of_their_paths
    lines = Differences.new(role: "store", src_dir: "src").lines(["b.ts", "a.ts", "both.ts"], ["z.ts", "both.ts", "y.ts"])

    assert_equal [
      "node-glob finds src/a.ts as a store, and CrossLint doesn't",
      "node-glob finds src/b.ts as a store, and CrossLint doesn't",
      "CrossLint finds src/y.ts as a store, and node-glob doesn't",
      "CrossLint finds src/z.ts as a store, and node-glob doesn't",
], lines
  end

  def test_names_a_file_relative_to_the_projects_root_when_src_dir_is_empty
    assert_equal ["node-glob finds a.ts as a pipe, and CrossLint doesn't"], Differences.new(role: "pipe", src_dir: "").lines(["a.ts"], [])
  end

  def test_says_nothing_when_the_two_find_the_same_files
    assert_empty Differences.new(role: "pipe", src_dir: "src").lines(["a.ts", "b.ts"], ["b.ts", "a.ts"])
  end
end
