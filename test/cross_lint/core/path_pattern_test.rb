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

  private

  def assert_invalid(message, source)
    error = assert_raises(PathPattern::Invalid) { PathPattern.new(source:) }

    assert_equal message, error.message
  end
end
