# frozen_string_literal: true

module CrossLint
  module Core
    class JavaScriptError < StandardError; end

    # JavaScript refused the regular expression itself.
    class InvalidExpression < JavaScriptError; end
  end
end
