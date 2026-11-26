# frozen_string_literal: true

require "rbconfig"

module CrossLint
  module Adapters
    class HelperEnvironment
      # Bundler's preserver, which the Fledge launcher uses as bundle exec
      # does, saves each variable it sets as BUNDLER_ORIG_NAME, and an
      # unset one as UNSET.
      SAVED = "BUNDLER_ORIG_"

      UNSET = "BUNDLER_ENVIRONMENT_PRESERVER_INTENTIONALLY_NIL"

      # The launcher saves PATH after it has put the Ruby it carries first
      # (Fledge's design notes call this deliberate), so the saved PATH
      # still holds that folder. Fledge's launcher reads fledge.cfg, which
      # no other Ruby has, in the folder above the Ruby's bin folder on
      # macOS and Linux and two above it on Windows; where the Ruby is the
      # project's own, as under bundle exec in a checkout, its folder is
      # on the PATH the user started CrossLint with and stays.
      # How two paths compare equal: Windows folds case. A table, not a
      # branch, since each system takes only its own.
      COMPARING = {nil => :==}.fetch(File::ALT_SEPARATOR, :casecmp?)

      def self.app_folder
        bin = RbConfig::CONFIG.fetch("bindir")
        above = [File.dirname(bin), File.dirname(bin, 2)]
        bin if above.any? { |folder| File.file?(File.join(folder, "fledge.cfg")) }
      end

      def initialize(env, app_folder: self.class.app_folder)
        @env = env
        @app_folder = app_folder
      end

      def changes
        saved = @env.select { |name, _| name.start_with?(SAVED) }
        changes = saved.to_h { |name, value| [name.delete_prefix(SAVED), (value unless value == UNSET)] }
        saved.each_key { |name| changes[name] = nil }
        path = changes.fetch("PATH") { @env.fetch("PATH", nil) }
        app = @app_folder
        changes["PATH"] = without_app(path, app) if app && path
        changes
      end

      def fetch(name, default)
        changed = changes
        changed.key?(name) ? (changed.fetch(name) || default) : @env.fetch(name, default)
      end

      private

      def without_app(path, app)
        folders = path.each_line(File::PATH_SEPARATOR, chomp: true).to_a
        # each_line ends at the last separator, which a PATH that ends
        # with one means to have an empty folder after.
        folders << "" if path.end_with?(File::PATH_SEPARATOR)
        folders.reject { |folder| !folder.empty? && same?(folder, app) }.join(File::PATH_SEPARATOR)
      end

      def same?(one, other) = File.expand_path(one).public_send(COMPARING, File.expand_path(other))
    end
  end
end
