# frozen_string_literal: true

module CrossLint
  module Core
    class Setting < Data.define(:name, :arguments, :properties, :children, :line); end

    class ListedPlugin < Data.define(:name, :ref, :path, :settings, :line)
      def initialize(name:, ref:, settings:, line:, path: nil) = super

      # What the plugin is called: its repository's name, or, when it is
      # listed from a folder of the repository, the folder's.
      def plugin_name = path ? File.basename(path) : SharedPlugin.plugin_name(name)

      def kind
        return :local if name.start_with?(".", "/")
        return :shared if name.start_with?("https://")

        :built_in
      end

      def shared?(shared_plugins) = kind == :shared || (kind == :built_in && shared_plugins.accepts?(name))

      # The plugin as a person reads it in a message: its URL, and its
      # folder when it has one.
      def shown = path ? "#{name} (#{path})" : name
    end

    class PolicySetting < Data.define(:name, :enabled, :severity, :line); end

    class Configuration < Data.define(:file, :plugins, :policies, :warnings, :verbosity); end
  end
end
