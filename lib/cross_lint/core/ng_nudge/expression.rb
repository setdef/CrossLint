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

        # A character class's contents for the code points and ranges of
        # code points given, as \uHHHH escapes.
        def self.escapes(codes)
          codes.map do |code|
            case code
            when Range then format('\u%04x-\u%04x', code.begin, code.end)
            else format('\u%04x', code)
            end
          end.join
        end

        # What JavaScript's \s is: white space and line terminators.
        SPACE = escapes([0x09..0x0d, 0x20, 0xa0, 0x1680, 0x2000..0x200a, 0x2028, 0x2029, 0x202f, 0x205f, 0x3000, 0xfeff])

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
            refuse("isn't a regular expression Ruby reads once translated: " + error.message)
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

        def escape(inside:)
          char = @source[@at] || refuse("ends with a \\ that escapes nothing")
          @at += 1
          atom(case char
          when "d", "w", "n", "t" then "\\#{char}"
          when "s" then inside ? SPACE : "[#{SPACE}]"
          when "S" then "[^#{SPACE}]"
          when "b", "B" then boundary(char, inside)
          when "x" then hex(2)
          when "u" then hex(4)
          when "k" then named_reference
          when "1".."9" then reference
          else
            refuse("has \\#{char}, which CrossLint doesn't translate") unless LITERAL.include?(char)
            "\\#{char}"
          end)
        end

        def boundary(char, inside)
          refuse("has \\#{char} in a class, where JavaScript and Ruby read it differently") if inside
          (char == "b") ? BOUNDARY : NOT_BOUNDARY
        end

        # \xHH and \uHHHH are the character with that code. Ruby reads \xHH
        # above 7F as a byte, so both are written as \uHHHH.
        def hex(size)
          digits = @source[@at, size] #: String
          refuse("has \\#{(size == 2) ? "x" : "u"} without #{size} hexadecimal digits after it") unless digits.match?(/\A\h{#{size}}\z/)
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
          loop do
            char = @source[@at] || refuse("has a [ with no ] to close it")
            @at += 1
            break if char == "]"

            member(char)
          end
          atom("]")
        end

        def member(char)
          return escape(inside: true) if char == "\\"

          refuse("has a [ inside a class, as in a POSIX class, which Ruby reads differently") if char == "["
          refuse("has && in a class, which Ruby reads as an intersection") if char == "&" && @source[@at] == "&"
          @out << char
        end
      end
    end
  end
end
