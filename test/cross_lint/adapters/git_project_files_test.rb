# frozen_string_literal: true

require "test_helper"
require "open3"

class GitProjectFilesTest < Minitest::Test
  cover "CrossLint::Adapters::GitProjectFiles*"

  include CrossLint::Testing::ProjectFilesContract

  Mistake = CrossLint::Core::Mistake

  def setup
    @base = Dir.mktmpdir("crosslint")
  end

  def teardown
    FileUtils.rm_rf(@base)
  end

  # Half the listed files are tracked and half untracked; the ignored
  # ones are in .git/info/exclude, which Git doesn't list.
  def project_files_port(listed:, ignored: [])
    git("init", "-q")
    (listed + ignored).each { |path| write(project_root, path, "#{path}\n") }
    write(project_root, ".git/info/exclude", ignored.map { |path| "/#{path}\n" }.join)
    tracked = listed.each_slice(2).map(&:first)
    git("add", "--", *tracked) unless tracked.empty?
    CrossLint::Adapters::GitProjectFiles.new
  end

  def project_root = File.join(@base, "app")

  # A .git file that points nowhere stops Git looking in the folders
  # above, which may be a repository, as a checkout of CrossLint is.
  def outside_root
    write(@base, "outside/.git", "gitdir: nowhere\n")
    File.join(@base, "outside")
  end

  def test_leaves_out_a_tracked_file_deleted_from_the_working_tree
    port = project_files_port(listed: ["kept.rb", "other.rb", "deleted.rb"])
    File.delete(File.join(project_root, "deleted.rb"))

    assert_equal ["kept.rb", "other.rb"], port.files(project_root).sort
  end

  def test_leaves_out_a_repository_inside_the_project
    port = project_files_port(listed: ["a.rb"])
    write(project_root, "vendor/other/b.rb", "")
    Open3.capture3("git", "init", "-q", chdir: File.join(project_root, "vendor/other"))

    assert_equal ["a.rb"], port.files(project_root)
  end

  def test_lists_a_path_once_while_a_merge_conflict_holds_it_three_times
    port = project_files_port(listed: ["f.rb"])
    commit("one")
    git("checkout", "-q", "-b", "other")
    write(project_root, "f.rb", "two\n")
    commit("two")
    git("checkout", "-q", "-")
    write(project_root, "f.rb", "three\n")
    commit("three")
    git("-c", "user.name=t", "-c", "user.email=t@example.com", "merge", "-q", "other")

    assert_equal 3, git("ls-files", "--stage").lines.size
    assert_equal ["f.rb"], port.files(project_root)
  end

  def test_lists_the_files_of_a_root_inside_a_repository_relative_to_that_root
    project_files_port(listed: ["top.rb", "app/lib/a.rb", "app/lib/b.rb"])
    inner = File.join(project_root, "app")

    assert_equal ["lib/a.rb", "lib/b.rb"], CrossLint::Adapters::GitProjectFiles.new.files(inner).sort
  end

  def test_lists_a_name_that_isnt_ascii_as_utf_8_whatever_the_locale
    port = project_files_port(listed: ["lib/café.rb"])
    external = Encoding.default_external
    quietly { Encoding.default_external = Encoding::US_ASCII }
    files = port.files(project_root)

    assert_equal [["lib/café.rb"], Encoding::UTF_8], [files, files.first.encoding]
  ensure
    quietly { Encoding.default_external = external }
  end

  def test_lists_the_projects_files_whatever_repository_git_variables_name
    port = project_files_port(listed: ["a.rb", "b.rb"])
    other = File.join(@base, "other")
    FileUtils.mkdir_p(other)
    Open3.capture3("git", "init", "-q", chdir: other)
    ENV["GIT_DIR"] = File.join(other, ".git")
    ENV["GIT_WORK_TREE"] = other

    assert_equal ["a.rb", "b.rb"], port.files(project_root).sort
  ensure
    ENV.delete("GIT_DIR")
    ENV.delete("GIT_WORK_TREE")
  end

  def test_leaves_the_other_variables_for_git
    port = project_files_port(listed: ["a.rb", "x.rb"])
    write(@base, "home/.gitconfig", "[core]\n\texcludesFile = #{@base}/ignore\n")
    write(@base, "ignore", "x.rb\n")
    home = ENV.fetch("HOME", nil)
    ENV["HOME"] = File.join(@base, "home")

    assert_equal ["a.rb"], port.files(project_root)
  ensure
    ENV["HOME"] = home
  end

  def test_gives_gits_own_message_when_git_refuses_a_working_tree
    port = project_files_port(listed: ["a.rb"])
    write(project_root, ".git/index", "not an index\n")
    mistake = assert_raises(Mistake) { port.files(project_root) }

    assert_match(/\ACrossLint lists a project's files with Git, and Git refused #{Regexp.escape(project_root)}: .*index/, mistake.message)
    refute_match(/isn't in a Git working tree/, mistake.message)
  end

  def test_gives_gits_message_without_a_trailing_newline
    port = project_files_port(listed: ["a.rb"])
    write(project_root, ".git/index", "not an index\n")
    mistake = assert_raises(Mistake) { port.files(project_root) }

    refute_match(/\s\z/, mistake.message)
  end

  def test_says_a_folder_inside_the_git_directory_isnt_in_a_working_tree
    port = project_files_port(listed: ["a.rb"])
    mistake = assert_raises(Mistake) { port.files(File.join(project_root, ".git")) }

    assert_equal CrossLint::Adapters::GitProjectFiles.outside(File.join(project_root, ".git")), mistake.message
  end

  def test_asks_whether_a_folder_is_a_working_tree_whatever_repository_git_variables_name
    port = project_files_port(listed: ["a.rb"])
    other = File.join(@base, "other")
    FileUtils.mkdir_p(other)
    Open3.capture3("git", "init", "-q", chdir: other)
    ENV["GIT_DIR"] = File.join(other, ".git")
    mistake = assert_raises(Mistake) { port.files(outside_root) }

    assert_equal CrossLint::Adapters::GitProjectFiles.outside(outside_root), mistake.message
  ensure
    ENV.delete("GIT_DIR")
    ENV.delete("GIT_WORK_TREE")
  end

  def test_says_when_it_finds_no_git
    mistake = assert_raises(Mistake) { CrossLint::Adapters::GitProjectFiles.new(git: "no-such-git").files(@base) }

    assert_equal "CrossLint lists a project's files with Git, and found no no-such-git command on the PATH; install Git",
      mistake.message
  end

  def test_follows_dot_and_dot_dot_in_a_path
    port = project_files_port(listed: ["README.md", "lib/a.rb"])

    assert port.exist?(project_root, "./lib/../README.md")
    refute port.exist?(project_root, "lib/../missing.md")
  end

  # Linux tells a name's case apart whatever the code does, so a
  # filesystem that ignores case is made up: File.exist? finds anything.
  def test_looks_for_a_name_in_its_folders_listing_on_a_filesystem_that_ignores_case
    port = project_files_port(listed: ["lib/one.rb"])
    exist = File.method(:exist?)
    quietly { File.define_singleton_method(:exist?) { |*| true } }
    found = ["lib/one.rb", "lib/One.rb", "Lib/one.rb"].map { |path| port.exist?(project_root, path) }
    missing = assert_raises(Errno::ENOENT) { port.read(project_root, "lib/One.rb") }
    quietly { File.define_singleton_method(:exist?, exist) }

    assert_equal [true, false, false], found
    assert_equal "No such file or directory - lib/One.rb", missing.message
  ensure
    quietly { File.define_singleton_method(:exist?, exist) }
  end

  def test_reads_each_folder_once
    port = project_files_port(listed: ["lib/a.rb"])

    refute port.exist?(project_root, "lib/b.rb")
    write(project_root, "lib/b.rb", "")

    refute port.exist?(project_root, "lib/b.rb")
    assert CrossLint::Adapters::GitProjectFiles.new.exist?(project_root, "lib/b.rb")
  end

  def test_reads_a_file_with_its_line_endings_as_they_are
    port = project_files_port(listed: ["a.txt"])
    write(project_root, "a.txt", "one\r\ntwo\n")

    assert_equal "one\r\ntwo\n", port.read(project_root, "a.txt")
  end

  def test_finds_nothing_under_a_file
    port = project_files_port(listed: ["lib/a.rb"])

    refute port.exist?(project_root, "lib/a.rb/b.rb")
  end

  private

  def git(*arguments)
    FileUtils.mkdir_p(project_root)
    out, err, status = Open3.capture3("git", *arguments, chdir: project_root)
    assert_predicate status, :success?, err unless arguments.include?("merge")
    out
  end

  # Ruby warns at every change of Encoding.default_external.
  def quietly
    verbose = $VERBOSE
    $VERBOSE = nil
    yield
  ensure
    $VERBOSE = verbose
  end

  def commit(message)
    git("add", "-A")
    git("-c", "user.name=t", "-c", "user.email=t@example.com", "-c", "commit.gpgsign=false", "commit", "-q", "-m", message)
  end
end
