# frozen_string_literal: true

module CrossLint
  class Help
    WIDTH = 100

    class Plugins < Data.define(:commands, :notes)
      def self.none = new(commands: [], notes: [])
    end

    def initialize(spec, plugins: Plugins.none)
      @spec = spec
      @plugins = plugins
    end

    def render(command = nil)
      sections = command ? command_sections(command) : program_sections
      sections.compact.join("\n")
    end

    def plugin(name, commands)
      [
        block("The commands of the #{name} plugin"),
        "Usage: #{@spec.bin} #{name} COMMAND [FLAGS]\n",
        section("Commands", commands.map { |command| [command.name, [command.help]] }),
        section("Global flags", flag_rows(@spec.global_flags + extra_flags))
      ].join("\n")
    end

    def plugin_command(name, command)
      [
        block(command.help),
        "Usage: #{@spec.bin} #{name} #{command.name} [FLAGS]\n",
        section("Flags", flag_rows(command.flags)),
        section("Global flags", flag_rows(@spec.global_flags + extra_flags))
      ].compact.join("\n")
    end

    def short
      [
        block(@spec.about),
        examples(@spec.examples.first(2)),
        "Run #{@spec.bin} --help to list every command.\n"
      ].join("\n")
    end

    private

    def program_sections
      after = @spec.after_long_help
      [
        "#{@spec.name} #{@spec.version}\n",
        block(@spec.long_about || @spec.about),
        "Usage: #{@spec.bin} [FLAGS] [SUBCOMMAND]\n",
        section("Commands", @spec.commands.map { |command| [command.name, [command.help]] }),
        plugin_commands,
        section("Flags", flag_rows(@spec.flags + extra_flags)),
        examples(@spec.examples),
        exit_codes,
        after && block(after)
      ]
    end

    # The commands the project's plugins add, and a line for each thing
    # that keeps one from showing, in a section after CrossLint's commands.
    def plugin_commands
      rows = @plugins.commands.map { |plugin, command| ["#{plugin} #{command.name}", [command.help]] } #: Array[[String, Array[String]]]
      return if rows.empty? && @plugins.notes.empty?

      notes = @plugins.notes.flat_map { |note| wrap(note, "  ") }.map { |line| "#{line}\n" }
      (section("Plugin commands", rows) || "Plugin commands:\n") + notes.join
    end

    def command_sections(command)
      [
        block(command.long_help || command.help),
        "Usage: #{[@spec.bin, command.name, "[FLAGS]", *command.arguments.map { |argument| "[#{argument.name}]" }].join(" ")}\n",
        section("Arguments", command.arguments.map { |argument| ["[#{argument.name}]", [argument.help]] }),
        section("Flags", flag_rows(command.flags)),
        section("Global flags", flag_rows(@spec.global_flags + extra_flags)),
        examples(command.examples),
        exit_codes
      ]
    end

    def extra_flags = [CommandLine::HELP, CommandLine::VERSION]

    def flag_rows(flags)
      flags.map do |flag|
        names = [flag.short ? "-#{flag.short}," : "   ", "--#{flag.long}"]
        names << "<#{flag.value}>" if flag.value
        lines = [flag.long_help || flag.help]
        choices = flag.choices
        lines << "Choices: #{choices.join(", ")}" if choices
        lines << "Default: #{flag.default}" if flag.default
        [names.join(" "), lines]
      end
    end

    def exit_codes
      section("Exit status", @spec.exit_codes.map { |exit_code| [exit_code.code.to_s, [exit_code.meaning]] })
    end

    def examples(examples)
      return if examples.empty?

      entries = examples.map do |example|
        header = example.header && "  #{example.header}:"
        [header, *wrap(example.help.to_s, "    "), "    $ #{example.code}"].compact.join("\n")
      end
      "Examples:\n#{entries.join("\n\n")}\n"
    end

    def section(heading, rows)
      return if rows.empty?

      width = rows.map { |name, _| name.size }.max
      entries = rows.map do |name, descriptions|
        first, *rest = descriptions.flat_map { |description| wrap(description, " " * (width + 4)) }
        ["  #{name.ljust(width)}  #{first.to_s.lstrip}".rstrip, *rest].join("\n")
      end
      "#{heading}:\n#{entries.map { |entry| "#{entry}\n" }.join}"
    end

    def block(text) = "#{wrap(text, "").join("\n")}\n"

    def wrap(text, indent)
      text.split("\n").flat_map do |line|
        line.split.each_with_object([+""]) do |word, lines|
          if lines.last.empty?
            lines.last << word
          elsif indent.size + lines.last.size + 1 + word.size <= WIDTH
            lines.last << " " << word
          else
            lines << word
          end
        end
      end.map { |line| (indent + line).rstrip }
    end
  end
end
