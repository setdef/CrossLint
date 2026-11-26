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
      if line.action == :run && command
        return check(line, command) if command.name == "check"
        return update(line) if command.name == "update"
        return explain(spec, line.topic) if command.name == "help"

        return say("#{spec.bin} #{command.name} doesn't work yet")
      end

      help = Help.new(spec)
      @out.write(
        if line.action == :version
          "#{spec.bin} #{spec.version}\n"
        elsif line.action == :run
          help.short
        else
          help.render(command)
        end
      )
      0
    rescue CommandLine::Error => error
      say(error.message)
    rescue Core::Mistake => mistake
      say([mistake.location, mistake.message].reject(&:empty?).join(": "))
    rescue Interrupt
      130
    rescue StandardError, ScriptError => error
      bug(error)
    end

    private

    def explain(spec, topic)
      @out.write(Help.new(spec).render(topic))
      0
    end

    def check(line, command)
      app = @app || App.new(err: @err, debug: debug?)
      given = line.value("warnings") if line.given?("warnings")
      warnings = WARNINGS.fetch(given) if given
      verbosity = (:silent if line.flags.key?("silent")) || (:quiet if line.flags.key?("quiet")) #: (:quiet | :silent)?
      report = app.report(out: @out, err: @err, json: line.flags.key?("json"), color: color?(line), debug: debug?)
      # Steep reads a lambda's one argument, an array of pairs, as one pair,
      # so the argument goes untyped.
      result = app.check(line.value("project") || Dir.pwd, warnings:, verbosity:, all: line.flags.key?("all"),
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
