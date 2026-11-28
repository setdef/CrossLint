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

  def test_gives_each_string_the_line_and_column_it_starts_at_counted_in_characters
    nodes = Document.new(%(plugin "é" ref="v1"\n  other ref=#"v2"# "a"), "a.kdl").nodes
    words = [nodes.first.properties.fetch("ref"), nodes.first.arguments.first, nodes.last.properties.fetch("ref"), nodes.last.arguments.first]

    assert_equal [["v1", 1, 16], ["é", 1, 8], ["v2", 2, 13], ["a", 2, 20]], words.map { |word| [word, word.line, word.column] }
  end

  def test_reads_values_as_plain_ruby_values
    node = Document.new(%(n "s" 1 2.5 #true #false #null raw=#"r"# bare=word), "a.kdl").nodes.first

    assert_equal [["s", 1, 2.5, true, false, nil], { "raw" => "r", "bare" => "word" }], [node.arguments, node.properties]
  end

  def test_names_the_file_and_line_of_a_syntax_error
    assert_mistake "isn't valid KDL: unexpected $end :EOF", "a.kdl", 3, %(a 1\nb {\n)
    assert_mistake "isn't valid KDL: Identifier cannot be a literal", "a.kdl", 2, %(a 1\nb true\n)
    assert_mistake %(isn't valid KDL: unexpected STRING "late"), "a.kdl", 2, %(n {\n} "late"\n)
    assert_mistake "isn't valid KDL: Unexpected NEWLINE in string literal", "a.kdl", 12, %(#{"x\n" * 11}n            "a\n)
  end

  def test_refuses_a_type_annotation
    assert_mistake "n has the type annotation (t), which CrossLint doesn't read", "a.kdl", 1, %((t)n)
    assert_mistake "n has the type annotation (t), which CrossLint doesn't read", "a.kdl", 2, %(m\nn x=(t)1)
    assert_mistake "n has the type annotation (date), which CrossLint doesn't read", "a.kdl", 1, %(n (date)"nope")
  end

  def test_reads_a_type_annotation_it_is_told_a_property_at_the_top_may_have
    typed = { "helper" => { "command" => ["crosslint"] } }
    helper = Document.new(%(helper command=(crosslint)"ruby" file="a.rb"), "a.kdl", typed:).nodes.first

    assert_equal [Document::Typed.new(type: "crosslint", value: "ruby"), "a.rb"], helper.properties.values_at("command", "file")
    [
      %(helper command=(other)"ruby"),
      %(helper file=(crosslint)"a.rb"),
      %(other command=(crosslint)"ruby"),
      %(helper (crosslint)"x"),
      %(a {\n  helper command=(crosslint)"ruby"\n}\n),
].each do |source|
      assert_raises(Mistake, source) { Document.new(source, "a.kdl", typed:) }
    end
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

    assert_equal({ "a" => 1 }, document.properties(node, ["a"]))
    document.children(node, %w[c d e])
    assert_refuses %(unknown property "a"; n takes none), document, node, -> { document.properties(node, []) }
    assert_refuses %(unknown node "d"; expected "c"), document, node.children.last, -> { document.children(node, ["c"]) }
    assert_refuses %(unknown node "c"; n takes no children), document, node.children.first, -> { document.children(node, []) }
  end

  def test_reads_a_string_or_boolean_property
    document = Document.new(%(n s="x" b=#false t=#true i=1 z=#null), "a.kdl")
    node = document.nodes.first

    assert_equal ["x", nil, false, true, nil], [
      document.string_property(node, "s"),
      document.string_property(node, "none"),
      document.boolean_property(node, "b"),
      document.boolean_property(node, "t"),
      document.boolean_property(node, "none"),
]
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

  def test_reads_the_minimum_version_on_the_first_line
    found = Document.new(%(// for CrossLint 1.2\ncrosslint min="1.2"\nplugin "a"\n), "a.kdl").minimum

    assert_equal ["1.2", [1, 2, 0], "a.kdl", 2], [found.text, found.version.numbers, found.file, found.line]
    assert_nil Document.new(%(plugin "a"\n), "a.kdl").minimum
    assert_nil Document.new("", "a.kdl").minimum
  end

  def test_reads_only_the_minimum_of_the_crosslint_line_so_a_newer_crosslint_can_add_to_it
    found = Document.new(%(crosslint "x" min="2" soft=#true {\n  more\n}\nunknown-node\n), "a.kdl").minimum

    assert_equal "2", found.text
  end

  def test_refuses_a_crosslint_line_that_is_not_first_or_is_there_twice
    assert_minimum_mistake "crosslint comes after plugin on line 1; write it as the first line, so that a CrossLint too old for the file " \
      "says so before it reads any other", 2, %(plugin "a"\ncrosslint min="1.2"\n)
    assert_minimum_mistake "crosslint is set twice; the first is on line 1", 3, %(crosslint min="1.2"\nplugin "a"\ncrosslint min="1.3"\n)
  end

  def test_refuses_a_crosslint_line_with_no_bare_version
    assert_minimum_mistake %(crosslint has no min=; write it as crosslint min="1.2"), 1, %(crosslint "1.2"\n)
    [%(">=1.2"), %("1.2.0-rc.1"), %("v1.2"), %("1.2.3.4"), "1.2", "#null"].each do |value|
      shown = Document.new("n x=#{value}", "a.kdl").nodes.first.properties.fetch("x").inspect
      assert_minimum_mistake "crosslint min= takes a version of one to three numbers in a string, with no operator or pre-release part, " \
        "such as min=\"1.2\", not #{shown}", 1, %(crosslint min=#{value}\n)
    end
  end

  def test_refuses_anything_but_min_on_the_crosslint_line_once_the_minimum_is_read
    assert_minimum_mistake %(crosslint has 1 argument; write it as crosslint min="1.2"), 1, %(crosslint "x" min="1.2"\n), whole: true
    assert_minimum_mistake %(unknown property "soft"; expected "min"), 1, %(crosslint min="1.2" soft=#true\n), whole: true
    assert_minimum_mistake %(unknown node "more"; crosslint takes no children), 2, %(crosslint min="1.2" {\n  more\n}\n), whole: true
    assert_equal "1.2", Document.new(%(crosslint min="1.2"\n), "a.kdl").whole_minimum.text
    assert_nil Document.new(%(plugin "a"\n), "a.kdl").whole_minimum
  end

  def test_reads_the_minimum_version_from_the_lines_before_one_it_cant_parse
    found = Document.minimum(%(crosslint min="9"\nplugin "a"\nnew-syntax "a\n), "a.kdl")
    typed = Document.minimum(%(crosslint min="9"\nhelper command=(crosslint)"node"\n), "a.kdl", typed: { "helper" => { "command" => ["crosslint"] } })

    commented = Document.minimum(%(// for CrossLint 9\n\ncrosslint min="9"\nnew-syntax "a\n), "a.kdl")

    assert_equal [["9", 1], ["9", 1], ["9", 3]], [found, typed, commented].map { |each| [each.text, each.line] }
    assert_equal "1.2", Document.minimum(%(crosslint min="1.2"\nplugin "a"\n), "a.kdl").text
  end

  def test_raises_the_files_own_mistake_when_no_line_before_it_has_the_minimum_version
    [%(plugin "a"\nnew-syntax "a\n), %(new-syntax "a\n), %(plugin {\ncrosslint min="9"\nnew-syntax "a\n), "\xFF"].each do |source|
      expected = assert_raises(Mistake) { Document.new(source.dup.force_encoding(Encoding::UTF_8), "a.kdl") }
      mistake = assert_raises(Mistake) { Document.minimum(source.dup.force_encoding(Encoding::UTF_8), "a.kdl") }

      assert_equal [expected.message, expected.line], [mistake.message, mistake.line]
    end
  end

  private

  def assert_minimum_mistake(message, line, source, whole: false)
    document = Document.new(source, "a.kdl")
    mistake = assert_raises(Mistake) { whole ? document.whole_minimum : document.minimum }

    assert_equal [message, "a.kdl", line], [mistake.message, mistake.file, mistake.line]
  end

  def assert_mistake(message, file, line, source)
    mistake = assert_raises(Mistake) { Document.new(source, file) }

    assert_equal [message, file, line], [mistake.message, mistake.file, mistake.line]
  end

  def assert_refuses(message, document, node, call)
    mistake = assert_raises(Mistake, &call)

    assert_equal [message, document.file, node.line], [mistake.message, mistake.file, mistake.line]
  end
end
