# frozen_string_literal: true

require "did_you_mean"

module CrossLint
  class CommandLine
    class Error < StandardError; end

    HELP = UsageSpec::Flag.new(short: "h", long: "help", value: nil, help: "Print help", long_help: nil,
      choices: nil, default: nil, global: true)
    VERSION = UsageSpec::Flag.new(short: "V", long: "version", value: nil, help: "Print version", long_help: nil,
      choices: nil, default: nil, global: true)

    # Quoting keeps every message ASCII.
    def self.shown(word) = word.match?(/\A[!-~]+\z/) ? word : word.dump

    attr_reader :action

    attr_reader :command

    attr_reader :flags

    attr_reader :topic

    attr_reader :words

    def initialize(spec, argv)
      @spec = spec
      @flags = {}
      @words = []
      # --help and --version set @action, which stops the reading there, so a
      # mistake after either one is never read and the help still shows.
      read(argv.dup)
      @action ||= :run
      @given = @flags.keys
      known_flags.each { |flag| @flags[flag.long] ||= flag.default if flag.default }
    end

    def value(long)
      value = flags[long]
      case value
      when String then value
      end
    end

    def given?(long) = @given.include?(long)

    def known_flags
      command = @command
      flags = command ? command.flags + @spec.global_flags : @spec.flags
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

      value ||= words.shift if flag.value
      set(flag, value)
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

    # A word that is none of CrossLint's commands may be a plugin's name, or
    # its command's, which the plugins the project lists say, so it is kept
    # for the caller, with the words after it.
    def read_argument(word)
      return read_topic(word) if @command&.name == "help"
      return @words << word if @command.nil? && (@words.any? || spec_command(word).nil?)
      raise Error, "#{scope} takes no arguments; remove #{shown(word)}" if @command

      @command = spec_command(word)
    end

    def read_topic(word)
      raise Error, "#{scope} takes one command at most; remove #{shown(word)}" if @topic
      return @words << word if @words.any?

      # The command help explains is one of the program's, so the program's
      # --help is what lists the commands, not help's own.
      @topic = spec_command(word)
      @words << word unless @topic
    end

    def spec_command(word) = @spec.commands.find { |command| command.name == word }

    def unknown_flag(name, names) = suggest("#{scope} has no flag #{shown(name)}", name, names, scope)

    def suggest(message, typed, names, where)
      guess = DidYouMean::SpellChecker.new(dictionary: names).correct(typed).first
      return "#{message}; did you mean #{guess}?" if guess

      "#{message}; #{where} --help lists them"
    end

    def scope
      command = @command
      (command ? [@spec.bin, command.name] : [@spec.bin, *@words]).join(" ")
    end

    def shown(word) = self.class.shown(word)

    def list(words)
      return words.join(" or ") if words.size < 3

      "#{words.take(words.size - 1).join(", ")}, or #{words.last}"
    end
  end
end
