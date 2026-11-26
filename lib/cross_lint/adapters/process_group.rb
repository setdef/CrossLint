# frozen_string_literal: true

require "open3"

module CrossLint
  module Adapters
    class ProcessGroup
      def self.popen3(command, root)
        program, file = command
        Open3.popen3(program, file, chdir: root, pgroup: true)
      end

      def self.close_input(input) = input.close

      def initialize(pid)
        @pid = pid
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
