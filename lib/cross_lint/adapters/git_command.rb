# frozen_string_literal: true

require "open3"
require_relative "../core"

module CrossLint
  module Adapters
    class GitCommand
      PIPE_LIMIT = 1

      CHUNK = 4096

      class Late < StandardError; end

      class Output < Data.define(:out, :err, :success); end

      attr_reader :pipe_limit

      def initialize(git:, tree:, environment:, pipe_limit: PIPE_LIMIT)
        @git = git
        @tree_class = tree
        @environment = environment
        @pipe_limit = pipe_limit
      end

      def run(arguments, folder, deadline)
        command = [*@git, *arguments]
        begin
          stdin, stdout, stderr, wait = @tree_class.popen3(command, folder, @environment)
        rescue SystemCallError => error
          raise Core::FetchError, "couldn't run #{command.first}, which CrossLint fetches shared plugins with, so install Git: #{error.message}"
        end
        tree = nil #: ProcessHelpers::_TreeProcesses?
        begin
          stdin.close
          tree = contain(wait, [stdout, stderr])
          texts = read(stdout, stderr, wait, tree, deadline)
          Output.new(out: texts.first, err: texts.last, success: wait.value.exitstatus == 0)
        ensure
          # Git's own children, a credential helper among them, end with it.
          tree&.kill
          [stdin, stdout, stderr].each(&:close)
        end
      end

      private

      # Waits for git to exit, no later than `deadline`, on the monotonic
      # clock, and ends it and everything it started when it hasn't.
      def read(stdout, stderr, wait, tree, deadline)
        [stdout, stderr].each(&:binmode)
        texts = ["".b, "".b]
        readers = [stdout, stderr].each_with_index.map do |pipe, index|
          Thread.new do
            loop { texts[index] << pipe.readpartial(CHUNK) }
          rescue IOError, SystemCallError
            # The pipe has ended, or was closed with git's tree.
          end
        end
        finished = wait.join([deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC), 0].max)
        tree.kill
        wait.join
        # A process that left the tree keeps the pipes open, so the readers
        # are waited for a little, and no longer.
        readers.each { |reader| reader.join(@pipe_limit) }
        readers.each(&:kill)
        raise Late unless finished

        texts.map { |text| text.force_encoding(Encoding::UTF_8).scrub }
      end

      # The tree git is in. Git is ended when it can't be put in one, since
      # CrossLint couldn't end what it starts.
      def contain(wait, pipes)
        @tree_class.new(wait.pid)
      rescue Core::PluginError => error
        begin
          Process.kill("KILL", wait.pid)
        rescue Errno::ESRCH
          # It has exited already.
        end
        wait.join
        pipes.each(&:close)
        raise Core::FetchError, "git #{error.message}, so CrossLint ended it"
      end
    end
  end
end
