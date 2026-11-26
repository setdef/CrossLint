# frozen_string_literal: true

require_relative "../core"
require_relative "file_ng_nudge"

module CrossLint
  module Adapters
    class MemoryNgNudge
      def initialize(projects = {})
        @projects = projects
      end

      def settings(root) = @projects[root].to_h[Core::NgNudge::SETTINGS_FILE]

      def extensions(root)
        FileNgNudge::SUFFIXES.flat_map do |folder, suffix|
          prefix = "#{FileNgNudge::FOLDER}/#{folder}/"
          @projects[root].to_h.keys.select { |path| path.start_with?(prefix) && path.end_with?(suffix) && !path.delete_prefix(prefix).include?("/") }.sort
        end
      end
    end
  end
end
