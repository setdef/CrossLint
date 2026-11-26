# frozen_string_literal: true

require_relative "process_helpers"

module CrossLint
  module Adapters
    # Inside a Git hook, Git sets GIT_DIR and others, and a Git run that
    # inherits them reads that repository instead of the one it is meant
    # for. The values are nil, which unsets the variable.
    module GitEnvironment
      # Ruby keeps the case a variable was set in, and Windows ignores
      # case in a name, so `git_dir` there is GIT_DIR. Elsewhere it is
      # another variable, which Git doesn't read.
      def self.cleared(env = ENV, windows: ProcessHelpers::WINDOWS)
        env.keys.filter_map { |name| [name, nil] if (windows ? name.upcase : name).start_with?("GIT_") }.to_h
      end
    end
  end
end
