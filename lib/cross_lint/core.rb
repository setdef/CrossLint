# frozen_string_literal: true

module CrossLint
  module Core
  end
end

require_relative "core/mistake"
require_relative "core/spelling"
require_relative "core/path_pattern"
require_relative "core/condition"
require_relative "core/manifest"
require_relative "core/configuration"
require_relative "core/built_in_rule"
require_relative "core/project"
require_relative "core/load_project"
require_relative "core/artifact"
require_relative "core/fault"
require_relative "core/rule"
require_relative "core/ruby_rule"
require_relative "core/check_result"
require_relative "core/check"
require_relative "core/debt_file"
