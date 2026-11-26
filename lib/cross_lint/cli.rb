# frozen_string_literal: true

module CrossLint
  class CLI
    PREFIX = "crosslint: "

    ISSUES = "https://github.com/setdef/CrossLint/issues"

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
      project = (@app || App.new).load_project(line.value("project") || Dir.pwd)
      quiet = %w[quiet silent].any? { |flag| line.flags.key?(flag) } || %i[quiet silent].include?(project.configuration.verbosity)
      unless quiet
        project.unused_rules.each do |plugin, rule|
          say("#{plugin.manifest.file}:#{rule.line}: warning: no policy runs rule #{rule.name.dump}, so CrossLint doesn't load it")
        end
      end
      count = project.plugins.size
      say("read #{project.configuration.file} and #{count} #{(count == 1) ? "plugin" : "plugins"}; checking files doesn't work yet")
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
