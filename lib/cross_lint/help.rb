# frozen_string_literal: true

module CrossLint
  # The help crosslint --help prints, made from the usage spec: for the program,
  # or for one of its commands.
  #
  # Texts keep their line breaks from the spec. A line longer than
  # WIDTH columns is wrapped between words, with the indent of the column
  # it is in.
  class Help
    # The widest a line gets, unless one word is wider.
    WIDTH = 100

    def initialize(spec)
      @spec = spec
    end

    # The help for +command+, a UsageSpec::Command, or for the program when
    # it is nil.
    def render(command = nil)
      sections = command ? command_sections(command) : program_sections
      sections.compact.join("\n")
    end

    private

    def program_sections
      [
        "#{@spec.name} #{@spec.version}\n",
        block(@spec.long_about || @spec.about),
        "Usage: #{@spec.bin} [FLAGS] [SUBCOMMAND]\n",
        section("Commands", @spec.commands.map { |command| [command.name, [command.help]] }),
        section("Flags", flag_rows(@spec.flags + extra_flags)),
        examples(@spec.examples),
        exit_codes,
        @spec.after_long_help && block(@spec.after_long_help)
      ]
    end

    def command_sections(command)
      [
        block(command.long_help || command.help),
        "Usage: #{@spec.bin} #{command.name} [FLAGS]\n",
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
        lines << "Choices: #{flag.choices.join(", ")}" if flag.choices
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
        lines = []
        lines << "  #{example.header}:" if example.header
        lines.concat(wrap(example.help, "    ")) if example.help
        lines << "    $ #{example.code}"
        lines.join("\n")
      end
      "Examples:\n#{entries.join("\n\n")}\n"
    end

    # A heading, and a row for each of +rows+: a name, and the lines that
    # describe it, which start in the same column in every row.
    def section(heading, rows)
      return if rows.empty?

      width = rows.map { |name, _| name.size }.max
      entries = rows.map do |name, descriptions|
        first, *rest = descriptions.flat_map { |description| wrap(description, " " * (width + 4)) }
        ["  #{name.ljust(width)}  #{first.lstrip}", *rest].join("\n")
      end
      "#{heading}:\n#{entries.map { |entry| "#{entry}\n" }.join}"
    end

    def block(text) = "#{wrap(text, "").join("\n")}\n"

    # The lines of +text+, each starting with +indent+ and wrapped to WIDTH,
    # with no space at the end.
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
