# frozen_string_literal: true

require_relative "configuration"
require_relative "mistake"

module CrossLint
  module Core
    class InitResult < Data.define(:file, :plugins, :replaced, :dry_run)
      def lines
        verbs = dry_run ? ["would write", "would replace"] : ["wrote", "replaced"]
        ["#{verbs.fetch(replaced ? 1 : 0)} #{file}, with the recommended plugins: #{plugins.join(', ')}"]
      end
    end

    class InitConfiguration
      RECOMMENDED = %w[debt].freeze

      def initialize(configuration:)
        @configuration = configuration
      end

      def call(root, force: false, dry_run: false)
        file = @configuration.file
        replaced = @configuration.exist?(root)
        raise Mistake.new("already exists, and crosslint init changes nothing in it; crosslint init --force replaces it", file:) if replaced && !force

        plugins = RECOMMENDED.map { |name| ListedPlugin.new(name:, ref: nil, settings: [], line: 1) }
        @configuration.write(root, Configuration.new(file:, plugins:, policies: [], warnings: nil, verbosity: nil)) unless dry_run
        InitResult.new(file:, plugins: RECOMMENDED, replaced:, dry_run:)
      end
    end
  end
end
