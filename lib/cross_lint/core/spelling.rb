# frozen_string_literal: true

require "did_you_mean"

module CrossLint
  module Core
    module Spelling
      module_function

      def nearest(word, known) = DidYouMean::SpellChecker.new(dictionary: known).correct(word).first

      def unknown(kind, word, known, none: "there are none")
        guess = nearest(word, known)
        return "unknown #{kind} #{word.dump}, did you mean #{guess.dump}?" if guess
        return "unknown #{kind} #{word.dump}; #{none}" if known.empty?

        "unknown #{kind} #{word.dump}; expected #{list(known.map(&:dump))}"
      end

      def list(words, conjunction = "or")
        return words.join(" #{conjunction} ") if words.size < 3

        "#{words.take(words.size - 1).join(", ")}, #{conjunction} #{words.last}"
      end
    end
  end
end
