# frozen_string_literal: true

require_relative "../core"

module CrossLint
  module Adapters
    class MemoryConfiguration
      attr_reader :file

      def initialize(projects = {}, file: ".config/crosslint/config.kdl")
        @projects = projects
        @file = file
      end

      def find_root(start)
        folder = start
        until @projects.key?(folder)
          parent = File.dirname(folder)
          return if parent == folder

          folder = parent
        end
        folder
      end

      def exist?(root) = @projects.key?(root)

      def write(root, configuration)
        @projects[root] = configuration
      end

      def set_refs(root, refs)
        configuration = read(root)
        plugins = configuration.plugins.map { |listing| refs.key?([listing.name, listing.path]) ? listing.with(ref: refs.fetch([listing.name, listing.path])) : listing }
        @projects[root] = configuration.with(plugins:)
      end

      def read(root)
        configuration = @projects.fetch(root) { Core::Mistake.new("doesn't exist", file:) }
        raise configuration if configuration.is_a?(Core::Mistake)

        configuration
      end
    end
  end
end
