# frozen_string_literal: true

module CrossLint
  class CLI
    PREFIX = "crosslint: "

    ISSUES = "https://github.com/setdef/CrossLint/issues"

    NEXT_STEPS = "moved from ng-nudge; next, replace ng-nudge's dev dependency and each npx ng-nudge in your scripts and CI with crosslint check, " \
      "and run crosslint debt update once"

    WARNINGS = {"all" => :all, "none" => :none, "error" => :error}.freeze

    def initialize(argv, out:, err:, env:, spec: nil, app: nil)
      @argv = argv
      @out = out
      @err = err
      @env = env
      @spec = spec
      @app = app
    end

    def run
      spec = @spec || UsageSpec.load
      line = CommandLine.new(spec, @argv)
      command = line.command
      words = line.words
      running = line.action == :run
      return version(spec) if line.action == :version

      if words.any?
        # Words come with no command of CrossLint's but help. A plugin's name
        # alone, as in crosslint debt, asks what the plugin has.
        return plugin_help(spec, line) if line.action == :help || command || words.size == 1

        return plugin_command(spec, line)
      end

      if running && command
        return check(spec, line) if command.name == "check"
        return update(line) if command.name == "update"
        return init(spec, line) if command.name == "init"
        return explain(spec, line, line.topic) if command.name == "help"

        return say("#{spec.bin} #{command.name} doesn't work yet")
      end

      @out.write(
        if running
          Help.new(spec).short
        else
          render_help(spec, line, command)
        end
      )
      0
    rescue CommandLine::Error => error
      say(error.message)
    rescue Core::Mistake => mistake
      say(text(mistake))
    rescue Interrupt
      130
    rescue StandardError, ScriptError => error
      bug(error)
    end

    private

    def version(spec)
      @out.write("#{spec.bin} #{spec.version}\n")
      0
    end

    def explain(spec, line, topic)
      @out.write(render_help(spec, line, topic))
      0
    end

    # The help of `command`, or of the program with the commands of the
    # project's plugins, which only the program's help reads the project for.
    def render_help(spec, line, command)
      return Help.new(spec).render(command) if command

      Help.new(spec, plugins: help_plugins(listing(spec, line))).render
    end

    # What the plugins the project lists have on disk, or the mistake that
    # stopped the reading, since help never fails for one.
    def listing(spec, line)
      application(spec).listing(line.value("project") || Dir.pwd)
    rescue Core::Mistake => mistake
      mistake
    end

    def help_plugins(found)
      if found.is_a?(Core::Mistake)
        return Help::Plugins.new(commands: [], notes: ["Not shown, because CrossLint couldn't read the project's plugins: #{text(found)}"])
      end

      commands = found.plugins.flat_map { |plugin| plugin.manifest.commands.map { |command| [plugin.name, command] } } #: Array[[String, Core::CommandDeclaration]]
      notes = found.unfetched.map { |listed| "#{listed.plugin_name} isn't fetched yet, so its commands aren't shown; crosslint check fetches it" }
      Help::Plugins.new(commands:, notes:)
    end

    # crosslint PLUGIN, crosslint PLUGIN COMMAND --help, and crosslint help
    # PLUGIN COMMAND: what the plugin or its command is, read from the
    # manifests on disk. Without a project, or with one that can't be read,
    # or for a plugin not fetched yet, it prints the program's help with the
    # reason, unless the first word is a typo of a command of CrossLint's.
    def plugin_help(spec, line)
      commands, found = resolved(spec, line)
      word = line.words.fetch(0)
      if !found.is_a?(Core::Mistake) && found.unfetched.none? { |listed| listed.plugin_name == word }
        help = Help.new(spec)
        plugin, command = commands.find(line.words, found.plugins)
        @out.write(command ? help.plugin_command(plugin.name, command) : help.plugin(plugin.name, plugin.manifest.commands))
        return 0
      end
      @out.write(Help.new(spec, plugins: help_plugins(found)).render)
      0
    end

    def text(mistake) = [mistake.location, mistake.message].reject(&:empty?).join(": ")

    def check(spec, line)
      app = application(spec)
      check_project(app, line, app.load_project(line.value("project") || Dir.pwd))
    end

    # crosslint PLUGIN COMMAND runs the check on the project, with the
    # command's name for the plugin's step, so a project that lists no
    # such plugin is refused before any check runs.
    def plugin_command(spec, line)
      app = application(spec)
      commands, = resolved(spec, line)
      # Only a word that names a shared plugin not fetched yet fetches it,
      # and a project that can't be read raises its own mistake here.
      project = app.load_project(line.value("project") || Dir.pwd)
      plugin, command = commands.find(line.words, project.plugins)
      # Two words or more name a command, which find has found.
      named = command #: Core::CommandDeclaration
      check_project(app, line, project, [plugin.name, named.name])
    end

    # The reader of plugin commands, and what the project lists, once the
    # first word is known to be a plugin the configuration lists: a word
    # that isn't raises before anything is fetched or loaded.
    def resolved(spec, line)
      commands = PluginCommands.new(spec)
      found = listing(spec, line)
      commands.resolve(line.words, found, -> { application(spec).built_in_commands })
      [commands, found]
    end

    def application(spec) = @app || App.new(err: @err, debug: debug?, reserved: spec.commands.map(&:name))

    def check_project(app, line, project, command = nil)
      given = line.value("warnings") if line.given?("warnings")
      warnings = WARNINGS.fetch(given) if given
      verbosity = (:silent if line.flags.key?("silent")) || (:quiet if line.flags.key?("quiet")) #: (:quiet | :silent)?
      report = app.report(out: @out, err: @err, json: line.flags.key?("json"), color: color?(line), debug: debug?)
      # Steep reads a lambda's one argument, an array of pairs, as one pair,
      # so the argument goes untyped.
      result = app.check_project(project, warnings:, verbosity:, all: line.flags.key?("all"), command:,
        started: ->(kinds) { report.start(_ = kinds) })
      report.write(result)
      return 2 unless result.faults.empty?

      result.failed ? 1 : 0
    end

    # --silent leaves out the lines that say what init changes and wrote.
    def init(spec, line)
      app = application(spec)
      root = line.value("project") || Dir.pwd
      force = line.flags.key?("force")
      dry_run = line.flags.key?("dry-run")
      silent = line.flags.key?("silent")
      return move_from_ng_nudge(app, root, force:, dry_run:, silent:) if line.flags.key?("from-ng-nudge")

      result = app.init(root, force:, dry_run:)
      result.lines.each { |text| @err.puts(PREFIX + text) } unless silent
      0
    end

    # Lists every change before it makes the first, as "will" or, with
    # --dry-run, "would", and then says what to do next.
    def move_from_ng_nudge(app, root, force:, dry_run:, silent:)
      tense = dry_run ? "would" : "will"
      planned = lambda do |changes, notes|
        unless silent
          changes.each { |change| @err.puts("#{PREFIX}#{tense} #{change}") }
          notes.each { |note| @err.puts(PREFIX + note) }
        end
      end
      app.move_from_ng_nudge(root, force:, dry_run:, planned:)
      @err.puts("#{PREFIX}#{NEXT_STEPS}") unless dry_run || silent
      0
    end

    # --silent leaves out each plugin's line, but not the line before each
    # request, which tells the person that CrossLint is reaching the network.
    def update(line)
      app = @app || App.new(err: @err)
      result = app.update(line.value("project") || Dir.pwd, dry_run: line.flags.key?("dry-run"))
      result.lines.each { |text| @err.puts(PREFIX + text) } unless line.flags.key?("silent")
      0
    end

    # NO_COLOR, TERM=dumb, and --no-color win over FORCE_COLOR, which
    # only stands in for a terminal.
    def color?(line)
      return false if line.flags.key?("no-color") || !@env.fetch("NO_COLOR", "").empty? || @env.fetch("TERM", "").casecmp?("dumb")

      !@env.fetch("FORCE_COLOR", "").empty? || @out.tty?
    end

    def say(message)
      @err.puts(PREFIX + message)
      2
    end

    def bug(error)
      say("stopped on a bug in CrossLint: #{error.class}: #{error}")
      say("please report it at #{ISSUES}, with the command you ran and what crosslint --version prints")
      return say("run it again with --debug to see where it stopped") unless debug?

      error.backtrace.to_a.each { |line| say("  from #{line}") }
      2
    end

    def debug? = @argv.include?("--debug") || !@env.fetch("DEBUG", "").empty?
  end
end
