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
        @job = call("CreateJobObjectW", [pointer, pointer], pointer, nil, nil)
        limits = "\0" * LIMITS_SIZE
        limits[LIMIT_FLAGS, 4] = [KILL_ON_JOB_CLOSE].pack("L")
        call("SetInformationJobObject", [pointer, int, pointer, int], int, @job, EXTENDED_LIMIT_INFORMATION, limits, LIMITS_SIZE)
        process = call("OpenProcess", [int, int, int], pointer, ASSIGN, 0, pid)
        assigned = call("AssignProcessToJobObject", [pointer, pointer], int, @job, process)
        call("CloseHandle", [pointer], int, process)
        raise Core::PluginError, "started a helper CrossLint couldn't put in a job object, so it couldn't end what the helper starts" if assigned.zero?
      end

      # Binary, or Windows' Ruby turns each "\n" written to the helper
      # into "\r\n".
      def self.popen3(command, root)
        program, file = command
        Open3.popen3(program, file, chdir: root).tap { |input, *| input.binmode }
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

      def call(name, arguments, result, *values) = Fiddle::Function.new(@kernel32[name], arguments, result).call(*values)
    end
  end
end
