# frozen_string_literal: true

require_relative "../core"
require_relative "git_project_files"

module CrossLint
  module Adapters
    class MemoryProjectFiles
      def initialize(projects = {}, ignored: {})
        @projects = projects
        @ignored = ignored
      end

      def files(root) = @projects.fetch(root) { raise Core::Mistake, GitProjectFiles.outside(root) }

      def exist?(root, path)
        (@projects.fetch(root, []) + @ignored.fetch(root, [])).any? { |file| file == path || file.start_with?("#{path}/") }
      end
    end
  end
end
