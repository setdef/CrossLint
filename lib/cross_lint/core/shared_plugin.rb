# frozen_string_literal: true

module CrossLint
  module Core
    module SharedPlugin
      # Not "." or "..", which would leave the cache's folder.
      NAME = /\A(?!\.{1,2}\z)[\w.-]+\z/

      SHA = /\A\h{40}\z/

      # Git reads ":" and "*" in a ref as part of a refspec, so only the
      # characters a tag name usually has pass. A full SHA passes too.
      TAG = %r{\A[A-Za-z0-9][A-Za-z0-9._/+-]*\z}

      VERSION = /\Av?(\d+)\.(\d+)\.(\d+)\z/

      # split drops the empty parts a trailing slash leaves.
      def self.plugin_name(url)
        last = url.split("/").last.to_s.delete_suffix(".git")
        last if last.match?(NAME)
      end

      def self.ref?(ref) = ref.match?(TAG)

      def self.sha?(ref) = ref.match?(SHA)

      def self.version?(ref) = ref.match?(VERSION)

      # Everything between the scheme and the first /, ?, or # is the
      # authority, and a user name or password comes before an @ in it.
      def self.credentials?(url) = url.match?(%r{\A[a-z][a-z0-9+.-]*://[^/?#]*@}i)

      # Before any request is made, so that no secret is sent, or printed
      # in a later message. Every listing is checked, since a name that is
      # no plugin, such as one with the scheme http, is printed in the
      # mistake that says so.
      def self.refuse_credentials(configuration)
        configuration.plugins.each do |listing|
          raise Mistake.credentials(configuration.file, listing.line) if credentials?(listing.name)
        end
      end

      # `keep` stands in for the other tags of its version, so that v1.2.0
      # and 1.2.0 on one commit don't send a project from one to the other.
      # A `keep` of a higher version than any tag stays, so that no update
      # moves a project to a lower version.
      def self.newest_tag(tags, keep: nil)
        versions = tags.filter_map { |tag| (found = VERSION.match(tag)) && [tag, found.captures.map(&:to_i)] } #: Array[[String, Array[Integer]]]
        highest = versions.map(&:last).max
        kept = VERSION.match(keep)
        return keep if kept && (kept.captures.map(&:to_i) <=> highest) == 1

        tied = versions.select { |_, version| version == highest }.map(&:first).sort
        tied.include?(keep) ? keep : tied.first
      end
    end
  end
end
