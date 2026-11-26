# frozen_string_literal: true

require_relative "../core"

module CrossLint
  module Adapters
    class MemoryHelpers
      def initialize(helpers = {}, commands: [])
        @helpers = helpers
        @commands = commands
      end

      def start(root, plugins)
        plugins.each do |plugin|
          missing = plugin.manifest.helpers.find { |helper| !@commands.include?(helper.command) }
          raise missing.missing_command(plugin) if missing
        end
        Running.new(root, @helpers)
      end

      class Running
        attr_reader :root, :stopped, :killed

        def initialize(root, helpers)
          @root = root
          @helpers = helpers
          @stopped = false
          @killed = false
        end

        def call(plugin, name, input) = @helpers.fetch("#{plugin.name}/#{name}").call(input)

        def stop
          @stopped = true
        end

        def kill
          @killed = true
        end
      end
    end
  end
end
