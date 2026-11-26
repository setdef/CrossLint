# frozen_string_literal: true

require "did_you_mean"

module CrossLint
  # A command line, read by the usage spec: the command in it, if any,
  # and the value of each flag given, or that has a default.
  #
  # A flag is written as --name, --name=value, or --name value, and one
  # with a one-letter name as -n, -nvalue, or -n value, with several
  # one-letter flags in one word, as in -qa. After --, every word is an
  # argument. Before a command, only the top-level flags are known; after
  # it, the command's and the global ones.
  class CommandLine
    # A mistake in the command line, with a message that says how to fix
    # it.
    class Error < StandardError; end

    # The flags that usage adds to every program, which the spec doesn't
    # list.
    HELP = UsageSpec::Flag.new(short: "h", long: "help", value: nil, help: "Print help", long_help: nil,
      choices: nil, default: nil, global: true)
    VERSION = UsageSpec::Flag.new(short: "V", long: "version", value: nil, help: "Print version", long_help: nil,
      choices: nil, default: nil, global: true)

    # What the person asked for: :help, :version, or :run.
    attr_reader :action

    # The command given, a UsageSpec::Command, or nil for none.
    attr_reader :command

    # Each flag's value by its long name: true for a flag that takes no
    # value, or the value given or the default.
    attr_reader :flags

    # Reads +argv+ by +spec+, and raises Error at a mistake.
    def initialize(spec, argv)
      @spec = spec
      @flags = {}
      # @action stays nil while reading, until --help or --version ends it.
      read(argv.dup)
      @action ||= :run
      known_flags.each { |flag| @flags[flag.long] ||= flag.default if flag.default }
    end

    # The flags known where the reading is: the top-level flags
    # before a command, and the command's and the global ones after it,
    # with --help and --version.
    def known_flags
      flags = @command ? @command.flags + @spec.global_flags : @spec.flags
      flags + [HELP, VERSION]
    end

    private

    def read(words)
      until words.empty? || @action
        word = words.shift
        if word == "--"
          return words.each { |argument| read_argument(argument) }
        elsif word.start_with?("--")
          read_long(word, words)
        elsif word.start_with?("-") && word.size > 1
          read_short(word.delete_prefix("-"), words)
        else
          read_argument(word)
        end
      end
    end

    def read_long(word, words)
      name, value = word.delete_prefix("--").split("=", 2)
      flag = known_flags.find { |known| known.long == name }
      raise Error, unknown_flag("--#{name}", known_flags.map { |known| "--#{known.long}" }) unless flag

      set(flag, value || (flag.value && words.shift))
    end

    def read_short(letters, words)
      until letters.empty? || @action
        letter = letters[0]
        letters = letters[1..]
        flag = known_flags.find { |known| known.short == letter }
        raise Error, unknown_flag("-#{letter}", known_flags.filter_map(&:short).map { |short| "-#{short}" }) unless flag
        next set(flag, nil) unless flag.value

        set(flag, letters.empty? ? words.shift : letters)
        letters = ""
      end
    end

    def set(flag, value)
      return @action = :help if flag == HELP
      return @action = :version if flag == VERSION

      if flag.value
        @flags[flag.long] = flag_value(flag, value)
      else
        raise Error, "--#{flag.long} takes no value; remove =#{shown(value)}" if value

        @flags[flag.long] = true
      end
    end

    def flag_value(flag, value)
      raise Error, "--#{flag.long} takes a value, as in #{flag.usage}" unless value
      return value if flag.choices.nil? || flag.choices.include?(value)

      raise Error, "--#{flag.long} takes #{list(flag.choices)}, not #{shown(value)}"
    end

    def read_argument(word)
      raise Error, "#{scope} takes no arguments; remove #{shown(word)}" if @command

      @command = @spec.commands.find { |command| command.name == word }
      raise Error, suggest("#{scope} has no command #{shown(word)}", word, @spec.commands.map(&:name)) unless @command
    end

    def unknown_flag(name, names) = suggest("#{scope} has no flag #{shown(name)}", name, names)

    # +message+, with the name the person most likely meant, or where to
    # see them all.
    def suggest(message, typed, names)
      guess = DidYouMean::SpellChecker.new(dictionary: names).correct(typed).first
      return "#{message}; did you mean #{guess}?" if guess

      "#{message}; #{scope} --help lists them"
    end

    def scope = [@spec.bin, @command&.name].compact.join(" ")

    # A word the person typed, quoted when it holds anything but printable
    # ASCII, so the message stays ASCII.
    def shown(word) = word.match?(/\A[!-~]+\z/) ? word : word.dump

    # Words joined as in a sentence: "a", "a or b", "a, b, or c".
    def list(words)
      *others, last = words
      return last if others.empty?
      return "#{others.first} or #{last}" if others.size == 1

      "#{others.join(", ")}, or #{last}"
    end
  end
end
