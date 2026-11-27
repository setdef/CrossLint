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

      # What is wrong with `path`, the folder of a repository that holds a
      # plugin, or nil when nothing is: folders joined by /, none of them
      # empty, "." or "..", so that the path can't leave the repository,
      # and no backslash or drive letter, so that it means the same on
      # every system. The last folder is cut at the last /, not by
      # File.basename, which on Windows drops a drive letter such as "c:".
      def self.path_problem(path)
        if path.empty?
          "is empty"
        elsif path.include?("\\")
          "has a backslash; write the folders with / between them"
        elsif path.start_with?("/") || path.match?(/\A[A-Za-z]:/)
          "is absolute; write it relative to the repository's root"
        elsif path.end_with?("/") || path.include?("//")
          "has an empty part; write each folder's name, with a single / between them"
        elsif (dots = path.split("/").find { |part| part == "." || part == ".." })
          "has #{dots.dump}; write each folder's name, with a single / between them"
        elsif !path.split("/").last.match?(NAME)
          "ends in a folder whose name has other characters than letters, digits, and . _ -; a plugin's name is its folder's name"
        end
      end

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

      # The tags among `tags` that are compatible with the version tag
      # `ref`, by the caret rule of Cargo and npm, which Semantic
      # Versioning's 0.y.z rule leads to: the same X from X.Y.Z on, the
      # same 0.Y at 0.Y.Z, and only 0.0.Z itself at 0.0.Z.
      def self.compatible(tags, ref)
        line = compatibility(numbers(ref))
        tags.select { |tag| version?(tag) && compatibility(numbers(tag)) == line }
      end

      # The tag with the highest version of each set of mutually
      # compatible versions above the version tag `ref`'s own, the lowest
      # first. Of tags tied for a version, the one `newest_tag` picks.
      def self.newer_incompatible(tags, ref)
        from = numbers(ref)
        versions = tags.select { |tag| version?(tag) }
        above = versions.select { |tag| (numbers(tag) <=> from) == 1 && compatibility(numbers(tag)) != compatibility(from) }
        above.group_by { |tag| compatibility(numbers(tag)) }.values.filter_map { |group| newest_tag(group, keep: ref) }.sort_by { |tag| numbers(tag) }
      end

      # The leading part of `version` that stays the same across
      # compatible versions.
      def self.compatibility(version)
        if version.first.positive?
          version.first(1)
        elsif version[1].positive?
          version.first(2)
        else
          version
        end
      end

      def self.numbers(tag) = VERSION.match(tag).to_a.drop(1).map(&:to_i)

      private_class_method :compatibility, :numbers

      # `keep` stands in for the other tags of its version, so that v1.2.0
      # and 1.2.0 on one commit don't send a project from one to the other.
      # When `keep` is not one of the tied tags, the tie goes to the tag
      # that has a "v" only when `keep` has one.
      # A `keep` of a higher version than any tag stays, so that no update
      # moves a project to a lower version.
      def self.newest_tag(tags, keep: nil)
        versions = tags.filter_map { |tag| (found = VERSION.match(tag)) && [tag, found.captures.map(&:to_i)] } #: Array[[String, Array[Integer]]]
        highest = versions.map(&:last).max
        kept = VERSION.match(keep)
        return keep if kept && (kept.captures.map(&:to_i) <=> highest) == 1

        tied = versions.select { |_, version| version == highest }.map(&:first).sort
        return keep if tied.include?(keep)

        tied.find { |tag| tag.start_with?("v") == keep.to_s.start_with?("v") } || tied.first
      end
    end
  end
end
