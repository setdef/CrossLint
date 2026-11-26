# frozen_string_literal: true

# CrossLint checks the rules that span files, such as "every source file
# has its test".
module CrossLint
end

require_relative "crosslint/usage_spec"
require_relative "crosslint/command_line"
require_relative "crosslint/help"
require_relative "crosslint/cli"
