# frozen_string_literal: true

require "json"

module CrossLint
  module Core
    module HelperExchange
      def self.said(debug, name, input)
        debug&.write("helper") { "#{name} gets #{JSON.generate(input)}" }
        answer = yield
        debug&.write("helper") { "#{name} answers #{JSON.generate(answer)}" }
        answer
      end
    end
  end
end
