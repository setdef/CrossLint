# frozen_string_literal: true

module CrossLint
  module Core
    class PluginError < StandardError; end

    class Fault < Data.define(:plugin, :rule, :artifact, :message, :trace)
      def self.of(error, plugin:, rule:, artifact: nil)
        new(plugin: plugin.name, rule:, artifact:, message: describe(error, plugin.folder), trace: error.backtrace || [])
      end

      def self.describe(error, folder)
        case error
        when PluginError then error.message
        when LoadError then loading(error, folder)
        else "raised #{error.class}: #{error}"
        end
      end

      # A feature by name, such as "rainbow", is a gem's or the standard
      # library's; one by path is a file of the plugin's, such as a
      # require_relative names.
      def self.loading(error, folder)
        feature = error.path
        return "raised #{error.class}: #{error}" unless feature
        return "requires #{feature.delete_prefix("#{folder}/")}, which doesn't exist" if File.absolute_path?(feature) || feature.start_with?(".")

        "requires #{feature}, which is neither in Ruby's standard library nor in the plugin's folder, " \
          "and CrossLint can load no gem it wasn't built with"
      end

      def line
        where = " on #{artifact}" if artifact
        "fault in plugin #{plugin}: rule #{rule}#{where} #{message}"
      end
    end
  end
end
