# frozen_string_literal: true

require "test_helper"

# Core::NgNudge::Glob: the forms of node-glob pattern it converts, and
# every other form it refuses with the reason.
class NgNudgeGlobTest < Minitest::Test
  cover "CrossLint::Core::NgNudge::Glob*"

  Glob = CrossLint::Core::NgNudge::Glob

  def test_converts_ng_nudges_seven_default_patterns
    %w[component directive pipe service guard resolver interceptor].each do |role|
      assert_equal "{path}.#{role}.ts", Glob.convert("**/*.#{role}.ts")
    end
  end

  def test_converts_each_form_that_was_compared_with_node_glob
    {
      "**/*.store.ts" => "{path}.store.ts",
      "*.store.ts" => "{name}.store.ts",
      "app/**/*.store.ts" => "app/{path}.store.ts",
      "d/*/**/*.store.ts" => "d/{name}/{path}.store.ts",
      ".storybook/**/*.story.ts" => ".storybook/{path}.story.ts",
      "main.ts" => "main.ts",
      "app/main.ts" => "app/main.ts",
      "*/main.ts" => "{name}/main.ts",
      "app/*.d.ts" => "app/{name}.d.ts",
      "**/*.ts" => "{path}.ts"
    }.each { |pattern, converted| assert_equal converted, Glob.convert(pattern), pattern }
  end

  def test_cleans_up_dot_slash_double_slash_and_a_folder_followed_by_dot_dot
    {
      "./**/*.store.ts" => "{path}.store.ts",
      "app//**/*.store.ts" => "app/{path}.store.ts",
      "./app/./x//y.ts" => "app/x/y.ts",
      "app/../lib/*.store.ts" => "lib/{name}.store.ts",
      "a/b/../../c.ts" => "c.ts",
      "a/b/../c.ts" => "a/c.ts",
      "a/b/c/../../d/*.ts" => "a/d/{name}.ts"
    }.each { |pattern, converted| assert_equal converted, Glob.convert(pattern), pattern }
  end

  def test_refuses_a_pattern_that_finds_folders_or_starts_at_the_root_or_is_empty
    assert_refused "is empty", ""
    assert_refused "is empty", "."
    assert_refused "is empty", "./."
    assert_refused "starts at the root; write it relative to srcDir", "/src/*.ts"
    assert_refused "starts at the root; write it relative to srcDir", "C:/src/*.ts"
    assert_refused "ends with /, so it finds folders, and an artifact is a file", "app/"
  end

  def test_refuses_dot_dot_that_cleaning_cannot_take_out
    message = "has .. that doesn't follow a folder name; write the path without it"
    assert_refused message, "../x.ts"
    assert_refused message, "a/../../x.ts"
    assert_refused message, "*/../x.ts"
    assert_refused message, "**/../x.ts"
  end

  def test_refuses_a_brace_list_and_says_to_list_a_role_for_each
    message = "has a brace list; CrossLint's path patterns have none, so list a role for each file name"
    assert_refused message, "**/*.{a,b}.ts"
    assert_refused message, "{app,lib}/*.ts"
    assert_refused message, "app/x}.ts"
  end

  def test_refuses_the_wildcards_classes_extglobs_and_negations_a_path_pattern_does_not_have
    {"?" => "app/?.ts", "[" => "app/[ab].ts", "]" => "app/a].ts", "(" => "app/@(a|b).ts", ")" => "app/a).ts", "!" => "!app/*.ts",
     "\\" => "app\\a.ts", "*" => "app/a*b/*.ts"}.each do |found, pattern|
      assert_refused "has #{found}, which CrossLint's path patterns don't have", pattern
    end
    assert_refused "has !, which CrossLint's path patterns don't have", "**/*.!(spec).ts"
  end

  def test_refuses_a_double_star_anywhere_but_before_the_last_segment_and_before_a_wildcard_name
    assert_refused "ends with **; write the files it finds, as in **/*.store.ts", "app/**"
    assert_refused "has ** that isn't right before a last segment of the form *SUFFIX, as in **/*.store.ts", "**/app/*.store.ts"
    assert_refused "has ** that isn't right before a last segment of the form *SUFFIX, as in **/*.store.ts", "**/**/*.store.ts"
    assert_refused "has ** before a file name; CrossLint reads ** only before *SUFFIX, as in **/*.store.ts", "**/main.ts"
    assert_refused "has * in a file name; CrossLint reads * only at the start of the last segment, and as a whole folder name", "app/a*.ts"
    assert_refused "has *, which CrossLint's path patterns don't have", "**/**x.ts"
  end

  def test_refuses_a_suffix_that_does_not_start_with_a_dot_or_end_with_ts
    assert_refused %(has a suffix, "store.ts", that doesn't start with .), "**/*store.ts"
    assert_refused %(has a suffix, "", that doesn't start with .), "**/*"
    assert_refused %(has a suffix, ".store.js", that doesn't end with .ts), "**/*.store.js"
    assert_refused "doesn't end in .ts", "app/main.js"
  end

  def test_refuses_two_wildcard_names_since_one_placeholder_matches_one_text_twice
    message = "has * in two places that CrossLint writes as {name}, which would have to match one text twice"
    assert_refused message, "*/*.store.ts"
    assert_refused message, "*/*/x.ts"
    assert_refused message, "*/*/**/*.store.ts"
    assert_refused message, "app/*/*.store.ts"
    assert_equal "{name}/{path}.store.ts", Glob.convert("*/**/*.store.ts")
  end

  private

  def assert_refused(message, pattern)
    error = assert_raises(Glob::Unsupported, pattern) { Glob.convert(pattern) }

    assert_equal message, error.message, pattern
  end
end
