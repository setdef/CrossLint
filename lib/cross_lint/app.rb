# frozen_string_literal: true

require_relative "core"
require_relative "adapters"

module CrossLint
  class App
    PLUGINS = File.expand_path("../../../plugins", __FILE__)

    # The other folders of PLUGINS are shared plugins, which a project lists
    # by URL and path=, so a folder there is built in only by name.
    BUILT_IN = %w[angular debt].freeze

    def initialize(configuration: Adapters::KDLConfiguration.new, manifests: Adapters::KDLPluginManifests.new,
      project_files: Adapters::GitProjectFiles.new, crosslint_ruby: Adapters::FileCrossLintRuby.new, helpers: nil, shared_plugins: nil, plugins: PLUGINS,
      built_in: BUILT_IN, debt_files: Adapters::TSVDebtFiles.new, ng_nudge: Adapters::FileNgNudge.new, javascript: Adapters::NodeJavaScript.new,
      reserved: nil, reserved_flags: nil, version: nil, err: $stderr, debug: false)
      @configuration = configuration
      @manifests = manifests
      @project_files = project_files
      @crosslint_ruby = crosslint_ruby
      @helpers = helpers || Adapters::ProcessHelpers.new(err:, debug:)
      @shared_plugins = shared_plugins || Adapters::GitSharedPlugins.new(err:)
      @debt_files = debt_files
      @ng_nudge = ng_nudge
      @javascript = javascript
      @built_in = built_in_plugins(plugins, built_in)
      @reserved = reserved || UsageSpec.load.commands.map(&:name)
      @reserved_flags = reserved_flags || self.class.global_flag_names(UsageSpec.load)
      @version = version || UsageSpec.load.version
      @crosslint = Core::Version.parse(@version) || raise(ArgumentError, "#{@version.dump} isn't a version of CrossLint, X.Y.Z")
      @steps = {"track-debt" => Core::TrackDebt.new(debt_files:)} #: Hash[String, Core::_Step]
    end

    # How each global flag of `spec`, with --help and --version, is
    # written on a command line, which no flag of a plugin's command takes.
    def self.global_flag_names(spec)
      (spec.global_flags + [CommandLine::HELP, CommandLine::VERSION]).flat_map { |flag| ["--#{flag.long}", ("-#{flag.short}" if flag.short)].compact }.uniq
    end

    def load_project(start) = loader.call(start)

    def check(start, **options) = check_project(load_project(start), **options)

    def check_project(project, warnings: nil, verbosity: nil, all: false, command: nil, flags: {}, started: nil)
      Core::Check.new(project_files: @project_files, crosslint_ruby: @crosslint_ruby, helpers: @helpers, steps: @steps)
        .call(project, warnings:, verbosity:, all:, command:, flags:, started:)
    end

    def listing(start) = loader.listed(start)

    def built_in_commands
      @built_in.to_h do |name, folder|
        manifest = @manifests.read(File.dirname(folder), File.basename(folder)) #: Core::Manifest
        [name, manifest.commands.map(&:name)]
      end
    end

    def update(start, dry_run: false, latest: false)
      Core::UpdatePlugins.new(configuration: @configuration, shared_plugins: @shared_plugins, crosslint: @crosslint).call(start, dry_run:, latest:)
    end

    def init(start, force: false, dry_run: false)
      Core::InitConfiguration.new(configuration: @configuration).call(start, force:, dry_run:)
    end

    def move_from_ng_nudge(start, force: false, dry_run: false, planned: nil)
      Core::NgNudge::Move.new(configuration: @configuration, ng_nudge: @ng_nudge, debt_files: @debt_files, javascript: @javascript,
        project_files: @project_files)
        .call(start, force:, dry_run:, planned:)
    end

    def report(out:, err:, json: false, color: false, debug: false)
      json ? Adapters::JSONReport.new(out:, err:, crosslint: @version, debug:) : Adapters::TextReport.new(out:, err:, color:, debug:)
    end

    private

    def loader
      Core::LoadProject.new(configuration: @configuration, manifests: @manifests, crosslint_ruby: @crosslint_ruby, shared_plugins: @shared_plugins, helpers: @helpers,
        crosslint: @crosslint,
        built_in: @built_in, steps: @steps, reserved: @reserved, reserved_flags: @reserved_flags)
    end

    def built_in_plugins(folder, names)
      Dir.glob("*/#{@manifests.file}", base: folder).map { File.dirname(it) }.select { names.include?(it) }.to_h { [it, File.join(folder, it)] }
    end
  end
end
