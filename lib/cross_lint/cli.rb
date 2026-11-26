# frozen_string_literal: true

module CrossLint
  class CLI
    PREFIX = "crosslint: "

    ISSUES = "https://github.com/setdef/CrossLint/issues"

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
      # A plugin's name alone, as in crosslint debt, asks what the plugin has.
      return plugin_help(spec, line) if words.any? && (line.action == :help || (running && (command&.name == "help" || (command.nil? && words.size == 1))))
      return plugin_command(spec, line) if running && command.nil? && words.any?

      if running && command
        return check(spec, line) if command.name == "check"
        return update(line) if command.name == "update"
        return explain(spec, line, line.topic) if command.name == "help"

        return say("#{spec.bin} #{command.name} doesn't work yet")
      end

      @out.write(
        if line.action == :version
          "#{spec.bin} #{spec.version}\n"
        elsif running
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

    def explain(spec, line, topic)
      @out.write(render_help(spec, line, topic))
      0
    end

    # The help of `command`, or of the program with the commands of the
    # project's plugins, which only the program's help reads the project for.
    def render_help(spec, line, command)
      plugins = command ? Help::Plugins.none : help_plugins(listing(spec, line))
      Help.new(spec, plugins:).render(command)
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
      notes = found.unfetched.map { |listed| "#{Core::SharedPlugin.plugin_name(listed.name)} isn't fetched yet, so its commands aren't shown; crosslint check fetches it" }
      Help::Plugins.new(commands:, notes:)
    end

    # crosslint PLUGIN, crosslint PLUGIN COMMAND --help, and crosslint help
    # PLUGIN COMMAND: what the plugin or its command is, read from the
    # manifests on disk. Without a project, or with one that can't be read,
    # or for a plugin not fetched yet, it prints the program's help with the
    # reason, unless the first word is a typo of a command of CrossLint's.
    def plugin_help(spec, line)
      found = listing(spec, line)
      commands = PluginCommands.new(spec)
      word = line.words.fetch(0)
      if found.is_a?(Core::Mistake)
        refusal = commands.refusal(word)
        raise refusal if refusal
      elsif found.unfetched.none? { |listed| Core::SharedPlugin.plugin_name(listed.name) == word }
        help = Help.new(spec)
        plugin, command = commands.find(line.words, found.plugins, found.file, -> { application(spec).built_in_commands })
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
      commands = PluginCommands.new(spec)
      project = begin
        app.load_project(line.value("project") || Dir.pwd)
      rescue Core::Mistake => mistake
        raise commands.refusal(line.words.fetch(0)) || mistake
      end
      plugin, command = commands.find(line.words, project.plugins, project.configuration.file, -> { app.built_in_commands })
      # Two words or more name a command, which find has found.
      named = command #: Core::CommandDeclaration
      check_project(app, line, project, [plugin.name, named.name])
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
