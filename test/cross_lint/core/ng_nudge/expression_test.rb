# frozen_string_literal: true

require "test_helper"

# Core::NgNudge::Expression: what it rewrites, what it keeps, and what it
# refuses.
class NgNudgeExpressionTest < Minitest::Test
  cover "CrossLint::Core::NgNudge::Expression*"

  Expression = CrossLint::Core::NgNudge::Expression

  # JavaScript's \s, and the characters its . leaves out, as Ruby escapes.
  def self.escaped(*codes) = codes.map { |code| "\\" + "u" + code }.join

  SPACE = [escaped("0009"), "-", escaped("000d", "0020", "00a0", "1680", "2000"), "-", escaped("200a", "2028", "2029", "202f", "205f", "3000", "feff")].join
  LINE_END = escaped("000a", "000d", "2028", "2029")
  BOUNDARY = "(?:(?<![A-Za-z0-9_])(?=[A-Za-z0-9_])|(?<=[A-Za-z0-9_])(?![A-Za-z0-9_]))"
  NOT_BOUNDARY = "(?:(?<![A-Za-z0-9_])(?![A-Za-z0-9_])|(?<=[A-Za-z0-9_])(?=[A-Za-z0-9_]))"

  def test_writes_the_contents_of_a_class_for_codes_and_ranges_of_codes_as_unicode_escapes
    expected = self.class.escaped("0041", "0061") + "-" + self.class.escaped("0063", "0020")

    assert_equal expected, Expression.escapes([0x41, 0x61..0x63, 0x20])
    assert_equal "", Expression.escapes([])
  end

  def test_writes_the_start_and_end_of_the_text_where_javascript_means_them
    assert_equal '\Aabc\z', Expression.translate("^abc$")
    assert_equal '\Aa|b\z', Expression.translate("^a|b$")
  end

  def test_writes_a_dot_as_anything_but_a_line_terminator
    assert_equal "a[^#{LINE_END}]b", Expression.translate("a.b")
  end

  def test_writes_white_space_as_javascript_has_it
    assert_equal "[#{SPACE}]", Expression.translate('\s')
    assert_equal "[^#{SPACE}]", Expression.translate('\S')
    assert_equal "[#{SPACE}a]", Expression.translate('[\sa]')
    assert_equal "[a[^#{SPACE}]]", Expression.translate('[a\S]')
    assert_equal "[^#{SPACE}x]", Expression.translate('[^\sx]')
  end

  def test_writes_a_word_boundary_as_ascii_does
    assert_equal "#{BOUNDARY}foo#{NOT_BOUNDARY}", Expression.translate('\bfoo\B')
  end

  def test_keeps_literals_digits_words_new_lines_and_tabs
    assert_equal 'a-b_c 1\d\w\n\t', Expression.translate('a-b_c 1\d\w\n\t')
  end

  def test_writes_a_code_given_by_x_or_u_as_the_character_with_that_code
    source = '\x41\xE9' + self.class.escaped("00E9") + "é"

    assert_equal "#{self.class.escaped("0041", "00e9", "00e9")}é", Expression.translate(source)
    assert_equal "[#{self.class.escaped("00ff")}]", Expression.translate('[\xff]')
  end

  def test_keeps_groups_lookarounds_and_named_groups
    source = "(a)(?:b)(?<n>c)(?=d)(?!e)(?<=f)(?<!g)|h"

    assert_equal source, Expression.translate(source)
  end

  def test_keeps_quantifiers_and_the_lazy_mark_after_one
    source = "a*?b+?c??d{2}e{2,}f{2,3}?g*h+i?j{10}"

    assert_equal source, Expression.translate(source)
  end

  def test_keeps_what_an_escape_makes_stand_for_itself
    source = '\^\$\\\\\.\*\+\?\(\)\[\]\{\}\|\/\-'

    assert_equal source, Expression.translate(source)
  end

  def test_keeps_a_class_with_a_range_a_negation_and_escapes_in_it
    assert_equal '[a-z_\-.]', Expression.translate('[a-z_\-.]')
    assert_equal '[^abc\]\d]', Expression.translate('[^abc\]\d]')
    assert_equal "[a.$^(|]", Expression.translate("[a.$^(|]")
  end

  def test_keeps_a_backreference_to_a_group_defined_before_it
    assert_equal '(a)\k<1>', Expression.translate('(a)\1')
    assert_equal '(a)(b)\k<2>', Expression.translate('(a)(b)\2')
    assert_equal '(?<n>a)\k<n>', Expression.translate('(?<n>a)\k<n>')
    assert_equal '(a(b)\k<2>)', Expression.translate('(a(b)\2)')
  end

  def test_refuses_what_it_cannot_say_in_ruby_with_the_same_meaning
    {
      '\p{L}' => 'has \p, which CrossLint doesn\'t translate',
      '\h' => 'has \h, which CrossLint doesn\'t translate',
      '\A' => 'has \A, which CrossLint doesn\'t translate',
      '\D' => 'has \D, which CrossLint doesn\'t translate',
      '\0' => 'has \0, which CrossLint doesn\'t translate',
      "[[:alpha:]]" => "has a [ inside a class, as in a POSIX class, which Ruby reads differently",
      "[]" => "has [] or [^], which JavaScript and Ruby read differently",
      "[^]" => "has [] or [^], which JavaScript and Ruby read differently",
      "[a-z" => "has a [ with no ] to close it",
      "[a&&b]" => "has && in a class, which Ruby reads as an intersection",
      '[\b]' => 'has \b in a class, where JavaScript and Ruby read it differently',
      '[\B]' => 'has \B in a class, where JavaScript and Ruby read it differently',
      "a\\" => "ends with a \\ that escapes nothing",
      '\x4' => 'has \x without 2 hexadecimal digits after it',
      '\u{41}' => 'has \u without 4 hexadecimal digits after it',
      '\u12' => 'has \u without 4 hexadecimal digits after it',
      "a*+" => "has a quantifier after a quantifier, which JavaScript refuses and Ruby reads as a possessive or nested one",
      "a{2}+" => "has a quantifier after a quantifier, which JavaScript refuses and Ruby reads as a possessive or nested one",
      "a*?*" => "has a quantifier after a quantifier, which JavaScript refuses and Ruby reads as a possessive or nested one",
      "a{,3}" => "has a { that isn't a quantifier such as {2} or {2,3}; write a { that stands for itself as \\{",
      "a{" => "has a { that isn't a quantifier such as {2} or {2,3}; write a { that stands for itself as \\{",
      "(?i)a" => "has a group that starts with (?i, which CrossLint doesn't translate",
      "(?>a)" => "has a group that starts with (?>, which CrossLint doesn't translate",
      "(?" => "has a group that starts with (?, which CrossLint doesn't translate",
      "(?<n$>a)" => %(has a group name, "n$", that isn't letters, digits, and _ from a letter or _),
      "(?<n" => "has a group that starts with (?<, which CrossLint doesn't translate",
      '\1(a)' => 'has \1, a backreference to a group that isn\'t defined before it',
      '(a\1)' => 'has \1, a backreference to a group that isn\'t defined before it',
      '(a)\2' => 'has \2, a backreference to a group that isn\'t defined before it',
      '(a)(?<n>b)\1' => "has a backreference by number in a pattern with named groups, which Ruby numbers differently",
      '\k<n>(?<n>a)' => 'has \k<n>, which names no group defined before it',
      '\k' => 'has \k that isn\'t followed by <name>',
      '(?<n>a)\k<m>' => 'has \k<m>, which names no group defined before it',
      "a)" => "has a ) that closes no group",
      "(a))" => "has a ) that closes no group"
    }.each do |source, message|
      error = assert_raises(Expression::Unsupported, source) { Expression.translate(source) }

      assert_equal message, error.message, source
    end
  end

  def test_refuses_a_translation_that_ruby_does_not_read
    ["(a", "*a", "a(?<=b+)c", "(?<n>a)(?<=(?<m>b|cc))"].each do |source|
      error = assert_raises(Expression::Unsupported, source) { Expression.translate(source) }

      assert_match(/\Aisn't a regular expression Ruby reads once translated: \S/, error.message, source)
    end
  end

  def test_reads_a_backreference_with_two_digits_as_that_group_and_refuses_one_when_there_are_fewer_groups
    ten = "(a)" * 10

    assert_equal "#{ten}\\k<10>", Expression.translate("#{ten}\\10")
    assert_equal "#{ten}\\k<1>", Expression.translate("#{ten}\\1")
    assert_equal "(a)b\\k<1>x", Expression.translate('(a)b\1x')
    error = assert_raises(Expression::Unsupported) { Expression.translate('(a)\10') }

    assert_equal 'has \10, a backreference to a group that isn\'t defined before it', error.message
  end

  def test_refuses_a_backreference_inside_the_group_it_names_even_after_a_group_that_captures_nothing
    ['(a(?:b)\1)', '(a(?=b)\1)', '(?:a)\1', '(a(?<=b)\1)'].each do |source|
      error = assert_raises(Expression::Unsupported, source) { Expression.translate(source) }

      assert_match(/\Ahas \\1, a backreference to a group that isn't defined before it/, error.message)
    end
    assert_equal '(?:(a))\k<1>', Expression.translate('(?:(a))\1')
  end

  def test_refuses_a_named_backreference_that_names_no_group_defined_before_it_or_names_a_number
    {'(a)\k<1>' => 'has \k<1>, which names no group defined before it', '(a)(?<n>b)\k<>' => 'has \k<>, which names no group defined before it',
     '(?<n>a)\k<n' => 'has \k that isn\'t followed by <name>', '(?<n>a)\k' => 'has \k that isn\'t followed by <name>',
     '(?<n>a)\kn>' => 'has \k that isn\'t followed by <name>'}.each do |source, message|
      error = assert_raises(Expression::Unsupported, source) { Expression.translate(source) }

      assert_equal message, error.message, source
    end
    assert_equal '(?<n>a)\k<n>b', Expression.translate('(?<n>a)\k<n>b')
  end

  def test_keeps_a_quantifier_after_an_escape_and_after_a_closed_group_and_refuses_one_after_a_quantifier
    assert_equal '\d+\w*(a)?x{2}', Expression.translate('\d+\w*(a)?x{2}')
    assert_equal 'a*\d+', Expression.translate('a*\d+')
    assert_equal 'a*[\d]+', Expression.translate('a*[\d]+')
    message = "has a quantifier after a quantifier, which JavaScript refuses and Ruby reads as a possessive or nested one"
    ["a?+", "a?*", "a{2}?+", "a*{2}", "a+?*"].each { |source| assert_equal message, assert_raises(Expression::Unsupported) { Expression.translate(source) }.message }
  end

  def test_keeps_an_ampersand_in_a_class_unless_it_is_followed_by_another
    assert_equal "[a&]", Expression.translate("[a&]")
    assert_equal "[&b]", Expression.translate("[&b]")
    assert_equal "[&a&b]", Expression.translate("[&a&b]")
    assert_raises(Expression::Unsupported) { Expression.translate("[a&&]") }
    assert_raises(Expression::Unsupported) { Expression.translate("[&&a]") }
  end

  def test_reads_the_names_of_groups_by_what_both_languages_allow
    assert_equal "(?<n_1>a)", Expression.translate("(?<n_1>a)")
    assert_equal "(?<n>a)", Expression.translate("(?<n>a)")
    {"(?<1n>a)" => "1n", "(?<>a)" => "", "(?<n m>a)" => "n m", "(?<n$>a)" => "n$"}.each do |source, name|
      error = assert_raises(Expression::Unsupported, source) { Expression.translate(source) }

      assert_equal "has a group name, #{name.dump}, that isn't letters, digits, and _ from a letter or _", error.message
    end
  end

  def test_translates_each_backreference_digit_run_as_one_number
    nine = "(a)" * 9
    translated = Expression.translate("#{nine}\\9\\1")

    assert_equal "#{nine}\\k<9>\\k<1>", translated
    assert_match(/\A#{translated}\z/, "a" * 11)
  end
end
