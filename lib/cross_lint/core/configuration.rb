# frozen_string_literal: true

module CrossLint
  module Core
    class Setting < Data.define(:name, :arguments, :properties, :children, :line); end

    class ListedPlugin < Data.define(:name, :ref, :settings, :line)
      def kind
        return :local if name.start_with?(".", "/")
        return :shared if name.start_with?("https://")

        :built_in
      end
    end

    class PolicySetting < Data.define(:name, :enabled, :severity, :line); end

    class Configuration < Data.define(:file, :plugins, :policies, :warnings, :verbosity); end
  end
end
