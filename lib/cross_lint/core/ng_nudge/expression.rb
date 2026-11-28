# frozen_string_literal: true

module CrossLint
  module Core
    module NgNudge
      # A JavaScript regular expression from ng-nudge's rc.json, as the Ruby
      # regular expression with the same meaning: its source is rewritten
      # where Ruby's meaning differs, kept where it doesn't, and refused
      # (Unsupported, saying why) where the two can't be told to agree.
      class Expression
        class Unsupported < ArgumentError; end

        # The code points from `first` to `last`, both included.
        class Span < Data.define(:first, :last); end

        # What a class member stands for: the Ruby text that says it, the
        # code points it holds, its code point when it is one character,
        # and the text of the source it came from.
        class Member < Data.define(:text, :spans, :code, :source); end

        # One code point as \uHHHH, or \u{H...} above U+FFFF.
        def self.written(code) = (code > 0xffff) ? format('\u{%x}', code) : format('\u%04x', code)

        # A character class's contents for the code points and ranges of
        # code points given, as \uHHHH escapes.
        def self.escapes(codes)
          codes.map do |code|
            case code
            when Range then "#{written(code.begin)}-#{written(code.end)}"
            else written(code)
            end
          end.join
        end

        # The spans of the code points and ranges of code points given.
        def self.spans(codes) = codes.map { |code| code.is_a?(Range) ? Span.new(first: code.begin, last: code.end) : Span.new(first: code, last: code) }

        # The code points that no span of `taken` has, as spans, leaving
        # out the surrogates, which no Ruby text holds.
        def self.complement(taken)
          from = 0
          gaps = [] #: Array[Span]
          (taken + [Span.new(first: 0xd800, last: 0xdfff)]).sort_by(&:first).each do |span|
            gaps << Span.new(first: from, last: span.first - 1) if span.first > from
            from = [from, span.last + 1].max
          end
          (from > 0x10ffff) ? gaps : [*gaps, Span.new(first: from, last: 0x10ffff)]
        end

        # What JavaScript's \s is, as code points and ranges of them.
        SPACE_CODES = [0x09..0x0d, 0x20, 0xa0, 0x1680, 0x2000..0x200a, 0x2028, 0x2029, 0x202f, 0x205f, 0x3000, 0xfeff].freeze

        # What JavaScript's \s is: white space and line terminators.
        SPACE = escapes(SPACE_CODES)

        # What JavaScript's \s holds.
        SPACE_SPANS = spans(SPACE_CODES).freeze

        # What JavaScript's \S holds.
        NOT_SPACE_SPANS = complement(SPACE_SPANS).freeze

        # What JavaScript's \d holds.
        DIGIT_SPANS = spans([0x30..0x39]).freeze

        # What JavaScript's \w holds.
        WORD_SPANS = spans([0x30..0x39, 0x41..0x5a, 0x5f, 0x61..0x7a]).freeze

        # What each escape that stands for a set of characters holds.
        SETS = { "d" => DIGIT_SPANS, "w" => WORD_SPANS, "s" => SPACE_SPANS, "S" => NOT_SPACE_SPANS }.freeze

        # What JavaScript's . is not.
        LINE_END = escapes([0x0a, 0x0d, 0x2028, 0x2029])

        # JavaScript's \b and \B know only ASCII word characters.
        WORD = "A-Za-z0-9_"

        BOUNDARY = "(?:(?<![#{WORD}])(?=[#{WORD}])|(?<=[#{WORD}])(?![#{WORD}]))"

        NOT_BOUNDARY = "(?:(?<![#{WORD}])(?![#{WORD}])|(?<=[#{WORD}])(?=[#{WORD}]))"

        # What a backslash can make a character stand for itself before: the
        # characters that mean something in a regular expression, and /.
        LITERAL = "^$\\.*+?()[]{}|/-"

        # What can follow a ( for a group that doesn't capture, longest last.
        LOOKAROUND = %w[?: ?= ?! ?<= ?<!].freeze

        QUANTIFIER = /\A\{\d+(?:,\d*)?\}/

        NAME = /\A[A-Za-z_][A-Za-z0-9_]*\z/

        def self.translate(source) = new(source).translated

        def initialize(source)
          @source = source
        end

        def translated
          @out = +""
          @at = 0
          @open = [] #: Array[Array[String]]
          @groups = 0
          @closed = [] #: Array[String]
          @named = @source.match?(/\(\?<[^=!]/)
          step while @at < @source.size
          begin
            Regexp.new(@out)
          rescue RegexpError => error
            refuse("isn't a regular expression Ruby reads once translated: #{error.message}")
          end
          @out
        end

        private

        def refuse(message) = raise(Unsupported, message)

        # The source from the character at `from` on, which is never past
        # its end.
        def rest(from) = @source[from..] #: String

        def step
          char = @source[@at] #: String
          @at += 1
          case char
          when "\\" then escape(inside: false)
          when "[" then set
          when "(" then open
          when ")" then close
          when "^" then atom('\A')
          when "$" then atom('\z')
          when "." then atom("[^#{LINE_END}]")
          when "*", "+", "?" then quantifier(char)
          when "{" then braces
          else atom(char)
          end
        end

        def atom(text)
          @quantified = false
          @out << text
        end

        # A quantifier, and the ? after it that makes it lazy. Another one
        # after that is a possessive quantifier in Ruby, and an error in
        # JavaScript.
        def quantifier(text)
          refuse("has a quantifier after a quantifier, which JavaScript refuses and Ruby reads as a possessive or nested one") if @quantified
          @out << text
          @quantified = true
          return unless @source[@at] == "?"

          @out << "?"
          @at += 1
        end

        # {n}, {n,}, and {n,m} are quantifiers. JavaScript reads any other {
        # as itself, and Ruby reads {,m} as a quantifier.
        def braces
          found = rest(@at - 1)[QUANTIFIER]
          refuse("has a { that isn't a quantifier such as {2} or {2,3}; write a { that stands for itself as \\{") unless found
          @at += found.size - 1
          quantifier(found)
        end

        def open
          return capture([], "(") unless @source[@at] == "?"

          plain = LOOKAROUND.find { |kind| @source[@at, kind.size] == kind }
          if plain
            @at += plain.size
            @open.push([])
            return atom("(#{plain}")
          end

          name = rest(@at)[/\A\?<([^>]*)>/, 1]
          refuse("has a group that starts with (?#{@source[@at + 1]}, which CrossLint doesn't translate") unless name
          refuse("has a group name, #{name.dump}, that isn't letters, digits, and _ from a letter or _") unless NAME.match?(name)
          @at += name.size + 3
          capture([name], "(?<#{name}>")
        end

        # A group that captures, which a backreference can name by its number
        # or its name, once it is closed. A name is kept in <>, so that no
        # number is one.
        def capture(names, text)
          @groups += 1
          @open.push([@groups.to_s, *names.map { |name| "<#{name}>" }])
          atom(text)
        end

        def close
          @closed.concat(@open.pop || refuse("has a ) that closes no group"))
          atom(")")
        end

        def escape(inside:) = atom(escaped(inside:))

        def escaped(inside:)
          char = @source[@at] || refuse("ends with a \\ that escapes nothing")
          @at += 1
          case char
          when "d", "w", "n", "t" then "\\#{char}"
          when "s" then inside ? SPACE : "[#{SPACE}]"
          when "S" then "[^#{SPACE}]"
          when "b", "B" then boundary(char, inside)
          when "x" then hex(2)
          when "u" then hex(4)
          when "k", "1".."9" then back_reference(char, inside)
          else
            refuse("has \\#{char}, which CrossLint doesn't translate") unless LITERAL.include?(char)
            "\\#{char}"
          end
        end

        # \k<name> or \N, which JavaScript reads in a class as characters, not
        # as a reference.
        def back_reference(char, inside)
          refuse("has \\#{char} in a class, where JavaScript reads it as characters and a reference is meant outside one") if inside
          (char == "k") ? named_reference : reference
        end

        def boundary(char, inside)
          refuse("has \\#{char} in a class, where JavaScript and Ruby read it differently") if inside
          (char == "b") ? BOUNDARY : NOT_BOUNDARY
        end

        # \xHH and \uHHHH are the character with that code. Ruby reads \xHH
        # above 7F as a byte, so both are written as \uHHHH.
        def hex(size)
          digits = @source[@at, size] #: String
          refuse("has \\#{(size == 2) ? 'x' : 'u'} without #{size} hexadecimal digits after it") unless digits.match?(/\A\h{#{size}}\z/)
          @at += size
          format('\u%04x', digits.hex)
        end

        # \N, with every digit after the first, since JavaScript reads
        # \10 as group 10 when there is one.
        def reference
          digits = rest(@at - 1)[/\A[1-9]\d*/] #: String
          @at += digits.size - 1
          refuse("has a backreference by number in a pattern with named groups, which Ruby numbers differently") if @named
          refuse("has \\#{digits}, a backreference to a group that isn't defined before it") unless @closed.include?(digits)
          "\\k<#{digits}>"
        end

        def named_reference
          name = rest(@at)[/\A<([^>]*)>/, 1]
          refuse("has \\k that isn't followed by <name>") unless name
          refuse("has \\k<#{name}>, which names no group defined before it") unless @closed.include?("<#{name}>")
          @at += name.size + 2
          "\\k<#{name}>"
        end

        # A class. JavaScript and Ruby read [], [^], a [ inside one, and &&
        # in one differently.
        def set
          @out << "["
          if @source[@at] == "^"
            @out << "^"
            @at += 1
          end
          refuse("has [] or [^], which JavaScript and Ruby read differently") if @source[@at] == "]"
          members = [] #: Array[Member]
          loop do
            char = @source[@at] || refuse("has a [ with no ] to close it")
            @at += 1
            break if char == "]"

            members << member(char)
          end
          @out << contents(ranged(members))
          atom("]")
        end

        def member(char)
          return class_escape if char == "\\"

          refuse("has a [ inside a class, as in a POSIX class, which Ruby reads differently") if char == "["
          refuse("has && in a class, which Ruby reads as an intersection") if char == "&" && @source[@at] == "&"
          Member.new(text: char, spans: [Span.new(first: char.ord, last: char.ord)], code: char.ord, source: char)
        end

        # The member a backslash in a class starts: a set of characters, or
        # one.
        def class_escape
          start = @at - 1
          text = escaped(inside: true)
          letter = @source[start + 1] #: String
          source = @source[start...@at] #: String
          code = case letter
          when "n" then 0x0a
          when "t" then 0x09
          when "x", "u" then source[2..].to_s.hex
          when "d", "w", "s", "S" then nil
          else letter.ord
          end
          spans = code ? [Span.new(first: code, last: code)] : SETS.fetch(letter)
          Member.new(text:, spans:, code:, source:)
        end

        # The members with each a-b as one, where both ends are one
        # character. JavaScript reads the - in any other place as itself.
        def ranged(members)
          found = [] #: Array[Member]
          index = 0
          while index < members.size
            from = members.fetch(index)
            dash = members[index + 1]
            to = members[index + 2]
            if dash && to && dash.source == "-" && from.code && to.code
              first = from.code
              last = to.code
              refuse("has a range in a class that ends before it starts, #{from.source}-#{to.source}") if first > last
              found << Member.new(text: "#{from.text}-#{to.text}", spans: [Span.new(first:, last:)], code: nil, source: "#{from.source}-#{to.source}")
              index += 3
            else
              found << from
              index += 1
            end
          end
          found
        end

        # What goes between [ and ]: the members as they are, or, when two
        # of them hold the same code point, which Ruby warns of, the
        # code points they hold, each range written once.
        def contents(members)
          merged = [] #: Array[Span]
          twice = false
          members.flat_map(&:spans).sort_by(&:first).each do |span|
            before = merged.last
            twice ||= !before.nil? && span.first <= before.last
            if before && span.first <= before.last + 1
              merged[-1] = Span.new(first: before.first, last: [before.last, span.last].max)
            else
              merged << span
            end
          end
          return members.map(&:text).join unless twice

          merged.map { |span| (span.first == span.last) ? Expression.written(span.first) : "#{Expression.written(span.first)}-#{Expression.written(span.last)}" }.join
        end
      end
    end
  end
end
