# frozen_string_literal: true

require "digest"
require "fileutils"
require "securerandom"
require_relative "../core"
require_relative "git_command"
require_relative "git_environment"
require_relative "helper_environment"
require_relative "process_helpers"

module CrossLint
  module Adapters
    class GitSharedPlugins
      TIME_LIMIT = 60

      SCHEMES = ["https://"].freeze

      # Git on Windows keeps no file past 260 characters unless it is
      # told to, and a checkout must give the same bytes on every system.
      SETTINGS = %w[-c core.autocrlf=false -c core.longpaths=true -c advice.detachedHead=false].freeze

      attr_reader :time_limit

      # An XDG_CACHE_HOME that isn't an absolute path is unset, as the
      # XDG specification says.
      def self.cache_folder(env, windows:, home:)
        if windows
          local = env.fetch("LOCALAPPDATA", "")
          File.join(local.empty? ? File.join(home.call, "AppData", "Local") : local, "crosslint", "cache")
        else
          xdg = env.fetch("XDG_CACHE_HOME", "")
          File.join(File.absolute_path?(xdg) ? xdg : File.join(home.call, ".cache"), "crosslint")
        end
      end

      def initialize(err:, cache: nil, schemes: SCHEMES, time_limit: TIME_LIMIT, git: "git", env: ENV, windows: ProcessHelpers::WINDOWS,
        home: -> { Dir.home }, tree: ProcessHelpers::TREE)
        @err = err
        @cache = cache
        @schemes = schemes
        @time_limit = time_limit
        @env = env
        @windows = windows
        @home = home
        # Proxies are left to Git, which reads HTTPS_PROXY, HTTP_PROXY, and
        # NO_PROXY itself. Git must never wait for a person to type a
        # password: the time limit would end it, a minute later.
        program = Array(git) #: Array[String]
        @command = GitCommand.new(git: program, tree:,
          environment: HelperEnvironment.new(env).changes.merge(GitEnvironment.cleared(env), "GIT_TERMINAL_PROMPT" => "0"))
      end

      def accepts?(url) = @schemes.any? { |scheme| url.start_with?(scheme) }

      def folder(url, ref)
        key = Digest::SHA256.hexdigest("#{url}\0#{ref}")[0, 32] #: String
        File.join(plugins, key, plugin_name(url))
      end

      def fetch(url, ref)
        check(url)
        raise Core::FetchError.bad_ref(ref) unless Core::SharedPlugin.ref?(ref)

        folder = folder(url, ref)
        return folder if File.directory?(folder)

        @err.puts("crosslint: fetching #{url} at #{ref}")
        download(url, ref, File.dirname(folder), File.basename(folder))
        folder
      end

      def tags(url)
        check(url)
        @err.puts("crosslint: listing the tags of #{url}")
        listed = limited { |deadline| git!(["ls-remote", "--tags", "--refs", url], Dir.pwd, deadline) }
        listed.lines.map { |line| line.chomp.split("\t", 2).last.delete_prefix("refs/tags/") }
      end

      private

      def check(url)
        raise Core::FetchError.scheme(url, @schemes) unless accepts?(url)
      end

      def plugin_name(url)
        Core::SharedPlugin.plugin_name(url) || raise(Core::FetchError, "can't name a plugin from #{url}, whose last path segment has other characters than " \
          "letters, digits, and . _ -")
      end

      # Where fetched plugins are kept, a folder for each URL and ref
      # holding the plugin's folder, which has the plugin's name.
      def plugins
        File.join(@cache || self.class.cache_folder(@env, windows: @windows, home: @home), "plugins")
      rescue ArgumentError => error
        raise Core::FetchError, "CrossLint keeps what it fetches in a cache folder, and found no home folder for it (#{error.message}); " \
          "set XDG_CACHE_HOME"
      end

      # Fetches into a folder of its own and renames it to `entry`, so that
      # a fetch that stops partway leaves no entry.
      def download(url, ref, entry, name)
        work = File.join(plugins, ".fetching-#{SecureRandom.hex}")
        begin
          files = File.join(work, "files")
          FileUtils.mkdir_p(File.join(files, name))
          limited { |deadline| clone(url, ref, work, name, deadline) }
          save(files, entry)
        rescue SystemCallError => error
          raise Core::FetchError, "couldn't write in #{plugins}: #{error.message}"
        ensure
          FileUtils.rm_rf(work)
        end
      end

      # The rename fails when another CrossLint saved the same plugin first,
      # and its copy is as good as this one.
      def save(files, entry)
        File.rename(files, entry)
      rescue SystemCallError
        raise unless File.directory?(entry)
      end

      def limited
        yield Process.clock_gettime(Process::CLOCK_MONOTONIC) + @time_limit
      rescue GitCommand::Late
        raise Core::FetchError, "took more than #{@time_limit} seconds, so CrossLint ended git and everything it started"
      end

      # The commit alone, with no history, in a work tree of its own and a
      # repository beside it that the caller deletes, so that the plugin's
      # folder holds no .git.
      def clone(url, ref, work, name, deadline)
        from = Core::SharedPlugin.sha?(ref) ? ref : tag(url, ref, work, deadline)
        place = ["--git-dir", File.join(work, "repository"), "--work-tree", File.join(work, "files", name), *SETTINGS]
        git!([*place, "init", "-q"], work, deadline)
        git!([*place, "fetch", "-q", "--depth", "1", "--no-tags", url, from], work, deadline, "couldn't fetch #{ref}")
        git!([*place, "checkout", "-q", "--detach", "FETCH_HEAD"], work, deadline)
      end

      # The ref to fetch for the tag `ref`. A ref that names a branch and
      # no tag is refused, since a branch moves.
      def tag(url, ref, work, deadline)
        listed = git!(["ls-remote", url, "refs/tags/#{ref}", "refs/heads/#{ref}"], work, deadline)
        names = listed.lines.map { |line| line.chomp.split("\t", 2).last }
        return "refs/tags/#{ref}" if names.include?("refs/tags/#{ref}")

        raise(names.include?("refs/heads/#{ref}") ? Core::FetchError.branch(ref) : Core::FetchError.no_tag(ref))
      end

      # What git writes to standard output, or Core::FetchError with what
      # it wrote to standard error when it fails.
      def git!(arguments, folder, deadline, what = nil)
        output = @command.run(arguments, folder, deadline)
        return output.out if output.success

        said = output.err.strip
        raise Core::FetchError, [what, said.empty? ? "git failed" : said].compact.join(": ")
      end
    end
  end
end
