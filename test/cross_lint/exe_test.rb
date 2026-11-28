# frozen_string_literal: true

require "test_helper"
require "open3"
require "rbconfig"

# The crosslint program, run as a person runs it. These, ArchitectureTest,
# and GitProjectFilesTest are the only tests that start a process.
class ExeTest < Minitest::Test
  EXE = File.join(ROOT, "exe", "crosslint")

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

  def test_runs_the_tutorials_checks_as_it_shows_them
    plugin, configuration = doc_blocks("docs/getting-started.md", "kdl")
    first, fixed = doc_blocks("docs/getting-started.md", "console").select { |block| block.start_with?("$ crosslint check\n") }
    Dir.mktmpdir("crosslint") do |project|
      write(project, ".config/crosslint/tests/plugin.kdl", plugin)
      write(project, ".config/crosslint/config.kdl", configuration.sub(%(plugin "debt"\n), ""))
      %w[currency customer discount invoice line_item payment pdf tax total].each { |name| write(project, "lib/invoices/#{name}.rb", "") }
      %w[customer discount invoice line_item payment total].each { |name| write(project, "test/invoices/#{name}_test.rb", "") }
      Open3.capture3("git", "init", "-q", chdir: project)
      out, err, status = crosslint("check", chdir: project)

      assert_equal [first.delete_prefix("$ crosslint check\n"), 1], [out + err, status]
      write(project, "test/invoices/tax_test.rb", "")
      out, err, status = crosslint("check", chdir: project)

      assert_equal [fixed.delete_prefix("$ crosslint check\n"), 1], [out + err, status]
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
    plugin, _regexes, _methods, _helpers, _helped, rule = doc_blocks("docs/reference/plugin.md", "kdl")
    code = doc_blocks("docs/reference/plugin.md", "ruby").first
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

  def test_stops_at_the_mistake_the_tutorial_shows
    plugin, configuration = doc_blocks("docs/getting-started.md", "kdl")
    Dir.mktmpdir("crosslint") do |project|
      write(project, ".config/crosslint/tests/plugin.kdl", plugin.sub("primary", "primay"))
      write(project, ".config/crosslint/config.kdl", configuration.sub(%(plugin "debt"\n), ""))

      assert_equal ["", %(crosslint: .config/crosslint/tests/plugin.kdl:2: unknown node "primay", did you mean "primary"?\n), 2],
        crosslint("check", "-C", project)
    end
  end

  private

  def crosslint(*argv, chdir: ROOT)
    out, err, status = Open3.capture3(RbConfig.ruby, EXE, *argv, stdin_data: "", chdir:)
    [out, err, status.exitstatus]
  end
end
