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

  def test_exits_with_2_at_a_mistake
    assert_equal ["", "crosslint: crosslint has no flag --quite; did you mean --quiet?\n", 2], crosslint("--quite")
  end

  def test_checks_that_every_file_under_lib_has_its_signature
    count = Dir.glob("lib/**/*.rb", base: ROOT).size

    assert_equal ["", "crosslint: checked #{count} ruby-file artifacts: no violations\n", 0], crosslint("check", chdir: File.join(ROOT, "lib"))
  end

  def test_runs_the_tutorials_checks_as_it_shows_them
    plugin, configuration = doc_blocks("docs/getting-started.md", "kdl")
    first, fixed = doc_blocks("docs/getting-started.md", "console").select { |block| block.start_with?("$ crosslint check\n") }
    Dir.mktmpdir("crosslint") do |project|
      write(project, ".config/crosslint/tests/plugin.kdl", plugin)
      write(project, ".config/crosslint.kdl", configuration.sub(%(plugin "debt"\n), ""))
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

  def test_stops_at_the_mistake_the_tutorial_shows
    plugin, configuration = doc_blocks("docs/getting-started.md", "kdl")
    Dir.mktmpdir("crosslint") do |project|
      write(project, ".config/crosslint/tests/plugin.kdl", plugin.sub("files", "file"))
      write(project, ".config/crosslint.kdl", configuration.sub(%(plugin "debt"\n), ""))

      assert_equal ["", %(crosslint: .config/crosslint/tests/plugin.kdl:2: unknown node "file", did you mean "files"?\n), 2],
        crosslint("check", "-C", project)
    end
  end

  private

  def crosslint(*argv, chdir: ROOT)
    out, err, status = Open3.capture3(RbConfig.ruby, EXE, *argv, stdin_data: "", chdir:)
    [out, err, status.exitstatus]
  end
end
