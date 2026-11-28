# frozen_string_literal: true

require "test_helper"
require "open3"

# The agents-md plugin, listed as a shared plugin from its folder of this
# repository, on projects the tests write.
class AgentsMdTest < Minitest::Test
  URL = "https://github.com/setdef/CrossLint"

  LISTED = %(plugin "#{URL}" ref="v0.1.0" path="plugins/agents-md"\n).freeze

  def setup
    @root = Dir.mktmpdir("crosslint")
  end

  def teardown
    FileUtils.rm_rf(@root)
  end

  def test_asks_for_a_claude_md_beside_each_agents_md_at_the_root_and_in_folders
    write(@root, "AGENTS.md", "# Agents\n")
    write(@root, "docs/AGENTS.md", "# Docs\n")
    write(@root, "lib/deep/AGENTS.md", "# Deep\n")
    write(@root, "lib/deep/CLAUDE.md", "@AGENTS.md\n")
    write(@root, "web/AGENTS.md", "# Web\n")
    write(@root, "web/claude.md", "@AGENTS.md\n")
    result = check

    assert_equal [["AGENTS.md", "agents-md", "claude-md-exists", "no claude file at CLAUDE.md"],
      ["docs/AGENTS.md", "nested-agents-md", "claude-md-exists", "no claude file at docs/CLAUDE.md"],
      ["web/AGENTS.md", "nested-agents-md", "claude-md-exists", "no claude file at web/CLAUDE.md"]], findings(result)
    assert_equal "checked 1 agents-md and 3 nested-agents-md artifacts: 3 errors", result.summary.line
  end

  def test_asks_that_the_first_line_of_each_claude_md_be_the_import_of_its_agents_md
    {"AGENTS.md" => "# Notes\n@AGENTS.md\n", "a/AGENTS.md" => "", "b/AGENTS.md" => "\n@AGENTS.md\n", "c/AGENTS.md" => "@./AGENTS.md\n",
     "d/AGENTS.md" => "@AGENTS.md more\n", "e/AGENTS.md" => " @AGENTS.md\n"}.each do |agents, claude|
      write(@root, agents, "# Agents\n")
      write(@root, agents.sub("AGENTS", "CLAUDE"), claude)
    end

    assert_equal [["AGENTS.md", "agents-md", "claude-md-imports-agents-md", %(CLAUDE.md starts with "# Notes"; its first line should be @AGENTS.md)],
      ["a/AGENTS.md", "nested-agents-md", "claude-md-imports-agents-md", "a/CLAUDE.md starts with a blank line; its first line should be @AGENTS.md"],
      ["b/AGENTS.md", "nested-agents-md", "claude-md-imports-agents-md", "b/CLAUDE.md starts with a blank line; its first line should be @AGENTS.md"],
      ["c/AGENTS.md", "nested-agents-md", "claude-md-imports-agents-md", %(c/CLAUDE.md starts with "@./AGENTS.md"; its first line should be @AGENTS.md)],
      ["d/AGENTS.md", "nested-agents-md", "claude-md-imports-agents-md", %(d/CLAUDE.md starts with "@AGENTS.md more"; its first line should be @AGENTS.md)],
      ["e/AGENTS.md", "nested-agents-md", "claude-md-imports-agents-md", %(e/CLAUDE.md starts with " @AGENTS.md"; its first line should be @AGENTS.md)]],
      findings(check)
  end

  def test_takes_the_import_with_a_byte_order_mark_a_crlf_or_spaces_after_it_and_no_line_end
    {"AGENTS.md" => "\uFEFF@AGENTS.md\n", "a/AGENTS.md" => "@AGENTS.md\r\nmore\r\n", "b/AGENTS.md" => "@AGENTS.md \t\n", "c/AGENTS.md" => "@AGENTS.md"}
      .each do |agents, claude|
        write(@root, agents, "# Agents\n")
        write(@root, agents.sub("AGENTS", "CLAUDE"), claude)
      end
    result = check

    assert_empty findings(result)
    assert_equal "checked 1 agents-md and 3 nested-agents-md artifacts: no violations", result.summary.line
  end

  def test_warns_only_of_a_project_with_no_agents_md_anywhere
    write(@root, "AGENTS.md", "")
    write(@root, "CLAUDE.md", "@AGENTS.md\n")

    assert_empty check.notices
    FileUtils.rm(File.join(@root, "AGENTS.md"))
    FileUtils.rm(File.join(@root, "CLAUDE.md"))
    write(@root, "a/AGENTS.md", "")
    write(@root, "a/CLAUDE.md", "@AGENTS.md\n")

    assert_empty check.notices
    FileUtils.rm_rf(File.join(@root, "a"))
    write(@root, "README.md", "")

    assert_equal [%(no file matches the primary of any artifact of plugin agents-md, such as "AGENTS.md")], check.notices.map(&:message)
  end

  private

  def check
    write(@root, ".config/crosslint/config.kdl", LISTED)
    Open3.capture3("git", "init", "-q", chdir: @root) unless File.directory?(File.join(@root, ".git"))
    repository = CrossLint::Adapters::MemorySharedPlugins::Repository.new(tags: {"v0.1.0" => ROOT}, branches: [], commits: {})
    shared_plugins = CrossLint::Adapters::MemorySharedPlugins.new({URL => repository}, err: StringIO.new)
    CrossLint::App.new(crosslint_ruby: LoadedPlugins::CrossLintRuby.new, shared_plugins:).check(@root)
  end

  def findings(result) = result.violations.map { |violation| [violation.artifact, violation.role, violation.policy, violation.message] }.sort
end
