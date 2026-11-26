# frozen_string_literal: true

require_relative "../core"
require_relative "git_project_files"

module CrossLint
  module Adapters
    class MemoryProjectFiles
      def initialize(projects = {}, ignored: {}, contents: {})
        @projects = projects
        @ignored = ignored
        @contents = contents
      end

      def files(root) = @projects.fetch(root) { raise Core::Mistake, GitProjectFiles.outside(root) }

      def exist?(root, path)
        (@projects.fetch(root, []) + @ignored.fetch(root, [])).any? { |file| file == path || file.start_with?("#{path}/") }
      end

      def read(root, path)
        text = @contents.dig(root, path)
        raise Errno::ENOENT, path unless text

        text
      end
    end
  end
end
