# frozen_string_literal: true

require "open3"
require_relative "../core"
require_relative "git_environment"

module CrossLint
  module Adapters
    class GitProjectFiles
      LIST = %w[ls-files -z --cached --others --exclude-standard].freeze

      def initialize(git: "git")
        @git = git
        @entries = {}
      end

      def files(root)
        # RBS types Open3's env values as String, though nil unsets one.
        env = environment #: untyped
        listed, error, status = Open3.capture3(env, @git, "-C", root, *LIST)
        raise Core::Mistake, refusal(env, root, error) unless status.success?

        # --cached lists a tracked file deleted from the working tree, and
        # --others lists an untracked repository as a folder.
        listed.force_encoding(Encoding::UTF_8).split("\0").uniq.select do |path|
          full = File.join(root, path)
          File.file?(full)
        end
      rescue Errno::ENOENT
        raise Core::Mistake, "CrossLint lists a project's files with Git, and found no #{@git} command on the PATH; install Git"
      end

      # File.exist? ignores case on macOS and Windows, so each segment is
      # looked for in its folder's listing.
      def exist?(root, path)
        folder = root
        path.split("/").all? do |segment|
          found = %w[. ..].include?(segment) || entries(folder).include?(segment)
          folder = File.join(folder, segment)
          found
        end
      end

      # Binary, since Ruby on Windows turns CRLF into LF when it reads text.
      def read(root, path)
        raise Errno::ENOENT, path unless exist?(root, path)

        File.binread(File.join(root, path)).force_encoding(Encoding::UTF_8)
      end

      def self.outside(root)
        "#{root} isn't in a Git working tree, and CrossLint lists a project's files with Git; run git init in the project's root"
      end

      private

      def environment = GitEnvironment.cleared

      # A folder Git refuses for another reason, such as safe.directory, is
      # a working tree, so Git's own message says why.
      def refusal(env, root, error)
        inside, _, status = Open3.capture3(env, @git, "-C", root, "rev-parse", "--is-inside-work-tree")
        return GitProjectFiles.outside(root) unless status.success? && inside.strip == "true"

        "CrossLint lists a project's files with Git, and Git refused #{root}: #{error.strip}"
      end

      def entries(folder)
        @entries[folder] ||= begin
          Dir.children(folder)
        rescue SystemCallError
          []
        end
      end
    end
  end
end
