# frozen_string_literal: true

require_relative "../core"

module CrossLint
  module Adapters
    class MemoryPluginRuby
      def initialize(files = {})
        @files = files
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
