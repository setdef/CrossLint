# frozen_string_literal: true

require "test_helper"
require "open3"

# The decision-log plugin, listed as a shared plugin from its folder of
# this repository, on decision logs the tests write.
class DecisionLogTest < Minitest::Test
  URL = "https://github.com/setdef/CrossLint"

  def setup
    @root = Dir.mktmpdir("crosslint")
    %w[0001-use-ruby.md 0002-use-kdl.md 0003-use-git.md template.md].each { write(@root, "docs/decisions/#{it}", "# Record\n") }
  end

  def teardown
    FileUtils.rm_rf(@root)
  end

  def test_takes_an_index_that_links_to_each_record_in_any_form
    index = <<~MARKDOWN
      | Number | Decision |
      | --- | --- |
      | [0001](0001-use-ruby.md#context) | Use Ruby |

      - <a href="./0002-use-kdl.md">Use KDL</a> <img alt="" src='logo.png'>
      - [Use Git][git]
      - [The template](template.md), [the plan](../plan.md), [elsewhere](../other/0004-x.md), [a site](https://example.com/0005-y.md)

      [git]: /docs/decisions/0003-use-git.md
    MARKDOWN
    result = check({"docs/decisions/README.md" => index})

    assert_equal [], findings(result)
    assert_equal "checked 1 index and 5 document artifacts: no violations", result.summary.line
  end

  def test_reports_each_record_the_index_doesnt_link_to_and_each_link_to_a_record_that_isnt_there
    write(@root, "docs/decisions/old/0009-nested.md", "")
    index = <<~MARKDOWN
      - [0001](0001-use-ruby.md)
      - [0004](0004-deleted.md) and again [0004](0004-deleted.md)

      - [0004](0004-deleted.md)
      - [0005](0005%20spaced.md)
      - `[0002](0002-use-kdl.md)`
      - [far](../../../0006-x.md)
    MARKDOWN

    assert_equal [["docs/decisions/README.md", "index-lists-records", "0002-use-kdl.md is a record in docs/decisions, and the index has no link to it",
      "0002-use-kdl.md"],
      ["docs/decisions/README.md", "index-lists-records", "0003-use-git.md is a record in docs/decisions, and the index has no link to it", "0003-use-git.md"],
      ["docs/decisions/README.md", "index-lists-records", "line 5: links to 0005 spaced.md, which isn't a record in docs/decisions", "0005 spaced.md"],
      ["docs/decisions/README.md", "index-lists-records", "lines 2, 4: links to 0004-deleted.md, which isn't a record in docs/decisions",
        "0004-deleted.md"]], findings(check({"docs/decisions/README.md" => index}))
  end

  def test_reports_records_that_share_a_number
    %w[0002-also-kdl.md 3-git-again.md 0003-git-thrice.md].each { write(@root, "docs/decisions/#{it}", "") }
    index = Dir.children(File.join(@root, "docs/decisions")).map { "[x](#{it})" }.join("\n")

    assert_equal [["docs/decisions/README.md", "numbers-unique", "0002-also-kdl.md and 0002-use-kdl.md in docs/decisions have the same number, 2", "2"],
      ["docs/decisions/README.md", "numbers-unique", "0003-git-thrice.md, 0003-use-git.md, and 3-git-again.md in docs/decisions have the same number, 3", "3"]],
      findings(check({"docs/decisions/README.md" => index}))
  end

  def test_reports_a_citation_of_a_number_no_record_has
    text = <<~MARKDOWN
      As ADR 1, ADR 0002, ADR-0003, and ADR0003 say; but ADR 7 and ADR 0004 don't exist.
      The former ADR 5, now ADR 3, and the Former ADR 6.
      MADR 4, ADRs 4, ADR 4a, and `ADR 4` cite nothing.
      ```
      ADR 8
      ```
      ADR 7 again.
    MARKDOWN
    index = %w[0001-use-ruby.md 0002-use-kdl.md 0003-use-git.md].map { "[x](#{it})" }.join("\n")

    assert_equal [["guide.md", "citations-resolve", "line 1: ADR 0004 matches no record in docs/decisions", "ADR 0004"],
      ["guide.md", "citations-resolve", "lines 1, 7: ADR 7 matches no record in docs/decisions", "ADR 7"]],
      findings(check({"docs/decisions/README.md" => index, "guide.md" => text}))
  end

  def test_finds_the_log_and_its_index_where_the_settings_say
    write(@root, "doc/adr/0001-record-decisions.md", "")
    write(@root, "doc/adr/0002-use-ruby.md", "Unlike ADR 0001 of docs/decisions, this cites ADR 3.\n")
    result = check({"doc/adr.md" => "[x](adr/0001-record-decisions.md)\n"}, settings: %(folder "./doc/adr/"\n  index "doc/adr.md"))

    assert_equal [["doc/adr.md", "index-lists-records", "0002-use-ruby.md is a record in doc/adr, and the index has no link to it", "0002-use-ruby.md"],
      ["doc/adr/0002-use-ruby.md", "citations-resolve", "line 1: ADR 3 matches no record in doc/adr", "ADR 3"]], findings(result)
    assert_equal [["doc/adr/README.md"], ["index", "doc/adr/README.md", "doc/adr"]], declared(%(folder "doc/adr"))
  end

  def test_warns_of_a_log_with_no_index
    result = check({}, settings: nil)

    assert_equal [%(no file matches "docs/decisions/README.md", the files of artifact "index")], result.notices.map(&:message)
  end

  def test_refuses_a_setting_that_isnt_one_path_inside_the_project
    {%(folder "a"\n  folder "b") => [3, "folder is set twice; the first is on line 2"],
     %(folder "a" "b") => [2, %(folder takes one path and nothing else, as in folder "docs/decisions")],
     %(index 1) => [2, %(index takes one path and nothing else, as in index "docs/decisions/README.md")],
     %(folder "a" x=1) => [2, %(folder takes one path and nothing else, as in folder "docs/decisions")],
     %(folder "a" { b; }) => [2, %(folder takes one path and nothing else, as in folder "docs/decisions")],
     %(folder "/a") => [2, %(folder takes a path inside the project, relative to its root, with / between folders, not "/a")],
     %(folder "C:/a") => [2, %(folder takes a path inside the project, relative to its root, with / between folders, not "C:/a")],
     %(folder "a\\\\b") => [2, %(folder takes a path inside the project, relative to its root, with / between folders, not "a\\\\b")],
     %(folder "a/{name}") => [2, %(folder takes a path inside the project, relative to its root, with / between folders, not "a/{name}")],
     %(folder "a/../..") => [2, %(folder takes a path inside the project, relative to its root, with / between folders, not "a/../..")],
     %(index "./") => [2, %(index takes a path inside the project, relative to its root, with / between folders, not "./")]}.each do |settings, (line, message)|
      mistake = assert_raises(CrossLint::Core::Mistake, settings) { check({}, settings:) }

      assert_equal [".config/crosslint/config.kdl", line, message], [mistake.file, mistake.line, mistake.message], settings
    end
  end

  private

  def check(files, settings: nil) = app(files, settings).check(@root)

  def declared(settings)
    plugin = app({}, settings).load_project(@root).plugins.first
    artifacts = plugin.manifest.artifacts
    [artifacts.map { it.files.source } - ["{path}.md"], [artifacts.first.name, artifacts.first.files.source, artifacts.first.companions.first.pattern.source]]
  end

  # The app, over a project whose configuration lists the plugin with
  # these settings.
  def app(files, settings)
    files.each { |path, text| write(@root, path, text) }
    block = settings ? " {\n  #{settings}\n}" : ""
    write(@root, ".config/crosslint/config.kdl", %(plugin "#{URL}" ref="v0.1.0" path="plugins/decision-log"#{block}\n))
    Open3.capture3("git", "init", "-q", chdir: @root) unless File.directory?(File.join(@root, ".git"))
    repository = CrossLint::Adapters::MemorySharedPlugins::Repository.new(tags: {"v0.1.0" => ROOT}, branches: [], commits: {})
    CrossLint::App.new(plugin_ruby: LoadedPlugins::PluginRuby.new, shared_plugins: CrossLint::Adapters::MemorySharedPlugins.new({URL => repository}, err: StringIO.new))
  end

  def findings(result) = result.violations.map { [it.artifact, it.policy, it.message, it.detail] }
end
