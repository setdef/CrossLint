# frozen_string_literal: true

require_relative "configuration"
require_relative "mistake"

module CrossLint
  module Core
    class InitResult < Data.define(:file, :plugins, :replaced, :dry_run)
      def lines = ["#{verb} #{file}, with the recommended plugins: #{plugins.join(', ')}"]

      def verb = (dry_run ? ["would write", "would replace"] : ["wrote", "replaced"]).fetch(replaced ? 1 : 0)
    end

    class InitConfiguration
      RECOMMENDED = %w[debt].freeze

      def initialize(configuration:, debug: nil)
        @configuration = configuration
        @debug = debug
      end

      def call(root, force: false, dry_run: false)
        file = @configuration.file
        replaced = @configuration.exist?(root)
        @debug&.write("read") { "#{file}: #{replaced ? 'is there' : "isn't there"}" }
        raise Mistake.new("already exists, and crosslint init changes nothing in it; crosslint init --force replaces it", file:) if replaced && !force

        plugins = RECOMMENDED.map { |name| ListedPlugin.new(name:, ref: nil, settings: [], line: 1) }
        @configuration.write(root, Configuration.new(file:, plugins:, policies: [], warnings: nil, verbosity: nil)) unless dry_run
        result = InitResult.new(file:, plugins: RECOMMENDED, replaced:, dry_run:)
        @debug&.write("write") { plugins.map { |plugin| "#{result.verb} #{file}, which lists plugin #{plugin.name}" }.join("\n") }
        result
      end
    end
  end
end
