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
      # AssignProcessToJobObject needs of the process's handle, and
      # SYNCHRONIZE, which WaitForSingleObject needs to tell whether the
      # process has exited, and PROCESS_QUERY_LIMITED_INFORMATION, which
      # GetProcessTimes needs.
      ASSIGN = 0x0101 | 0x00100000 | 0x1000

      # How many milliseconds a process that Windows refuses to put in a
      # job has to signal that it has exited. A process on its way out is
      # refused before it signals, and signals within moments.
      EXIT_WAIT = 1000

      # Seconds from 1601, which a FILETIME counts from, to 1970.
      EPOCH = 11_644_473_600

      # FILETIME counts 100-nanosecond ticks.
      TICKS = 10_000_000

      # When popen3 started each child that no job holds yet, by pid. A
      # pid is free once its process has exited and been reaped, and
      # another process can take it before the job holds it.
      SPAWNED = {}

      # What OpenProcess answers for a pid no process has, as a process that
      # has exited and been reaped.
      INVALID_PARAMETER = 87

      def initialize(pid, spawned: SPAWNED.delete(pid))
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
          hold(pid, spawned)
        rescue Core::PluginError
          kill
          raise
        end
      end

      # Binary, or Windows' Ruby turns each "\n" written to the helper
      # into "\r\n".
      def self.popen3(command, root, environment)
        env = environment #: untyped
        Open3.popen3(env, *command, chdir: root).tap do |input, _, _, wait|
          input.binmode
          # After the spawn, not before: Windows rounds a creation time
          # down to its clock's tick, so a time before the spawn could
          # fall after the child's.
          SPAWNED[wait.pid] = Time.now
        end
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

      # Puts the process `pid` in the job, unless it was created after
      # `spawned`, when the child that had the pid has exited and been
      # reaped and another process took it: that process is no child's,
      # and the child has nothing to hold.
      def hold(pid, spawned)
        pointer = Fiddle::TYPE_VOIDP
        int = Fiddle::TYPE_INT
        process = call("OpenProcess", [int, int, int], pointer, ASSIGN, 0, pid)
        if process.to_i.zero?
          # A process that has exited has nothing to hold, and its output
          # and status are read as for any process that has finished.
          return if pid.positive? && Fiddle.win32_last_error.to_i == INVALID_PARAMETER

          raise failed("OpenProcess")
        end
        begin
          return if spawned && created(process) > spawned

          checked("AssignProcessToJobObject", [pointer, pointer], int, @job, process)
        rescue Core::PluginError
          # Windows refuses to put a process that has exited, but has not
          # been reaped, in a job, with error 5, access denied.
          raise unless exited?(process)
        ensure
          call("CloseHandle", [pointer], int, process)
        end
      end

      # When the process that `process` is a handle of was created.
      def created(process)
        pointer = Fiddle::TYPE_VOIDP
        creation = "\0" * 8
        checked("GetProcessTimes", [pointer] * 5, Fiddle::TYPE_INT, process, creation, "\0" * 8, "\0" * 8, "\0" * 8)
        Time.at(Rational(creation.unpack1("Q"), TICKS) - EPOCH)
      end

      # What the call `name` returns, or an error when Windows returns
      # zero, which is how each of these calls fails.
      def checked(name, arguments, result, *values)
        value = call(name, arguments, result, *values)
        raise failed(name) if value.to_i.zero?

        value
      end

      # Whether the process that `process` is a handle of has exited,
      # which WAIT_OBJECT_0, 0, answers.
      def exited?(process) = call("WaitForSingleObject", [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT], Fiddle::TYPE_INT, process, EXIT_WAIT).to_i.zero?

      def failed(name) = Core::PluginError.new("couldn't be put in a job object: #{name} failed with Windows error #{Fiddle.win32_last_error.to_i}")

      def call(name, arguments, result, *values) = Fiddle::Function.new(@kernel32[name], arguments, result).call(*values)
    end
  end
end
