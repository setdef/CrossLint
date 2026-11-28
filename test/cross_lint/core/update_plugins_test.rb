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

  # The CrossLint that updates each project.
  CROSSLINT = Core::Version.parse("1.4.0")

  # Raises the mistake it holds for a folder when it is asked for the
  # oldest CrossLint of the manifest there.
  class BrokenManifests < CrossLint::Adapters::MemoryPluginManifests
    def initialize(mistakes)
      super()
      @mistakes = mistakes
    end

    def minimum(root, folder) = @mistakes.key?(File.expand_path(folder, root)) ? raise(@mistakes.fetch(File.expand_path(folder, root))) : nil
  end

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
    result = update_plugins(configuration, shared).call(APP)

    assert_equal [["v1.10.0", false], ["v2.1.1", false]], result.updates.map { |update| [update.newest, update.current?] }
    assert_equal ["v1.10.0", "v2.1.1"], configuration.read(APP).plugins.map(&:ref)
    assert_equal [{[ONE, nil] => "v1.10.0", [TWO, nil] => "v2.1.1"}], configuration.set
    assert_equal ["#{ONE}: moved from v1.0.0 to v1.10.0", "#{TWO}: moved from v2.1.0 to v2.1.1"], result.lines
  end

  def test_moves_each_folder_listed_from_a_repository_by_itself_keeps_its_path_and_lists_the_tags_once
    configuration, shared = project([listing(ONE, "v1.0.0", 1, path: "plugins/a"), listing(ONE, "v9.0.0", 2, path: "plugins/b"), listing(ONE, "v1.0.0", 3)],
      ONE => %w[v1.0.0 v1.2.0])
    result = update_plugins(configuration, shared).call(APP)

    assert_equal [{[ONE, "plugins/a"] => "v1.2.0", [ONE, nil] => "v1.2.0"}], configuration.set
    assert_equal [["v1.2.0", "plugins/a"], ["v9.0.0", "plugins/b"], ["v1.2.0", nil]], configuration.read(APP).plugins.map { |plugin| [plugin.ref, plugin.path] }
    assert_equal ["#{ONE} (plugins/a): moved from v1.0.0 to v1.2.0", "#{ONE} (plugins/b): is at its newest tag, v9.0.0", "#{ONE}: moved from v1.0.0 to v1.2.0"], result.lines
    assert_equal ["crosslint: listing the tags of #{ONE}", "crosslint: fetching #{ONE} at v1.2.0"], @err.string.lines(chomp: true)
  end

  def test_lists_what_it_would_move_and_changes_nothing_with_dry_run
    configuration, shared = project([listing(ONE, "v1.0.0")], ONE => %w[v1.2.0])
    result = update_plugins(configuration, shared).call(APP, dry_run: true)

    assert_equal ["#{ONE}: would move from v1.0.0 to v1.2.0"], result.lines
    assert_nil configuration.set
    assert_equal ["v1.0.0"], configuration.read(APP).plugins.map(&:ref)
  end

  # A tag that isn't a plain version is a choice, such as a prerelease,
  # and a SHA or a branch name is no version: update moves none of them.
  def test_leaves_a_plugin_whose_ref_is_not_a_plain_version_tag_alone_and_says_so_without_asking_for_its_tags
    refs = ["a" * 40, "v1.0.0-rc.1", "2.0.0-beta.2", "latest", "v1.0", "main", "v1.0.0+build.5"]
    configuration, shared = project(refs.each_with_index.map { |ref, index| listing("#{ONE}#{index}", ref, index + 1) }, {})
    result = update_plugins(configuration, shared).call(APP)

    assert_equal refs.each_with_index.map { |ref, index| "#{ONE}#{index}: is at #{ref}, which isn't a plain version tag, vX.Y.Z or X.Y.Z, so update leaves it alone" },
      result.lines
    assert_equal [[true] * refs.size, nil, refs], [result.updates.map(&:pinned?), configuration.set, configuration.read(APP).plugins.map(&:ref)]
    assert_empty @err.string
  end

  def test_moves_the_plugins_that_are_at_a_plain_version_tag_and_leaves_the_others_in_one_run
    configuration, shared = project([listing(ONE, "v1.0.0"), listing(TWO, "v2.0.0-rc.1", 2)], ONE => %w[v1.1.0 v2.0.0-rc.2], TWO => %w[v2.0.0])
    result = update_plugins(configuration, shared).call(APP)

    assert_equal [{[ONE, nil] => "v1.1.0"}], configuration.set
    assert_equal ["v1.1.0", "v2.0.0-rc.1"], configuration.read(APP).plugins.map(&:ref)
    assert_equal ["#{ONE}: moved from v1.0.0 to v1.1.0", "#{TWO}: is at v2.0.0-rc.1, which isn't a plain version tag, vX.Y.Z or X.Y.Z, so update leaves it alone"],
      result.lines
  end

  def test_leaves_a_plugin_that_is_at_its_newest_tag_and_writes_nothing_for_it
    configuration, shared = project([listing(ONE, "v1.2.0")], ONE => %w[v1.0.0 v1.2.0])
    result = update_plugins(configuration, shared).call(APP)

    assert_equal ["#{ONE}: is at its newest tag, v1.2.0"], result.lines
    assert_nil configuration.set
  end

  def test_leaves_a_plugin_at_the_tag_it_has_when_another_tag_has_the_same_version
    configuration, shared = project([listing(ONE, "v1.2.0")], ONE => %w[v1.2.0 1.2.0])
    result = update_plugins(configuration, shared).call(APP)

    assert_equal [true, nil], [result.updates.first.current?, configuration.set]
  end

  def test_leaves_a_plugin_whose_repository_has_no_version_tag_and_says_so
    configuration, shared = project([listing(ONE, "v1.0.0")], ONE => %w[v1.0.0-rc.1 latest v2])
    result = update_plugins(configuration, shared).call(APP)

    assert_equal [true, false, nil], [result.updates.first.untagged?, result.updates.first.pinned?, configuration.set]
    assert_equal ["#{ONE}: has no tag that is a version, vX.Y.Z or X.Y.Z, so it stays at v1.0.0"], result.lines
  end

  def test_leaves_local_and_built_in_plugins_alone_and_asks_for_no_tags_of_them
    configuration, shared = project([listing(".config/crosslint/tests", nil), listing("debt", nil, 2), listing(ONE, "v1.0.0", 3)], ONE => %w[v1.1.0])
    result = update_plugins(configuration, shared).call(APP)

    assert_equal [ONE], result.updates.map { |update| update.listing.name }
    assert_equal [nil, nil, "v1.1.0"], configuration.read(APP).plugins.map(&:ref)
    assert_equal ["crosslint: listing the tags of #{ONE}", "crosslint: fetching #{ONE} at v1.1.0"], @err.string.lines(chomp: true)
  end

  def test_stops_at_the_url_of_a_shared_plugin_that_has_a_user_name_or_password_and_doesnt_print_it
    url = "https://user:secret@example.com/OWNER/one"
    configuration, shared = project([listing(ONE, "v1.0.0"), listing(url, "v1.0.0", 3)], ONE => %w[v1.1.0])
    mistake = assert_raises(Core::Mistake) { update_plugins(configuration, shared).call(APP) }

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

    assert_equal ["#{url}: moved from v1.0.0 to v1.4.0"], update_plugins(configuration, shared).call(APP).lines
  end

  def test_stops_at_a_shared_plugin_with_no_ref_naming_the_file_and_the_line
    configuration, shared = project([listing(ONE, "v1.0.0"), listing(TWO, nil, 5)], ONE => %w[v1.1.0], TWO => %w[v1.1.0])
    mistake = assert_raises(Core::Mistake) { update_plugins(configuration, shared).call(APP) }

    assert_equal [FILE, 5, %(shared plugin "#{TWO}" needs ref=, a tag or a full commit SHA)], [mistake.file, mistake.line, mistake.message]
    assert_nil configuration.set
  end

  def test_stops_at_a_repository_whose_tags_it_cant_list_naming_the_plugin_and_changes_nothing
    configuration, shared = project([listing(ONE, "v1.0.0"), listing(TWO, "v1.0.0", 4)], ONE => %w[v1.1.0])
    mistake = assert_raises(Core::Mistake) { update_plugins(configuration, shared).call(APP) }

    assert_equal [FILE, 4, "couldn't list the tags of shared plugin #{TWO}: no repository at #{TWO}"], [mistake.file, mistake.line, mistake.message]
    assert_nil configuration.set
    assert_equal ["v1.0.0", "v1.0.0"], configuration.read(APP).plugins.map(&:ref)
  end

  def test_finds_the_project_from_a_folder_inside_it_and_says_how_to_write_a_configuration_when_there_is_none
    configuration, shared = project([listing(ONE, "v1.0.0")], ONE => %w[v1.1.0])
    use_case = update_plugins(configuration, shared)
    mistake = assert_raises(Core::Mistake) { use_case.call(File.expand_path("/elsewhere/lib")) }

    assert_equal 1, use_case.call(File.join(APP, "lib", "deep")).changes.size
    assert_equal "no #{FILE} in #{File.expand_path("/elsewhere/lib")} or any folder above it; run crosslint init in the project's root to write one", mistake.message
  end

  def test_moves_within_the_compatible_versions_and_names_the_newer_incompatible_versions_on_the_line
    configuration, shared = project([listing(ONE, "v1.4.0"), listing(TWO, "2.0.0", 2)], ONE => %w[v1.4.0 v1.5.2 v2.0.0 v2.1.0 v3.0.0], TWO => %w[2.0.0 v3.0.0])
    result = update_plugins(configuration, shared).call(APP)

    assert_equal ["v1.5.2", "2.0.0"], configuration.read(APP).plugins.map(&:ref)
    assert_equal ["#{ONE}: moved from v1.4.0 to v1.5.2; newer incompatible versions: v2.1.0, v3.0.0; crosslint update --latest moves to v3.0.0, or, when v3.0.0 needs a newer CrossLint, to the newest tag below it that this CrossLint reads",
      "#{TWO}: is at its newest compatible tag, 2.0.0; newer incompatible versions: v3.0.0; crosslint update --latest moves to v3.0.0, or, when v3.0.0 needs a newer CrossLint, to the newest tag below it that this CrossLint reads"], result.lines
  end

  def test_names_the_newer_incompatible_versions_with_dry_run_too
    configuration, shared = project([listing(ONE, "v1.4.0")], ONE => %w[v1.4.0 v1.5.0 v2.0.0])
    result = update_plugins(configuration, shared).call(APP, dry_run: true)

    assert_equal ["#{ONE}: would move from v1.4.0 to v1.5.0; newer incompatible versions: v2.0.0; crosslint update --latest moves to v2.0.0, or, when v2.0.0 needs a newer CrossLint, to the newest tag below it that this CrossLint reads"], result.lines
    assert_nil configuration.set
  end

  def test_stays_when_every_compatible_tag_is_lower_and_a_newer_incompatible_version_exists
    configuration, shared = project([listing(ONE, "v1.4.0"), listing(TWO, "v0.0.3", 2)], ONE => %w[v1.2.0 v2.0.0], TWO => %w[v0.0.3 v0.0.4])
    result = update_plugins(configuration, shared).call(APP)

    assert_nil configuration.set
    assert_equal ["#{ONE}: is at its newest compatible tag, v1.4.0; newer incompatible versions: v2.0.0; crosslint update --latest moves to v2.0.0, or, when v2.0.0 needs a newer CrossLint, to the newest tag below it that this CrossLint reads",
      "#{TWO}: is at its newest compatible tag, v0.0.3; newer incompatible versions: v0.0.4; crosslint update --latest moves to v0.0.4, or, when v0.0.4 needs a newer CrossLint, to the newest tag below it that this CrossLint reads"], result.lines
  end

  def test_moves_to_the_highest_version_even_when_it_isnt_compatible_with_latest
    configuration, shared = project([listing(ONE, "v1.4.0"), listing(TWO, "v0.0.3", 2)], ONE => %w[v1.4.0 v1.5.0 v2.0.0 v3.0.0], TWO => %w[v0.0.4])
    result = update_plugins(configuration, shared).call(APP, latest: true)

    assert_equal ["v3.0.0", "v0.0.4"], configuration.read(APP).plugins.map(&:ref)
    assert_equal ["#{ONE}: moved from v1.4.0 to v3.0.0", "#{TWO}: moved from v0.0.3 to v0.0.4"], result.lines
  end

  def test_combines_latest_with_dry_run_and_leaves_pinned_refs_alone
    configuration, shared = project([listing(ONE, "v1.4.0"), listing(TWO, "v1.0.0-rc.1", 2)], ONE => %w[v1.4.0 v2.0.0])
    result = update_plugins(configuration, shared).call(APP, latest: true, dry_run: true)

    assert_equal ["#{ONE}: would move from v1.4.0 to v2.0.0", "#{TWO}: is at v1.0.0-rc.1, which isn't a plain version tag, vX.Y.Z or X.Y.Z, so update leaves it alone"], result.lines
    assert_nil configuration.set
  end

  def test_leaves_a_plugin_whose_repository_has_no_version_tag_where_it_is_with_latest
    configuration, shared = project([listing(ONE, "v1.0.0")], ONE => %w[latest])
    result = update_plugins(configuration, shared).call(APP, latest: true)

    assert_equal ["#{ONE}: has no tag that is a version, vX.Y.Z or X.Y.Z, so it stays at v1.0.0"], result.lines
    assert_nil configuration.set
  end

  def test_says_the_incompatible_tag_it_names_may_need_a_newer_crosslint_without_fetching_it
    configuration, shared = project([listing(ONE, "v1.0.0"), listing(TWO, "v1.0.0", 2)], {ONE => %w[v1.0.0 v1.1.0 v2.0.0], TWO => %w[v1.0.0 v2.0.0]}, {"v2.0.0" => "2"})
    result = update_plugins(configuration, shared).call(APP)

    hint = "crosslint update --latest moves to v2.0.0, or, when v2.0.0 needs a newer CrossLint, to the newest tag below it that this CrossLint reads"
    assert_equal ["#{ONE}: moved from v1.0.0 to v1.1.0; newer incompatible versions: v2.0.0; #{hint}",
      "#{TWO}: is at its newest compatible tag, v1.0.0; newer incompatible versions: v2.0.0; #{hint}"], result.lines
    assert_equal [[ONE, "v1.1.0"]], shared.fetched
  end

  def test_stops_before_reading_a_configuration_that_needs_a_newer_crosslint_and_makes_no_request
    configuration = Memory::MemoryConfiguration.new({APP => Core::Mistake.new("unknown node", file: FILE, line: 2)},
      minimums: {APP => Core::MinimumVersion.parse("2", file: FILE, line: 1)})
    _, shared = project([], ONE => %w[v1.1.0])
    mistake = assert_raises(Core::Mistake) { update_plugins(configuration, shared).call(APP) }

    assert_equal ["#{FILE}:1", "needs CrossLint 2 or later, and this is CrossLint 1.4.0; upgrade CrossLint"], [mistake.location, mistake.message]
    assert_empty @err.string
  end

  def test_skips_each_tag_that_needs_a_newer_crosslint_and_moves_to_the_newest_one_this_crosslint_reads
    configuration, shared = project([listing(ONE, "v1.0.0")], {ONE => %w[v1.0.0 v1.1.0 v1.2.0 v1.3.0 v2.0.0]}, {"v1.3.0" => "1.6", "v1.2.0" => "1.5"})
    result = update_plugins(configuration, shared).call(APP)

    assert_equal ["v1.1.0"], configuration.read(APP).plugins.map(&:ref)
    assert_equal ["#{ONE}: moved from v1.0.0 to v1.1.0; skipped v1.3.0, which needs CrossLint 1.6 or later, and v1.2.0, which needs CrossLint 1.5 or later, " \
      "as this is CrossLint 1.4.0; newer incompatible versions: v2.0.0; crosslint update --latest moves to v2.0.0, or, when v2.0.0 needs a newer CrossLint, to the newest tag below it that this CrossLint reads"], result.lines
    assert_equal [[ONE, "v1.3.0"], [ONE, "v1.2.0"], [ONE, "v1.1.0"]], shared.fetched
  end

  def test_fetches_no_tag_of_a_plugin_that_is_at_its_newest_tag_or_has_none_newer
    configuration, shared = project([listing(ONE, "v1.2.0"), listing(TWO, "v1.0.0", 2)], ONE => %w[v1.0.0 v1.2.0 v2.0.0], TWO => %w[v0.9.0])
    update_plugins(configuration, shared).call(APP)

    assert_empty shared.fetched
  end

  def test_stays_where_it_is_when_every_newer_tag_needs_a_newer_crosslint
    configuration, shared = project([listing(ONE, "v1.0.0")], {ONE => %w[v1.0.0 v1.1.0]}, {"v1.1.0" => "2"})
    result = update_plugins(configuration, shared).call(APP)

    assert_equal [nil, true], [configuration.set, result.updates.first.current?]
    assert_equal ["#{ONE}: stays at v1.0.0; skipped v1.1.0, which needs CrossLint 2 or later, as this is CrossLint 1.4.0"], result.lines
  end

  def test_skips_a_tag_that_needs_a_newer_crosslint_with_latest_and_dry_run_too
    configuration, shared = project([listing(ONE, "v1.0.0")], {ONE => %w[v1.0.0 v2.0.0 v3.0.0]}, {"v3.0.0" => "3"})
    result = update_plugins(configuration, shared).call(APP, latest: true, dry_run: true)

    assert_equal ["#{ONE}: would move from v1.0.0 to v2.0.0; skipped v3.0.0, which needs CrossLint 3 or later, as this is CrossLint 1.4.0"], result.lines
    assert_nil configuration.set
  end

  def test_reads_the_manifest_in_the_folder_a_plugin_is_listed_from
    configuration, shared = project([listing(ONE, "v1.0.0", path: "plugins/a"), listing(ONE, "v1.0.0", 2)], {ONE => %w[v1.0.0 v1.1.0]},
      {"v1.1.0/plugins/a" => "2"})
    update_plugins(configuration, shared).call(APP)

    assert_equal [{[ONE, nil] => "v1.1.0"}], configuration.set
  end

  def test_skips_a_tag_whose_crosslint_line_this_crosslint_cant_read
    configuration, shared = project([listing(ONE, "v1.0.0")], ONE => %w[v1.0.0 v1.1.0 v1.2.0])
    broken = Core::Mistake.new("crosslint is set twice; the first is on line 1", file: "plugin.kdl", line: 3)
    @manifests = BrokenManifests.new(File.expand_path("/cache/v1.2.0") => broken)
    result = update_plugins(configuration, shared).call(APP)

    assert_equal ["#{ONE}: moved from v1.0.0 to v1.1.0; skipped v1.2.0, which has a crosslint line this CrossLint can't read: plugin.kdl:3: crosslint is set " \
      "twice; the first is on line 1, as this is CrossLint 1.4.0"], result.lines
  end

  def test_stops_at_a_tag_it_cant_fetch_naming_the_plugin_and_the_tag_and_changes_nothing
    configuration, = project([listing(ONE, "v1.0.0", 4)], {})
    repository = Memory::MemorySharedPlugins::Repository.new(tags: {"v1.0.0" => "/cache/v1.0.0"}, branches: ["v1.1.0"], commits: {})
    shared = Memory::MemorySharedPlugins.new({ONE => repository}, err: StringIO.new)
    listed = Class.new(SimpleDelegator) { def tags(_url) = %w[v1.0.0 v1.1.0] }.new(shared)
    mistake = assert_raises(Core::Mistake) { update_plugins(configuration, listed).call(APP) }

    assert_equal [FILE, 4, "couldn't fetch shared plugin one from #{ONE} at v1.1.0: v1.1.0 is a branch, and a ref is a tag or a full 40-character commit SHA"],
      [mistake.file, mistake.line, mistake.message]
    assert_nil configuration.set
  end

  def test_says_what_each_plugin_did
    update = ->(ref, newest) { Core::Update.new(listing: listing(ONE, ref), newest:) }
    result = Core::UpdateResult.new(updates: [update.call("v1.0.0", "v1.1.0"), update.call("v1.1.0", "v1.1.0"), update.call("v1.0.0", nil), update.call("main", nil), update.call(nil, "v1.0.0")],
      dry_run: false, crosslint: CROSSLINT)

    assert_equal [[false, false, false], [true, false, false], [false, true, false], [false, false, true], [false, false, true]],
      result.updates.map { |each| [each.current?, each.untagged?, each.pinned?] }
    assert_equal [result.updates.first], result.changes
  end

  private

  def update_plugins(configuration, shared)
    Core::UpdatePlugins.new(configuration:, shared_plugins: shared, manifests: @manifests || Memory::MemoryPluginManifests.new, crosslint: CROSSLINT)
  end

  # A configuration for the project at APP that lists `plugins`, and a
  # port with a repository at each URL that has these tags.
  # Each tag's manifest, in its folder of the cache or in the folder of
  # that given after it, names the CrossLint in `minimums`, by tag.
  def project(plugins, tags, minimums = {})
    held = minimums.to_h { |folder, text| [File.expand_path("/cache/#{folder}"), Core::MinimumVersion.parse(text, file: "plugin.kdl", line: 1)] }
    @manifests = Memory::MemoryPluginManifests.new({}, minimums: held)
    configuration = Core::Configuration.new(file: FILE, plugins:, policies: [], warnings: nil, verbosity: nil)
    @err = StringIO.new
    repositories = tags.transform_values { |names| repository(names) }
    [RecordingConfiguration.new({APP => configuration}), Memory::MemorySharedPlugins.new(repositories, err: @err)]
  end

  def repository(names) = Memory::MemorySharedPlugins::Repository.new(tags: names.to_h { |name| [name, "/cache/#{name}"] }, branches: [], commits: {})

  def listing(name, ref, line = 1, path: nil) = Core::ListedPlugin.new(name:, ref:, path:, settings: [], line:)
end
