# frozen_string_literal: true

# Runs every Ruby example in the documentation, and checks it against the
# results it shows (rake doctest).
#
# An example is a fenced code block marked `ruby`, in a Markdown file or
# in a comment in sig/. A line that ends with `# => VALUE` shows a
# result: the code up to that line runs, and the inspected value of its
# last expression must be VALUE. An example with no such line must run
# without raising.
#
# An example that uses a part of CrossLint not built yet is skipped while
# PENDING names that part, and fails the check once the part exists, so
# that the entry is removed.

require "cross_lint"

module Doctest
  PENDING = {}.freeze

  Example = Data.define(:file, :line, :code)

  class Failure < StandardError; end

  module_function

  def examples(root)
    markdown = Dir.glob("{*.md,docs/**/*.md}", base: root).sort
    signatures = Dir.glob("sig/**/*.rbs", base: root).sort
    markdown.flat_map { |file| blocks(file, File.read(File.join(root, file))) } +
      signatures.flat_map { |file| blocks(file, comments(File.read(File.join(root, file)))) }
  end

  def comments(source)
    source.lines.map { |line| line[/\A\s*# ?(.*)/m, 1] || "\n" }.join
  end

  def blocks(file, text)
    found = []
    open = nil
    text.lines.each_with_index do |line, index|
      if open
        next open[:code] << line unless line.match?(/\A\s*```\s*\z/)

        found << Example.new(file:, line: open[:line], code: open[:code])
        open = nil
      elsif line.match?(/\A\s*```ruby\s*\z/)
        open = {line: index + 2, code: +""}
      end
    end
    raise Failure, "#{file}:#{open[:line] - 1}: a ruby block with no closing fence" if open

    found
  end

  def run(example)
    pending = PENDING.keys.find { |name| example.code.include?(name) }
    if pending
      raise Failure, "#{where(example)}: #{pending} exists, so remove it from Doctest::PENDING" if Object.const_defined?(pending)

      return "uses #{pending}, which #{PENDING.fetch(pending)} builds"
    end

    # A block's binding at the top level: an example's constants are the
    # top level's, and its local variables are its own.
    context = TOPLEVEL_BINDING.eval("proc { binding }.call")
    chunks(example).each { |code, line, expected, shown| check(example, context, code, line, expected, shown) }
    nil
  end

  def chunks(example)
    runs = []
    code = +""
    start = example.line
    example.code.lines.each_with_index do |line, index|
      code << line.sub(/\s*# => .*\z/m, "\n")
      expected = line[/# => (.*)$/, 1]
      next unless expected

      runs << [code, start, expected, example.line + index]
      code = +""
      start = example.line + index + 1
    end
    runs << [code, start, nil, nil] unless code.strip.empty?
    runs
  end

  def check(example, context, code, line, expected, shown)
    actual = context.eval(code, example.file, line)
    return if expected.nil? || actual.inspect == expected

    raise Failure, "#{example.file}:#{shown}: shows #{expected}, and the code returns #{actual.inspect}"
  rescue Failure
    raise
  rescue StandardError, ScriptError => error
    raise Failure, "#{where(example)}: raised #{error.class}: #{error.message}"
  end

  def where(example) = "#{example.file}:#{example.line}"
end

if $PROGRAM_NAME == __FILE__
  root = File.expand_path("..", __dir__)
  failures = 0
  Doctest.examples(root).each do |example|
    skipped = Doctest.run(example)
    puts(skipped ? "#{Doctest.where(example)}: skipped: #{skipped}" : "#{Doctest.where(example)}: passed")
  rescue Doctest::Failure => failure
    failures += 1
    warn "rake doctest: #{failure.message}"
  end
  exit(failures.zero? ? 0 : 1)
end
