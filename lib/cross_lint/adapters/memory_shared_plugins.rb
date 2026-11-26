# frozen_string_literal: true

require_relative "../core"

module CrossLint
  module Adapters
    class MemorySharedPlugins
      class Repository < Data.define(:tags, :branches, :commits); end

      attr_reader :fetched

      def initialize(repositories = {}, err: $stderr, schemes: ["https://"])
        @repositories = repositories
        @err = err
        @schemes = schemes
        @saved = {}
        @fetched = []
      end

      def accepts?(url) = @schemes.any? { |scheme| url.start_with?(scheme) }

      def fetch(url, ref)
        check(url)
        raise Core::FetchError.bad_ref(ref) unless Core::SharedPlugin.ref?(ref)

        @saved.fetch([url, ref]) do
          @err.puts("crosslint: fetching #{url} at #{ref}")
          @saved[[url, ref]] = find(repository(url), ref).tap { @fetched << [url, ref] }
        end
      end

      def tags(url)
        check(url)
        @err.puts("crosslint: listing the tags of #{url}")
        repository(url).tags.keys
      end

      private

      def check(url)
        raise Core::FetchError.scheme(url, @schemes) unless accepts?(url)
      end

      def repository(url) = @repositories.fetch(url) { raise Core::FetchError, "no repository at #{url}" }

      def find(repository, ref)
        return repository.commits.fetch(ref) { raise Core::FetchError.no_commit(ref) } if Core::SharedPlugin.sha?(ref)

        repository.tags.fetch(ref) do
          raise(repository.branches.include?(ref) ? Core::FetchError.branch(ref) : Core::FetchError.no_tag(ref))
        end
      end
    end
  end
end
