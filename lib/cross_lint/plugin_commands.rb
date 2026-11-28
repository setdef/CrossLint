# frozen_string_literal: true

module CrossLint
  class PluginCommands
    def initialize(spec)
      @spec = spec
    end

    # Settles the first word before any plugin is fetched or loaded: the
    # name of a plugin the configuration lists, whether or not it is
    # fetched, or else a mistake, which raises. When the configuration
    # can't be read, it may be a plugin's name, so only a typo of a command
    # of CrossLint's, or a flag's name, is a mistake, unless `helping`: help
    # never fails, so it goes on, and anything else raises the configuration's.
    def resolve(words, listing, built_in, helping: false)
      name = words.fetch(0)
      return refuse_unreadable(name, listing, helping) if listing.is_a?(Core::Mistake)

      listed = listing.plugins.map(&:name) + unfetched(listing)
      unlisted(name, words.fetch(1, nil), listing, built_in) unless listed.include?(name)
    end

    # The plugin that the first of `words` names, which `resolve` found
    # among `plugins`, and its command.
    def find(words, plugins)
      name = words.fetch(0)
      word = words.fetch(1, nil)
      plugin = plugins.find { |listed| listed.name == name } #: Core::Plugin

      commands = plugin.manifest.commands
      raise error("#{name} is a plugin the configuration lists, and it adds no commands") if commands.empty?
      return [plugin, nil] unless word

      command = commands.find { |declared| declared.name == word }
      raise error(missing(name, word, commands.map(&:name))) unless command
      raise error("#{scope(name, word)} takes no arguments; remove #{shown(words.fetch(2))}") if words.size > 2

      [plugin, command]
    end

    private

    # A shared plugin's name comes from its URL, so it is known unfetched.
    def unfetched(listing)
      listing.unfetched.map do |plugin|
        Core::SharedPlugin.plugin_name(plugin.name) #: String
      end
    end

    def refuse_unreadable(word, mistake, helping)
      names = guesses(word, [])
      raise error("#{@spec.bin} has no command #{shown(word)}; did you mean #{Core::Spelling.list(names)}?") unless names.empty?

      raise mistake unless helping
    end

    def unlisted(name, word, listing, built_in)
      if built_in.call.fetch(name, []).include?(word)
        raise error("#{name} #{word} is a command of the #{name} plugin, which #{listing.file} doesn't list")
      end

      others = listing.plugins.reject { |plugin| plugin.manifest.commands.empty? }.map(&:name) + unfetched(listing)
      names = guesses(name, others)
      raise error("#{@spec.bin} has no command #{shown(name)}, and the configuration lists no plugin of that name; " +
        (names.empty? ? "#{@spec.bin} --help lists the commands" : "did you mean #{Core::Spelling.list(names)}?"))
    end

    def missing(name, word, commands)
      guess = nearest(word, commands)
      "#{scope(name)} has no command #{shown(word)}; " + (guess ? "did you mean #{guess}?" : "its commands are #{Core::Spelling.list(commands, 'and')}")
    end

    # The nearest command of CrossLint's and the nearest of `others`, and
    # the flag the word is the name of, such as --version for version.
    def guesses(word, others)
      flag = "--#{word}" if flag_names.include?(word)
      [nearest(word, commands), nearest(word, others), flag].compact.uniq
    end

    def flag_names = (@spec.global_flags + [CommandLine::HELP, CommandLine::VERSION]).map(&:long)

    def commands = @spec.commands.map(&:name)

    def nearest(word, known) = Core::Spelling.nearest(word, known)

    def scope(*words) = [@spec.bin, words].join(" ")

    def shown(word) = CommandLine.shown(word)

    def error(message) = CommandLine::Error.new(message)
  end
end
