# frozen_string_literal: true

module CrossLint
  module Core
    class Update < Data.define(:listing, :newest, :newer, :skipped)
      def initialize(listing:, newest:, newer: [], skipped: [])
        super
      end

      def current? = newest == listing.ref

      def untagged? = newest.nil? && !pinned?

      def pinned? = VersionTag.parse(listing.ref.to_s).nil?
    end

    class UpdateResult < Data.define(:updates, :dry_run, :crosslint)
      def changes = updates.reject { |update| update.pinned? || update.current? || update.untagged? }

      def lines = updates.map { |update| what(update) + skipped(update) + newer(update) }

      private

      def what(update)
        listing = update.listing
        if update.pinned?
          "#{listing.shown}: is at #{listing.ref}, which isn't a plain version tag, vX.Y.Z or X.Y.Z, so update leaves it alone"
        elsif update.untagged?
          "#{listing.shown}: has no tag that is a version, vX.Y.Z or X.Y.Z, so it stays at #{listing.ref}"
        elsif update.current? && update.skipped.any?
          "#{listing.shown}: stays at #{listing.ref}"
        elsif update.current?
          "#{listing.shown}: is at its newest #{"compatible " if update.newer.any?}tag, #{listing.ref}"
        else
          "#{listing.shown}: #{dry_run ? "would move" : "moved"} from #{listing.ref} to #{update.newest}"
        end
      end

      def skipped(update)
        return "" if update.skipped.empty?

        tags = update.skipped.map { |tag, reason| "#{tag}, which #{reason}" }
        "; skipped #{tags.join(", and ")}, as this is CrossLint #{crosslint}"
      end

      # Newer incompatible versions are named whether or not the plugin moved.
      def newer(update)
        return "" if update.newer.empty?

        "; newer incompatible versions: #{update.newer.join(", ")}; crosslint update --latest moves to #{update.newer.last}"
      end
    end

    class UpdatePlugins
      def initialize(configuration:, shared_plugins:, manifests:, crosslint:)
        @configuration = configuration
        @shared_plugins = shared_plugins
        @manifests = manifests
        @crosslint = crosslint
      end

      def call(start, dry_run: false, latest: false)
        root = @configuration.find_root(start) || raise(Mistake.no_configuration(@configuration.file, start))
        @configuration.minimum(root)&.check(@crosslint)
        configuration = @configuration.read(root)
        SharedPlugin.refuse_credentials(configuration)
        shared = configuration.plugins.select { |listing| listing.shared?(@shared_plugins) }
        # Plugins listed from folders of one repository share its tags.
        tags = {} #: Hash[String, Array[String]]
        result = UpdateResult.new(updates: shared.map { |listing| update(listing, configuration.file, tags, latest) }, dry_run:, crosslint: @crosslint)
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
        reachable = latest ? versions : versions.compatible_with(current)
        newer = (latest ? VersionTags.parse([]) : versions.newer_incompatible(current)).tags.map(&:text)
        target = latest ? versions.newest(keep: current) : versions.compatible_update(current)
        return Update.new(listing:, newest: target&.text, newer:) unless target && target.version > current.version

        found, skipped = readable(listing, reachable.above(current), file)
        Update.new(listing:, newest: (found || current).text, newer:, skipped:)
      rescue FetchError => error
        raise Mistake.new("couldn't list the tags of shared plugin #{listing.name}: " + error.message, file:, line: listing.line)
      end

      # The newest of `candidates`, newest first, whose manifest this
      # CrossLint reads, and each one before it, with why it can't. Each
      # is fetched in turn, so a tag below the one found is never fetched,
      # and the one found is in the cache for the check that follows.
      def readable(listing, candidates, file)
        skipped = [] #: Array[[String, String]]
        found = candidates.find do |tag|
          reason = unreadable(listing, tag, file)
          skipped << [tag.text, reason] if reason
          reason.nil?
        end
        [found, skipped]
      end

      # Why this CrossLint can't read the plugin at `tag`, or nil when it can.
      def unreadable(listing, tag, file)
        folder = @shared_plugins.fetch(listing.name, tag.text)
        unread(folder, listing.path || "")
      rescue FetchError => error
        raise Mistake.new("couldn't fetch shared plugin #{listing.plugin_name} from #{listing.name} at #{tag.text}: " + error.message,
          file:, line: listing.line)
      end

      # A tag whose crosslint line is a mistake is one this CrossLint can't
      # read, and not a reason to stop the update of every other plugin.
      def unread(folder, path)
        minimum = @manifests.minimum(folder, path)
        minimum.requirement unless minimum.nil? || minimum.met_by?(@crosslint)
      rescue Mistake => mistake
        "has a crosslint line this CrossLint can't read: #{mistake.location}: #{mistake.message}"
      end
    end
  end
end
