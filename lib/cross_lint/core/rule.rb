# frozen_string_literal: true

require_relative "artifact"
require_relative "fault"

module CrossLint
  # A rule file names this class CrossLint::Rule, as the plugin
  # reference does, so it is outside Core though core/ defines it.
  class Rule
    # Rule files run in CrossLint's process, where Bundler is loaded, and
    # bundler/inline would install gems into CrossLint's folder. Ruby
    # finds the bundler/inline in this folder first, which refuses.
    REFUSED = File.expand_path("refused", File.dirname(__FILE__))
    $LOAD_PATH.unshift(REFUSED)

    class Companion
      attr_reader :name, :path

      def initialize(companion, read)
        @name = companion.name
        @path = companion.path
        @exists = companion.exist?
        @read = read
      end

      def exist? = @exists

      def read = @read.call(path)
    end

    class Artifact
      attr_reader :role, :path, :match

      def initialize(artifact, read)
        @role = artifact.role
        @path = artifact.path
        @match = artifact.match.freeze
        @companions = artifact.companions.map { |companion| Companion.new(companion, read) }
        @read = read
      end

      def companion(name)
        @companions.find { |companion| companion.name == name } || raise(KeyError, "artifact #{role.dump} has no companion #{name.dump}")
      end

      def read = @read.call(path)
    end

    def check(_artifact)
      raise Core::PluginError, "has no check method"
    end

    def violation(artifact, message, detail: nil)
      raise Core::PluginError, "made a violation of #{artifact.inspect}, which is no artifact it was given" unless artifact.instance_of?(Artifact)
      raise Core::PluginError, "made a violation whose message is #{message.inspect}, which is no string" unless message.instance_of?(String)
      raise Core::PluginError, "made a violation whose detail is #{detail.inspect}, which is no string" unless detail.nil? || detail.instance_of?(String)

      Core::RuleResult.new(path: artifact.path, role: artifact.role, message:, detail:)
    end
  end
end
