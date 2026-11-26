# frozen_string_literal: true

# A built-in plugin's Ruby, which a check loads anew into a namespace of
# its own. Coverage and mutant follow a file's methods from the time it
# loads, so a file loaded anew for each check is measured as the last
# check loaded it, and mutant, which finds a method in the file by the
# constants around it there, changes the methods of a constant at the top
# level. Here each file loads once, at the top level, before any test
# runs (.mutant.yml has mutant require this file); the plugins' tests give
# CrossLint::App a PluginRuby, which puts the classes that file defined in
# the namespace a check asks for.
require "cross_lint"

module LoadedPlugins
  FOLDER = File.expand_path("../plugins", __dir__)

  # Each plugin's Ruby, by its file's path: the constants the file defines,
  # kept here because a test may remove one from the top level.
  FILES = {}
  private_constant :FILES

  Dir.glob("*/**/*.rb", base: FOLDER).sort.each do |file|
    next if file.split("/")[1] == "test"

    path = File.join(FOLDER, file)
    before = Object.constants
    Kernel.load(path)
    defined = (Object.constants - before).to_h { |name| [name, Object.const_get(name)] }
    # A constant a file defines that another already defined is reopened,
    # which is no definition of its own.
    raise "#{file} defines no constant that is new, so a plugin's file of that name was loaded before it" if defined.empty?

    FILES[path] = defined
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
