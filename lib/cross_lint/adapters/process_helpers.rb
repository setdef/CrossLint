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

      STOP_LIMIT = 2

      WINDOWS = RbConfig::CONFIG.fetch("host_os").match?(/mswin|mingw/)

      # A table, not a branch, since each system runs only its own.
      TREE = {true => JobObject, false => ProcessGroup}.fetch(WINDOWS)

      attr_reader :time_limit, :stop_limit

      def initialize(err:, debug:, time_limit: TIME_LIMIT, stop_limit: STOP_LIMIT, env: ENV, tree: TREE)
        @err = err
        @tree_class = tree
        @debug = debug
        @time_limit = time_limit
        @stop_limit = stop_limit
        @env = env
      end

      def start(root, plugins)
        commands = plugins.flat_map do |plugin|
          plugin.manifest.helpers.map do |helper|
            [[plugin.name, helper.name], command(plugin, helper)] #: [[String, String], [String, String]]
          end
        end
        Running.new(root, commands.to_h, err: @err, debug: @debug, time_limit: @time_limit, stop_limit: @stop_limit, tree: @tree_class)
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
        def initialize(root, commands, err:, debug:, time_limit:, stop_limit:, tree:)
          @tree_class = tree
          @root = root
          @commands = commands
          @err = err
          @debug = debug
          @time_limit = time_limit
          @stop_limit = stop_limit
          @processes = {}
        end

        def call(plugin, name, input)
          key = [plugin.name, name] #: [String, String]
          process = @processes[key] ||= HelperProcess.new(name, @commands.fetch(key), root: @root, err: @err, debug: @debug, time_limit: @time_limit,
            stop_limit: @stop_limit, tree: @tree_class)
          process.call(input)
        end

        # Each helper ends in a thread of its own, so that the waits for
        # several helpers overlap. Ctrl-C ends every tree at once.
        def stop
          @processes.each_value.map { |process| Thread.new { process.stop } }.each(&:join)
        rescue Interrupt
          kill
          raise
        end

        def kill = @processes.each_value(&:kill)
      end

      class HelperProcess
        def initialize(name, command, root:, err:, debug:, time_limit:, stop_limit:, tree:)
          @name = name
          @time_limit = time_limit
          @stop_limit = stop_limit
          @tree_class = tree
          @stdin, @stdout, stderr, @wait = @tree_class.popen3(command, root)
          # Before the first request, so that every process the helper
          # starts to answer one is in the tree.
          @tree = contain(stderr)
          # A binary string, which JSON reads as UTF-8 whatever the
          # locale's encoding.
          @stdout.binmode
          @written = +""
          @reader = Thread.new do
            stderr.each_line do |line|
              @written << line
              err.puts("crosslint: helper #{name}: #{line}") if debug
            rescue IOError, SystemCallError
              # CrossLint's own standard error is closed or broken: the
              # line is lost, and the helper's standard error is still read.
            end
          end
        end

        def call(input)
          line = exchange(input)
          fail! unless line
          parse(line)
        end

        def stop
          @tree_class.close_input(@stdin)
          @wait.join(@stop_limit)
          finish
        end

        # Nothing is left to read after the tree is killed, and Ctrl-C
        # means CrossLint is ending.
        def kill
          @killed = true
          @tree.kill
        end

        private

        # The tree the helper is in. A helper that can't be put in one is
        # ended, since CrossLint couldn't end what it starts, and is a
        # fault.
        def contain(stderr)
          @tree_class.new(@wait.pid)
        rescue Core::PluginError => error
          begin
            Process.kill("KILL", @wait.pid)
          rescue Errno::ESRCH
            # It has exited already.
          end
          @wait.join
          [@stdin, @stdout, stderr].each(&:close)
          raise Core::PluginError, "called helper #{@name}, which #{error}, so CrossLint ended it"
        end

        def exchange(input)
          # The write too, since a helper that reads nothing fills the pipe.
          Timeout.timeout(@time_limit) do
            @stdin.write("#{JSON.generate(input)}\n")
            @stdout.gets
          end
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
          status = @wait.value
          # A process that left the tree keeps standard error open, so the
          # reader is waited for as long as an answer is, and no longer.
          @reader.join(@time_limit) unless @killed
          [status, @written]
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
