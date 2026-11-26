# frozen_string_literal: true

# CrossLint checks the rules that span files, such as "every source file
# has its test".
module CrossLint
end

require_relative "cross_lint/usage_spec"
require_relative "cross_lint/command_line"
require_relative "cross_lint/help"
require_relative "cross_lint/cli"
