# frozen_string_literal: true

require "open3"

require_relative "../core"

module CrossLint
  module Adapters
    class ProcessGroup
      def self.popen3(command, root, environment)
        env = environment #: untyped
        Open3.popen3(env, *command, chdir: root, pgroup: true)
      end

      def self.close_input(input) = input.close

      def initialize(pid)
        @pid = pid
        # Ruby starts the process in its group before popen3 returns.
        raise Core::PluginError, "wasn't put in a process group of its own" unless Process.getpgid(pid) == pid
      rescue Errno::ESRCH
        # The process has exited, and left nothing to end.
      end

      # The group outlives its first process while any process in it is
      # running, and is gone, so Ruby raises ESRCH, once none is.
      def kill
        Process.kill("KILL", -@pid)
      rescue Errno::ESRCH, Errno::EPERM
        nil
      end
    end
  end
end
