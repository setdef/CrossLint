# frozen_string_literal: true

require_relative "../core"

module CrossLint
  module Adapters
    class FilePluginRuby
      def load(plugin, file, line, namespace)
        path = File.expand_path(file, plugin.folder)
        raise Core::Mistake.new("no file #{file.dump} in the plugin's folder", file: plugin.manifest.file, line:) unless File.file?(path)

        # Kernel's, which this method's name hides.
        Kernel.load(path, namespace)
      end
    end
  end
end
