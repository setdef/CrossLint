# frozen_string_literal: true

require "kdl"

module CrossLint
  class UsageSpec
    PATH = File.expand_path("../../../crosslint.usage.kdl", __FILE__)

    class Error < StandardError; end

    class Flag < Data.define(:short, :long, :value, :help, :long_help, :choices, :default, :global)
      def usage = value ? "--#{long} <#{value}>" : "--#{long}"
    end

    class Argument < Data.define(:name, :help); end

    class Command < Data.define(:name, :help, :long_help, :arguments, :flags, :examples); end

    class Example < Data.define(:code, :header, :help); end

    class ExitCode < Data.define(:code, :meaning); end

    TEXTS = %w[min_usage_version name bin version author license repository about long_about after_long_help].freeze

    REQUIRED = %w[name bin version about].freeze

    attr_reader(*TEXTS.map(&:to_sym), :flags, :commands, :examples, :exit_codes)

    def self.load(path = PATH) = new(File.read(path))

    def initialize(source)
      @flags = []
      @commands = []
      @examples = []
      @exit_codes = []
      KDL.parse(source).each { |node| read_top(node) }
      missing = REQUIRED.find { |name| instance_variable_get(:"@#{name}").nil? }
      raise Error, "the spec has no #{missing}, which the help shows" if missing
    end

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

    FLAG_SETTINGS = %w[choices default long_help].freeze

    def flag(node)
      words, = arguments(node, 1)
      properties = properties(node, %w[effect global help])
      short, long, value = flag_names(words)
      settings = node.to_h do |child|
        raise Error, unknown(child) unless FLAG_SETTINGS.include?(child.name)

        [child.name, child]
      end
      long_help_node, choices_node, default_node = settings.values_at("long_help", "choices", "default")
      long_help = long_help_node && text(long_help_node)
      choices = choices_node && only(choices_node)
      default = default_node && text(default_node)
      Flag.new(short:, long:, value:, help: help("flag", words, properties), long_help:, choices:, default:,
        global: properties.fetch("global", false))
    end

    def flag_names(words)
      names = words.split.to_h do |word|
        case word
        when /\A-([A-Za-z0-9])\z/ then [:short, $1]
        when /\A--([a-z0-9][a-z0-9-]*)\z/ then [:long, $1]
        when /\A<([a-z][a-z0-9_-]*)>\z/ then [:value, $1]
        else raise Error, "flag #{words.dump} has #{word.dump}, which CrossLint doesn't read"
        end
      end
      long = names[:long]
      raise Error, "flag #{words.dump} has no long name" unless long

      [names[:short], long, names[:value]]
    end

    COMMAND_CHILDREN = %w[long_help arg flag example].freeze

    def command(node)
      name, = arguments(node, 1)
      properties = properties(node, %w[effect help])
      node.each { |child| raise Error, unknown(child) unless COMMAND_CHILDREN.include?(child.name) }
      Command.new(name:, help: help("cmd", name, properties), long_help: node.select { |child| child.name == "long_help" }.map { |child| text(child) }.last,
        arguments: node.select { |child| child.name == "arg" }.map { |child| argument(child) },
        flags: node.select { |child| child.name == "flag" }.map { |child| flag(child) },
        examples: node.select { |child| child.name == "example" }.map { |child| example(child) })
    end

    def argument(node)
      written, = arguments(node, 1)
      properties = properties(node, %w[help])
      no_children(node)
      name = written[/\A\[([a-z][a-z0-9-]*)\]\z/, 1]
      raise Error, "arg #{written.dump} is not written as [name], the only form CrossLint reads" unless name

      Argument.new(name:, help: help("arg", written, properties))
    end

    def help(kind, name, properties)
      properties.fetch("help") { raise Error, "#{kind} #{name.dump} has no help=, which the help shows" }
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

    def text(node) = only(node, 1).first

    def only(node, count = nil)
      properties(node, [])
      no_children(node)
      arguments(node, count)
    end

    def arguments(node, count)
      values = node.arguments.map(&:value)
      return values if count.nil? || values.size == count

      raise Error, "#{node.name} has #{values.size} arguments, and CrossLint reads #{count}"
    end

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
