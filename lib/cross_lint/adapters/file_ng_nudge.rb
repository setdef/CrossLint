# frozen_string_literal: true

require_relative "../core"

module CrossLint
  module Adapters
    class FileNgNudge
      FOLDER = ".config/ng-nudge"

      # The folder of each kind of extension, and what ng-nudge reads in it.
      SUFFIXES = {"artifacts" => ".artifact.js", "policies" => ".policy.js", "rules" => ".rule.js"}.freeze

      def settings(root)
        path = File.join(root, Core::NgNudge::SETTINGS_FILE)
        return unless File.file?(path)

        text = File.binread(path).force_encoding(Encoding::UTF_8)
        raise Core::Mistake.new("isn't valid UTF-8", file: Core::NgNudge::SETTINGS_FILE) unless text.valid_encoding?

        text
      end

      def extensions(root)
        SUFFIXES.flat_map do |folder, suffix|
          where = File.join(root, FOLDER, folder)
          # ng-nudge reads the names that end in the suffix, a dotfile among them. Dir.glob sorts them.
          found = Dir.glob("*#{suffix}", File::FNM_DOTMATCH, base: where).select { |name| File.file?(File.join(where, name)) }
          found.map { |name| "#{FOLDER}/#{folder}/#{name}" }
        end
      end
    end
  end
end
