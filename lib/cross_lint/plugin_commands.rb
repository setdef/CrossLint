# frozen_string_literal: true

module CrossLint
  class PluginCommands
    def initialize(spec)
      @spec = spec
    end

    def find(words, plugins, file, built_in)
      name = words.fetch(0)
      word = words.fetch(1, nil)
      plugin = plugins.find { |listed| listed.name == name } || unlisted(name, word, plugins, file, built_in)

      commands = plugin.manifest.commands
      raise error("#{name} is a plugin the configuration lists, and it adds no commands") if commands.empty?
      return [plugin, nil] unless word

      command = commands.find { |declared| declared.name == word }
      raise error(missing(name, word, commands.map(&:name))) unless command
      raise error("#{scope(name, word)} takes no arguments; remove #{shown(words.fetch(2))}") if words.size > 2

      [plugin, command]
    end

    def refusal(word)
      guess = nearest(word, commands)
      error("#{@spec.bin} has no command #{shown(word)}; did you mean #{guess}?") if guess
    end

    private

    def unlisted(name, word, plugins, file, built_in)
      if built_in.call.fetch(name, []).include?(word)
        raise error("#{name} #{word} is a command of the #{name} plugin, which #{file} doesn't list")
      end

      guesses = [nearest(name, commands), nearest(name, plugins.reject { |plugin| plugin.manifest.commands.empty? }.map(&:name))].compact.uniq
      raise error("#{@spec.bin} has no command #{shown(name)}, and the configuration lists no plugin of that name; " +
        (guesses.empty? ? "#{@spec.bin} --help lists the commands" : "did you mean #{Core::Spelling.list(guesses)}?"))
    end

    def missing(name, word, commands)
      guess = nearest(word, commands)
      "#{scope(name)} has no command #{shown(word)}; " + (guess ? "did you mean #{guess}?" : "its commands are #{Core::Spelling.list(commands, "and")}")
    end

    def commands = @spec.commands.map(&:name)

    def nearest(word, known) = Core::Spelling.nearest(word, known)

    def scope(*words) = [@spec.bin, words].join(" ")

    def shown(word) = CommandLine.shown(word)

    def error(message) = CommandLine::Error.new(message)
  end
end
