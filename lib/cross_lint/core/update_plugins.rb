# frozen_string_literal: true

module CrossLint
  module Core
    class Update < Data.define(:listing, :newest)
      def current? = newest == listing.ref

      def untagged? = newest.nil? && !pinned?

      def pinned? = !SharedPlugin.version?(listing.ref.to_s)
    end

    class UpdateResult < Data.define(:updates, :dry_run)
      def changes = updates.reject { |update| update.pinned? || update.current? || update.untagged? }

      def lines
        updates.map do |update|
          listing = update.listing
          if update.pinned?
            "#{listing.name}: is at #{listing.ref}, which isn't a plain version tag, vX.Y.Z or X.Y.Z, so update leaves it alone"
          elsif update.untagged?
            "#{listing.name}: has no tag that is a version, vX.Y.Z or X.Y.Z, so it stays at #{listing.ref}"
          elsif update.current?
            "#{listing.name}: is at its newest tag, #{listing.ref}"
          else
            "#{listing.name}: #{dry_run ? "would move" : "moved"} from #{listing.ref} to #{update.newest}"
          end
        end
      end
    end

    class UpdatePlugins
      def initialize(configuration:, shared_plugins:)
        @configuration = configuration
        @shared_plugins = shared_plugins
      end

      def call(start, dry_run: false)
        root = @configuration.find_root(start) || raise(Mistake.no_configuration(@configuration.file, start))
        configuration = @configuration.read(root)
        SharedPlugin.refuse_credentials(configuration, @shared_plugins)
        shared = configuration.plugins.select { |listing| listing.shared?(@shared_plugins) }
        result = UpdateResult.new(updates: shared.map { |listing| update(listing, configuration.file) }, dry_run:)
        changes = result.changes
        @configuration.set_refs(root, refs(changes)) unless dry_run || changes.empty?
        result
      end

      private

      # A change always has a newest tag: a plugin with none is untagged.
      def refs(changes)
        changes.to_h do |change|
          newest = change.newest #: String
          [change.listing.name, newest]
        end
      end

      def update(listing, file)
        ref = listing.ref || raise(Mistake.new("shared plugin #{listing.name.dump} needs ref=, a tag or a full commit SHA", file:, line: listing.line))
        # No request for a ref that is no version: a prerelease or a
        # commit is somewhere a person put it.
        return Update.new(listing:, newest: nil) unless SharedPlugin.version?(ref)

        Update.new(listing:, newest: SharedPlugin.newest_tag(@shared_plugins.tags(listing.name), keep: ref))
      rescue FetchError => error
        raise Mistake.new("couldn't list the tags of shared plugin #{listing.name}: " + error.message, file:, line: listing.line)
      end
    end
  end
end
