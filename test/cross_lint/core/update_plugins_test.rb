# frozen_string_literal: true

require "test_helper"

# Core::UpdatePlugins against the in-memory adapters.
class UpdatePluginsTest < Minitest::Test
  cover "CrossLint::Core::UpdatePlugins*"
  cover "CrossLint::Core::Update*"
  cover "CrossLint::Core::UpdateResult*"
  cover "CrossLint::Core::Mistake*"

  Core = CrossLint::Core
  Memory = CrossLint::Adapters

  APP = File.expand_path("/app")
  FILE = ".config/crosslint/config.kdl"
  ONE = "https://example.com/OWNER/one"
  TWO = "https://example.com/OWNER/two"

  # Sets each ref, as the configuration port should, and keeps what it was
  # asked to set.
  class RecordingConfiguration < CrossLint::Adapters::MemoryConfiguration
    attr_reader :set

    def set_refs(root, refs)
      (@set ||= []) << refs
      super
    end
  end

  def test_moves_each_shared_plugin_to_the_newest_version_tag_of_its_repository
    configuration, shared = project([listing(ONE, "v1.0.0"), listing(TWO, "v2.1.0", 2)], ONE => %w[v1.0.0 v1.10.0 v1.9.0], TWO => %w[v2.1.0 v2.1.1 latest])
    result = Core::UpdatePlugins.new(configuration:, shared_plugins: shared).call(APP)

    assert_equal [["v1.10.0", false], ["v2.1.1", false]], result.updates.map { |update| [update.newest, update.current?] }
    assert_equal ["v1.10.0", "v2.1.1"], configuration.read(APP).plugins.map(&:ref)
    assert_equal [{ONE => "v1.10.0", TWO => "v2.1.1"}], configuration.set
    assert_equal ["#{ONE}: moved from v1.0.0 to v1.10.0", "#{TWO}: moved from v2.1.0 to v2.1.1"], result.lines
  end

  def test_lists_what_it_would_move_and_changes_nothing_with_dry_run
    configuration, shared = project([listing(ONE, "v1.0.0")], ONE => %w[v1.2.0])
    result = Core::UpdatePlugins.new(configuration:, shared_plugins: shared).call(APP, dry_run: true)

    assert_equal ["#{ONE}: would move from v1.0.0 to v1.2.0"], result.lines
    assert_nil configuration.set
    assert_equal ["v1.0.0"], configuration.read(APP).plugins.map(&:ref)
  end

  # A tag that isn't a plain version is a choice, such as a prerelease,
  # and a SHA or a branch name is no version: update moves none of them.
  def test_leaves_a_plugin_whose_ref_is_not_a_plain_version_tag_alone_and_says_so_without_asking_for_its_tags
    refs = ["a" * 40, "v1.0.0-rc.1", "2.0.0-beta.2", "latest", "v1.0", "main", "v1.0.0+build.5"]
    configuration, shared = project(refs.each_with_index.map { |ref, index| listing("#{ONE}#{index}", ref, index + 1) }, {})
    result = Core::UpdatePlugins.new(configuration:, shared_plugins: shared).call(APP)

    assert_equal refs.each_with_index.map { |ref, index| "#{ONE}#{index}: is at #{ref}, which isn't a plain version tag, vX.Y.Z or X.Y.Z, so update leaves it alone" },
      result.lines
    assert_equal [[true] * refs.size, nil, refs], [result.updates.map(&:pinned?), configuration.set, configuration.read(APP).plugins.map(&:ref)]
    assert_empty @err.string
  end

  def test_moves_the_plugins_that_are_at_a_plain_version_tag_and_leaves_the_others_in_one_run
    configuration, shared = project([listing(ONE, "v1.0.0"), listing(TWO, "v2.0.0-rc.1", 2)], ONE => %w[v1.1.0 v2.0.0-rc.2], TWO => %w[v2.0.0])
    result = Core::UpdatePlugins.new(configuration:, shared_plugins: shared).call(APP)

    assert_equal [{ONE => "v1.1.0"}], configuration.set
    assert_equal ["v1.1.0", "v2.0.0-rc.1"], configuration.read(APP).plugins.map(&:ref)
    assert_equal ["#{ONE}: moved from v1.0.0 to v1.1.0", "#{TWO}: is at v2.0.0-rc.1, which isn't a plain version tag, vX.Y.Z or X.Y.Z, so update leaves it alone"],
      result.lines
  end

  def test_leaves_a_plugin_that_is_at_its_newest_tag_and_writes_nothing_for_it
    configuration, shared = project([listing(ONE, "v1.2.0")], ONE => %w[v1.0.0 v1.2.0])
    result = Core::UpdatePlugins.new(configuration:, shared_plugins: shared).call(APP)

    assert_equal ["#{ONE}: is at its newest tag, v1.2.0"], result.lines
    assert_nil configuration.set
  end

  def test_leaves_a_plugin_at_the_tag_it_has_when_another_tag_has_the_same_version
    configuration, shared = project([listing(ONE, "v1.2.0")], ONE => %w[v1.2.0 1.2.0])
    result = Core::UpdatePlugins.new(configuration:, shared_plugins: shared).call(APP)

    assert_equal [true, nil], [result.updates.first.current?, configuration.set]
  end

  def test_leaves_a_plugin_whose_repository_has_no_version_tag_and_says_so
    configuration, shared = project([listing(ONE, "v1.0.0")], ONE => %w[v1.0.0-rc.1 latest v2])
    result = Core::UpdatePlugins.new(configuration:, shared_plugins: shared).call(APP)

    assert_equal [true, false, nil], [result.updates.first.untagged?, result.updates.first.pinned?, configuration.set]
    assert_equal ["#{ONE}: has no tag that is a version, vX.Y.Z or X.Y.Z, so it stays at v1.0.0"], result.lines
  end

  def test_leaves_local_and_built_in_plugins_alone_and_asks_for_no_tags_of_them
    configuration, shared = project([listing(".config/crosslint/tests", nil), listing("debt", nil, 2), listing(ONE, "v1.0.0", 3)], ONE => %w[v1.1.0])
    result = Core::UpdatePlugins.new(configuration:, shared_plugins: shared).call(APP)

    assert_equal [ONE], result.updates.map { |update| update.listing.name }
    assert_equal [nil, nil, "v1.1.0"], configuration.read(APP).plugins.map(&:ref)
    assert_equal ["crosslint: listing the tags of #{ONE}"], @err.string.lines(chomp: true)
  end

  def test_stops_at_the_url_of_a_shared_plugin_that_has_a_user_name_or_password_and_doesnt_print_it
    url = "https://user:secret@example.com/OWNER/one"
    configuration, shared = project([listing(ONE, "v1.0.0"), listing(url, "v1.0.0", 3)], ONE => %w[v1.1.0])
    mistake = assert_raises(Core::Mistake) { Core::UpdatePlugins.new(configuration:, shared_plugins: shared).call(APP) }

    assert_equal [FILE, 3, "a plugin's URL has a user name or password, which would be in the configuration and on standard error; " \
      "remove it, and give Git the credentials with a Git credential helper (git help credentials)"], [mistake.file, mistake.line, mistake.message]
    refute_includes mistake.message, "secret"
    assert_empty @err.string
    assert_nil configuration.set
  end

  def test_asks_a_port_that_accepts_other_urls_for_their_tags_too
    url = "file:///tmp/one"
    configuration, = project([listing(url, "v1.0.0")], {})
    shared = Memory::MemorySharedPlugins.new({url => repository(%w[v1.4.0])}, err: StringIO.new, schemes: ["file://"])

    assert_equal ["#{url}: moved from v1.0.0 to v1.4.0"], Core::UpdatePlugins.new(configuration:, shared_plugins: shared).call(APP).lines
  end

  def test_stops_at_a_shared_plugin_with_no_ref_naming_the_file_and_the_line
    configuration, shared = project([listing(ONE, "v1.0.0"), listing(TWO, nil, 5)], ONE => %w[v1.1.0], TWO => %w[v1.1.0])
    mistake = assert_raises(Core::Mistake) { Core::UpdatePlugins.new(configuration:, shared_plugins: shared).call(APP) }

    assert_equal [FILE, 5, %(shared plugin "#{TWO}" needs ref=, a tag or a full commit SHA)], [mistake.file, mistake.line, mistake.message]
    assert_nil configuration.set
  end

  def test_stops_at_a_repository_whose_tags_it_cant_list_naming_the_plugin_and_changes_nothing
    configuration, shared = project([listing(ONE, "v1.0.0"), listing(TWO, "v1.0.0", 4)], ONE => %w[v1.1.0])
    mistake = assert_raises(Core::Mistake) { Core::UpdatePlugins.new(configuration:, shared_plugins: shared).call(APP) }

    assert_equal [FILE, 4, "couldn't list the tags of shared plugin #{TWO}: no repository at #{TWO}"], [mistake.file, mistake.line, mistake.message]
    assert_nil configuration.set
    assert_equal ["v1.0.0", "v1.0.0"], configuration.read(APP).plugins.map(&:ref)
  end

  def test_finds_the_project_from_a_folder_inside_it_and_says_how_to_write_a_configuration_when_there_is_none
    configuration, shared = project([listing(ONE, "v1.0.0")], ONE => %w[v1.1.0])
    use_case = Core::UpdatePlugins.new(configuration:, shared_plugins: shared)
    mistake = assert_raises(Core::Mistake) { use_case.call(File.expand_path("/elsewhere/lib")) }

    assert_equal 1, use_case.call(File.join(APP, "lib", "deep")).changes.size
    assert_equal "no #{FILE} in #{File.expand_path("/elsewhere/lib")} or any folder above it; run crosslint init in the project's root to write one", mistake.message
  end

  def test_says_what_each_plugin_did
    update = ->(ref, newest) { Core::Update.new(listing: listing(ONE, ref), newest:) }
    result = Core::UpdateResult.new(updates: [update.call("v1.0.0", "v1.1.0"), update.call("v1.1.0", "v1.1.0"), update.call("v1.0.0", nil), update.call("main", nil), update.call(nil, "v1.0.0")],
      dry_run: false)

    assert_equal [[false, false, false], [true, false, false], [false, true, false], [false, false, true], [false, false, true]],
      result.updates.map { |each| [each.current?, each.untagged?, each.pinned?] }
    assert_equal [result.updates.first], result.changes
  end

  private

  # A configuration for the project at APP that lists `plugins`, and a
  # port with a repository at each URL that has these tags.
  def project(plugins, tags)
    configuration = Core::Configuration.new(file: FILE, plugins:, policies: [], warnings: nil, verbosity: nil)
    @err = StringIO.new
    repositories = tags.transform_values { |names| repository(names) }
    [RecordingConfiguration.new({APP => configuration}), Memory::MemorySharedPlugins.new(repositories, err: @err)]
  end

  def repository(names) = Memory::MemorySharedPlugins::Repository.new(tags: names.to_h { |name| [name, "/cache/#{name}"] }, branches: [], commits: {})

  def listing(name, ref, line = 1) = Core::ListedPlugin.new(name:, ref:, settings: [], line:)
end
