# frozen_string_literal: true

require "test_helper"
require "digest"
require "json"
require "open3"
require "rbconfig"

class MemorySharedPluginsTest < Minitest::Test
  cover "CrossLint::Adapters::MemorySharedPlugins*"

  include CrossLint::Testing::SharedPluginsContract

  Repository = CrossLint::Adapters::MemorySharedPlugins::Repository

  URL = "https://github.com/OWNER/signatures"

  SHA = "a" * 40

  def setup
    @err = StringIO.new
    @repositories = {
URL => Repository.new(tags: CrossLint::Testing::SharedPluginsContract::TAGS.to_h { |tag| [tag, "/cache/#{tag}/signatures"] },
  branches: ["main"], commits: { SHA => "/cache/#{SHA}/signatures" }),
}
  end

  def shared_plugins_port = CrossLint::Adapters::MemorySharedPlugins.new(@repositories, err: @err)

  def repository_url = URL

  def commit_sha = SHA

  def missing_repository_url = "https://github.com/OWNER/missing"

  def remove_repository = @repositories.clear

  def said = @err.string

  def test_gives_the_folder_each_tag_and_commit_has
    port = shared_plugins_port

    assert_equal ["/cache/v1.2.0/signatures", "/cache/#{SHA}/signatures"], [port.fetch(URL, "v1.2.0"), port.fetch(URL, SHA)]
  end

  def test_lists_each_fetch_once_in_order
    port = shared_plugins_port
    ["v1.2.0", SHA, "v1.2.0"].each { |ref| port.fetch(URL, ref) }

    assert_equal [[URL, "v1.2.0"], [URL, SHA]], port.fetched
  end

  def test_fetches_a_failed_ref_again_and_says_so_again
    port = shared_plugins_port
    2.times { assert_raises(CrossLint::Core::FetchError) { port.fetch(URL, "main") } }

    assert_equal ["crosslint: fetching #{URL} at main"] * 2, said.lines(chomp: true)
    assert_empty port.fetched
  end

  def test_accepts_the_schemes_it_is_given
    port = CrossLint::Adapters::MemorySharedPlugins.new(err: @err, schemes: ["file://", "ssh://"])

    assert_equal [true, true, false], [port.accepts?("file:///tmp/repo"), port.accepts?("ssh://host/repo"), port.accepts?("https://github.com/OWNER/REPO")]
    assert_equal "http://x doesn't start with file:// or ssh://", assert_raises(CrossLint::Core::FetchError) { port.fetch("http://x", "v1.0.0") }.message
    assert_equal "http://x doesn't start with file:// or ssh://", assert_raises(CrossLint::Core::FetchError) { port.tags("http://x") }.message
  end

  def test_says_when_it_holds_no_repository_at_a_url
    port = CrossLint::Adapters::MemorySharedPlugins.new(err: @err)
    messages = [-> { port.fetch(URL, "v1.0.0") }, -> { port.tags(URL) }].map { |call| assert_raises(CrossLint::Core::FetchError, &call).message }

    assert_equal ["no repository at #{URL}"] * 2, messages
  end

  def test_writes_to_standard_error_unless_it_is_given_somewhere_else
    _, err = capture_io { CrossLint::Adapters::MemorySharedPlugins.new(@repositories).fetch(URL, "v1.0.0") }

    assert_equal "crosslint: fetching #{URL} at v1.0.0\n", err
  end
end

# The repository the Git tests copy, built once: one commit with the
# tags v1.0.0, v1.2.0 (annotated), v1.10.0, 2.0.0-rc.1, and latest, on
# the branch main.
module Origin
  PLUGIN = %(artifact "doc" {\n  primary "{path}.md"\n}\n)

  @lock = Mutex.new

  class << self
    attr_reader :commit

    def template
      @lock.synchronize do
        @template ||= build
      end
    end

    def git(folder, *arguments)
      out, status = Open3.capture2e("git", *arguments, chdir: folder)
      raise "git #{arguments.join(' ')} failed: #{out}" unless status.success?

      out
    end

    private

    def build
      folder = File.join(Dir.mktmpdir("crosslint-origin"), "signatures")
      Minitest.after_run { FileUtils.rm_rf(File.dirname(folder)) }
      FileUtils.mkdir_p(folder)
      git(folder, "init", "-q", "-b", "main", "--template=")
      File.binwrite(File.join(folder, "plugin.kdl"), PLUGIN)
      git(folder, "add", "-A")
      git(folder, "commit", "-q", "-m", "one")
      @commit = git(folder, "rev-parse", "HEAD").strip
      %w[v1.0.0 v1.10.0 2.0.0-rc.1 latest].each { |tag| git(folder, "tag", tag) }
      git(folder, "tag", "-a", "-m", "annotated", "v1.2.0")
      folder
    end
  end
end

# Lets a test deny a rename, which on macOS and Linux a folder rarely
# fails to take.
module DeniedRenames
  def rename(from, to)
    raise Errno::EACCES, "#{from}, #{to}" if Thread.current[:crosslint_shared_rename_denied]

    super
  end
end
File.singleton_class.prepend(DeniedRenames)

# Lets a test make a folder's time unreadable, as when another CrossLint
# removes the folder between listing it and reading it.
module VanishingFolders
  def mtime(path)
    raise Errno::ENOENT, path if Thread.current[:crosslint_shared_vanishing]&.include?(File.basename(path))

    super
  end
end
File.singleton_class.prepend(VanishingFolders)

# Stands in for a pipe of Git's output, so that a test controls what a
# read of it does: each step is a String it gives, an exception class it
# raises, or :hang, which waits until the thread is ended. It is an IO,
# for the RBS checker, that closes the pipe it stands in for.
class ScriptedPipe < IO
  attr_reader :binmoded

  def initialize(real, *steps)
    super(real.fileno, autoclose: false)
    @real = real
    @steps = steps
    @binmoded = false
  end

  def binmode
    @binmoded = true
    self
  end

  def readpartial(_length)
    step = @steps.shift
    case step
    when String then step
    when Class then raise step
    else sleep
    end
  end

  def close
    @real.close
    super
  end
end

# The shared-plugins port with Git, against repositories built in a
# temporary folder and used by file:// URLs, so that no test reaches the
# network. A fake git is a Ruby script that GitSharedPlugins runs as
# `ruby SCRIPT ARGUMENTS`.
class GitSharedPluginsTest < Minitest::Test
  cover "CrossLint::Adapters::GitSharedPlugins*"
  cover "CrossLint::Adapters::GitCommand*"
  cover "CrossLint::Adapters::GitEnvironment*"

  include CrossLint::Testing::SharedPluginsContract

  Adapters = CrossLint::Adapters
  Core = CrossLint::Core

  WINDOWS = Adapters::ProcessHelpers::WINDOWS

  SETTINGS = Adapters::GitSharedPlugins::SETTINGS

  PLUGIN = Origin::PLUGIN

  # The arguments before each run of the port's git, which accepts file URLs
  # too.
  PROTOCOLS = %w[-c protocol.allow=never -c protocol.https.allow=always -c protocol.file.allow=always].freeze

  # Logs each run of git, and the environment it was given, and runs the
  # real one.
  LOGS = <<~RUBY
    require "json"
    interesting = %w[HTTPS_PROXY HTTP_PROXY NO_PROXY GIT_DIR GIT_INDEX_FILE GIT_TERMINAL_PROMPT]
    File.open(File.join(__dir__, "log.jsonl"), "a") { |log| log.puts(JSON.generate({"argv" => ARGV, "env" => ENV.to_h.slice(*interesting), "pwd" => Dir.pwd})) }
    exec("git", *ARGV)
  RUBY

  HANGS = <<~RUBY
    child = Process.spawn(RbConfig.ruby, "-e", "sleep 30")
    File.write(File.join(__dir__, "child.pid"), child.to_s)
    sleep 30
  RUBY

  def setup
    @base = Dir.mktmpdir("crosslint")
    @err = StringIO.new
    @origin = File.join(@base, "origin", "signatures")
    FileUtils.mkdir_p(File.dirname(@origin))
    FileUtils.cp_r(Origin.template, @origin)
    @commit = Origin.commit
  end

  def teardown
    FileUtils.rm_rf(@base)
  end

  def shared_plugins_port = port

  def repository_url = file_url(@origin)

  def commit_sha = @commit

  def missing_repository_url = file_url(File.join(@base, "nowhere", "missing"))

  def remove_repository = FileUtils.rm_rf(@origin)

  def said = @err.string

  def test_waits_a_minute_unless_it_is_told_otherwise
    default = Adapters::GitSharedPlugins.new(err: @err, cache: @base)

    assert_equal [60, 1, 0.5], [default.time_limit, Adapters::GitCommand::PIPE_LIMIT, port(time_limit: 0.5).time_limit]
  end

  def test_accepts_https_only_unless_it_is_told_otherwise
    default = Adapters::GitSharedPlugins.new(err: @err, cache: @base)

    assert_equal [true, false, true], [default.accepts?("https://github.com/OWNER/REPO"), default.accepts?(repository_url), port.accepts?(repository_url)]
  end

  def test_allows_git_https_and_file_and_no_other_transport_whatever_schemes_the_port_accepts
    silent = fake("logs.rb", LOGS.sub(/^exec.*\n/, "exit 0\n"))
    Adapters::GitSharedPlugins.new(err: @err, cache: @base, git: silent).tags("https://example.test/OWNER/signatures")
    Adapters::GitSharedPlugins.new(err: @err, cache: @base, git: silent, schemes: ["https://", "ssh://"]).tags("ssh://example.test/OWNER/signatures")

    assert_equal [PROTOCOLS, PROTOCOLS], logged.map { |entry| entry.fetch("argv").first(PROTOCOLS.size) }
    assert_equal %w[-c protocol.allow=never -c protocol.https.allow=always -c protocol.file.allow=always], Adapters::GitSharedPlugins::PROTOCOLS
  end

  # A Git setting of the user's, such as url.BASE.insteadOf, can send a
  # request for one address to another, to ssh or a command, and Git
  # would follow it.
  def test_refuses_a_git_setting_that_sends_a_request_to_another_transport_than_https_or_file
    url = "https://example.test/OWNER/signatures"
    default = Adapters::GitSharedPlugins.new(err: @err, cache: @base)
    targets = %w[ssh://example.test/o/r http://example.test/o/r git://example.test/o/r ext::true]
    messages = targets.flat_map do |target|
      rewriting(url, target) do
        [-> { default.fetch(url, "v1.0.0") }, -> { default.fetch(url, commit_sha) }, -> { default.tags(url) }].map { |call| assert_raises(Core::FetchError, &call).message }
      end
    end

    assert_equal targets.flat_map { |target| ["transport '#{target[/\A[a-z]+/]}' not allowed"] * 3 }, messages.map { |message| message[/transport '[a-z]+' not allowed/] }
    assert_empty Dir.children(File.join(@base, "plugins"))
  end

  def test_follows_a_git_setting_that_sends_https_to_a_file
    url = "https://example.test/OWNER/signatures"
    default = Adapters::GitSharedPlugins.new(err: @err, cache: @base)
    folder = rewriting(url, repository_url) { default.fetch(url, "v1.0.0") }

    assert_equal PLUGIN, File.binread(File.join(folder, "plugin.kdl"))
  end

  def test_saves_the_plugin_as_files_in_a_folder_with_its_name_in_a_folder_for_the_url_and_ref
    folder = port.fetch(repository_url, "v1.2.0")
    key = Digest::SHA256.hexdigest("#{repository_url}\0v1.2.0")[0, 32]

    assert_equal File.join(@base, "cache", "plugins", key, "signatures"), folder
    assert_equal [PLUGIN, ["plugin.kdl"]], [File.binread(File.join(folder, "plugin.kdl")), Dir.children(folder)]
    assert_equal [key], Dir.children(File.join(@base, "cache", "plugins"))
    assert_equal folder, port.folder(repository_url, "v1.2.0")
  end

  # A plugin in a folder of its repository (path=) is read from the saved
  # copy, so the copy holds the whole commit, every folder of it.
  def test_saves_every_folder_of_the_commit_whether_or_not_a_plugin_is_in_it
    write(@origin, "plugins/alpha/plugin.kdl", "// alpha\n")
    write(@origin, "plugins/beta/rules/check.rb", "# beta\n")
    write(@origin, "docs/guide.md", "guide\n")
    commit("folders")
    git(@origin, "tag", "folders")
    folder = port.fetch(repository_url, "folders")
    saved = Dir.glob("**/*", File::FNM_DOTMATCH, base: folder).reject { |path| File.directory?(File.join(folder, path)) || path.start_with?(".git/") }

    assert_equal %w[docs/guide.md plugin.kdl plugins/alpha/plugin.kdl plugins/beta/rules/check.rb], saved.sort
    assert_equal "// alpha\n", File.binread(File.join(folder, "plugins", "alpha", "plugin.kdl"))
  end

  def test_names_the_plugin_for_its_repository_without_dot_git
    assert_equal "signatures", File.basename(port.folder("https://example.com/OWNER/signatures.git/", "v1.0.0"))
    error = assert_raises(Core::FetchError) { port.folder("https://example.com/OWNER/a b", "v1.0.0") }

    assert_equal "can't name a plugin from https://example.com/OWNER/a b, whose last path segment has other characters than letters, digits, and . _ -",
      error.message
  end

  def test_leaves_nothing_in_the_cache_when_a_fetch_fails
    assert_raises(Core::FetchError) { port.fetch(repository_url, "main") }
    assert_raises(Core::FetchError) { port.fetch(repository_url, "#{'0' * 39}1") }

    assert_empty Dir.children(File.join(@base, "cache", "plugins"))
  end

  def test_fetches_the_commit_alone_with_git_run_as_a_program
    port(git: fake("logs.rb", LOGS)).fetch(repository_url, "v1.0.0")
    commands = logged_arguments
    repository = commands.drop(1)

    assert_equal ["ls-remote", repository_url, "refs/tags/v1.0.0", "refs/heads/v1.0.0"], commands.first
    assert(repository.all? { |argv| argv[0] == "--git-dir" && argv[2] == "--work-tree" && argv[4, SETTINGS.size] == SETTINGS })
    assert_equal [File.join(File.dirname(repository.first.fetch(1)), "files", "signatures")], repository.map { |argv| argv.fetch(3) }.uniq
    assert_equal [
      ["init", "-q"],
      ["fetch", "-q", "--depth", "1", "--no-tags", repository_url, "refs/tags/v1.0.0"],
      ["checkout", "-q", "--detach", "FETCH_HEAD"],
], repository.map { |argv| argv.drop(4 + SETTINGS.size) }
  end

  def test_asks_git_for_no_tags_when_the_ref_is_a_commit
    port(git: fake("logs.rb", LOGS)).fetch(repository_url, commit_sha)

    assert_equal [["init", "-q"], ["fetch", "-q", "--depth", "1", "--no-tags", repository_url, commit_sha], ["checkout", "-q", "--detach", "FETCH_HEAD"]],
      logged_arguments.map { |argv| argv.drop(4 + SETTINGS.size) }
  end

  def test_lists_tags_with_ls_remote
    port(git: fake("logs.rb", LOGS)).tags(repository_url)

    assert_equal [["ls-remote", "--tags", "--refs", repository_url]], logged_arguments
  end

  # The project's repository is the folder CrossLint runs in, and its local
  # Git configuration applies to a Git run there.
  def test_runs_every_git_in_a_folder_of_its_own_in_the_cache_and_removes_it_after_listing_tags_too
    project = File.join(@base, "project")
    FileUtils.mkdir_p(project)
    Dir.chdir(project) do
      port(git: fake("logs.rb", LOGS)).tags(repository_url)
      port(git: fake("logs.rb", LOGS)).fetch(repository_url, "v1.0.0")
    end
    folders = logged.map { |entry| File.dirname(entry.fetch("pwd")) }.uniq
    names = logged.map { |entry| File.basename(entry.fetch("pwd")) }

    assert_equal [File.join(File.realpath(@base), "cache", "plugins")], folders
    assert(names.all? { |name| name.start_with?(".fetching-") })
    assert_empty Dir.children(File.join(@base, "cache", "plugins")).grep(/\A\.fetching-/)
  end

  def test_gives_git_the_proxies_and_never_a_password_prompt_or_a_git_variable_of_crosslints
    names = %w[HTTPS_PROXY HTTP_PROXY NO_PROXY GIT_DIR GIT_TERMINAL_PROMPT GIT_INDEX_FILE]
    before = ENV.values_at(*names)
    ENV.update("HTTPS_PROXY" => "http://secure.invalid:3128", "HTTP_PROXY" => "http://plain.invalid:3128", "NO_PROXY" => "internal.invalid",
      "GIT_DIR" => File.join(@base, "elsewhere"), "GIT_TERMINAL_PROMPT" => "1", "GIT_INDEX_FILE" => File.join(@base, "index"))
    port(git: fake("logs.rb", LOGS)).tags(repository_url)

    assert_equal [
{
"HTTPS_PROXY" => "http://secure.invalid:3128",
"HTTP_PROXY" => "http://plain.invalid:3128",
"NO_PROXY" => "internal.invalid",
"GIT_TERMINAL_PROMPT" => "0",
},
], logged.map { |entry| entry.fetch("env") }
  ensure
    names.zip(before) { |name, value| ENV[name] = value }
  end

  def test_says_what_it_fetches_before_it_makes_a_request
    port(git: fake("logs.rb", LOGS), err: logging).fetch(repository_url, "v1.0.0")

    assert_equal [["said"], %w[argv env pwd], %w[argv env pwd], %w[argv env pwd], %w[argv env pwd]], logged.map(&:keys)
    assert_equal "crosslint: fetching #{repository_url} at v1.0.0", logged.first.fetch("said")
  end

  def test_says_what_it_lists_before_it_makes_a_request
    port(git: fake("logs.rb", LOGS), err: logging).tags(repository_url)

    assert_equal [["said"], %w[argv env pwd]], logged.map(&:keys)
    assert_equal "crosslint: listing the tags of #{repository_url}", logged.first.fetch("said")
  end

  def test_keeps_a_tag_that_has_moved_since_it_was_fetched
    first = port
    folder = first.fetch(repository_url, "latest")
    write(@origin, "plugin.kdl", "// moved\n")
    commit("two")
    git(@origin, "tag", "-f", "latest")

    assert_equal [folder, PLUGIN, ["crosslint: fetching #{repository_url} at latest"]],
      [first.fetch(repository_url, "latest"), File.binread(File.join(folder, "plugin.kdl")), said.lines(chomp: true)]
    assert_equal "// moved\n", File.binread(File.join(port("other").fetch(repository_url, "latest"), "plugin.kdl"))
  end

  def test_fetches_the_bytes_that_were_committed_whatever_the_users_git_settings_say_about_line_endings
    write(@origin, "lf.txt", "a\nb\n")
    commit("lf")
    git(@origin, "tag", "lf-ending")
    home = File.join(@base, "home")
    write(home, ".gitconfig", "[core]\n\tautocrlf = true\n")
    names = %w[HOME USERPROFILE]
    before = ENV.values_at(*names)
    names.each { |name| ENV[name] = home }
    folder = port.fetch(repository_url, "lf-ending")

    assert_equal "a\nb\n", File.binread(File.join(folder, "lf.txt"))
  ensure
    names.zip(before) { |name, value| ENV[name] = value }
  end

  # A fetch that is killed leaves its folder, which no later fetch would
  # use, so a fetch removes the ones that are an hour old.
  def test_removes_the_folder_of_a_fetch_that_was_killed_an_hour_ago_and_no_other
    plugins = File.join(@base, "cache", "plugins")
    now = Time.at(1_800_000_000)
    ages = { ".fetching-old" => 3601, ".fetching-hour" => 3600, ".fetching-recent" => 3599, "other-old" => 7200 }
    ages.each do |name, age|
      FileUtils.mkdir_p(File.join(plugins, name, "files"))
      File.utime(now - age, now - age, File.join(plugins, name))
    end
    port(clock: Struct.new(:now).new(now)).fetch(repository_url, "v1.0.0")

    assert_equal [".fetching-recent", "other-old"], Dir.children(plugins).reject { |name| name == File.basename(entry_for(repository_url, "v1.0.0")) }.sort
  end

  def test_fetches_when_a_folder_of_an_earlier_fetch_goes_before_its_age_is_read
    plugins = File.join(@base, "cache", "plugins")
    FileUtils.mkdir_p(File.join(plugins, ".fetching-gone"))
    Thread.current[:crosslint_shared_vanishing] = [".fetching-gone"]
    folder = port.fetch(repository_url, "v1.0.0")

    assert_equal PLUGIN, File.binread(File.join(folder, "plugin.kdl"))
  ensure
    Thread.current[:crosslint_shared_vanishing] = nil
  end

  def test_keeps_the_copy_another_crosslint_saved_first
    entry = entry_for(repository_url, "v1.0.0")
    err = StringIO.new
    test = self
    err.define_singleton_method(:puts) { |_| test.write(File.join(entry, "signatures"), "plugin.kdl", "// theirs\n") }
    folder = port(err:).fetch(repository_url, "v1.0.0")

    assert_equal "// theirs\n", File.binread(File.join(folder, "plugin.kdl"))
    assert_equal [File.basename(entry)], Dir.children(File.join(@base, "cache", "plugins"))
  end

  def test_stops_when_it_cant_save_the_copy
    error = denying_renames { assert_raises(Core::FetchError) { port.fetch(repository_url, "v1.0.0") } }

    assert_match(/\Acouldn't write in #{Regexp.escape(File.join(@base, 'cache', 'plugins'))}: Permission denied/, error.message)
    assert_empty Dir.children(File.join(@base, "cache", "plugins"))
  end

  def test_stops_when_the_cache_cant_be_a_folder
    blocked = write(@base, "blocked", "a file")
    error = assert_raises(Core::FetchError) { port(cache: blocked).fetch(repository_url, "v1.0.0") }

    assert_match(/\Acouldn't write in #{Regexp.escape(File.join(blocked, 'plugins'))}: \S.*#{Regexp.escape(blocked)}/, error.message)
  end

  def test_ends_git_and_everything_it_started_at_the_time_limit
    fetching = port(git: fake("hangs.rb", HANGS), time_limit: 1)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    error = assert_raises(Core::FetchError) { fetching.fetch(repository_url, "v1.0.0") }

    assert_equal "took more than 1 seconds, so CrossLint ended git and everything it started", error.message
    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 10
    assert_gone File.read(File.join(@base, "fakes", "child.pid")).to_i
    assert_empty Dir.children(File.join(@base, "cache", "plugins"))
  end

  def test_ends_git_and_everything_it_started_at_the_time_limit_when_listing_tags
    listing = port(git: fake("hangs.rb", HANGS), time_limit: 1)
    error = assert_raises(Core::FetchError) { listing.tags(repository_url) }

    assert_equal "took more than 1 seconds, so CrossLint ended git and everything it started", error.message
    assert_gone File.read(File.join(@base, "fakes", "child.pid")).to_i
  end

  def test_counts_the_time_limit_over_every_run_of_git
    slow = fake("slow.rb", "sleep 0.4\nexec(\"git\", *ARGV)\n")
    error = assert_raises(Core::FetchError) { port(git: slow, time_limit: 1.0).fetch(repository_url, "v1.0.0") }

    assert_equal "took more than 1.0 seconds, so CrossLint ended git and everything it started", error.message
  end

  def test_ends_git_when_it_cant_be_put_in_a_tree
    started = []
    joined = []
    began = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    error = assert_raises(Core::FetchError) { port(git: fake("sleeps.rb", "sleep 30\n"), tree: unholding_tree(started, joined)).tags(repository_url) }
    *pipes, waiter = started

    assert_equal "git couldn't be put in a tree, so CrossLint ended it", error.message
    assert_equal [true, true, true, false], [*pipes.map(&:closed?), waiter.alive?]
    assert_equal 1, joined.size
    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - began, :<, 10
  end

  def test_ends_git_when_it_cant_be_put_in_a_tree_and_has_exited_already
    tree = unholding_tree([]) { |pid| sleep 0.05 while process_exists?(pid) }
    error = assert_raises(Core::FetchError) { port(git: fake("quits.rb", "exit 0\n"), tree:).tags(repository_url) }

    assert_equal "git couldn't be put in a tree, so CrossLint ended it", error.message
  end

  # Windows can't put a process that has exited and been reaped in a job
  # object, and answers error 87.
  def test_reads_what_git_wrote_when_it_exited_before_it_was_put_in_a_tree
    started = []
    tree = Class.new(Adapters::ProcessHelpers::TREE) do
      define_singleton_method(:popen3) { |*arguments| super(*arguments, &nil).tap { |by_it| started.concat(by_it) } }
      define_method(:initialize) do |pid|
        # The waiter ends once Ruby has reaped the process.
        started.last.join
        sleep 0.3
        super(pid)
      end
    end
    quick = fake("quick.rb", "puts \"a\\trefs/tags/v1.0.0\"\n")

    assert_equal ["v1.0.0"], port(git: quick, tree:).tags(repository_url)
  end

  def test_says_what_git_wrote_when_it_fails
    failing = fake("fails.rb", "warn \"\\n boom \\n\"\nexit(ARGV.include?(\"init\") ? 0 : 1)\n")
    messages = [commit_sha, "v1.0.0"].map { |ref| assert_raises(Core::FetchError) { port(git: failing).fetch(repository_url, ref) }.message }

    assert_equal ["couldn't fetch #{commit_sha}: boom", "boom"], messages
  end

  def test_says_that_git_failed_when_it_wrote_nothing
    failing = fake("silent.rb", "exit 3\n")

    assert_equal "git failed", assert_raises(Core::FetchError) { port(git: failing).tags(repository_url) }.message
  end

  def test_says_what_git_wrote_when_it_isnt_a_repository
    message = assert_raises(Core::FetchError) { port.tags(missing_repository_url) }.message

    assert_match(/fatal/, message)
  end

  def test_says_to_install_git_when_there_is_none
    error = assert_raises(Core::FetchError) { port(git: "crosslint-no-such-git").tags(repository_url) }

    assert_match(/\Acouldn't run crosslint-no-such-git, which CrossLint fetches shared plugins with, so install Git: /, error.message)
  end

  def test_says_why_it_couldnt_run_git
    error = assert_raises(Core::FetchError) { port(git: "crosslint-no-such-git").tags(repository_url) }
    reason = begin
      Process.spawn("crosslint-no-such-git")
    rescue SystemCallError => spawned
      spawned.message
    end

    assert_equal "couldn't run crosslint-no-such-git, which CrossLint fetches shared plugins with, so install Git: #{reason}", error.message
  end

  def test_reads_what_git_wrote_as_utf_8_whatever_it_is
    printing = fake("bytes.rb", "$stderr.write(\"caf\\xC3\\xA9 \\xFF\".b)\nexit 1\n")

    assert_equal "caf\u00e9 \uFFFD", assert_raises(Core::FetchError) { port(git: printing).tags(repository_url) }.message
  end

  def test_reads_all_of_what_git_writes_however_much_and_closes_its_input
    chatty = fake("chatty.rb", "$stdin.read\n$stdout.write(\"x\" * 100_000)\n$stderr.write(\"y\" * 50_000)\n")
    command = Adapters::GitCommand.new(git: chatty, tree: Adapters::ProcessHelpers::TREE, environment: {})
    output = command.run([], @base, Process.clock_gettime(Process::CLOCK_MONOTONIC) + 30)

    assert_equal [100_000, 50_000, true], [output.out.size, output.err.size, output.success]
  end

  def test_waits_a_second_for_what_a_process_that_left_gits_tree_still_writes_unless_it_is_told_otherwise
    command = Adapters::GitCommand.new(git: ["git"], tree: Adapters::ProcessHelpers::TREE, environment: {})

    assert_equal 1, command.pipe_limit
  end

  def test_reads_what_git_writes_as_bytes
    pipes = []
    command = Adapters::GitCommand.new(git: fake("quits.rb", "exit 0\n"), tree: scripting_tree(pipes, [IOError], [IOError]), environment: {})
    command.run([], @base, Process.clock_gettime(Process::CLOCK_MONOTONIC) + 30)

    assert_equal [true, true], pipes.map(&:binmoded)
  end

  def test_keeps_what_git_wrote_when_a_pipe_fails_with_a_system_error
    pipes = []
    command = Adapters::GitCommand.new(git: fake("quits.rb", "exit 0\n"), tree: scripting_tree(pipes, ["partial", Errno::EPIPE], [Errno::EIO]), environment: {})
    output = command.run([], @base, Process.clock_gettime(Process::CLOCK_MONOTONIC) + 30)

    assert_equal ["partial", "", true], [output.out, output.err, output.success]
  end

  def test_ends_the_threads_that_read_gits_pipes_before_it_returns
    before = Thread.list
    command = Adapters::GitCommand.new(git: fake("quits.rb", "exit 0\n"), tree: scripting_tree([], [:hang], [:hang]), environment: {}, pipe_limit: 0.05)
    command.run([], @base, Process.clock_gettime(Process::CLOCK_MONOTONIC) + 30)

    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
    sleep 0.01 while (Thread.list - before).any? && Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline

    assert_empty Thread.list - before
  end

  def test_waits_a_little_for_what_a_process_that_left_gits_tree_still_writes
    skip "a process leaves its job object only on macOS and Linux" if WINDOWS

    late = fake("late.rb", "Process.spawn(RbConfig.ruby, \"--disable=rubyopt\", \"-e\", \"sleep 0.4; $stdout.write('late')\", pgroup: true)\n")
    command = Adapters::GitCommand.new(git: late, tree: Adapters::ProcessHelpers::TREE, environment: {}, pipe_limit: 5)
    output = command.run([], @base, Process.clock_gettime(Process::CLOCK_MONOTONIC) + 30)

    assert_equal "late", output.out
  end

  def test_fetches_each_time_in_a_folder_of_its_own_in_the_cache
    port(git: fake("logs.rb", LOGS)).fetch(repository_url, "v1.0.0")
    port(git: fake("logs.rb", LOGS)).fetch(repository_url, "v1.2.0")
    work = logged_arguments.select { |argv| argv.first == "--git-dir" }.map { |argv| File.dirname(argv.fetch(1)) }.uniq

    assert_equal 2, work.size
    assert(work.all? { |folder| File.basename(folder).match?(/\A\.fetching-\h{32}\z/) })
  end

  def test_doesnt_wait_for_a_process_that_left_gits_tree_to_close_its_output
    skip "a process leaves its job object only on macOS and Linux" if WINDOWS

    leaving = fake("leaves.rb", "Process.spawn(RbConfig.ruby, \"-e\", \"sleep 4\", pgroup: true)\nputs \"out\"\n")
    command = Adapters::GitCommand.new(git: leaving, tree: Adapters::ProcessHelpers::TREE, environment: {}, pipe_limit: 0.2)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    output = command.run([], @base, started + 30)

    assert_equal ["out\n", "", true], [output.out, output.err, output.success]
    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 3
    assert_equal 0.2, command.pipe_limit
  end

  def test_keeps_its_cache_in_xdg_cache_home_or_dot_cache_in_the_home_folder
    xdg = File.expand_path("/xdg/cache")
    home = -> { File.expand_path("/home/me") }
    cache = -> (env, where = home) { Adapters::GitSharedPlugins.cache_folder(env, windows: false, home: where) }
    dot_cache = File.join(home.call, ".cache", "crosslint")

    assert_equal [File.join(xdg, "crosslint"), dot_cache, dot_cache, dot_cache],
      [
        cache.call({ "XDG_CACHE_HOME" => xdg }, -> { raise "no home needed" }),
        cache.call({}),
        cache.call({ "XDG_CACHE_HOME" => "" }),
        cache.call({ "XDG_CACHE_HOME" => "relative/cache" }),
]
  end

  def test_keeps_its_cache_in_local_app_data_on_windows
    local = File.expand_path("/local")
    home = -> { File.expand_path("/home/me") }
    cache = -> (env, where = home) { Adapters::GitSharedPlugins.cache_folder(env, windows: true, home: where) }
    fallback = File.join(home.call, "AppData", "Local", "crosslint", "cache")

    assert_equal [File.join(local, "crosslint", "cache"), fallback, fallback],
      [cache.call({ "LOCALAPPDATA" => local }, -> { raise "no home needed" }), cache.call({}), cache.call({ "LOCALAPPDATA" => "" })]
  end

  def test_keeps_what_it_fetches_in_plugins_in_the_cache_of_the_user_unless_it_is_given_a_folder
    base = File.expand_path("/xdg/cache")
    unix = Adapters::GitSharedPlugins.new(err: @err, env: { "XDG_CACHE_HOME" => base }, windows: false)
    windows = Adapters::GitSharedPlugins.new(err: @err, env: { "LOCALAPPDATA" => base }, windows: true)
    url = "https://example.com/OWNER/signatures"

    assert_equal [File.join(base, "crosslint", "plugins"), File.join(base, "crosslint", "cache", "plugins")],
      [unix, windows].map { |each| File.dirname(each.folder(url, "v1.0.0"), 2) }
  end

  def test_keeps_what_it_fetches_in_dot_cache_of_the_home_folder_when_it_finds_no_other_place
    elsewhere = Adapters::GitSharedPlugins.new(err: @err, env: {}, windows: false)

    assert_equal File.join(Dir.home, ".cache", "crosslint", "plugins"), File.dirname(elsewhere.folder("https://example.com/OWNER/signatures", "v1.0.0"), 2)
  end

  def test_says_to_set_xdg_cache_home_when_there_is_no_home_folder
    nothing = Adapters::GitSharedPlugins.new(err: @err, env: {}, windows: false, home: -> { raise ArgumentError, "couldn't find HOME" })
    error = assert_raises(Core::FetchError) { nothing.fetch("https://example.com/OWNER/signatures", "v1.0.0") }

    assert_equal "CrossLint keeps what it fetches in a cache folder, and found no home folder for it (couldn't find HOME); set XDG_CACHE_HOME", error.message
  end

  def test_gives_no_folder_for_a_plugin_when_there_is_no_home_folder_for_the_cache_and_when_the_url_names_no_plugin
    nothing = Adapters::GitSharedPlugins.new(err: @err, env: {}, windows: false, home: -> { raise ArgumentError, "couldn't find HOME" })

    assert_nil nothing.cached("https://example.com/OWNER/signatures", "v1.0.0")
    assert_nil port.cached("https://example.com/OWNER/a b", "v1.0.0")
    assert_empty said
  end

  def test_keeps_its_cache_where_this_system_keeps_one_unless_it_is_told_otherwise
    env = { "XDG_CACHE_HOME" => File.expand_path("/xdg/cache"), "LOCALAPPDATA" => File.expand_path("/local") }
    url = "https://example.com/OWNER/signatures"
    caches = [true, false].map do |windows|
      as_windows(windows) { File.dirname(Adapters::GitSharedPlugins.new(err: @err, env:).folder(url, "v1.0.0"), 2) }
    end

    assert_equal [File.join(File.expand_path("/local"), "crosslint", "cache", "plugins"), File.join(File.expand_path("/xdg/cache"), "crosslint", "plugins")], caches
  end

  def test_gives_git_the_environment_a_launcher_saved_before_it_changed_it
    saved = fake("saved.rb", "puts \"abc\\trefs/tags/\#{ENV.fetch(\"CROSSLINT_SAVED\")}-\#{ENV.fetch(\"BUNDLER_ORIG_CROSSLINT_SAVED\", \"none\")}\"\n")
    ENV["CROSSLINT_SAVED"] = "after"

    assert_equal ["before-none"], port(git: saved, env: { "BUNDLER_ORIG_CROSSLINT_SAVED" => "before" }).tags(repository_url)
  ensure
    ENV.delete("CROSSLINT_SAVED")
  end

  def test_gives_no_folder_for_a_url_the_port_doesnt_accept
    fetched = port.fetch(repository_url, "v1.0.0")
    https_only = Adapters::GitSharedPlugins.new(err: @err, cache: File.join(@base, "cache"))

    assert_equal [fetched, nil], [port.cached(repository_url, "v1.0.0"), https_only.cached(repository_url, "v1.0.0")]
  end

  def test_gives_no_folder_for_a_ref_that_git_would_read_as_more_than_a_tag
    FileUtils.mkdir_p(File.join(entry_for(repository_url, "a:b"), "signatures"))
    FileUtils.mkdir_p(File.join(entry_for(repository_url, "-x"), "signatures"))

    assert_equal [nil, nil], [port.cached(repository_url, "a:b"), port.cached(repository_url, "-x")]
  end

  def test_lists_each_tag_as_what_follows_the_first_tab_of_its_line
    listing = fake("lists.rb", "print \"abc\\trefs/tags/v1.0.0\\nabc\\trefs/tags/with space\\n\"\n")

    assert_equal ["v1.0.0", "with space"], port(git: listing).tags(repository_url)
  end

  def test_unsets_each_git_variable_and_no_other
    assert_equal({ "GIT_DIR" => nil, "GIT_INDEX_FILE" => nil }, Adapters::GitEnvironment.cleared({ "GIT_DIR" => "x", "PATH" => "y", "GIT_INDEX_FILE" => "z", "XGIT_A" => "b" }))
    assert_equal ENV.keys.grep(/\AGIT_/).sort, Adapters::GitEnvironment.cleared.keys.sort
  end

  def test_unsets_a_git_variable_whatever_its_case_on_windows_and_only_there
    env = { "Git_Dir" => "x", "git_index_file" => "y", "PATH" => "p", "XGIT_A" => "b", "GIT_WORK_TREE" => "z" }

    assert_equal({ "Git_Dir" => nil, "git_index_file" => nil, "GIT_WORK_TREE" => nil }, Adapters::GitEnvironment.cleared(env, windows: true))
    assert_equal({ "GIT_WORK_TREE" => nil }, Adapters::GitEnvironment.cleared(env, windows: false))
  end

  def test_unsets_a_git_variable_in_any_case_when_this_is_windows_and_only_then_unless_it_is_told_otherwise
    env = { "Git_Dir" => "x", "GIT_WORK_TREE" => "z" }

    assert_equal [{ "Git_Dir" => nil, "GIT_WORK_TREE" => nil }, { "GIT_WORK_TREE" => nil }],
      [as_windows(true) { Adapters::GitEnvironment.cleared(env) }, as_windows(false) { Adapters::GitEnvironment.cleared(env) }]
  end

  # Ruby keeps the case a variable was set in, and Windows names ignore
  # case, so a GIT_DIR in lower case reaches Git unless it is named as set.
  def test_gives_a_child_no_git_variable_of_any_case_where_the_system_ignores_case
    ENV.update("git_dir" => "x", "Git_Index_File" => "y")
    out, = Open3.capture2(Adapters::GitEnvironment.cleared, RbConfig.ruby, "-e", 'print ENV.keys.grep(/\Agit_/i).sort.join(",")')

    assert_equal(WINDOWS ? "" : "Git_Index_File,git_dir", out)
  ensure
    ENV.delete("git_dir")
    ENV.delete("Git_Index_File")
  end

  private

  # The folder the cache keeps the fetch of `ref` of `url` in, worked out
  # here, so that a test that writes there writes in the test's base even
  # when the code is wrong.
  def entry_for(url, ref) = File.join(@base, "cache", "plugins", Digest::SHA256.hexdigest("#{url}\0#{ref}")[0, 32])

  # A port that keeps its cache in the test's base, accepts file URLs, and
  # writes to the test's `said`. A String as the first argument names
  # another cache, beside the first.
  def port(name = nil, **options)
    options = { cache: File.join(@base, name || "cache"), schemes: ["https://", "file://"], err: @err }.merge(options)
    Adapters::GitSharedPlugins.new(**options)
  end

  def git(folder, *) = Origin.git(folder, *)

  def commit(message)
    git(@origin, "add", "-A")
    git(@origin, "commit", "-q", "-m", message)
  end

  # A fake git: a program and its file, as GitSharedPlugins runs it. Ruby
  # reads no RUBYOPT, so that Bundler doesn't slow every run.
  def fake(name, script)
    [RbConfig.ruby, "--disable=rubyopt", write(File.join(@base, "fakes"), name, script)]
  end

  # The arguments of each run the fake git logged, after the ones that
  # limit the protocols, which every run must have first.
  def logged_arguments
    logged.map do |entry|
      argv = entry.fetch("argv")
      assert_equal PROTOCOLS, argv.first(PROTOCOLS.size)
      argv.drop(PROTOCOLS.size)
    end
  end

  # What the fake git logged, one JSON object a line.
  def logged
    File.read(File.join(@base, "fakes", "log.jsonl")).lines.map { |line| JSON.parse(line) }
  end

  # A standard error that writes what it is told to the fake git's log.
  def logging
    log = File.join(@base, "fakes", "log.jsonl")
    FileUtils.mkdir_p(File.dirname(log))
    StringIO.new.tap { |err| err.define_singleton_method(:puts) { |line| File.write(log, "#{JSON.generate({ 'said' => line })}\n", mode: "a") } }
  end

  # A tree class that holds nothing: it pushes the pipes and waiter of each
  # process it starts to `started`, runs the block, if there is one, with
  # the pid, and raises that it couldn't hold the process.
  def unholding_tree(started, joined = [], &before)
    before ||= -> (_pid) {}
    Class.new(Adapters::ProcessHelpers::TREE) do
      define_singleton_method(:popen3) do |*arguments|
        super(*arguments, &nil).tap do |started_by_it|
          started.concat(started_by_it)
          started_by_it.last.define_singleton_method(:join) do |*limit|
            joined << limit
            super(*limit)
          end
        end
      end
      define_method(:initialize) do |pid|
        before.call(pid)
        raise Core::PluginError, "couldn't be put in a tree"
      end
    end
  end

  # A tree class that gives GitCommand a ScriptedPipe for each of git's
  # output pipes, with the steps for standard output and then standard
  # error, and keeps them in `pipes`.
  def scripting_tree(pipes, out, err)
    Class.new(Adapters::ProcessHelpers::TREE) do
      define_singleton_method(:popen3) do |*arguments|
        stdin, stdout, stderr, wait = super(*arguments, &nil)
        pipes.replace([ScriptedPipe.new(stdout, *out), ScriptedPipe.new(stderr, *err)])
        [stdin, *pipes, wait]
      end
    end
  end

  # Runs the block as it would run on Windows, or on another system, so
  # that a default that reads which system this is can be seen to read it.
  def as_windows(windows)
    processes = Adapters::ProcessHelpers
    actual = processes::WINDOWS
    processes.__send__(:remove_const, :WINDOWS)
    processes.const_set(:WINDOWS, windows)
    yield
  ensure
    processes.__send__(:remove_const, :WINDOWS)
    processes.const_set(:WINDOWS, actual)
  end

  # Denies each File.rename in this thread while the block runs, as Windows
  # does for a folder another program has open.
  def denying_renames
    Thread.current[:crosslint_shared_rename_denied] = true
    yield
  ensure
    Thread.current[:crosslint_shared_rename_denied] = nil
  end

  def process_exists?(pid)
    Process.kill(0, pid)
    true
  rescue Errno::ESRCH
    false
  end

  def assert_gone(pid)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
    alive = true
    while alive && Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
      alive = process_exists?(pid)
      sleep 0.05 if alive
    end

    refute alive, "process #{pid} is still running"
  end
end
