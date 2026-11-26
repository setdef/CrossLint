# frozen_string_literal: true

require_relative "core"
require_relative "adapters"

module CrossLint
  class App
    PLUGINS = File.expand_path("../../../plugins", __FILE__)

    def initialize(configuration: Adapters::KDLConfiguration.new, manifests: Adapters::KDLPluginManifests.new,
      plugins: PLUGINS)
      @configuration = configuration
      @manifests = manifests
      @built_in = built_in_plugins(plugins)
    end

    def load_project(start)
      Core::LoadProject.new(configuration: @configuration, manifests: @manifests, built_in: @built_in).call(start)
    end

    private

    def built_in_plugins(folder)
      Dir.glob("*/#{@manifests.file}", base: folder).to_h do |path|
        name = File.dirname(path)
        [name, File.join(folder, name)]
      end
    end
  end
end
