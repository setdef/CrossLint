# frozen_string_literal: true

require_relative "../core"

module CrossLint
  module Adapters
    class MemoryCrossLintRuby
      def initialize(files = {})
        # Windows puts a drive letter on the expanded path a file is
        # looked up by, so the paths it is given must be expanded too.
        @files = files.transform_keys { |path| File.expand_path(path) }
      end

      def load(plugin, file, line, namespace)
        code = @files.fetch(File.expand_path(file, plugin.folder)) do
          raise Core::Mistake.new("no file #{file.dump} in the plugin's folder", file: plugin.manifest.file, line:)
        end
        code.call(namespace)
      end
    end
  end
end
