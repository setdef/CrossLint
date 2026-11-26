# frozen_string_literal: true

require_relative "../core"

module CrossLint
  module Adapters
    class MemoryPluginManifests
      attr_reader :file

      def initialize(folders = {}, file: "plugin.kdl")
        @folders = folders
        @file = file
      end

      def read(root, folder)
        manifest = @folders[File.expand_path(folder, root)]
        raise manifest if manifest.is_a?(Core::Mistake)

        manifest
      end
    end
  end
end
