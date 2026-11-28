# frozen_string_literal: true

require "test_helper"
require "open3"
require "rbconfig"

# The crosslint program, run as a person runs it. These, ArchitectureTest,
# and GitProjectFilesTest are the only tests that start a process.
class ExeTest < Minitest::Test
  EXE = File.join(ROOT, "exe", "crosslint")
  TUTORIAL = "docs/getting-started.md"

  def test_prints_the_version_and_exits_with_0
    assert_equal ["crosslint #{shipped_spec.version}\n", "", 0], crosslint("--version")
  end

  def test_prints_the_help_the_spec_gives
    assert_equal [CrossLint::Help.new(shipped_spec).render, "", 0], crosslint("--help")
  end

  def test_help_prints_the_help_of_a_command_as_help_does
    assert_equal [CrossLint::Help.new(shipped_spec).render(shipped_spec.commands.first), "", 0], crosslint("help", "check")
    assert_equal crosslint("check", "--help"), crosslint("help", "check")
    assert_equal crosslint("--help"), crosslint("help")
    assert_equal [CrossLint::Help.new(shipped_spec).short, "", 0], crosslint
  end

  def test_help_exits_with_2_at_a_command_it_does_not_have
    assert_equal ["", "crosslint: crosslint has no command chekc, and the configuration lists no plugin of that name; did you mean check?\n", 2], crosslint("help", "chekc")
  end

  def test_exits_with_2_at_a_mistake
    assert_equal ["", "crosslint: crosslint has no flag --quite; did you mean --quiet?\n", 2], crosslint("--quite")
  end

  def test_checks_that_every_file_has_its_signature_every_link_resolves_and_the_decision_index_is_exact
    count = Dir.glob("lib/**/*.rb", base: ROOT).size
    markdown, = Open3.capture3("git", "-C", ROOT, "ls-files", "-z", "--cached", "--others", "--exclude-standard", "*.md")
    documents = markdown.split("\0").uniq.size

    assert_equal ["", "crosslint: checked #{count} ruby-file, #{documents} markdown-file, 1 index, and #{documents} document artifacts: no violations\n", 0],
      crosslint("check", chdir: File.join(ROOT, "lib"))
  end

  # The tutorial as a reader works through it, from an empty folder: a
  # file block, whose first line is a comment with the file's path, is
  # written whole, and each command of a transcript runs in the page's
  # order and prints exactly what the page shows after it.
  def test_runs_the_tutorial_as_it_shows_it
    blocks = File.read(File.join(ROOT, TUTORIAL)).scan(/^```(console|kdl)\n(.*?)^```$/m)
    Dir.mktmpdir("crosslint") do |folder|
      shell = Shell.new(folder) { |words, chdir| crosslint(*words, chdir:) }
      ran = blocks.map do |language, block|
        next block.tap { shell.write(block[%r{\A// (\S+)\n}, 1], block) } if language == "kdl"

        block.scan(/^\$ (.*)\n/).map { |(line)| "$ #{line}\n#{shell.run(line)}" }.join
      end

      assert_equal blocks.map(&:last), ran
    end
  end

  # A recipe's files are its blocks whose first line is a comment with
  # the file's path, each written whole, in the page's order, and each
  # `$ crosslint check` runs where the page shows it.
  def test_runs_each_cookbook_recipe_as_it_shows_it
    {"docs/cookbook/rails-routes.md" => [1, 1], "docs/cookbook/scoped-vue-styles.md" => [0, 0]}.each do |page, statuses|
      Dir.mktmpdir("crosslint") do |project|
        Open3.capture3("git", "init", "-q", chdir: project)
        ran = File.read(File.join(ROOT, page)).scan(/^```\w+\n(.*?)^```$/m).flatten.filter_map do |block|
          next crosslint("check", chdir: project).then { |out, err, status| ["$ crosslint check\n#{out}#{err}", status] } if block.start_with?("$ crosslint check\n")

          path = block[%r{\A(?://|#|<!--) (\S+)(?: -->)?\n}, 1]
          write(project, path, block) if path
          nil
        end

        assert_equal doc_blocks(page, "console").zip(statuses), ran, page
      end
    end
  end

  def test_runs_the_plugin_references_ruby_rule_as_written
    plugin = doc_block("docs/reference/plugin.md", "kdl", /policy "has-declaration"/)
    rule = doc_block("docs/reference/plugin.md", "kdl", /^rule "declares-every-export" helper="exports"/)
    code = doc_block("docs/reference/plugin.md", "ruby", /\A# \S+declares_every_export\.rb\n/)
    Dir.mktmpdir("crosslint") do |project|
      write(project, ".config/crosslint/modules/plugin.kdl", "#{plugin}\n#{rule}")
      write(project, code[/\A# (\S+)\n/, 1], code)
      write(project, ".config/crosslint/config.kdl", %(plugin ".config/crosslint/modules"\n))
      {"cart" => "export function add() {}\n", "cart/total" => "export function total() {}\nexport function tax() {}\n"}.each do |path, source|
        write(project, "src/#{path}.js", source)
        write(project, "src/#{path}.d.ts", "export function add(): void\n")
        write(project, "test/#{path}.test.js", "")
      end
      Open3.capture3("git", "init", "-q", chdir: project)

      assert_equal ["src/cart/total.js: src/cart/total.d.ts declares no function tax (modules/declaration-matches)\n" \
        "src/cart/total.js: src/cart/total.d.ts declares no function total (modules/declaration-matches)\n",
        "crosslint: checked 2 module artifacts: 2 errors\n", 1], crosslint("check", chdir: project)
    end
  end

  # The mistake is the plugin with the typo the tutorial's message
  # names, so the message's file and line are checked against the page.
  def test_stops_at_the_mistake_the_tutorial_shows
    message = File.read(File.join(ROOT, TUTORIAL))[/If instead you see `(crosslint: [^`]+)`/, 1]
    path = message[/\Acrosslint: ([^:]+):/, 1]
    typo, meant = message.scan(/"(\w+)"/).flatten
    plugin = doc_block(TUTORIAL, "kdl", %r{\A// #{Regexp.escape(path)}\n})
    configuration = doc_block(TUTORIAL, "kdl", %r{\A// \.config/crosslint/config\.kdl\n})
    Dir.mktmpdir("crosslint") do |project|
      write(project, path, plugin.sub(meant, typo))
      write(project, ".config/crosslint/config.kdl", configuration.sub(%(plugin "debt"\n), ""))

      assert_equal ["", "#{message}\n", 2], crosslint("check", "-C", project)
    end
  end

  private

  # A reader at a shell, in a folder of their own, who runs the few
  # commands the tutorial gives, and sees what each prints: `crosslint`
  # as the block given runs it, and `touch` with the braces bash expands.
  class Shell
    def initialize(folder, &crosslint)
      @folder = folder
      @crosslint = crosslint
      @status = 0
    end

    def write(path, text)
      FileUtils.mkdir_p(File.dirname(here(path)))
      File.binwrite(here(path), text)
    end

    def run(line)
      name, *words = line.split
      case [name, words]
      in ["crosslint", _] then return crosslint(words)
      in ["echo", ["$?"]] then return "#{@status}\n"
      in ["cat", [path]] then return File.binread(here(path))
      in ["mkdir", _] then FileUtils.mkdir_p(words.grep_v(/\A-/).map { here(it) })
      in ["cd", [path]] then @folder = here(path)
      in ["touch", _] then FileUtils.touch(words.flat_map { expand(it) }.map { here(it) })
      in ["git", ["init", "--quiet"]] then Open3.capture3("git", "init", "--quiet", chdir: @folder)
      end
      ""
    end

    private

    def crosslint(words)
      out, err, @status = @crosslint.call(words, @folder)
      out + err
    end

    def here(path) = File.join(@folder, path)

    def expand(word)
      before, choices, after = word.match(/\A([^{]*)\{([^}]*)\}(.*)\z/)&.captures
      choices ? choices.split(",").map { "#{before}#{it}#{after}" } : [word]
    end
  end

  def crosslint(*argv, chdir: ROOT)
    out, err, status = Open3.capture3(RbConfig.ruby, EXE, *argv, stdin_data: "", chdir:)
    [out, err, status.exitstatus]
  end
end
