# frozen_string_literal: true

require "open3"

require_relative "../core"

module CrossLint
  module Adapters
    # Windows alone runs this, so only Windows tests it: mutant and the
    # coverage of macOS and Linux leave this file out (.mutant.yml,
    # test/test_helper.rb).
    class JobObject
      # JOBOBJECT_EXTENDED_LIMIT_INFORMATION's size on x64, and where its
      # LimitFlags are.
      LIMITS_SIZE = 144
      LIMIT_FLAGS = 16

      # Ends the job's processes when its last handle closes, as when
      # CrossLint itself ends.
      KILL_ON_JOB_CLOSE = 0x2000

      EXTENDED_LIMIT_INFORMATION = 9

      # PROCESS_SET_QUOTA and PROCESS_TERMINATE, which
      # AssignProcessToJobObject needs of the process's handle.
      ASSIGN = 0x0101

      def initialize(pid)
        # Ruby 4.1 has fiddle as a bundled gem, which the Gemfile asks for
        # on Windows.
        require "fiddle"
        @kernel32 = Fiddle.dlopen("kernel32")
        pointer = Fiddle::TYPE_VOIDP
        int = Fiddle::TYPE_INT
        @job = checked("CreateJobObjectW", [pointer, pointer], pointer, nil, nil)
        begin
          limits = "\0" * LIMITS_SIZE
          limits[LIMIT_FLAGS, 4] = [KILL_ON_JOB_CLOSE].pack("L")
          checked("SetInformationJobObject", [pointer, int, pointer, int], int, @job, EXTENDED_LIMIT_INFORMATION, limits, LIMITS_SIZE)
          hold(pid)
        rescue Core::PluginError
          kill
          raise
        end
      end

      # Binary, or Windows' Ruby turns each "\n" written to the helper
      # into "\r\n".
      def self.popen3(command, root, environment)
        program, file = command
        env = environment #: untyped
        Open3.popen3(env, program, file, chdir: root).tap { |input, *| input.binmode }
      end

      def self.close_input(input)
        input.close
      rescue Errno::EPIPE, Errno::EINVAL
        # Closing a pipe flushes it, and a helper that has exited makes the
        # flush raise EPIPE, which ends nothing.
      end

      # Ends the job's processes, and closes the job, once.
      def kill
        job = @job
        return unless job

        @job = nil
        call("TerminateJobObject", [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT], Fiddle::TYPE_INT, job, 1)
        call("CloseHandle", [Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT, job)
      end

      private

      # Puts the process `pid` in the job.
      def hold(pid)
        pointer = Fiddle::TYPE_VOIDP
        int = Fiddle::TYPE_INT
        process = checked("OpenProcess", [int, int, int], pointer, ASSIGN, 0, pid)
        begin
          checked("AssignProcessToJobObject", [pointer, pointer], int, @job, process)
        ensure
          call("CloseHandle", [pointer], int, process)
        end
      end

      # What the call `name` returns, or an error when Windows returns
      # zero, which is how each of these calls fails.
      def checked(name, arguments, result, *values)
        value = call(name, arguments, result, *values)
        raise Core::PluginError, "couldn't be put in a job object: #{name} failed with Windows error #{Fiddle.win32_last_error.to_i}" if value.to_i.zero?

        value
      end

      def call(name, arguments, result, *values) = Fiddle::Function.new(@kernel32[name], arguments, result).call(*values)
    end
  end
end
