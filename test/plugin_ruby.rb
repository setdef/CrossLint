# frozen_string_literal: true

# The Ruby of the plugins in plugins/, which a check loads anew into a
# namespace of the plugin's own. Coverage follows a file's methods from the
# time it loads, so a file loaded anew for each check is measured as the
# last check loaded it. Here each file a manifest names loads once, before
# any test runs (test/test_helper.rb requires this file), into a module of
# its plugin's own, since two plugins can each define Artifacts; the
# plugins' tests give CrossLint::App a PluginRuby, which puts the classes
# that file defined in the namespace a check asks for. A file no manifest
# names loads as a check loads it, by a require from one that is named.
require "cross_lint"

module LoadedPlugins
  FOLDER = File.expand_path("../plugins", __dir__)

  # Each named file's constants, by the file's path.
  FILES = {}
  private_constant :FILES

  Dir.glob("*/plugin.kdl", base: FOLDER).sort.each do |manifest|
    folder = File.join(FOLDER, File.dirname(manifest))
    namespace = Module.new
    File.read(File.join(FOLDER, manifest)).scan(/\bruby="([^"]+)"/).flatten.uniq.each do |file|
      path = File.expand_path(file, folder)
      before = namespace.constants
      Kernel.load(path, namespace)
      FILES[path] = (namespace.constants - before).to_h { |name| [name, namespace.const_get(name)] }
    end
  end

  # The port of CrossLint::Adapters::FilePluginRuby that gives each file
  # the classes it defined when it loaded, and loads any other file as
  # that port does.
  class PluginRuby
    def initialize(other = CrossLint::Adapters::FilePluginRuby.new)
      @other = other
    end

    def load(plugin, file, line, namespace)
      defined = FILES[File.expand_path(file, plugin.folder)]
      return @other.load(plugin, file, line, namespace) unless defined

      defined.each { |name, found| namespace.const_set(name, found) }
    end
  end
end
