# frozen_string_literal: true

require_relative "spelling"

module CrossLint
  module Core
    class Regex < Data.define(:source, :time_limit)
      TIME_LIMIT = 1

      # One unit of a source, read left to right, so that a backslash
      # always takes the character after it: an escape, a placeholder, an
      # inline option group, a POSIX bracket, a {,n} quantifier, or any
      # other character.
      TOKEN = /\\(?:[pP]\{[^}]*\}|.)|\{[A-Za-z_]\w*\}|\(\?[A-Za-z]*(?:-[A-Za-z]*)?[:)]|\[:\^?[A-Za-z]+:\]|\{,\d+\}|./m

      PLACEHOLDER = /\A\{([A-Za-z_]\w*)\}\z/

      # The letters whose escapes Ruby and PCRE read alike. Ruby reads an
      # escape of any other letter as the letter alone, with no error.
      ESCAPES = "aAbBcdDefgGkKnprRsStuwWxXzZ"

      REASONS = {
        "\\h" => "a hex digit and PCRE as a space or a tab; write [0-9a-fA-F] or [ \\t]",
        "\\H" => "anything but a hex digit and PCRE as anything but a space or a tab; write [^0-9a-fA-F] or [^ \\t]",
        "\\v" => "a vertical tab and PCRE as any vertical space; write \\x0B or [\\n\\f]"
      }.freeze

      class Invalid < ArgumentError; end

      class NotText < StandardError; end

      def self.problem(source, known)
        tokens = tokens(source)
        tokens.each do |token|
          refused = refusal(token, known)
          return "regex #{source.dump} has #{refused}" if refused
        end
        Regexp.new(tokens.map { |token| token.match?(PLACEHOLDER) ? "x" : token }.join)
        nil
      rescue RegexpError => error
        "regex #{source.dump} isn't one Ruby reads: #{error.message}"
      end

      def self.tokens(source) = source.scan(TOKEN) #: Array[String]

      # What a token is that Ruby reads without an error and PCRE or
      # JavaScript, the dialects most tools share, reads another way, or
      # nil.
      def self.refusal(token, known)
        placeholder = token[PLACEHOLDER, 1]
        return unknown(placeholder, known) if placeholder && !known.include?(placeholder)

        case token
        when /\A\\[pP]\z/ then "#{token} with no braces, which Ruby reads as the letter #{token.delete_prefix("\\")} alone and PCRE as a Unicode property; write #{token}{L}"
        when /\A\\[A-Za-z]\z/ then escape(token)
        when /\A\(\?[a-z]*m/ then "#{token.chomp(":").chomp(")")}, which Ruby reads as letting . match a newline and PCRE and JavaScript as letting ^ and $ " \
          "match at each line; ^ and $ match at each line here, and [\\s\\S] matches any character"
        when /\A\{,(\d+)\}\z/ then "#{token}, which Ruby reads as {0,#{Regexp.last_match(1)}} and JavaScript as the text #{token}; write {0,#{Regexp.last_match(1)}}"
        when /\A\[:/ then "#{token}, which Ruby reads with every Unicode character and PCRE with ASCII alone; " \
          "write a property, such as \\p{Alpha}, or the ASCII characters, such as [A-Za-z]"
        end
      end

      def self.unknown(placeholder, known)
        Spelling.unknown("placeholder", "{#{placeholder}}", known.map { |name| "{#{name}}" }, none: "write \\{ for a brace")
      end

      def self.escape(token)
        letter = token.delete_prefix("\\")
        return "#{token}, which Ruby reads as #{REASONS.fetch(token)}" if REASONS.key?(token)
        return if ESCAPES.include?(letter)

        "#{token}, which Ruby reads as the letter #{letter} alone and PCRE as an escape or an error; write #{letter}"
      end

      private_class_method :refusal, :unknown, :escape

      def initialize(source:, time_limit: TIME_LIMIT)
        problem = Regex.problem(source, placeholders_of(source))
        raise Invalid, problem if problem

        super
      end

      def placeholders = placeholders_of(source)

      def captures = regexp({}).names

      # Each match, with what each capture matched, nil for one that took
      # no part, and the line the match starts on.
      def matches(text, values)
        normal = lines(text)
        found = [] #: Array[[Hash[String, String?], Integer]]
        line = 1
        counted = 0
        normal.scan(regexp(values)) do
          match = Regexp.last_match #: MatchData
          start = match.byteoffset(0).fetch(0) #: Integer
          line += normal.byteslice(counted, start - counted).to_s.count("\n")
          counted = start
          found << [match.named_captures, line]
        end
        found
      end

      def first_line(text, values)
        normal = lines(text)
        match = regexp(values).match(normal)
        return unless match

        start = match.byteoffset(0).fetch(0) #: Integer
        normal.byteslice(0, start).to_s.count("\n") + 1
      end

      private

      def placeholders_of(text) = Regex.tokens(text).filter_map { |token| token[PLACEHOLDER, 1] }.uniq

      # Every system's line endings as \n, so ^, $, and . read the same on
      # each, and a leading byte order mark dropped, as editors do.
      def lines(text)
        raise NotText, "isn't UTF-8" unless text.valid_encoding?

        text.delete_prefix("\uFEFF").gsub(/\r\n?/, "\n")
      end

      def regexp(values)
        body = Regex.tokens(source).map do |token|
          name = token[PLACEHOLDER, 1]
          name ? Regexp.escape(values.fetch(name)) : token
        end
        Regexp.new(body.join, timeout: time_limit)
      end
    end
  end
end
