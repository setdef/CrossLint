# frozen_string_literal: true

require_relative "core"
require_relative "adapters"

module CrossLint
  class App
    PLUGINS = File.expand_path("../../../plugins", __FILE__)

    def initialize(configuration: Adapters::KDLConfiguration.new, manifests: Adapters::KDLPluginManifests.new,
      project_files: Adapters::GitProjectFiles.new, plugin_ruby: Adapters::FilePluginRuby.new, helpers: nil, shared_plugins: nil, plugins: PLUGINS,
      debt_files: Adapters::TSVDebtFiles.new, err: $stderr, debug: false)
      @configuration = configuration
      @manifests = manifests
      @project_files = project_files
      @plugin_ruby = plugin_ruby
      @helpers = helpers || Adapters::ProcessHelpers.new(err:, debug:)
      @shared_plugins = shared_plugins || Adapters::GitSharedPlugins.new(err:)
      @built_in = built_in_plugins(plugins)
      @steps = {"track-debt" => Core::TrackDebt.new(debt_files:)} #: Hash[String, Core::_Step]
    end

    def load_project(start)
      Core::LoadProject.new(configuration: @configuration, manifests: @manifests, plugin_ruby: @plugin_ruby, shared_plugins: @shared_plugins,
        built_in: @built_in, steps: @steps).call(start)
    end

    def check(start, warnings: nil, verbosity: nil, all: false, flags: [], started: nil)
      Core::Check.new(project_files: @project_files, plugin_ruby: @plugin_ruby, helpers: @helpers, steps: @steps)
        .call(load_project(start), warnings:, verbosity:, all:, flags:, started:)
    end

    def report(out:, err:, json: false, color: false, debug: false)
      json ? Adapters::JSONReport.new(out:, err:, debug:) : Adapters::TextReport.new(out:, err:, color:, debug:)
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
