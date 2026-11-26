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
        return check(line) if command.name == "check"

        return say("#{spec.bin} #{command.name} doesn't work yet")
      end

      @out.write((line.action == :version) ? "#{spec.bin} #{spec.version}\n" : Help.new(spec).render(command))
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

    def check(line)
      return say("--update-debt needs the debt plugin, which doesn't work yet") if line.flags.key?("update-debt")

      app = @app || App.new
      given = line.value("warnings") if line.given?("warnings")
      warnings = WARNINGS.fetch(given) if given
      verbosity = (:silent if line.flags.key?("silent")) || (:quiet if line.flags.key?("quiet")) #: (:quiet | :silent)?
      result = app.check(line.value("project") || Dir.pwd, warnings:, verbosity:, all: line.flags.key?("all"))
      app.report(out: @out, err: @err, json: line.flags.key?("json"), color: color?(line)).write(result)
      result.failed ? 1 : 0
    end

    # NO_COLOR, TERM=dumb, and --no-color win over FORCE_COLOR, which
    # only stands in for a terminal.
    def color?(line)
      return false if line.flags.key?("no-color") || !@env.fetch("NO_COLOR", "").empty? || @env.fetch("TERM", "").casecmp?("dumb")

      !@env.fetch("FORCE_COLOR", "").empty? || @out.tty?
    end

    def say(message)
      @err.puts "#{PREFIX}#{message.encode("US-ASCII", invalid: :replace, undef: :replace)}"
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
