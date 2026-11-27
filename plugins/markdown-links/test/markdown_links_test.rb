# frozen_string_literal: true

require "test_helper"
require "open3"

# The markdown-links plugin, listed as a shared plugin from its folder of
# this repository, on projects the tests write.
class MarkdownLinksTest < Minitest::Test
  URL = "https://github.com/setdef/CrossLint"

  LISTED = %(plugin "#{URL}" ref="v0.1.0" path="plugins/markdown-links"\n).freeze

  def setup
    @root = Dir.mktmpdir("crosslint")
    write(@root, "README.md", "# Project\n")
    write(@root, "docs/guide.md", "# Guide\n\n## Usage\n")
    write(@root, "docs/my file.md", "")
    write(@root, "lib/tool.rb", "")
    write(@root, ".gitignore", "/coverage/\n")
    write(@root, "coverage/index.html", "")
  end

  def teardown
    FileUtils.rm_rf(@root)
  end

  def test_takes_a_link_to_a_file_or_folder_from_the_files_folder_or_from_the_root
    links = ["guide.md", "./guide.md", "../README.md", "/README.md", "/docs", "../docs/", "..", "/", "my%20file.md", "<my file.md>",
      "guide.md?plain=1", "guide.md \"Title\"", "guide.md 'Title'", "guide.md (Title)", "../lib/tool.rb"]

    assert_equal [], findings(check("docs/index.md" => links.map { "[a](#{it})\n" }.join))
  end

  def test_reports_a_link_to_nothing_outside_the_project_or_to_a_name_that_differs_in_case
    text = "[a](missing.md)\n[b](../../up.md)\n![c](Guide.md)\n[d](../coverage/index.html)\n"

    assert_equal [["docs/index.md", "line 1: missing.md points to docs/missing.md, which isn't a file or folder of the project", "missing.md"],
      ["docs/index.md", "line 2: ../../up.md points outside the project", "../../up.md"],
      ["docs/index.md", "line 3: Guide.md points to docs/Guide.md, which isn't a file or folder of the project", "Guide.md"],
      ["docs/index.md", "line 4: ../coverage/index.html points to coverage/index.html, which isn't a file or folder of the project",
        "../coverage/index.html"]], findings(check("docs/index.md" => text))
  end

  def test_reports_each_destination_once_with_every_line_it_is_on
    text = "[a](gone.md) and [b](gone.md)\n\n[c](gone.md)\n[d](lost.md)\n"

    assert_equal [["index.md", "line 4: lost.md points to lost.md, which isn't a file or folder of the project", "lost.md"],
      ["index.md", "lines 1, 3: gone.md points to gone.md, which isn't a file or folder of the project", "gone.md"]],
      findings(check("index.md" => text))
  end

  def test_reads_images_badges_reference_definitions_and_href_and_src_in_html
    text = <<~MARKDOWN
      ![logo](a.svg)
      [![badge](b.svg)](c/)
      [ref]: d.md "Title"
        [split]:
        <e f.md>
      <a href="g.md">G</a> <img alt='x' src='h.png'>
      [^note]: not-a-link.md
    MARKDOWN

    assert_equal %w[a.svg b.svg c/ d.md e\ f.md g.md h.png], findings(check("index.md" => text)).map(&:last).sort
  end

  def test_skips_links_with_a_scheme_or_a_host_and_empty_ones
    text = "[a](https://example.com/x.md) [b](mailto:a@example.com) [c](//cdn.example.com/x.js) [d]() [e](<>) [f](#)\n"

    assert_equal [], findings(check("index.md" => text))
  end

  def test_skips_what_github_doesnt_render_as_a_link
    text = <<~MARKDOWN
      ---
      link: "[a](front.md)"
      ---
      ```ruby
      [b](fenced.md)
      ```
      ~~~~
      [c](tilde.md)
      ~~~
      ~~~~~
      `[d](span.md)` and ``[e](`double`.md)``
      <!-- [f](comment.md)
      -->
      \\[g](escaped.md) [h\\]](escaped\\).md)
      [i](fine.md)
      ````
      [j](unclosed.md)
    MARKDOWN

    assert_equal ["escaped).md", "fine.md"], findings(check("index.md" => text)).map(&:last).sort
  end

  def test_reads_a_file_with_a_byte_order_mark_crlf_line_endings_or_bytes_that_arent_utf_8
    assert_equal [["index.md", "line 2: b.md points to b.md, which isn't a file or folder of the project", "b.md"]],
      findings(check("index.md" => "\uFEFF# Title\r\n[b](b.md)\r\n```\r\n[c](c.md)\r\n```\r\n"))
    assert_equal ["b.md"], findings(check("index.md" => "\xFF\n[b](b.md)\n".b)).map(&:last)
  end

  def test_reports_an_anchor_that_no_heading_or_html_id_or_name_of_its_markdown_file_has
    text = "[a](guide.md#usage) [b](guide.md#guide) [c](guide.md#setup) [d](#here) [e](#gone) [f](../lib/tool.rb#L3) [g](/docs#x)\n" \
      "[h](guide.md) [i](guide.md#) [j](#%C3%A9t%C3%A9)\n\n## Here\n<a name=\"été\"></a>\n"

    assert_equal [["docs/index.md", %(line 1: #gone points to docs/index.md, which has no heading or anchor "gone"), "#gone"],
      ["docs/index.md", %(line 1: guide.md#setup points to docs/guide.md, which has no heading or anchor "setup"), "guide.md#setup"]], findings(check("docs/index.md" => text))
  end

  def test_checks_no_anchor_of_a_link_to_a_markdown_files_source
    text = "[a](guide.md?plain=1#L3) [b](guide.md?x=1&plain=1#L3-L5) [c](guide.md?plain=0#L3) [d](guide.md?plain=10#L3)\n"

    assert_equal [["docs/index.md", %(line 1: guide.md?plain=0#L3 points to docs/guide.md, which has no heading or anchor "L3"), "guide.md?plain=0#L3"],
      ["docs/index.md", %(line 1: guide.md?plain=10#L3 points to docs/guide.md, which has no heading or anchor "L3"), "guide.md?plain=10#L3"]],
      findings(check("docs/index.md" => text))
  end

  def test_makes_each_headings_anchor_as_github_does
    headings = <<~MARKDOWN
      # The `files` setting
      ## **Bold** and _emphasis_, with snake_case
      ### [A link](x.md) and ![an image](y.png) and <em>HTML</em>
      #### Usage
      ## Usage
      Usage
      =====
      Third: café, 1.2 & more!
      ---
      ####### Not a heading
      #Not a heading
      #
      \\# Escaped \\*star\\*
      <div id="custom" name='other'></div>
    MARKDOWN
    names = %w[the-files-setting bold-and-emphasis-with-snake_case a-link-and--and-html usage usage-1 usage-2 third-café-12--more]
    links = (names + %w[custom other not-a-heading escaped-star]).map { "[x](a.md##{it})" }.join(" ")

    assert_equal [%(a.md#escaped-star points to a.md, which has no heading or anchor "escaped-star"),
      %(a.md#not-a-heading points to a.md, which has no heading or anchor "not-a-heading")],
      findings(check("index.md" => links, "a.md" => headings)).map { it[1].delete_prefix("line 1: ") }.sort
  end

  def test_takes_an_underline_as_a_heading_only_under_a_line_of_a_paragraph
    text = <<~MARKDOWN
      ===
      - item
      ---
      > quote
      ---
      | table |
      ---

      ---
      ===
      ---
      Paragraph
      ---
    MARKDOWN
    anchors = %w[item quote table paragraph].map { "[x](a.md##{it})" }.join(" ")

    assert_equal [%(a.md#item points to a.md, which has no heading or anchor "item"), %(a.md#quote points to a.md, which has no heading or anchor "quote"),
      %(a.md#table points to a.md, which has no heading or anchor "table")], findings(check("index.md" => anchors, "a.md" => text)).map { it[1].delete_prefix("line 1: ") }.sort
  end

  def test_checks_no_anchor_of_a_folder_named_like_a_markdown_file
    write(@root, "notes.md/a.txt", "")

    assert_equal [], findings(check("index.md" => "[a](notes.md#x)\n"))
  end

  private

  def check(files)
    files.each { |path, text| write(@root, path, text) }
    write(@root, ".config/crosslint/config.kdl", LISTED)
    Open3.capture3("git", "init", "-q", chdir: @root) unless File.directory?(File.join(@root, ".git"))
    repository = CrossLint::Adapters::MemorySharedPlugins::Repository.new(tags: {"v0.1.0" => ROOT}, branches: [], commits: {})
    shared_plugins = CrossLint::Adapters::MemorySharedPlugins.new({URL => repository}, err: StringIO.new)
    CrossLint::App.new(plugin_ruby: LoadedPlugins::PluginRuby.new, shared_plugins:).check(@root).tap { assert_empty it.faults.map(&:message) }
  end

  # The violations of each file named index.md, where the tests keep the
  # links they check.
  def findings(result) = result.violations.select { File.basename(it.artifact) == "index.md" }.map { [it.artifact, it.message, it.detail] }
end
