# frozen_string_literal: true

module CrossLint
  module Adapters
    # Inside a Git hook, Git sets GIT_DIR and others, and a Git run that
    # inherits them reads that repository instead of the one it is meant
    # for. The values are nil, which unsets the variable.
    module GitEnvironment
      def self.cleared(env = ENV) = env.keys.filter_map { |name| [name, nil] if name.start_with?("GIT_") }.to_h
    end
  end
end
