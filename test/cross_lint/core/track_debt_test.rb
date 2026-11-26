# frozen_string_literal: true

require "test_helper"

# Core::TrackDebt against the in-memory debt-files adapter: what
# docs/design/debt.md requires of matching and updating, with each of
# ng-nudge's defects it lists as a test that it isn't copied.
class TrackDebtTest < Minitest::Test
  cover "CrossLint::Core::TrackDebt*"

  include CrossLint::Core

  ROOT = File.expand_path("/app")

  CONFIG = ".config/crosslint/config.kdl"

  FILE = ".config/crosslint/debt.tsv"

  def setup
    @files = CrossLint::Adapters::MemoryDebtFiles.new
  end

  def test_excuses_each_violation_an_entry_matches
    result = step([violation("lib/a.rb"), violation("lib/b.rb")], [entry("tests/has-test", "lib/a.rb", "later")])

    assert_equal [[violation("lib/a.rb")], [], [], [], ["1 accepted as debt"]],
      [result.excused, result.stale, result.notices, result.violations, result.summary]
  end

  def test_reports_an_entry_no_violation_matches_as_stale
    result = step([], [entry("tests/has-test", "lib/b.rb"), entry("tests/has-test", "lib/a.rb")])

    assert_equal Stale.new(plugin: "tests", policy: "has-test", artifact: "lib/a.rb", file: FILE, line: 3,
      message: "no violation is left for the debt entry at #{FILE}:3; crosslint debt update removes it"), result.stale.last
    assert_equal [[], []], [result.excused, result.summary]
  end

  def test_reads_no_debt_file_as_no_entries
    result = step([violation("lib/a.rb")], nil)

    assert_equal [[], []], [result.excused, result.stale]
  end

  def test_matches_by_plugin_policy_artifact_and_role
    entries = [entry("tests/has-test", "lib/a.rb"), entry("other/has-test", "lib/b.rb"), entry("tests/has-signature", "lib/c.rb"),
      entry("tests/has-test", "lib/d.rb.ruby-file"), entry("tests/has-test", "lib/e.rb.component")]
    violations = %w[a b c d e].map { |name| violation("lib/#{name}.rb") }
    result = step(violations, entries, plugins: %w[tests other])

    assert_equal [violation("lib/a.rb"), violation("lib/d.rb")], result.excused
    assert_equal ["lib/b.rb", "lib/c.rb", "lib/e.rb.component"], result.stale.map(&:artifact)
  end

  # ng-nudge matched by rule and base path alone (lib/debt.js:30-35).
  def test_keeps_a_component_entry_from_excusing_a_service_with_the_same_key
    result = step([violation("app/card", role: "service")], [entry("tests/has-test", "app/card.component")])

    assert_equal [[], ["app/card.component"]], [result.excused, result.stale.map(&:artifact)]
  end

  # ng-nudge's debt file names an Angular artifact by its base path, which
  # the Angular plugin gives its artifacts as their key.
  def test_matches_an_entry_by_the_artifacts_key_alone_or_with_its_role
    violations = [violation("src/app/a.component.ts", role: "component", key: "app/a"),
      violation("src/app/b.component.ts", role: "component", key: "app/b"), violation("src/app/c.component.ts", role: "component", key: "app/c")]
    entries = [entry("tests/has-test", "app/a"), entry("tests/has-test", "app/b.component"), entry("tests/has-test", "app/c.service")]
    result = step(violations, entries)

    assert_equal [violations.first(2), ["app/c.service"]], [result.excused, result.stale.map(&:artifact)]
  end

  def test_matches_no_entry_by_the_key_of_an_artifact_without_one
    result = step([violation("lib/a.rb")], [entry("tests/has-test", ".ruby-file"), entry("tests/has-test", "")])

    assert_equal [[], [".ruby-file", ""]], [result.excused, result.stale.map(&:artifact)]
  end

  # ng-nudge's base path drops the role (lib/artifact/artifact.js:34).
  def test_excuses_both_artifacts_an_ng_nudge_key_names_and_writes_one_entry_for_each
    violations = [violation("src/app/foo.component.ts", role: "component", key: "app/foo"), violation("src/app/foo.service.ts", role: "service", key: "app/foo")]
    result = step(violations, [entry("tests/has-test", "app/foo", "later")])

    assert_equal [violations, 1], [result.excused, result.notices.size]
    assert_match "matches the violations of 2 artifacts", result.notices.first.message
    step(violations, [entry("tests/has-test", "app/foo", "later")], update: true)

    assert_equal [["src/app/foo.component.ts", "later"], ["src/app/foo.service.ts", "later"]], written.map { [it.artifact, it.comment] }
  end

  def test_matches_an_entry_with_a_detail_only_to_that_detail_and_one_without_only_to_none
    violations = [violation("lib/a.rb", detail: "name"), violation("lib/a.rb", detail: "size"), violation("lib/b.rb")]
    result = step(violations, [entry("tests/has-test", "lib/a.rb", detail: "name"), entry("tests/has-test", "lib/b.rb", detail: "name"),
      entry("tests/has-test", "lib/a.rb", line: 4)])

    assert_equal [[violations.first], []], [result.excused, result.notices]
    assert_equal [3, 4], result.stale.map(&:line).sort
  end

  def test_reads_a_policy_name_alone_as_the_policy_of_the_one_listed_plugin_with_it
    result = step([violation("lib/a.rb")], [entry("has-test", "lib/a.rb"), entry("has-signature", "lib/b.rb", line: 3)])

    assert_equal [[violation("lib/a.rb")], [["tests", "has-signature", 3]]],
      [result.excused, result.stale.map { |stale| [stale.plugin, stale.policy, stale.line] }]
  end

  def test_stops_at_a_policy_name_alone_two_listed_plugins_have
    [false, true].each do |update|
      mistake = assert_raises(Mistake) do
        step([], [entry("tests/has-test", "lib/a.rb"), entry("has-test", "lib/a.rb")], plugins: %w[tests other], update:)
      end

      assert_equal [FILE, 3, %(has an entry for "has-test", a policy of tests and other; write it as PLUGIN/POLICY)],
        [mistake.file, mistake.line, mistake.message]
    end
  end

  # ng-nudge's disabled rule returned no violations, so its entries were
  # stale and deleted with their comments (lib/rule/rule.js:39-42,
  # lib/debt.js:45-49).
  def test_leaves_alone_an_entry_for_a_disabled_policy_an_unlisted_plugin_or_a_plugin_that_stopped
    entries = [entry("tests/has-signature", "lib/a.rb", "off for now"), entry("gone/has-test", "lib/a.rb", "elsewhere", line: 3),
      entry("spec-exists", "app/card", "angular later", line: 4), entry("other/has-test", "lib/a.rb", "stopped", line: 5)]
    options = {plugins: %w[tests other], disabled: ["tests/has-signature"], faulted: ["other"]}
    result = step([], entries, **options)

    assert_equal [[], [], []], [result.excused, result.stale, result.notices]
    update = step([], entries, update: true, **options)

    assert_equal ["wrote #{FILE}: 0 entries added, 0 removed"], update.wrote
    assert_equal entries.map(&:source), written.map(&:source)
  end

  # docs/design/debt.md: an entry for a disabled policy, or for a plugin
  # the configuration doesn't list, is neither stale nor reported.
  def test_reports_no_entry_for_a_disabled_policy_an_unlisted_plugin_or_a_plugin_that_stopped_and_reports_the_others
    entries = [entry("tests/has-signature", "lib/a.rb", "off for now"), entry("gone/has-test", "lib/a.rb", "elsewhere", line: 3),
      entry("spec-exists", "app/card", "angular later", line: 4), entry("other/has-test", "lib/a.rb", "stopped", line: 5),
      entry("tests/has-test", "lib/b.rb", "listed", line: 6)]
    result = step([], entries, plugins: %w[tests other], settings: [setting("report-entries")], disabled: ["tests/has-signature"], faulted: ["other"])

    assert_equal [%w[6], [FILE]], [result.violations.map(&:detail), result.violations.map(&:artifact).uniq]
  end

  def test_excuses_both_artifacts_an_entry_matches_with_a_warning_naming_both
    violations = [violation("app/card", role: "component"), violation("app/card", role: "service")]
    result = step(violations, [entry("tests/has-test", "app/other"), entry("tests/has-test", "app/card", "both")])

    assert_equal violations, result.excused
    assert_equal [Notice.new(file: FILE, line: 3, message: "the entry for tests/has-test on app/card matches the violations of 2 artifacts, " \
      "app/card as component and app/card as service; crosslint debt update writes one entry for each")], result.notices
  end

  def test_rewrites_an_entry_two_artifacts_match_as_one_for_each_keyed_with_its_role
    violations = [violation("app/card", role: "service"), violation("app/card", role: "component")]
    result = step(violations, [entry("tests/has-test", "app/card", "both")], update: true)

    assert_equal [["tests/has-test", "app/card.component", "both"], ["tests/has-test", "app/card.service", "both"]],
      written.map { |each| [each.rule, each.artifact, each.comment] }.sort
    assert_equal [[], ["wrote #{FILE}: 0 entries added, 0 removed, 1 rewritten"], ["2 accepted as debt"]],
      [result.notices, result.wrote, result.summary]
  end

  def test_matches_every_detail_with_an_entry_ng_nudge_wrote_with_a_warning
    violations = [violation("app/card", detail: "name"), violation("app/card", detail: "size")]
    result = step(violations, [entry("has-test", "app/card", "legacy"), entry("tests/has-test", "app/list", line: 3)])

    assert_equal violations, result.excused
    assert_equal [Notice.new(file: FILE, line: 2, message: "the entry for tests/has-test on app/card has no detail, so it matches every " \
      "violation of tests/has-test on it; crosslint debt update writes one entry for each, with its detail")], result.notices
  end

  def test_rewrites_an_entry_ng_nudge_wrote_as_one_for_each_violation_with_its_detail_and_comment
    violations = [violation("app/card", detail: "size"), violation("app/card", detail: "name"), violation("app/list")]
    result = step(violations, [entry("has-test", "app/card", "legacy"), entry("has-test", "app/list", "plain", line: 3)], update: true)

    assert_equal [["tests/has-test", "app/card", "legacy", "name"], ["tests/has-test", "app/card", "legacy", "size"], ["has-test", "app/list", "plain", nil]],
      written.map { |each| [each.rule, each.artifact, each.comment, each.detail] }
    assert_equal [[], violations, ["wrote #{FILE}: 0 entries added, 0 removed, 1 rewritten"]], [result.notices, result.excused, result.wrote]
  end

  # glob gave ng-nudge keys with \ on Windows (lib/codebase.js:45-47).
  def test_reads_a_key_with_backslashes_as_slashes_and_writes_it_with_slashes
    result = step([violation("lib/a/b.rb")], [entry("tests/has-test", "lib\\a\\b.rb", "kept"), entry("gone/x", "lib\\c.rb", line: 3)],
      update: true)

    assert_equal [[violation("lib/a/b.rb")], [["lib/a/b.rb", "kept"], ["lib/c.rb", ""]]],
      [result.excused, written.map { |each| [each.artifact, each.comment] }]
    assert_equal ["wrote #{FILE}: 0 entries added, 0 removed, 2 rewritten"], result.wrote
  end

  def test_updates_by_keeping_matching_entries_in_place_dropping_stale_ones_and_adding_new_ones_in_order
    violations = [violation("lib/z.rb"), violation("lib/b.rb", severity: :warning), violation("lib/a.rb", policy: "has-signature"),
      violation("lib/b.rb"), violation("lib/m.rb", detail: "x")]
    entries = [entry("tests/has-test", "lib/b.rb", "why"), entry("tests/has-test", "lib/gone.rb", "fixed", line: 3),
      entry("tests/has-test", "lib/b.rb", "again", line: 4)]
    result = step(violations, entries, update: true)

    assert_equal [["tests/has-test", "lib/b.rb", "why", nil], ["tests/has-signature", "lib/a.rb", "", nil], ["tests/has-test", "lib/m.rb", "", "x"],
      ["tests/has-test", "lib/z.rb", "", nil]], written.map { |each| [each.rule, each.artifact, each.comment, each.detail] }
    assert_equal "src2", written.first.source
    assert_equal ["wrote #{FILE}: 3 entries added, 2 removed"], result.wrote
    assert_equal written.sort_by(&:artifact), step(violations.reverse, entries, update: true).then { written.sort_by(&:artifact) }
  end

  def test_a_dry_run_lists_what_an_update_would_add_and_remove_in_the_order_it_writes_them_and_writes_nothing
    violations = [violation("lib/z.rb"), violation("lib/b.rb", severity: :warning), violation("lib/a.rb", policy: "has-signature"),
      violation("lib/m.rb", detail: "x")]
    entries = [entry("tests/has-test", "lib/b.rb", "why"), entry("tests/has-test", "lib/gone.rb", "fixed", line: 3),
      entry("tests/has-test", "lib/old.rb", "also fixed", line: 4)]
    dry = step(violations, entries, update: true, dry_run: true)
    before = written
    real = step(violations, entries, update: true)

    assert_equal entries, before
    assert_equal ["would remove tests/has-test on lib/gone.rb, line 3", "would remove tests/has-test on lib/old.rb, line 4",
      "would add tests/has-signature on lib/a.rb", "would add tests/has-test on lib/m.rb (x)", "would add tests/has-test on lib/z.rb",
      "would write #{FILE}: 3 entries added, 2 removed"], dry.wrote
    assert_equal ["wrote #{FILE}: 3 entries added, 2 removed"], real.wrote
    assert_equal [dry.excused, dry.stale], [[violation("lib/b.rb", severity: :warning)], [stale_at(3), stale_at(4)]]
  end

  def test_a_dry_run_matches_an_entry_written_with_backslashes_as_one_written_with_slashes
    dry = step([violation("lib/a/b.rb")], [entry("tests/has-test", "lib\\a\\b.rb", "kept")], update: true, dry_run: true)

    assert_equal [[violation("lib/a/b.rb")], [], ["would write #{FILE}: 0 entries added, 0 removed, 1 rewritten"]], [dry.excused, dry.stale, dry.wrote]
    assert_equal ["lib\\a\\b.rb"], written.map(&:artifact)
  end

  def test_a_dry_run_says_which_entry_it_would_replace_with_which
    violations = [violation("app/card", role: "service"), violation("app/card", role: "component")]
    dry = step(violations, [entry("tests/has-test", "app/card", "both")], update: true, dry_run: true)

    assert_equal ["would replace tests/has-test on app/card, line 2", "would add tests/has-test on app/card.component",
      "would add tests/has-test on app/card.service", "would write #{FILE}: 0 entries added, 0 removed, 1 rewritten"], dry.wrote
    assert_equal [entry("tests/has-test", "app/card", "both")], written
  end

  def test_a_dry_run_flag_without_the_update_command_changes_nothing
    result = step([violation("lib/a.rb")], nil, dry_run: true)

    assert_equal [], result.wrote
    assert_equal [], written
  end

  # ng-nudge reported the state before the update, so a run that just
  # removed a stale entry still said to run --update-debt
  # (lib/verification-task.js:25-39).
  def test_reports_the_state_the_update_left
    result = step([violation("lib/a.rb")], [entry("tests/has-test", "lib/gone.rb")], update: true)

    assert_equal [[violation("lib/a.rb")], [], ["1 accepted as debt"], ["wrote #{FILE}: 1 entry added, 1 removed"]],
      [result.excused, result.stale, result.summary, result.wrote]
  end

  def test_writes_a_file_that_doesnt_exist
    step([violation("lib/a.rb")], nil, update: true)

    assert_equal [["tests/has-test", "lib/a.rb"]], written.map { |each| [each.rule, each.artifact] }
  end

  # A violation with no rule name made ng-nudge write an empty rule
  # (lib/violation.js:20, lib/debt.js:4-13).
  def test_writes_every_entry_with_its_plugin_and_policy
    step([violation("lib/a.rb", plugin: "other", policy: "names-class")], nil, update: true, plugins: %w[tests other])

    assert_equal ["other/names-class"], written.map(&:rule)
  end

  def test_takes_the_update_only_from_the_command_update
    result = step([violation("lib/a.rb")], nil, command: "other")

    assert_equal [[], nil], [result.wrote, @files.read(ROOT, FILE).header]
    assert_equal [[], nil], [step([violation("lib/a.rb")], nil).wrote, @files.read(ROOT, FILE).header]
  end

  def test_reads_the_debt_file_the_settings_give
    @files.write(ROOT, "debt/other.tsv", DebtFile.new(file: "debt/other.tsv", entries: [entry("tests/has-test", "lib/a.rb")], header: nil))
    result = step([violation("lib/a.rb")], nil, settings: [setting("file", "debt/other.tsv")])

    assert_equal [violation("lib/a.rb")], result.excused
  end

  def test_reports_no_entry_unless_the_settings_say_to
    assert_empty step([], [entry("tests/has-test", "lib/a.rb", "why")]).violations
  end

  def test_reports_each_entry_as_a_violation_of_has_debt_at_its_severity
    entries = [entry("tests/has-test", "lib/a.rb", "why"), entry("tests/has-test", "lib/b.rb", line: 3)]
    result = step([violation("lib/a.rb"), violation("lib/b.rb")], entries, settings: [setting("report-entries")])

    assert_equal [debt_violation("line 2 lists tests/has-test on lib/a.rb as debt: why", :error, "2"),
      debt_violation("line 3 lists tests/has-test on lib/b.rb as debt, with no comment", :error, "3")], result.violations
    assert_equal [:warning, :warning], step([], entries, settings: [setting("report-entries")], severity: :warning).violations.map(&:severity)
  end

  def test_reports_an_entry_with_a_comment_at_the_severity_commented_gives
    entries = [entry("tests/has-test", "lib/a.rb", "ticket 12"), entry("tests/has-test", "lib/b.rb", "someday", line: 3),
      entry("tests/has-test", "lib/c.rb", line: 4)]
    severities = %w[warning none error].to_h do |commented|
      [commented, step([], entries, settings: [setting("report-entries", commented:)], severity: :warning).violations.map(&:severity)]
    end

    assert_equal({"warning" => %i[warning warning warning], "none" => [:warning], "error" => %i[error error warning]}, severities)
    matching = step([], entries, settings: [setting("report-entries", commented: "none", matching: "ticket \\d+")]).violations

    assert_equal [["3", :error], ["4", :error]], matching.map { |each| [each.detail, each.severity] }
  end

  def test_reports_no_entry_when_has_debt_is_disabled
    assert_empty step([], [entry("tests/has-test", "lib/a.rb")], settings: [setting("report-entries")], disabled: ["debt/has-debt"]).violations
  end

  # ng-nudge's --update-debt recorded the debt file's own violations
  # with the others (lib/config/debt-file.js:70-74).
  def test_never_records_its_own_violations
    step([], [entry("tests/has-test", "lib/a.rb")], update: true, settings: [setting("report-entries")])

    assert_empty written
  end

  def test_reports_has_debt_as_its_policy_and_reads_its_settings_through_check_settings
    track = TrackDebt.new(debt_files: @files)

    assert_equal ["has-debt"], track.policies
    mistake = assert_raises(Mistake) { track.check_settings([setting("file", "/abs.tsv")], CONFIG) }

    assert_equal [CONFIG, 2], [mistake.file, mistake.line]
  end

  def test_reads_the_settings
    assert_equal TrackDebt::Settings.new(file: FILE, report: nil), TrackDebt.settings([], CONFIG)
    settings = TrackDebt.settings([setting("file", "debt.tsv"), setting("report-entries", commented: "warning", matching: "^T-")], CONFIG)

    assert_equal ["debt.tsv", :warning, /^T-/], [settings.file, settings.report&.commented, settings.report&.matching]
    assert_equal [nil, nil], TrackDebt.settings([setting("report-entries")], CONFIG).report.then { |report| [report&.commented, report&.matching] }
  end

  # The KDL adapter gives each string as a String that knows its line.
  def test_reads_settings_whose_strings_are_of_a_kind_of_string
    word = Class.new(String)
    settings = TrackDebt.settings([setting("file", word.new("d.tsv")), setting("report-entries", matching: word.new("x"))], CONFIG)

    assert_equal ["d.tsv", /x/], [settings.file, settings.report&.matching]
  end

  def test_accepts_a_path_whose_names_merely_contain_two_dots
    path = "a..b/..c/d..tsv"

    assert_equal path, TrackDebt.settings([setting("file", path)], CONFIG).file
  end

  def test_stops_at_a_setting_it_cant_use_naming_the_line
    {
      [setting("file", "a.tsv"), setting("file", "b.tsv", line: 3)] => "file is set twice; the first is on line 2",
      [setting("file", "a.tsv").with(children: [setting("x")])] => "file takes no settings inside it",
      [setting("file")] => %(file takes one path and nothing else, as in file "#{FILE}"),
      [setting("file", "a", "b")] => %(file takes one path and nothing else, as in file "#{FILE}"),
      [setting("file", 1)] => %(file takes one path and nothing else, as in file "#{FILE}"),
      [setting("file", "a", x: "y")] => %(file takes one path and nothing else, as in file "#{FILE}"),
      [setting("file", "")] => %(file takes a path relative to the project's root, not ""),
      [setting("file", "/tmp/debt.tsv")] => %(file takes a path relative to the project's root, not "/tmp/debt.tsv"),
      [setting("file", "C:/abs.tsv")] => %(file takes a path relative to the project's root, not "C:/abs.tsv"),
      [setting("file", "\\abs.tsv")] => %(file takes a path relative to the project's root, not "\\\\abs.tsv"),
      [setting("file", "../debt.tsv")] => %(file takes a path relative to the project's root, not "../debt.tsv"),
      [setting("file", "a/../../debt.tsv")] => %(file takes a path relative to the project's root, not "a/../../debt.tsv"),
      [setting("file", "a\\..\\debt.tsv")] => %(file takes a path relative to the project's root, not "a\\\\..\\\\debt.tsv"),
      [setting("report-entries", "x")] => "report-entries takes no arguments, only commented= and matching=",
      [setting("report-entries", comented: "none", maching: "x")] => %(unknown property "comented", did you mean "commented"? for report-entries),
      [setting("report-entries", commented: "warn")] => %(commented= takes "error", "warning", or "none", not "warn"),
      [setting("report-entries", commented: true)] => %(commented= takes "error", "warning", or "none", not true),
      [setting("report-entries", matching: 1)] => "matching= takes a regular expression, as a string",
      [setting("report-entries", matching: "(")] => "matching= isn't a regular expression CrossLint reads: end pattern with unmatched parenthesis: /(/"
    }.each do |settings, message|
      mistake = assert_raises(Mistake) { TrackDebt.settings(settings, CONFIG) }

      assert_equal [CONFIG, settings.last.line, message], [mistake.file, mistake.line, mistake.message]
    end
  end

  def test_matches_an_entry_with_a_policy_name_alone_and_a_detail_only_to_that_detail
    violations = [violation("app/card", detail: "name"), violation("app/card", detail: "size")]
    result = step(violations, [entry("has-test", "app/card", detail: "size")])

    assert_equal [[violations.last], []], [result.excused, result.notices]
  end

  def test_checks_an_entry_whatever_the_configuration_says_of_other_policies
    entries = [entry("gone/has-test", "lib/a.rb"), entry("tests/has-test", "lib/a.rb")]
    result = step([], entries, disabled: ["tests/has-signature"], extra: [PolicySetting.new(name: "tests/has-test", enabled: nil, severity: :warning, line: 7)])

    assert_equal [3], result.stale.map(&:line)
  end

  def test_writes_one_entry_for_violations_with_one_identity
    step([violation("lib/a.rb"), violation("lib/a.rb").with(message: "other")], nil, update: true)

    assert_equal ["lib/a.rb"], written.map(&:artifact)
  end

  def test_keys_a_new_entry_with_its_role_only_when_its_policy_has_another_artifact_with_that_key
    violations = [violation("app/card", role: "component"), violation("app/card", role: "service", policy: "has-signature"),
      violation("app/card", role: "service", plugin: "other")]
    step(violations, nil, update: true, plugins: %w[tests other])

    assert_equal ["app/card", "app/card", "app/card"], written.map(&:artifact)
  end

  def test_reads_the_severity_of_has_debt_among_the_configurations_other_policy_lines
    extra = [PolicySetting.new(name: "tests/has-test", enabled: nil, severity: :error, line: 7)]
    result = step([], [entry("tests/has-test", "lib/a.rb")], settings: [setting("report-entries")], disabled: ["tests/has-signature"],
      severity: :warning, extra:)

    assert_equal [:warning], result.violations.map(&:severity)
  end

  def test_stops_at_settings_it_cant_use_when_it_runs
    mistake = assert_raises(Mistake) { step([], nil, settings: [setting("file", "/abs.tsv")]) }

    assert_equal [CONFIG, 2], [mistake.file, mistake.line]
  end

  private

  def violation(artifact, plugin: "tests", policy: "has-test", role: "ruby-file", detail: nil, severity: :error, key: nil)
    Violation.new(plugin:, policy:, artifact:, role:, message: "no test", severity:, detail:, key:)
  end

  def stale_at(line)
    gone = {3 => "lib/gone.rb", 4 => "lib/old.rb"}.fetch(line)
    Stale.new(plugin: "tests", policy: "has-test", artifact: gone, file: FILE, line:,
      message: "no violation is left for the debt entry at #{FILE}:#{line}; crosslint debt update removes it")
  end

  def debt_violation(message, severity, line)
    Violation.new(plugin: "debt", policy: "has-debt", artifact: FILE, role: "debt-file", message:, severity:, detail: line)
  end

  def entry(rule, artifact, comment = "", detail: nil, line: 2)
    DebtEntry.new(rule:, artifact:, comment:, detail:, line:, source: "src#{line}")
  end

  def setting(name, *arguments, line: 2, **properties)
    Setting.new(name:, arguments:, properties: properties.transform_keys(&:to_s), children: [], line:)
  end

  def written = @files.read(ROOT, FILE).entries

  def plugin(name, policies)
    manifest = Manifest.new(file: "#{name}/plugin.kdl", artifacts: [], rules: [], helpers: [], policies: policies.map do |policy|
      Policy.new(name: policy, applies_to: AppliesTo.new(artifact: "ruby-file", line: 2), condition: nil, rules: [], line: 1)
    end)
    Plugin.new(name:, folder: "#{ROOT}/#{name}", manifest:, listing: ListedPlugin.new(name: "./#{name}", ref: nil, settings: [], line: 1))
  end

  def step(violations, entries, plugins: %w[tests], settings: [], disabled: [], faulted: [], update: false, command: nil, severity: nil, extra: [], dry_run: false)
    @files.write(ROOT, FILE, DebtFile.new(file: FILE, entries:, header: nil)) if entries
    debt = plugin("debt", []).then { |found| found.with(listing: found.listing.with(name: "debt", settings:)) }
    listed = {"tests" => %w[has-test has-signature], "other" => %w[has-test names-class]}.slice(*plugins).map { |name, owned| plugin(name, owned) }
    policies = disabled.map { |name| PolicySetting.new(name:, enabled: false, severity: nil, line: 5) }
    policies << PolicySetting.new(name: "debt/has-debt", enabled: nil, severity:, line: 6) if severity
    policies.concat(extra)
    configuration = Configuration.new(file: CONFIG, plugins: [debt, *listed].map(&:listing), policies:, warnings: nil, verbosity: nil)
    project = Project.new(root: ROOT, configuration:, plugins: [debt, *listed])
    TrackDebt.new(debt_files: @files).call(StepInput.new(project:, plugin: debt, violations:, faulted:, command: update ? "update" : command,
      flags: dry_run ? {"dry-run" => true} : {}))
  end
end
