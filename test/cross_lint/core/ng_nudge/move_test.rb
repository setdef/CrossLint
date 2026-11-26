# frozen_string_literal: true

require "test_helper"
require "json"

# Core::NgNudge::Move against the in-memory adapters.
class NgNudgeMoveTest < Minitest::Test
  cover "CrossLint::Core::NgNudge::Move*"
  cover "CrossLint::Core::NgNudge::MoveResult*"

  Core = CrossLint::Core
  Memory = CrossLint::Adapters

  APP = File.expand_path("/app")
  RC = ".config/ng-nudge/rc.json"
  NG_DEBT = ".config/ng-nudge/debt.tsv"
  DEBT = ".config/crosslint/debt.tsv"
  CONFIG = ".config/crosslint/config.kdl"

  def test_writes_the_configuration_and_moves_the_debt_file_and_lists_every_change
    world = world({"srcDir" => "./app/"}, comments: %w[later])
    result = world.move

    assert_equal ["write #{CONFIG}, with the plugins angular and debt", "move #{NG_DEBT} to #{DEBT}, byte for byte, with 1 entry",
      %(convert srcDir "./app/" to src-dir "app")], result.changes
    assert_equal [false], [result.dry_run]
    assert_equal ["angular", "debt"], world.configuration.read(APP).plugins.map(&:name)
    assert_equal [["spec-exists", "app/card", "later"]], world.debt_files.read(APP, DEBT).entries.map { |entry| [entry.rule, entry.artifact, entry.comment] }
    refute world.debt_files.exist?(APP, NG_DEBT)
  end

  def test_says_how_many_entries_it_moves
    assert_includes world({}, comments: %w[a b]).move.changes, "move #{NG_DEBT} to #{DEBT}, byte for byte, with 2 entries"
    assert_includes world({}, comments: []).move.changes, "move #{NG_DEBT} to #{DEBT}, byte for byte, with 0 entries"
  end

  def test_lists_every_change_before_it_makes_the_first
    world = world({"$schema" => "x"})
    seen = []
    world.move(planned: ->(changes) { seen << [changes, world.configuration.exist?(APP), world.debt_files.exist?(APP, DEBT)] })

    assert_equal [[["write #{CONFIG}, with the plugins angular and debt", "move #{NG_DEBT} to #{DEBT}, byte for byte, with 1 entry",
      "drop $schema, which CrossLint doesn't read"], false, false]], seen
  end

  def test_makes_no_change_with_dry_run_and_lists_them
    world = world({})
    seen = []
    result = world.move(dry_run: true, planned: ->(changes) { seen << changes })

    assert_equal [seen.first, true], [result.changes, result.dry_run]
    refute world.configuration.exist?(APP)
    assert world.debt_files.exist?(APP, NG_DEBT)
    refute world.debt_files.exist?(APP, DEBT)
  end

  def test_moves_nothing_and_says_nothing_of_a_debt_file_ng_nudge_has_none_of
    world = world({}, debt: false)
    result = world.move

    assert_equal ["write #{CONFIG}, with the plugins angular and debt"], result.changes
    assert world.configuration.exist?(APP)
    refute world.debt_files.exist?(APP, DEBT)
  end

  def test_leaves_the_rules_ng_nudge_never_ran_and_lists_them
    world = world({}, files: {".config/ng-nudge/rules/b.rule.js" => "", ".config/ng-nudge/rules/a.rule.js" => ""})

    assert_equal ["leave .config/ng-nudge/rules/a.rule.js, which ng-nudge never ran", "leave .config/ng-nudge/rules/b.rule.js, which ng-nudge never ran"],
      world.move.changes.last(2)
  end

  def test_refuses_an_artifact_or_a_policy_of_ng_nudges_since_it_changes_what_ng_nudge_checks_and_changes_nothing
    %w[artifacts/store.artifact.js policies/x.policy.js].each do |path|
      world = world({}, files: {".config/ng-nudge/#{path}" => "", ".config/ng-nudge/rules/a.rule.js" => ""})
      mistake = assert_raises(Core::Mistake) { world.move }

      assert_equal [".config/ng-nudge/#{path}", "is a file ng-nudge loads to change what it checks, which CrossLint can't run; declare the same check in a local plugin " \
        "(docs/reference/plugin.md), then move the file out of .config/ng-nudge"], [mistake.file, mistake.message]
      assert_unchanged world
    end
  end

  def test_refuses_to_replace_a_configuration_unless_forced
    world = world({}, existing: true)
    mistake = assert_raises(Core::Mistake) { world.move }

    assert_equal [CONFIG, "already exists, and crosslint init --from-ng-nudge changes nothing in the configuration; " \
      "crosslint init --from-ng-nudge --force replaces it"], [mistake.file, mistake.message]
  end

  def test_replaces_a_configuration_and_a_debt_file_when_forced
    world = world({}, existing: true, own_debt: true)
    result = world.move(force: true)

    assert_equal "replace #{CONFIG}, with the plugins angular and debt", result.changes.first
    assert_equal ["angular", "debt"], world.configuration.read(APP).plugins.map(&:name)
    assert_equal ["app/card"], world.debt_files.read(APP, DEBT).entries.map(&:artifact)
  end

  def test_refuses_to_replace_a_debt_file_unless_forced_and_changes_nothing
    world = world({}, own_debt: true)
    mistake = assert_raises(Core::Mistake) { world.move }

    assert_equal [DEBT, "already exists, and crosslint init --from-ng-nudge changes nothing in the debt file; " \
      "crosslint init --from-ng-nudge --force replaces it"], [mistake.file, mistake.message]
    assert_unchanged world, own_debt: true
  end

  def test_does_not_mind_a_debt_file_of_crosslints_when_ng_nudge_has_none_to_move
    world = world({}, debt: false, own_debt: true)

    assert_equal ["write #{CONFIG}, with the plugins angular and debt"], world.move.changes
    assert_equal ["x"], world.debt_files.read(APP, DEBT).entries.map(&:artifact)
  end

  def test_refuses_a_project_with_no_rc_json
    world = world({}, rc: false)
    mistake = assert_raises(Core::Mistake) { world.move }

    assert_equal [RC, "doesn't exist; crosslint init --from-ng-nudge moves a project that has it, and crosslint init writes a configuration for any other"],
      [mistake.file, mistake.message]
  end

  def test_refuses_a_key_it_cannot_carry_before_it_changes_anything
    world = world({"srcDir" => "../x"})
    mistake = assert_raises(Core::Mistake) { world.move }

    assert_equal [RC, %(srcDir: is "../x", which is outside the project; write a path inside it, relative to the project's root)], [mistake.file, mistake.message]
    assert_unchanged world
  end

  def test_refuses_a_debt_file_with_a_mistake_in_it_before_it_changes_anything
    broken = Core::Mistake.new("has an entry with no rule", file: NG_DEBT, line: 3)
    world = world({}, debt_file: broken)
    mistake = assert_raises(Core::Mistake) { world.move }

    assert_equal [NG_DEBT, 3], [mistake.file, mistake.line]
    refute world.configuration.exist?(APP)
  end

  def test_tests_each_comment_with_javascript_and_with_the_translation_and_goes_on_when_they_agree
    json = {"rules" => {"has-debt" => {"withComment" => {"maxSeverity" => "warning", "matching" => "^TODO"}}}}
    world = world(json, comments: ["TODO fix", "", "later", "TODO fix"], expressions: {"^TODO" => ->(text) { text.start_with?("TODO") }})
    asked = []
    world.javascript.singleton_class.prepend(Module.new { define_method(:matches) { |source, texts| super(source, texts).tap { asked << [source, texts] } } })
    result = world.move

    assert_equal [["^TODO", ["TODO fix", "later"]]], asked
    assert_includes result.changes, %(convert rules.has-debt.withComment.matching "^TODO" to matching "\\\\ATODO")
    assert world.configuration.exist?(APP)
  end

  def test_refuses_a_matching_whose_translation_and_javascript_disagree_on_a_comment_and_changes_nothing
    json = {"rules" => {"has-debt" => {"withComment" => {"maxSeverity" => "warning", "matching" => "^TODO"}}}}
    {true => ["later", "doesn't"], false => ["TODO", "does"]}.each do |javascript, (comment, translation)|
      world = world(json, comments: [comment], expressions: {"^TODO" => ->(_) { javascript }})
      mistake = assert_raises(Core::Mistake) { world.move }
      same = javascript ? "matches" : "doesn't match"

      assert_equal [RC, %(rules.has-debt.withComment.matching: JavaScript #{same} the comment #{comment.dump} of line 2 of the debt file, and its translation, ) +
        %("\\\\ATODO", #{translation}; write the expression another way, or remove it)], [mistake.file, mistake.message]
      assert_unchanged world
    end
  end

  def test_refuses_a_matching_when_javascript_cannot_test_it_and_says_what_javascript_said
    json = {"rules" => {"has-debt" => {"withComment" => {"maxSeverity" => "warning", "matching" => "^TODO"}}}}
    world = world(json, comments: %w[TODO], expressions: {"^TODO" => Core::JavaScriptError.new("couldn't run node")})
    mistake = assert_raises(Core::Mistake) { world.move }

    assert_equal [RC, %(rules.has-debt.withComment.matching: CrossLint tests the expression, "^TODO", with JavaScript on each comment of the debt file, and couldn't run node)],
      [mistake.file, mistake.message]
    assert_unchanged world
  end

  def test_does_not_ask_javascript_when_no_comment_has_a_matching_to_test
    json = {"rules" => {"has-debt" => {"withComment" => {"maxSeverity" => "warning", "matching" => "^TODO"}}}}

    assert_includes world(json, comments: ["", ""]).move.changes.last, "matching"
    assert_includes world(json, comments: [], debt: false).move.changes.last, "matching"
  end

  private

  # A project, with ng-nudge's rc.json for `json`, a debt file with a
  # comment for each of `comments`, and the ports that hold them.
  World = Struct.new(:configuration, :ng_nudge, :debt_files, :javascript) do
    def move(**options) = Core::NgNudge::Move.new(configuration:, ng_nudge:, debt_files:, javascript:).call(APP, **options)
  end

  def world(json, comments: %w[legacy], debt: true, rc: true, existing: false, own_debt: false, files: {}, expressions: nil, debt_file: nil)
    files = files.merge(RC => JSON.generate(json)) if rc
    configuration = Memory::MemoryConfiguration.new
    held = {} #: Hash[String, Core::DebtFile | Core::Mistake]
    if debt
      entries = comments.each_with_index.map do |comment, index|
        Core::DebtEntry.new(rule: "spec-exists", artifact: "app/card", comment:, detail: nil, line: index + 2, source: "spec-exists\tapp/card\t#{comment}\n")
      end
      held[File.join(APP, NG_DEBT)] = debt_file || Core::DebtFile.new(file: NG_DEBT, entries:, header: "Rule\tArtifact\tComment\n")
    end
    if own_debt
      entry = Core::DebtEntry.new(rule: "spec-exists", artifact: "x", comment: "", detail: nil, line: 2, source: "spec-exists\tx\t\n")
      held[File.join(APP, DEBT)] = Core::DebtFile.new(file: DEBT, entries: [entry], header: "Rule\tArtifact\tComment\n")
    end
    configuration.write(APP, Core::Configuration.new(file: CONFIG, plugins: [], policies: [], warnings: nil, verbosity: nil)) if existing
    World.new(configuration, Memory::MemoryNgNudge.new({APP => files}), Memory::MemoryDebtFiles.new(held), Memory::MemoryJavaScript.new(expressions || {}))
  end

  # Nothing written, and nothing moved.
  def assert_unchanged(world, own_debt: false)
    refute world.configuration.exist?(APP)
    assert world.debt_files.exist?(APP, NG_DEBT)
    assert_equal own_debt, world.debt_files.exist?(APP, DEBT)
  end
end
