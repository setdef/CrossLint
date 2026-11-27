# frozen_string_literal: true

module CrossLint
  module Core
    class VersionTags < Data.define(:tags)
      def self.parse(texts) = new(tags: texts.filter_map { |text| VersionTag.parse(text) })

      def compatible_with(current) = with(tags: tags.select { |tag| current.version.compatible_with?(tag.version) })

      # `keep` stands in for the other tags of its version, so that v1.2.0
      # and 1.2.0 on one commit don't send a project from one to the other.
      # When `keep` is not one of the tied tags, the tie goes to the tag
      # that has a "v" only when `keep` has one.
      # A `keep` of a higher version than any tag stays, so that no update
      # moves a project to a lower version.
      def newest(keep: nil)
        highest = tags.map(&:version).max
        return unless highest
        return keep if keep && keep.version > highest

        tied = tags.select { |tag| tag.version == highest }.sort_by(&:text)
        return keep if tied.include?(keep)

        written_with_v = keep&.v? || false
        tied.find { |tag| tag.v? == written_with_v } || tied.first
      end

      def newer_incompatible(current)
        above = tags.select { |tag| tag.version > current.version && !current.version.compatible_with?(tag.version) }
        above.group_by { |tag| tag.version.group }.values.filter_map { |group| with(tags: group).newest(keep: current) }.sort_by(&:version)
      end
    end
  end
end
