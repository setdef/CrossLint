# frozen_string_literal: true

require "test_helper"

class KDLDocumentTest < Minitest::Test
  cover "CrossLint::Adapters::KDLDocument*"

  Document = CrossLint::Adapters::KDLDocument
  Mistake = CrossLint::Core::Mistake

  def test_gives_each_node_the_line_its_name_is_on
    document = Document.new(<<~KDL, "a.kdl")
      // a comment
      top "x" {
        /- skipped "y"
        inner \\
          "z"
        "quoted name" 1
      }
      last; after
    KDL

    assert_equal [["top", 2], ["last", 8], ["after", 8]], document.nodes.map { |node| [node.name, node.line] }
    assert_equal [["inner", 4, ["z"]], ["quoted name", 6, [1]]],
      document.nodes.first.children.map { |node| [node.name, node.line, node.arguments] }
  end

  def test_reads_values_as_plain_ruby_values
    node = Document.new(%(n "s" 1 2.5 #true #false #null raw=#"r"# bare=word), "a.kdl").nodes.first

    assert_equal [["s", 1, 2.5, true, false, nil], {"raw" => "r", "bare" => "word"}], [node.arguments, node.properties]
  end

  def test_names_the_file_and_line_of_a_syntax_error
    assert_mistake "isn't valid KDL: unexpected $end :EOF", "a.kdl", 3, %(a 1\nb {\n)
    assert_mistake "isn't valid KDL: Identifier cannot be a literal", "a.kdl", 2, %(a 1\nb true\n)
    assert_mistake %(isn't valid KDL: unexpected STRING "late"), "a.kdl", 2, %(n {\n} "late"\n)
    assert_mistake "isn't valid KDL: Unexpected NEWLINE in string literal", "a.kdl", 12, ("x\n" * 11) + %(n            "a\n)
  end

  def test_refuses_a_type_annotation
    assert_mistake "n has the type annotation (t), which CrossLint doesn't read", "a.kdl", 1, %((t)n)
    assert_mistake "n has the type annotation (t), which CrossLint doesn't read", "a.kdl", 2, %(m\nn x=(t)1)
    assert_mistake "n has the type annotation (date), which CrossLint doesn't read", "a.kdl", 1, %(n (date)"nope")
  end

  def test_refuses_what_is_not_utf_8
    assert_mistake "isn't valid UTF-8", "a.kdl", nil, %(n "\xFF")
  end

  def test_loads_a_file_as_utf_8
    Dir.mktmpdir("crosslint") do |folder|
      path = write(folder, "a.kdl", %(\xEF\xBB\xBFn "é"\n).b)
      document = Document.load(path, "a.kdl")

      assert_equal [["n", ["é"]], "a.kdl"], [document.nodes.map { |node| [node.name, node.arguments] }.first, document.file]
      assert_equal Encoding::UTF_8, document.nodes.first.arguments.first.encoding
    end
  end

  def test_takes_the_arguments_a_node_has
    document = Document.new(%(one "a"\ntwo "a" 2\nnone), "a.kdl")
    one, two, none = document.nodes

    assert_equal ["a"], document.strings(one, "one NAME", 1)
    assert_equal "a", document.string(one, "one NAME")
    assert_equal ["a", 2], document.arguments(two, "two NAME N", 2)
    assert_equal [], document.arguments(none, "none", 0)
    assert_refuses "two has 2 arguments; write it as two NAME", document, two, -> { document.string(two, "two NAME") }
    assert_refuses "one has 1 argument; write it as one A B", document, one, -> { document.arguments(one, "one A B", 2) }
    assert_refuses "two has 2 where a string goes; write it as two A B", document, two, -> { document.strings(two, "two A B", 2) }
    null = Document.new(%(n #null), "a.kdl").nodes.first

    assert_refuses "n has nil where a string goes; write it as n NAME", document, null, -> { document.string(null, "n NAME") }
  end

  def test_takes_the_properties_and_children_it_allows
    document = Document.new(%(n a=1 { c; d; }), "a.kdl")
    node = document.nodes.first

    assert_equal({"a" => 1}, document.properties(node, ["a"]))
    document.children(node, %w[c d e])
    assert_refuses %(unknown property "a"; n takes none), document, node, -> { document.properties(node, []) }
    assert_refuses %(unknown node "d"; expected "c"), document, node.children.last, -> { document.children(node, ["c"]) }
    assert_refuses %(unknown node "c"; n takes no children), document, node.children.first, -> { document.children(node, []) }
  end

  def test_reads_a_string_or_boolean_property
    document = Document.new(%(n s="x" b=#false t=#true i=1 z=#null), "a.kdl")
    node = document.nodes.first

    assert_equal ["x", nil, false, true, nil], [document.string_property(node, "s"), document.string_property(node, "none"),
      document.boolean_property(node, "b"), document.boolean_property(node, "t"), document.boolean_property(node, "none")]
    assert_refuses "i= takes a string, not 1", document, node, -> { document.string_property(node, "i") }
    assert_refuses "z= takes a string, not nil", document, node, -> { document.string_property(node, "z") }
    assert_refuses %(s= takes #true or #false, not "x"), document, node, -> { document.boolean_property(node, "s") }
    assert_refuses "z= takes #true or #false, not nil", document, node, -> { document.boolean_property(node, "z") }
  end

  def test_takes_one_of_the_choices
    document = Document.new(%(n), "a.kdl")
    node = document.nodes.first

    assert_equal :none, document.choice(node, "mode", "none", %w[all none])
    assert_refuses %(unknown mode "nnoe", did you mean "none"?), document, node, -> { document.choice(node, "mode", "nnoe", %w[all none]) }
  end

  def test_finds_a_child_that_is_there_once
    document = Document.new(%(p "x" {\n  a 1\n  b 2\n  b 3\n}\n), "a.kdl")
    node = document.nodes.first

    assert_equal [[1], nil], [document.optional_child(node, "a").arguments, document.optional_child(node, "c")]
    assert_equal [1], document.required_child(node, "a").arguments
    assert_refuses %(p "x" has no c), document, node, -> { document.required_child(node, "c") }
    assert_refuses "p has b twice; the first is on line 3", document, node.children.last, -> { document.optional_child(node, "b") }
  end

  private

  def assert_mistake(message, file, line, source)
    mistake = assert_raises(Mistake) { Document.new(source, file) }

    assert_equal [message, file, line], [mistake.message, mistake.file, mistake.line]
  end

  def assert_refuses(message, document, node, call)
    mistake = assert_raises(Mistake, &call)

    assert_equal [message, document.file, node.line], [mistake.message, mistake.file, mistake.line]
  end
end
