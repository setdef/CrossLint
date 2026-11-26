# frozen_string_literal: true

require "json"
require "open3"
require_relative "../core"

module CrossLint
  module Adapters
    class NodeJavaScript
      # Reads {source, texts} from standard input, and writes {matches} or
      # {error}. A script on one line, with no double quote, since
      # Windows passes a program's arguments as one string.
      SCRIPT = "const chunks = []; process.stdin.on('data', (chunk) => chunks.push(chunk)); " \
        "process.stdin.on('end', () => { const input = JSON.parse(Buffer.concat(chunks).toString('utf8')); let answer; " \
        "try { const expression = new RegExp(input.source); answer = { matches: input.texts.map((text) => expression.test(text)) }; } " \
        "catch (error) { answer = { error: error.message }; } process.stdout.write(JSON.stringify(answer)); });"

      LIMIT = 10

      attr_reader :limit

      def initialize(command: "node", script: SCRIPT, limit: LIMIT)
        @command = command
        @script = script
        @limit = limit
      end

      def matches(source, texts)
        answer = ask(JSON.generate({"source" => source, "texts" => texts}))
        error = answer["error"]
        raise Core::JavaScriptError, error if error

        answer.fetch("matches")
      end

      private

      def ask(input)
        out, err, status = run(input)
        raise Core::JavaScriptError, "#{@command} exited with status #{status.exitstatus}, and wrote:\n#{err}" unless status.success?

        JSON.parse(out)
      rescue JSON::ParserError
        raise Core::JavaScriptError, "#{@command} answered with something that isn't JSON: #{out.inspect}"
      end

      # What the program wrote to standard output and standard error, and
      # its status, once it has read `input`. The program answers once it
      # has read all of its input, so the input is written first. A timer
      # ends the program when it takes longer than the limit.
      def run(input)
        Open3.popen3(@command, "-e", @script) do |stdin, stdout, stderr, wait|
          timer = Thread.new { Process.kill("KILL", wait.pid) unless wait.join(@limit) }
          write(stdin, input)
          out = text(stdout)
          err = text(stderr)
          status = wait.value
          raise Core::JavaScriptError, "#{@command} didn't answer within #{@limit}s" if timer.value

          [out, err, status]
        end
      rescue SystemCallError => error
        raise Core::JavaScriptError, "couldn't run #{@command}, which CrossLint tests a regular expression with, so install Node: " + error.message
      end

      def write(stdin, input)
        stdin.write(input)
      rescue SystemCallError
        # The program ended without reading its input; its status says why.
      ensure
        stdin.close
      end

      def text(pipe) = pipe.read.force_encoding(Encoding::UTF_8).scrub
    end
  end
end
