# frozen_string_literal: true

module CrossLint
  module Core
    class Update < Data.define(:listing, :newest, :newer)
      def initialize(listing:, newest:, newer: [])
        super
      end

      def current? = newest == listing.ref

      def untagged? = newest.nil? && !pinned?

      def pinned? = VersionTag.parse(listing.ref.to_s).nil?
    end

    class UpdateResult < Data.define(:updates, :dry_run)
      def changes = updates.reject { |update| update.pinned? || update.current? || update.untagged? }

      def lines = updates.map { |update| what(update) + newer(update) }

      private

      def what(update)
        listing = update.listing
        if update.pinned?
          "#{listing.shown}: is at #{listing.ref}, which isn't a plain version tag, vX.Y.Z or X.Y.Z, so update leaves it alone"
        elsif update.untagged?
          "#{listing.shown}: has no tag that is a version, vX.Y.Z or X.Y.Z, so it stays at #{listing.ref}"
        elsif update.current?
          "#{listing.shown}: is at its newest #{"compatible " if update.newer.any?}tag, #{listing.ref}"
        else
          "#{listing.shown}: #{dry_run ? "would move" : "moved"} from #{listing.ref} to #{update.newest}"
        end
      end

      # Newer incompatible versions are named whether or not the plugin moved.
      def newer(update)
        return "" if update.newer.empty?

        "; newer incompatible versions: #{update.newer.join(", ")}; crosslint update --latest moves to #{update.newer.last}"
      end
    end

    class UpdatePlugins
      def initialize(configuration:, shared_plugins:)
        @configuration = configuration
        @shared_plugins = shared_plugins
      end

      def call(start, dry_run: false, latest: false)
        root = @configuration.find_root(start) || raise(Mistake.no_configuration(@configuration.file, start))
        configuration = @configuration.read(root)
        SharedPlugin.refuse_credentials(configuration)
        shared = configuration.plugins.select { |listing| listing.shared?(@shared_plugins) }
        # Plugins listed from folders of one repository share its tags.
        tags = {} #: Hash[String, Array[String]]
        result = UpdateResult.new(updates: shared.map { |listing| update(listing, configuration.file, tags, latest) }, dry_run:)
        changes = result.changes
        @configuration.set_refs(root, refs(changes)) unless dry_run || changes.empty?
        result
      end

      private

      # A change always has a newest tag: a plugin with none is untagged.
      def refs(changes)
        changes.to_h do |change|
          newest = change.newest #: String
          key = [change.listing.name, change.listing.path] #: [String, String?]
          [key, newest]
        end
      end

      def update(listing, file, tags, latest)
        ref = listing.ref || raise(Mistake.new("shared plugin #{listing.shown.dump} needs ref=, a tag or a full commit SHA", file:, line: listing.line))
        # No request for a ref that is no version: a prerelease or a
        # commit is somewhere a person put it.
        current = VersionTag.parse(ref)
        return Update.new(listing:, newest: nil) unless current

        listed = tags[listing.name] ||= @shared_plugins.tags(listing.name)
        versions = VersionTags.parse(listed)
        return Update.new(listing:, newest: versions.newest(keep: current)&.text) if latest

        Update.new(listing:, newest: versions.compatible_update(current)&.text, newer: versions.newer_incompatible(current).tags.map(&:text))
      rescue FetchError => error
        raise Mistake.new("couldn't list the tags of shared plugin #{listing.name}: " + error.message, file:, line: listing.line)
      end
    end
  end
end
