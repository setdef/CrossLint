# frozen_string_literal: true

module CrossLint
  # The crosslint command: reads its command line, does what the person
  # asked for, and returns the exit status.
  #
  # What the person asked for goes to +out+. Everything CrossLint says about
  # itself goes to +err+, each line beginning with "crosslint:".
  class CLI
    # What begins each line CrossLint writes about itself.
    PREFIX = "crosslint: "

    # Where to report a bug.
    ISSUES = "https://github.com/setdef/CrossLint/issues"

    # +argv+ is the command line's words, +out+ and +err+ standard output
    # and standard error, and +env+ the environment. +spec+ is the usage
    # spec, which is read from UsageSpec::PATH when it is nil.
    def initialize(argv, out:, err:, env:, spec: nil)
      @argv = argv
      @out = out
      @err = err
      @env = env
      @spec = spec
    end

    # Runs the command line, and returns the exit status.
    def run
      spec = @spec || UsageSpec.load
      line = CommandLine.new(spec, @argv)
      return say("#{spec.bin} #{line.command.name} doesn't work yet") if line.action == :run && line.command

      @out.write((line.action == :version) ? "#{spec.bin} #{spec.version}\n" : Help.new(spec).render(line.command))
      0
    rescue CommandLine::Error => error
      say(error.message)
    rescue Interrupt
      130
    rescue StandardError, ScriptError => error
      bug(error)
    end

    private

    # Writes +message+ to standard error, and returns exit status 2.
    def say(message)
      @err.puts "#{PREFIX}#{message.encode("US-ASCII", invalid: :replace, undef: :replace)}"
      2
    end

    def bug(error)
      say("stopped on a bug in CrossLint: #{error.class}: #{error}")
      say("please report it at #{ISSUES}, with the command you ran and what crosslint --version prints")
      return say("run it again with --debug to see where it stopped") unless debug?

      error.backtrace.each { |line| say("  from #{line}") }
      2
    end

    def debug? = @argv.include?("--debug") || !@env.fetch("DEBUG", "").empty?
  end
end
