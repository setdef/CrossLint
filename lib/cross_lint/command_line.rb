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

    def initialize(spec, argv, plugin_flags: nil, probing: false)
      @spec = spec
      @argv = argv
      @plugin_flags = plugin_flags
      @probing = probing
      @helping = helping?(argv)
      @declared = {}
      @flags = {}
      @words = []
      # --help and --version set @action, which stops the reading there, so a
      # mistake after either one is never read and the help still shows. With
      # --help or -h anywhere on the line, a mistake before it is skipped too,
      # since help never fails.
      read(argv.dup)
      @action ||= :run
      @given = @flags.keys
      base_flags.each { |flag| @flags[flag.long] ||= flag.default if flag.default }
    end

    def value(long)
      value = flags[long]
      case value
      when String then value
      end
    end

    def given?(long) = @given.include?(long)

    def known_flags = base_flags + declared_flags + [HELP, VERSION]

    private

    # Whether --help or -h is a flag of the line, not an argument after --.
    def helping?(argv) = argv.take_while { |word| word != "--" }.any? { |word| ["--help", "-h"].include?(word) }

    # The flags the spec gives where the reading is, without those of a
    # plugin's command, which the project says.
    def base_flags
      command = @command
      command ? command.flags + @spec.global_flags : @spec.flags
    end

    # The flag a block finds, among the spec's flags first, so the project
    # is read for a plugin's flags only when a flag isn't one of them.
    def find_flag(&matches) = (base_flags + [HELP, VERSION]).find(&matches) || declared_flags.find(&matches)

    # The flags that the plugin's command, named by the first two words,
    # declares, once both are read, which the project's plugins say. Only the
    # first reading asks, since the one for --project has no plugin_flags.
    def declared_flags
      asking = @plugin_flags
      return [] unless asking && @command.nil? && @words.size >= 2

      @declared[@words.first(2)] ||= asking.call(@words.first(2), project)
    rescue Core::Mistake
      raise unless @helping

      []
    end

    # The project given with --project, which can come after the flag that
    # needs it, so the line is read once more, skipping every flag the spec
    # doesn't give.
    def project = self.class.new(@spec, @argv, probing: true).value("project")

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
      flag = find_flag { |known| known.long == name }
      return unless flag || !(@probing || @helping)
      raise Error, unknown_flag("--#{name}", known_flags.map { |known| "--#{known.long}" }) unless flag

      value ||= words.shift if flag.value
      set(flag, value)
    end

    def read_short(letters, words)
      until letters.empty? || @action
        letter = letters[0]
        letters = letters[1..]
        flag = find_flag { |known| known.short == letter }
        return unless flag || !(@probing || @helping)
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
    rescue Error
      raise unless @helping
    end

    def flag_value(flag, value)
      raise Error, "--#{flag.long} takes a value, as in #{flag.usage}" unless value
      choices = flag.choices
      return value if choices.nil? || choices.include?(value)

      raise Error, "--#{flag.long} takes #{list(choices)}, not #{shown(value)}"
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

      "#{words.take(words.size - 1).join(', ')}, or #{words.last}"
    end
  end
end
