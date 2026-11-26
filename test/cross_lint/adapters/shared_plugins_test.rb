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
    @repositories = {URL => Repository.new(tags: CrossLint::Testing::SharedPluginsContract::TAGS.to_h { |tag| [tag, "/cache/#{tag}/signatures"] },
      branches: ["main"], commits: {SHA => "/cache/#{SHA}/signatures"})}
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
  PLUGIN = %(artifact "doc" {\n  files "{path}.md"\n}\n)

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
      raise "git #{arguments.join(" ")} failed: #{out}" unless status.success?

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
    File.open(File.join(__dir__, "log.jsonl"), "a") { |log| log.puts(JSON.generate({"argv" => ARGV, "env" => ENV.to_h.slice(*interesting)})) }
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

  def test_allows_git_the_transport_of_each_scheme_it_accepts_and_no_other
    silent = fake("logs.rb", LOGS.sub(/^exec.*\n/, "exit 0\n"))
    web = Adapters::GitSharedPlugins.new(err: @err, cache: @base, git: silent)
    web.tags("https://example.test/OWNER/signatures")
    ssh = Adapters::GitSharedPlugins.new(err: @err, cache: @base, git: silent, schemes: ["https://", "ssh://"])
    ssh.tags("ssh://example.test/OWNER/signatures")

    assert_equal [%w[-c protocol.allow=never -c protocol.https.allow=always], %w[-c protocol.allow=never -c protocol.https.allow=always -c protocol.ssh.allow=always]], logged.map { |entry| entry.fetch("argv").first(entry.fetch("argv").index("ls-remote")) }
  end

  # A Git setting of the user's, such as url.BASE.insteadOf, can send a
  # request for one address to another, a file or a command, and Git
  # would follow it.
  def test_fetches_over_https_only_so_that_a_git_setting_cant_send_it_to_another_transport
    url = "https://example.test/OWNER/signatures"
    default = Adapters::GitSharedPlugins.new(err: @err, cache: @base)
    messages = rewriting(url, repository_url) do
      [-> { default.fetch(url, "v1.0.0") }, -> { default.fetch(url, commit_sha) }, -> { default.tags(url) }].map { |call| assert_raises(Core::FetchError, &call).message }
    end

    assert_equal 3, messages.grep(/not allowed/).size, messages.inspect
    assert_empty Dir.children(File.join(@base, "plugins"))
  end

  def test_fetches_through_a_git_setting_that_sends_https_to_a_scheme_the_port_was_told_to_accept
    url = "https://example.test/OWNER/signatures"
    folder = rewriting(url, repository_url) { port.fetch(url, "v1.0.0") }

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

  def test_names_the_plugin_for_its_repository_without_dot_git
    assert_equal "signatures", File.basename(port.folder("https://example.com/OWNER/signatures.git/", "v1.0.0"))
    error = assert_raises(Core::FetchError) { port.folder("https://example.com/OWNER/a b", "v1.0.0") }

    assert_equal "can't name a plugin from https://example.com/OWNER/a b, whose last path segment has other characters than letters, digits, and . _ -",
      error.message
  end

  def test_leaves_nothing_in_the_cache_when_a_fetch_fails
    assert_raises(Core::FetchError) { port.fetch(repository_url, "main") }
    assert_raises(Core::FetchError) { port.fetch(repository_url, "0" * 39 + "1") }

    assert_empty Dir.children(File.join(@base, "cache", "plugins"))
  end

  def test_fetches_the_commit_alone_with_git_run_as_a_program
    port(git: fake("logs.rb", LOGS)).fetch(repository_url, "v1.0.0")
    commands = logged_arguments
    repository = commands.drop(1)

    assert_equal ["ls-remote", repository_url, "refs/tags/v1.0.0", "refs/heads/v1.0.0"], commands.first
    assert(repository.all? { |argv| argv[0] == "--git-dir" && argv[2] == "--work-tree" && argv[4, SETTINGS.size] == SETTINGS })
    assert_equal [["init", "-q"], ["fetch", "-q", "--depth", "1", "--no-tags", repository_url, "refs/tags/v1.0.0"],
      ["checkout", "-q", "--detach", "FETCH_HEAD"]], repository.map { |argv| argv.drop(4 + SETTINGS.size) }
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

  def test_gives_git_the_proxies_and_never_a_password_prompt_or_a_git_variable_of_crosslints
    names = %w[HTTPS_PROXY HTTP_PROXY NO_PROXY GIT_DIR GIT_TERMINAL_PROMPT GIT_INDEX_FILE]
    before = ENV.values_at(*names)
    ENV.update("HTTPS_PROXY" => "http://secure.invalid:3128", "HTTP_PROXY" => "http://plain.invalid:3128", "NO_PROXY" => "internal.invalid",
      "GIT_DIR" => File.join(@base, "elsewhere"), "GIT_TERMINAL_PROMPT" => "1", "GIT_INDEX_FILE" => File.join(@base, "index"))
    port(git: fake("logs.rb", LOGS)).tags(repository_url)

    assert_equal [{"HTTPS_PROXY" => "http://secure.invalid:3128", "HTTP_PROXY" => "http://plain.invalid:3128", "NO_PROXY" => "internal.invalid",
                   "GIT_TERMINAL_PROMPT" => "0"}], logged.map { |entry| entry.fetch("env") }
  ensure
    names.zip(before) { |name, value| ENV[name] = value }
  end

  def test_says_what_it_fetches_before_it_makes_a_request
    port(git: fake("logs.rb", LOGS), err: logging).fetch(repository_url, "v1.0.0")

    assert_equal [["said"], %w[argv env], %w[argv env], %w[argv env], %w[argv env]], logged.map(&:keys)
    assert_equal "crosslint: fetching #{repository_url} at v1.0.0", logged.first.fetch("said")
  end

  def test_says_what_it_lists_before_it_makes_a_request
    port(git: fake("logs.rb", LOGS), err: logging).tags(repository_url)

    assert_equal [["said"], %w[argv env]], logged.map(&:keys)
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

    assert_match(/\Acouldn't write in #{Regexp.escape(File.join(@base, "cache", "plugins"))}: /, error.message)
    assert_empty Dir.children(File.join(@base, "cache", "plugins"))
  end

  def test_stops_when_the_cache_cant_be_a_folder
    blocked = write(@base, "blocked", "a file")
    error = assert_raises(Core::FetchError) { port(cache: blocked).fetch(repository_url, "v1.0.0") }

    assert_match(/\Acouldn't write in #{Regexp.escape(File.join(blocked, "plugins"))}: /, error.message)
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
    error = assert_raises(Core::FetchError) { port(git: fake("sleeps.rb", "sleep 30\n"), tree: unholding_tree(started) { |_pid| }).tags(repository_url) }
    *pipes, waiter = started

    assert_equal "git couldn't be put in a tree, so CrossLint ended it", error.message
    assert_equal [true, true, true, false], [*pipes.map(&:closed?), waiter.alive?]
  end

  def test_ends_git_when_it_cant_be_put_in_a_tree_and_has_exited_already
    tree = unholding_tree([]) { |pid| sleep 0.05 while process_exists?(pid) }
    error = assert_raises(Core::FetchError) { port(git: fake("quits.rb", "exit 0\n"), tree:).tags(repository_url) }

    assert_equal "git couldn't be put in a tree, so CrossLint ended it", error.message
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
    cache = ->(env, where = home) { Adapters::GitSharedPlugins.cache_folder(env, windows: false, home: where) }
    dot_cache = File.join(home.call, ".cache", "crosslint")

    assert_equal [File.join(xdg, "crosslint"), dot_cache, dot_cache, dot_cache],
      [cache.call({"XDG_CACHE_HOME" => xdg}, -> { raise "no home needed" }), cache.call({}), cache.call({"XDG_CACHE_HOME" => ""}),
        cache.call({"XDG_CACHE_HOME" => "relative/cache"})]
  end

  def test_keeps_its_cache_in_local_app_data_on_windows
    local = File.expand_path("/local")
    home = -> { File.expand_path("/home/me") }
    cache = ->(env, where = home) { Adapters::GitSharedPlugins.cache_folder(env, windows: true, home: where) }
    fallback = File.join(home.call, "AppData", "Local", "crosslint", "cache")

    assert_equal [File.join(local, "crosslint", "cache"), fallback, fallback],
      [cache.call({"LOCALAPPDATA" => local}, -> { raise "no home needed" }), cache.call({}), cache.call({"LOCALAPPDATA" => ""})]
  end

  def test_keeps_what_it_fetches_in_plugins_in_the_cache_of_the_user_unless_it_is_given_a_folder
    base = File.expand_path("/xdg/cache")
    unix = Adapters::GitSharedPlugins.new(err: @err, env: {"XDG_CACHE_HOME" => base}, windows: false)
    windows = Adapters::GitSharedPlugins.new(err: @err, env: {"LOCALAPPDATA" => base}, windows: true)
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

  def test_unsets_each_git_variable_and_no_other
    assert_equal({"GIT_DIR" => nil, "GIT_INDEX_FILE" => nil}, Adapters::GitEnvironment.cleared({"GIT_DIR" => "x", "PATH" => "y", "GIT_INDEX_FILE" => "z", "XGIT_A" => "b"}))
    assert_equal ENV.keys.grep(/\AGIT_/).sort, Adapters::GitEnvironment.cleared.keys.sort
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
    options = {cache: File.join(@base, name || "cache"), schemes: ["https://", "file://"], err: @err}.merge(options)
    Adapters::GitSharedPlugins.new(**options)
  end

  def git(folder, *arguments) = Origin.git(folder, *arguments)

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
    StringIO.new.tap { |err| err.define_singleton_method(:puts) { |line| File.write(log, "#{JSON.generate({"said" => line})}\n", mode: "a") } }
  end

  # A tree class that holds nothing: it pushes the pipes and waiter of each
  # process it starts to `started`, runs the block with the pid, and
  # raises that it couldn't hold the process.
  def unholding_tree(started, &before)
    Class.new(Adapters::ProcessHelpers::TREE) do
      define_singleton_method(:popen3) { |*arguments| super(*arguments, &nil).tap { |started_by_it| started.concat(started_by_it) } }
      define_method(:initialize) do |pid|
        before.call(pid)
        raise Core::PluginError, "couldn't be put in a tree"
      end
    end
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
