# frozen_string_literal: true

module CrossLint
  module Core
    class TagVerdicts < Data.define(:shown, :current, :latest)
      def lines(texts) = texts.map { |text| "#{shown}: lists #{text}, which #{verdict(VersionTag.parse(text))}" }

      private

      def verdict(tag)
        return "isn't a version tag, vX.Y.Z or X.Y.Z, so update ignores it" unless tag

        above(tag.version) || "isn't above #{current.text}, so update ignores it"
      end

      def above(version)
        return unless version > current.version
        return "is above #{current.text}, so update may move to it" if latest
        return "is above #{current.text} and compatible with it, so update may move to it" if current.version.compatible_with?(version)

        "is above #{current.text} but not compatible with it, so update leaves it; --latest allows it"
      end
    end
  end
end
