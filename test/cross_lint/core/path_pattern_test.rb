# frozen_string_literal: true

require "test_helper"

class PathPatternTest < Minitest::Test
  cover "CrossLint::Core::PathPattern*"

  PathPattern = CrossLint::Core::PathPattern

  def test_lists_its_placeholders_once_each_in_order
    assert_equal ["name", "path"], PathPattern.new(source: "src/{name}/{path}.{name}.ts").placeholders
    assert_empty PathPattern.new(source: "README.md").placeholders
    assert_equal "lib/{path}.rb", PathPattern.new(source: "lib/{path}.rb").source
  end

  def test_refuses_an_empty_pattern
    assert_invalid %(path pattern "" is empty), ""
  end

  def test_refuses_a_backslash
    assert_invalid %(path pattern "lib\\\\{path}.rb" has \\; write / between folders on every system), "lib\\{path}.rb"
  end

  def test_refuses_a_placeholder_it_does_not_have
    assert_invalid %(path pattern "lib/{pth}.rb" has unknown placeholder "{pth}", did you mean "{path}"?), "lib/{pth}.rb"
    assert_invalid %(path pattern "{}.rb" has unknown placeholder "{}"; expected "{path}" or "{name}"), "{}.rb"
  end

  def test_refuses_a_brace_that_pairs_with_nothing
    assert_invalid %(path pattern "lib/{path.rb" has a { that pairs with nothing), "lib/{path.rb"
    assert_invalid %(path pattern "lib/path}.rb" has a } that pairs with nothing), "lib/path}.rb"
    assert_invalid %(path pattern "{{path}}" has a { that pairs with nothing), "{{path}}"
  end

  def test_matches_folders_and_a_file_name_with_path
    pattern = PathPattern.new(source: "lib/{path}.rb")

    assert_equal({ "path" => "fledge/archive" }, pattern.match("lib/fledge/archive.rb"))
    assert_equal({ "path" => "fledge" }, pattern.match("lib/fledge.rb"))
    assert_equal({ "path" => "a/b/c.d" }, pattern.match("lib/a/b/c.d.rb"))
    [".rb", "lib/.rb", "lib//a.rb", "lib/a/.rb", "lib/a.rbs", "xlib/a.rb", "lib/a.rb/x", "Lib/a.rb", "lib/a.RB"].each do |path|
      assert_nil pattern.match(path), path
    end
  end

  def test_matches_one_segment_with_name
    pattern = PathPattern.new(source: "docs/{name}.md")

    assert_equal({ "name" => "intro" }, pattern.match("docs/intro.md"))
    assert_nil pattern.match("docs/guide/intro.md")
    assert_equal({ "path" => "src/app", "name" => "card" },
      PathPattern.new(source: "{path}/{name}.component.ts").match("src/app/card.component.ts"))
  end

  def test_gives_the_first_placeholder_as_much_as_it_can_take
    assert_equal({ "path" => "a.b", "name" => "c" }, PathPattern.new(source: "{path}.{name}.ts").match("a.b.c.ts"))
  end

  def test_matches_a_placeholder_written_twice_to_the_same_text
    pattern = PathPattern.new(source: "{name}/{name}.ts")

    assert_equal({ "name" => "card" }, pattern.match("card/card.ts"))
    assert_nil pattern.match("card/other.ts")
  end

  def test_matches_the_rest_of_a_pattern_as_written
    assert_equal({}, PathPattern.new(source: "a+b (1).md").match("a+b (1).md"))
    assert_nil PathPattern.new(source: "a.md").match("abmd")
    assert_nil PathPattern.new(source: "*.md").match("a.md")
  end

  def test_expands_each_placeholder_to_its_value
    assert_equal "sig/fledge/archive.rbs", PathPattern.new(source: "sig/{path}.rbs").expand({ "path" => "fledge/archive" })
    assert_equal "a/b/b.spec.ts", PathPattern.new(source: "{path}/{name}/{name}.spec.ts").expand({ "path" => "a", "name" => "b" })
    assert_equal "README.md", PathPattern.new(source: "README.md").expand({})
  end

  private

  def assert_invalid(message, source)
    error = assert_raises(PathPattern::Invalid) { PathPattern.new(source:) }

    assert_equal message, error.message
  end
end
