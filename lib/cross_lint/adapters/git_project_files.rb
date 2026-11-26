# frozen_string_literal: true

require "open3"
require_relative "../core"

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
        listed, _, status = Open3.capture3(env, @git, "-C", root, *LIST)
        raise Core::Mistake, GitProjectFiles.outside(root) unless status.success?

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

      def self.outside(root)
        "#{root} isn't in a Git working tree, and CrossLint lists a project's files with Git; run git init in the project's root"
      end

      private

      # Inside a Git hook, Git sets GIT_DIR and others, and a Git run that
      # inherits them reads that repository instead of the project's. The
      # values are nil, which unsets the variable.
      def environment = ENV.keys.filter_map { |name| [name, nil] if name.start_with?("GIT_") }.to_h

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
