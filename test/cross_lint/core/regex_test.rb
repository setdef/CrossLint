# frozen_string_literal: true

require "test_helper"

class RegexTest < Minitest::Test
  cover "CrossLint::Core::Regex*"

  include CrossLint::Core

  ROUTE = %((?<verb>get|post) "(?<route>[^"]+)", to: "(?<controller>\\w+)#(?<action>\\w+)")

  def test_finds_each_match_with_its_named_captures_and_the_line_it_starts_on
    routes = %(get "/cart", to: "carts#show"\n\npost "/cart", to: "carts#create"\n)

    assert_equal %w[verb route controller action], Regex.new(source: ROUTE).captures
    assert_equal [[{"verb" => "get", "route" => "/cart", "controller" => "carts", "action" => "show"}, 1],
      [{"verb" => "post", "route" => "/cart", "controller" => "carts", "action" => "create"}, 3]], Regex.new(source: ROUTE).matches(routes, {})
  end

  def test_gives_a_capture_that_took_no_part_in_a_match_as_nil
    assert_equal [[{"a" => nil, "b" => "x"}, 1]], Regex.new(source: "(?<a>y)?(?<b>x)").matches("x", {})
  end

  def test_gives_the_line_of_the_first_match_or_nil
    regex = Regex.new(source: "def show")

    assert_equal [3, nil], [regex.first_line("class A\n\n  def show\n  def show\n", {}), regex.first_line("def index", {})]
  end

  def test_puts_in_each_placeholders_value_as_literal_text
    regex = Regex.new(source: 'def {action}\b')

    assert_equal [1, nil], [regex.first_line("  def show.all\n", {"action" => "show.all"}), regex.first_line("  def showXall\n", {"action" => "show.all"})]
    assert_equal 1, Regex.new(source: "^x{2}$").first_line("xx", {})
    assert_equal ["action"], regex.placeholders
  end

  def test_reads_a_brace_after_a_backslash_as_a_brace_and_never_as_a_placeholder
    assert_equal 1, Regex.new(source: '\{action}').first_line("{action}", {})
    assert_empty Regex.new(source: '\{action}').placeholders
  end

  def test_reads_every_systems_line_endings_as_a_newline_and_skips_a_byte_order_mark
    regex = Regex.new(source: "^b$")

    assert_equal [2, 2, 3], ["a\r\nb\r\n", "a\rb", "a\n\r\nb"].map { |text| regex.first_line(text, {}) }
    assert_equal 1, Regex.new(source: "^a").first_line("\uFEFFa", {})
    assert_nil Regex.new(source: "a.b").first_line("a\nb", {})
  end

  def test_says_what_makes_a_source_no_regex
    {
      ["(", []] => "regex \"(\" isn't one Ruby reads: ",
      ["{x}", []] => 'regex "{x}" has unknown placeholder "{x}"; write \\{ for a brace',
      ["{acton}", ["action"]] => 'regex "{acton}" has unknown placeholder "{acton}", did you mean "{action}"?',
      ["(?m:.)", []] => 'regex "(?m:.)" has (?m, which Ruby reads as letting . match a newline and PCRE and JavaScript as letting ^ and $ match at each line',
      ["(?im)", []] => 'regex "(?im)" has (?im, which Ruby reads',
      ['\h', []] => 'regex "\\\\h" has \\h, which Ruby reads as a hex digit and PCRE as a space or a tab; write [0-9a-fA-F] or [ \\t]',
      ['[\H]', []] => 'regex "[\\\\H]" has \\H, which Ruby reads as',
      ['\v', []] => 'regex "\\\\v" has \\v, which Ruby reads as a vertical tab and PCRE as any vertical space; write \\x0B or [\\n\\f]',
      ['\Qa\E', []] => 'regex "\\\\Qa\\\\E" has \\Q, which Ruby reads as the letter Q alone and PCRE as an escape or an error; write Q',
      ['\pL', []] => 'regex "\\\\pL" has \\p with no braces, which Ruby reads as the letter p alone and PCRE as a Unicode property; write \\p{L}',
      ["x{,3}", []] => 'regex "x{,3}" has {,3}, which Ruby reads as {0,3} and JavaScript as the text {,3}; write {0,3}',
      ["[[:alpha:]]", []] => 'regex "[[:alpha:]]" has [:alpha:], which Ruby reads with every Unicode character and PCRE with ASCII alone; ' \
        'write a property, such as \\p{Alpha}, or the ASCII characters, such as [A-Za-z]'
    }.each do |(source, known), message|
      problem = Regex.problem(source, known)

      assert problem&.start_with?(message), "#{source}: #{problem.inspect}"
    end
  end

  def test_takes_what_ruby_and_pcre_read_alike
    sources = ['(?i)(?<a>a)\b\d\w\s\A\z\Z\G\K\R\X\e\n\t\x41A\p{L}\P{L}\k<a>', '(?<a>x)(?-m)(?:y)\(?mode\)', "[(?m]", "a{2,3}", 'def {action}\b']

    assert_equal [nil] * sources.size, sources.map { |source| Regex.problem(source, ["action"]) }
    assert_raises(Regex::Invalid) { Regex.new(source: "(") }
  end

  def test_ends_a_search_that_runs_longer_than_its_time_limit
    regex = Regex.new(source: '^(a+)+\1$', time_limit: 0.01)

    assert_raises(Regexp::TimeoutError) { regex.first_line(("a" * 32) + "c", {}) }
    assert_equal 1, Regex::TIME_LIMIT
  end

  def test_refuses_text_that_isnt_utf_8
    error = assert_raises(Regex::NotText) { Regex.new(source: "a").first_line("caf\xE9".b.force_encoding(Encoding::UTF_8), {}) }

    assert_equal "isn't UTF-8", error.message
  end
end
