# frozen_string_literal: true

require "json"
require "rbconfig"
require "timeout"
require_relative "../core"
require_relative "process_group"
require_relative "job_object"

module CrossLint
  module Adapters
    class ProcessHelpers
      TIME_LIMIT = 60

      WINDOWS = RbConfig::CONFIG.fetch("host_os").match?(/mswin|mingw/)

      # A table, not a branch, since each system runs only its own.
      TREE = {true => JobObject, false => ProcessGroup}.fetch(WINDOWS)

      attr_reader :time_limit

      def initialize(err:, debug:, time_limit: TIME_LIMIT, env: ENV)
        @err = err
        @debug = debug
        @time_limit = time_limit
        @env = env
      end

      def start(root, plugins)
        commands = plugins.flat_map do |plugin|
          plugin.manifest.helpers.map do |helper|
            [[plugin.name, helper.name], command(plugin, helper)] #: [[String, String], [String, String]]
          end
        end
        Running.new(root, commands.to_h, err: @err, debug: @debug, time_limit: @time_limit)
      end

      # On Windows, node is node.exe or node.cmd, and a file with no
      # extension beside them, such as a shim for MSYS2's shell, is no
      # program Windows can start, so PATHEXT's extensions come first;
      # elsewhere PATHEXT is unset. An empty entry of the PATH, which
      # shells take for the current folder, is skipped, so that a
      # project's own files never stand in for a command.
      def find(command)
        extensions = @env.fetch("PATHEXT", "").split(";").reject(&:empty?) + [""]
        @env.fetch("PATH", "").split(File::PATH_SEPARATOR).reject(&:empty?).each do |folder|
          extensions.each do |extension|
            candidate = File.expand_path(command + extension, folder)
            return candidate if File.file?(candidate) && File.executable?(candidate)
          end
        end
        nil
      end

      private

      def command(plugin, helper)
        program = find(helper.command) || raise(helper.missing_command(plugin))
        file = File.expand_path(helper.file, plugin.folder)
        raise Core::Mistake.new("no file #{helper.file.dump} in the plugin's folder", file: plugin.manifest.file, line: helper.line) unless File.file?(file)

        [program, file]
      end

      class Running
        def initialize(root, commands, err:, debug:, time_limit:)
          @root = root
          @commands = commands
          @err = err
          @debug = debug
          @time_limit = time_limit
          @processes = {}
        end

        def call(plugin, name, input)
          key = [plugin.name, name] #: [String, String]
          process = @processes[key] ||= HelperProcess.new(name, @commands.fetch(key), root: @root, err: @err, debug: @debug, time_limit: @time_limit)
          process.call(input)
        end

        def stop = @processes.each_value(&:stop)
      end

      class HelperProcess
        def initialize(name, command, root:, err:, debug:, time_limit:)
          @name = name
          @time_limit = time_limit
          @stdin, @stdout, stderr, @wait = TREE.popen3(command, root)
          # Before the first request, so that every process the helper
          # starts to answer one is in the tree.
          @tree = TREE.new(@wait.pid)
          # A binary string, which JSON reads as UTF-8 whatever the
          # locale's encoding.
          @stdout.binmode
          @reader = Thread.new do
            stderr.each_line.with_object(+"") do |line, written|
              written << line
              err.puts("crosslint: helper #{name}: #{line}") if debug
            end
          end
        end

        def call(input)
          line = exchange(input)
          fail! unless line
          parse(line)
        end

        def stop
          TREE.close_input(@stdin)
          @wait.join(@time_limit)
          finish
        end

        private

        def exchange(input)
          @stdin.write("#{JSON.generate(input)}\n")
          Timeout.timeout(@time_limit) { @stdout.gets }
        rescue Errno::EPIPE, Errno::EINVAL
          # The helper has exited, so there is no answer.
        rescue Timeout::Error
          fail!("didn't answer within #{@time_limit} seconds, so CrossLint ended it and everything it started")
        end

        def parse(line)
          JSON.parse(line)
        rescue JSON::ParserError
          fail!("answered with a line that isn't JSON: #{format("%.80s", line.chomp).dump}")
        end

        # Ends what the helper left running, and the helper itself if it
        # is still running, and returns how it ended and what it wrote to
        # standard error.
        def finish
          @tree.kill
          [@wait.value, @reader.value]
        end

        def fail!(what = nil)
          status, written = finish
          # A status on exit, or a signal on macOS and Linux.
          ending = [status.exitstatus && "status #{status.exitstatus}", status.termsig && "signal #{status.termsig}"].join
          what ||= "exited with #{ending} before it answered"
          text = written.strip
          raise Core::PluginError, "called helper #{@name}, which #{what}#{", and wrote:\n#{text}" unless text.empty?}"
        end
      end
    end
  end
end
