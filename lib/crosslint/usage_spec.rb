# frozen_string_literal: true

require "kdl"

module CrossLint
  # The command-line interface that crosslint.usage.kdl declares, in the
  # usage spec format (https://usage.jdx.dev): the program's name and
  # version, its texts, flags, commands, examples, and exit statuses.
  #
  # It reads every node and property the spec has, and raises
  # UsageSpec::Error at one it doesn't know, so a line added to the spec
  # can't be left out of the help without a test failing.
  class UsageSpec
    # The spec CrossLint ships, in the folder above lib/.
    PATH = File.expand_path("../../crosslint.usage.kdl", __dir__)

    # A spec that CrossLint can't read, which is a bug in CrossLint.
    class Error < StandardError; end

    # A flag: its one-letter name, its long name, the name of the value it
    # takes (nil for none), its help, and for a flag with a value, the
    # values it takes (nil for any) and its default.
    Flag = Data.define(:short, :long, :value, :help, :long_help, :choices, :default, :global) do
      # How the flag is written with its value, such as "--project <dir>".
      def usage = value ? "--#{long} <#{value}>" : "--#{long}"
    end

    # A command, such as check, with its flags and examples.
    Command = Data.define(:name, :help, :long_help, :flags, :examples)

    # A command line to show, with a heading and a line of help.
    Example = Data.define(:code, :header, :help)

    # An exit status, and what it means.
    ExitCode = Data.define(:code, :meaning)

    # The nodes at the top of the spec that hold one string.
    TEXTS = %w[min_usage_version name bin version author license repository about long_about after_long_help].freeze

    attr_reader(*TEXTS.map(&:to_sym), :flags, :commands, :examples, :exit_codes)

    # Reads the spec at +path+.
    def self.load(path = PATH) = new(File.read(path))

    # Reads a spec from its KDL +source+.
    def initialize(source)
      @flags = []
      @commands = []
      @examples = []
      @exit_codes = []
      KDL.parse(source).each { |node| read_top(node) }
    end

    # The flags that every command takes as well.
    def global_flags = flags.select(&:global)

    private

    def read_top(node)
      if TEXTS.include?(node.name)
        instance_variable_set(:"@#{node.name}", text(node))
      else
        case node.name
        when "unknown_flags" then read_unknown_flags(node)
        when "flag" then @flags << flag(node)
        when "cmd" then @commands << command(node)
        when "example" then @examples << example(node)
        when "exit_code" then @exit_codes << exit_code(node)
        else raise Error, unknown(node)
        end
      end
    end

    # CrossLint stops at an unknown flag, as "error" means, and can do
    # nothing else.
    def read_unknown_flags(node)
      setting = text(node)
      raise Error, "unknown_flags is #{setting.dump}, and CrossLint only stops at an unknown flag" unless setting == "error"
    end

    # The children a flag may have.
    FLAG_SETTINGS = %w[choices default long_help].freeze

    def flag(node)
      words, = arguments(node, 1)
      properties = properties(node, %w[effect global help])
      short, long, value = flag_names(words)
      settings = {}
      node.each do |child|
        raise Error, unknown(child) unless FLAG_SETTINGS.include?(child.name)

        settings[child.name] = (child.name == "choices") ? only(child) : text(child)
      end
      Flag.new(short:, long:, value:, help: properties["help"], long_help: settings["long_help"],
        choices: settings["choices"], default: settings["default"], global: properties.fetch("global", false))
    end

    # The names in a flag's first argument, such as "-C --project <dir>".
    def flag_names(words)
      names = words.split.each_with_object({}) do |word, found|
        case word
        when /\A-([A-Za-z0-9])\z/ then found[:short] = $1
        when /\A--([a-z0-9][a-z0-9-]*)\z/ then found[:long] = $1
        when /\A<([a-z][a-z0-9_-]*)>\z/ then found[:value] = $1
        else raise Error, "flag #{words.dump} has #{word.dump}, which CrossLint doesn't read"
        end
      end
      long = names.fetch(:long) { raise Error, "flag #{words.dump} has no long name" }
      [names[:short], long, names[:value]]
    end

    def command(node)
      name, = arguments(node, 1)
      properties = properties(node, %w[effect help])
      long_help = nil
      flags = []
      examples = []
      node.each do |child|
        case child.name
        when "long_help" then long_help = text(child)
        when "flag" then flags << flag(child)
        when "example" then examples << example(child)
        else raise Error, unknown(child)
        end
      end
      Command.new(name:, help: properties["help"], long_help:, flags:, examples:)
    end

    def example(node)
      code, = arguments(node, 1)
      properties = properties(node, %w[header help])
      no_children(node)
      Example.new(code:, header: properties["header"], help: properties["help"])
    end

    def exit_code(node)
      code, meaning = only(node, 2)
      ExitCode.new(code:, meaning:)
    end

    # The one argument of a node that holds only a string.
    def text(node) = only(node, 1).first

    # The arguments of a node that has no properties and no children.
    def only(node, count = nil)
      properties(node, [])
      no_children(node)
      arguments(node, count)
    end

    # The values of a node's arguments, of which there must be +count+
    # when it is given.
    def arguments(node, count)
      values = node.arguments.map(&:value)
      return values if count.nil? || values.size == count

      raise Error, "#{node.name} has #{values.size} arguments, and CrossLint reads #{count}"
    end

    # The values of a node's properties, each of which must be +allowed+.
    def properties(node, allowed)
      values = node.properties.transform_values(&:value)
      unknown = values.keys - allowed
      raise Error, "#{node.name} has #{unknown.first}=, which CrossLint doesn't read" unless unknown.empty?

      values
    end

    def no_children(node)
      child = node.first
      raise Error, unknown(child) if child
    end

    def unknown(node) = "#{node.name} is a node CrossLint doesn't read"
  end
end
