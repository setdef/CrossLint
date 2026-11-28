# frozen_string_literal: true

require "test_helper"
require "json"

# Core::NgNudge::Rc: what each key of ng-nudge 0.3.0's rc.json becomes, and
# what stops the conversion.
class NgNudgeRcTest < Minitest::Test
  cover "CrossLint::Core::NgNudge::Rc*"
  cover "CrossLint::Core::NgNudge::Matching*"

  Core = CrossLint::Core
  FILE = ".config/ng-nudge/rc.json"

  def test_converts_an_empty_configuration_to_the_angular_and_debt_plugins_with_no_settings
    result = convert({})

    assert_equal [["angular", []], ["debt", []]], shape(result)
    assert_empty result.configuration.policies
    assert_equal [nil, nil, ".config/crosslint/config.kdl"], [result.configuration.warnings, result.configuration.verbosity, result.configuration.file]
    assert_empty result.changes
    assert_nil result.matching
  end

  def test_drops_schema_and_lists_it
    result = convert({ "$schema" => "./node_modules/@x/ng-nudge/rc.schema.json" })

    assert_equal [["angular", []], ["debt", []]], shape(result)
    assert_equal ["drop $schema, which CrossLint doesn't read"], result.changes
  end

  def test_converts_src_dir_and_ts_config_with_dot_slash_double_slash_and_a_trailing_slash_cleaned_up
    result = convert({ "srcDir" => "./projects//app/", "tsConfig" => "./config/../tsconfig.app.json" })

    assert_equal [["angular", [["src-dir", ["projects/app"], {}, []], ["tsconfig", ["tsconfig.app.json"], {}, []]]], ["debt", []]], shape(result)
    assert_equal [%(convert srcDir "./projects//app/" to src-dir "projects/app"), %(convert tsConfig "./config/../tsconfig.app.json" to tsconfig "tsconfig.app.json")],
      result.changes
  end

  def test_keeps_a_src_dir_and_a_ts_config_that_need_no_cleaning_without_listing_them
    result = convert({ "srcDir" => "app", "tsConfig" => "tsconfig.spec.json" })

    assert_equal [["angular", [["src-dir", ["app"], {}, []], ["tsconfig", ["tsconfig.spec.json"], {}, []]]], ["debt", []]], shape(result)
    assert_empty result.changes
  end

  def test_leaves_out_a_src_dir_and_a_ts_config_that_are_the_defaults
    ["src", "./src", "src/", ".//src//", "x/../src", "a/b/../../src", "a/b/../b/../../src"].each do |path|
      result = convert({ "srcDir" => path, "tsConfig" => "./tsconfig.json" })

      assert_equal [["angular", []], ["debt", []]], shape(result), path
      assert_empty result.changes
    end
  end

  def test_reads_an_empty_src_dir_and_ts_config_as_the_defaults_as_ng_nudge_does
    assert_equal [["angular", []], ["debt", []]], shape(convert({ "srcDir" => "", "tsConfig" => "" }))
  end

  def test_takes_out_the_folder_each_dot_dot_follows_not_the_first_one
    result = convert({ "srcDir" => "a/b/../c", "tsConfig" => "x/y/z/../../w.json" })

    assert_equal [["src-dir", ["a/c"]], ["tsconfig", ["x/w.json"]]], shape(result).first.last.map { |setting| setting.first(2) }
  end

  def test_gives_the_folder_the_angular_plugin_looks_in_and_the_seven_roles_it_finds_by_default
    result = convert({})
    roles = %w[component directive pipe service guard resolver interceptor]

    assert_equal "src", result.src_dir
    assert_equal roles.map { |role| [role, "**/*.#{role}.ts", "{path}.#{role}.ts"] }, result.roles.map { |role| [role.name, role.glob, role.files] }
  end

  def test_gives_the_src_dir_cleaned_up_whether_or_not_it_is_a_setting
    assert_equal ["app", "src", "src", "x/y"], [
      convert({ "srcDir" => "./app/" }).src_dir,
      convert({ "srcDir" => "" }).src_dir,
      convert({ "srcDir" => "src/" }).src_dir,
      convert({ "srcDir" => "x//y" }).src_dir,
]
  end

  def test_gives_each_role_the_configuration_changes_or_adds_after_the_built_in_ones
    result = convert({ "artifacts" => { "page" => {}, "service" => { "pattern" => "app/*/**/*.svc.ts" }, "store" => { "pattern" => "**/*.store.ts" }, "pipe" => { "pattern" => "" } } })

    assert_equal [
      ["component", "**/*.component.ts", "{path}.component.ts"],
      ["directive", "**/*.directive.ts", "{path}.directive.ts"],
      ["pipe", "**/*.pipe.ts", "{path}.pipe.ts"],
      ["service", "app/*/**/*.svc.ts", "app/{name}/{path}.svc.ts"],
      ["guard", "**/*.guard.ts", "{path}.guard.ts"],
      ["resolver", "**/*.resolver.ts", "{path}.resolver.ts"],
      ["interceptor", "**/*.interceptor.ts", "{path}.interceptor.ts"],
      ["page", "**/*.page.ts", "{path}.page.ts"],
      ["store", "**/*.store.ts", "{path}.store.ts"],
], result.roles.map { |role| [role.name, role.glob, role.files] }
  end

  def test_converts_a_src_dir_of_the_project_root_to_an_empty_one
    result = convert({ "srcDir" => "." })

    assert_equal [["angular", [["src-dir", [""], {}, []]]], ["debt", []]], shape(result)
    assert_equal [%(convert srcDir "." to src-dir "")], result.changes
  end

  def test_refuses_a_src_dir_or_ts_config_it_cannot_carry
    outside = "is %s, which is outside the project; write a path inside it, relative to the project's root"
    {
      "../app" => outside, "a/../../app" => outside, "/srv/app" => outside, "C:/app" => outside, "c:app" => outside
    }.each do |path, message|
      assert_refused "srcDir: #{format(message, path.dump)}", { "srcDir" => path }
      assert_refused "tsConfig: #{format(message, path.dump)}", { "tsConfig" => path }
    end
    ["a\\b", "a{b,c}", "a}"].each do |path|
      assert_refused "srcDir: is #{path.dump}, which has a \\ or a brace; CrossLint reads neither, so write / between folders and no brace", { "srcDir" => path }
    end
    assert_refused %(srcDir: is 5, and it takes a path as a string, such as "src"), { "srcDir" => 5 }
    assert_refused %(srcDir: is null, and it takes a path as a string, such as "src"), { "srcDir" => nil }
    assert_refused %(tsConfig: is ["a"], and it takes a path as a string, such as "tsconfig.json"), { "tsConfig" => ["a"] }
    assert_refused %(tsConfig: is ".", which is no file; write the path of the tsconfig.json to read), { "tsConfig" => "." }
  end

  def test_converts_each_role_with_its_pattern_and_expects
    result = convert({
"artifacts" => {
      "store" => { "pattern" => "**/*.store.ts", "expects" => ["spec"] },
      "service" => { "expects" => [] },
      "util" => { "pattern" => "app/*/**/*.util.ts" },
      "page" => {},
    },
})
    roles = shape(result).first.last

    assert_equal [
      ["role", ["store"], { "files" => "{path}.store.ts" }, [["expects", ["spec"], {}, []]]],
      ["role", ["service"], {}, [["expects", [], {}, []]]],
      ["role", ["util"], { "files" => "app/{name}/{path}.util.ts" }, []],
      ["role", ["page"], {}, []],
], roles
    assert_equal [
      %(convert artifacts.store.pattern "**/*.store.ts" to files "{path}.store.ts"),
      %(convert artifacts.util.pattern "app/*/**/*.util.ts" to files "app/{name}/{path}.util.ts"),
], result.changes
  end

  def test_keeps_a_pattern_that_is_already_a_path_pattern_without_listing_it
    result = convert({ "artifacts" => { "main" => { "pattern" => "main.ts" } } })

    assert_equal [["role", ["main"], { "files" => "main.ts" }, []]], shape(result).first.last
    assert_empty result.changes
  end

  def test_reads_an_empty_pattern_as_the_default_as_ng_nudge_does
    assert_equal [["role", ["store"], {}, []]], shape(convert({ "artifacts" => { "store" => { "pattern" => "" } } })).first.last
  end

  def test_refuses_a_pattern_and_names_the_role_and_the_reason
    assert_refused %(artifacts.store.pattern: is "**/*.{a,b}.ts", which has a brace list; CrossLint's path patterns have none, so list a role for each file name),
      { "artifacts" => { "store" => { "pattern" => "**/*.{a,b}.ts" } } }
    assert_refused %(artifacts.store.pattern: is "app/?.ts", which has ?, which CrossLint's path patterns don't have), { "artifacts" => { "store" => { "pattern" => "app/?.ts" } } }
    assert_refused %(artifacts.store.pattern: is 5, and it takes a glob pattern as a string), { "artifacts" => { "store" => { "pattern" => 5 } } }
  end

  def test_refuses_an_expects_other_than_an_empty_list_or_spec_and_says_why
    why = "and CrossLint's Angular plugin takes [] or [\"spec\"] only; in ng-nudge 0.3.0 any expects list turned the role's checks off, " \
      "so the setting never did what it says. Remove it, or write one of those"
    [["stub"], ["spec", "stub"], ["spec", "spec"], "spec", nil, {}].each do |expects|
      assert_refused "artifacts.store.expects: is #{JSON.generate(expects)}, #{why}", { "artifacts" => { "store" => { "expects" => expects } } }
    end
  end

  def test_refuses_a_role_or_artifacts_it_cannot_carry
    assert_refused "artifacts.my store: has a role name with a character other than a letter, digit, - or _, which a CrossLint role can't have; rename it",
      { "artifacts" => { "my store" => {} } }
    assert_refused %(artifacts.store.patern: unknown key "patern", did you mean "pattern"?; ng-nudge reads only these, so remove it),
      { "artifacts" => { "store" => { "patern" => "x" } } }
    assert_refused "artifacts.store: is [1], and it takes an object in braces", { "artifacts" => { "store" => [1] } }
    assert_refused "artifacts: is null, and it takes an object in braces", { "artifacts" => nil }
  end

  def test_converts_a_rules_enabled_and_severity_to_a_policy_line_of_the_angular_plugin
    result = convert({
"rules" => {
      "spec-exists" => { "enabled" => false },
      "stub-exists" => { "severity" => "warning" },
      "interface-exists" => { "enabled" => false, "severity" => "error" },
      "stub-matches-component" => { "enabled" => true },
      "interface-matches-component" => {},
      "prefer-css-over-scss" => { "enabled" => true, "severity" => "error" },
    },
})

    assert_equal [
      ["angular/spec-exists", false, nil],
      ["angular/stub-exists", nil, :warning],
      ["angular/interface-exists", false, :error],
      ["angular/prefer-css-over-scss", nil, :error],
], result.configuration.policies.map { |policy| [policy.name, policy.enabled, policy.severity] }
    assert_empty result.changes
  end

  def test_gives_a_rule_with_no_severity_none_so_the_plugins_declared_severity_applies
    policy = convert({ "rules" => { "prefer-css-over-scss" => { "enabled" => false } } }).configuration.policies.fetch(0)

    assert_equal ["angular/prefer-css-over-scss", false, nil], [policy.name, policy.enabled, policy.severity]
  end

  def test_converts_the_debt_rules_enabled_and_severity_to_a_policy_line_of_the_debt_plugin
    result = convert({ "rules" => { "has-debt" => { "severity" => "warning", "enabled" => false } } })

    assert_equal [["debt/has-debt", false, :warning]], result.configuration.policies.map { |policy| [policy.name, policy.enabled, policy.severity] }
    assert_empty result.changes
  end

  def test_refuses_a_rule_it_cannot_carry
    assert_refused %(rules.spec-exist: unknown rule "spec-exist", did you mean "spec-exists"?; ng-nudge has no other, so remove it), { "rules" => { "spec-exist" => {} } }
    assert_refused %(rules.zzzzzzzz: unknown rule "zzzzzzzz"; expected "spec-exists", "stub-exists", "interface-exists", "stub-matches-component", ) +
      %("interface-matches-component", "prefer-css-over-scss", or "has-debt"; ng-nudge has no other, so remove it), { "rules" => { "zzzzzzzz" => {} } }
    assert_refused "rules.spec-exists.withComment: is a setting of has-debt only; remove it", { "rules" => { "spec-exists" => { "withComment" => true } } }
    assert_refused %(rules.spec-exists.sev: unknown key "sev"; expected "enabled", "severity", or "withComment"; ng-nudge reads only these, so remove it), { "rules" => { "spec-exists" => { "sev" => "error" } } }
    assert_refused %(rules.spec-exists.enabled: is "no", and it takes true or false), { "rules" => { "spec-exists" => { "enabled" => "no" } } }
    assert_refused %(rules.spec-exists.enabled: is null, and it takes true or false), { "rules" => { "spec-exists" => { "enabled" => nil } } }
    assert_refused %(rules.spec-exists.severity: is "fatal", and it takes "error" or "warning"), { "rules" => { "spec-exists" => { "severity" => "fatal" } } }
    assert_refused "rules.spec-exists: is true, and it takes an object in braces", { "rules" => { "spec-exists" => true } }
    assert_refused "rules: is [], and it takes an object in braces", { "rules" => [] }
  end

  def test_gives_no_report_entries_when_the_debt_rule_has_no_with_comment
    result = convert({ "rules" => { "has-debt" => { "severity" => "error" } } })

    assert_equal [["angular", []], ["debt", []]], shape(result)
  end

  def test_reads_with_comment_as_a_ceiling_on_the_severity_of_an_entry_with_a_comment
    { false => {}, "error" => {}, true => { "commented" => "warning" }, "none" => { "commented" => "none" }, "warning" => { "commented" => "warning" } }.each do |given, properties|
      result = convert({ "rules" => { "has-debt" => { "withComment" => given } } })

      assert_equal [["angular", []], ["debt", [["report-entries", [], properties, []]]]], shape(result), given.inspect
      assert_nil result.matching
      assert_empty result.changes, given.inspect
    end
  end

  def test_reads_a_with_comment_object_with_only_a_max_severity_as_that_string
    { "none" => { "commented" => "none" }, "warning" => { "commented" => "warning" }, "error" => {} }.each do |ceiling, properties|
      result = convert({ "rules" => { "has-debt" => { "withComment" => { "maxSeverity" => ceiling } } } })

      assert_equal [["angular", []], ["debt", [["report-entries", [], properties, []]]]], shape(result), ceiling
    end
  end

  def test_translates_the_matching_of_a_with_comment_object_and_lists_the_change
    result = convert({ "rules" => { "has-debt" => { "withComment" => { "maxSeverity" => "warning", "matching" => "^TODO" } } } })

    assert_equal [["angular", []], ["debt", [["report-entries", [], { "commented" => "warning", "matching" => '\ATODO' }, []]]]], shape(result)
    assert_equal [%(convert rules.has-debt.withComment.matching "^TODO" to matching "\\\\ATODO")], result.changes
    assert_equal [Core::NgNudge::Matching.new(key: "rules.has-debt.withComment.matching", source: "^TODO", translated: '\ATODO')], [result.matching]
  end

  def test_keeps_a_matching_that_needs_no_translation_without_listing_it
    result = convert({ "rules" => { "has-debt" => { "withComment" => { "maxSeverity" => "none", "matching" => "ticket-\\d+" } } } })

    assert_equal [["angular", []], ["debt", [["report-entries", [], { "commented" => "none", "matching" => 'ticket-\d+' }, []]]]], shape(result)
    assert_empty result.changes
    assert_equal "ticket-\\d+", result.matching&.source
  end

  def test_drops_a_matching_with_a_ceiling_of_error_since_it_changes_no_severity_and_lists_it
    result = convert({ "rules" => { "has-debt" => { "withComment" => { "maxSeverity" => "error", "matching" => "(?i)x" } } } })

    assert_equal [["angular", []], ["debt", [["report-entries", [], {}, []]]]], shape(result)
    assert_equal ['drop rules.has-debt.withComment.matching, which changes nothing with a maxSeverity of "error"'], result.changes
    assert_nil result.matching
  end

  def test_reads_an_empty_matching_as_none_as_ng_nudge_does
    result = convert({ "rules" => { "has-debt" => { "withComment" => { "maxSeverity" => "none", "matching" => "" } } } })

    assert_equal [["angular", []], ["debt", [["report-entries", [], { "commented" => "none" }, []]]]], shape(result)
    assert_nil result.matching
    assert_empty result.changes
  end

  def test_refuses_a_with_comment_it_cannot_carry
    key = "rules.has-debt.withComment"
    forms = "it takes true, false, \"none\", \"warning\", \"error\", or an object with maxSeverity and matching"
    assert_refused "#{key}: is null, and #{forms}", with_comment(nil)
    assert_refused "#{key}: is 3, and #{forms}", with_comment(3)
    assert_refused "#{key}: is [], and #{forms}", with_comment([])
    assert_refused %(#{key}: is "all", and it takes "none", "warning", or "error"), with_comment("all")
    assert_refused %(#{key}.maxSeverity: is missing, and withComment as an object takes it, as "none", "warning", or "error"), with_comment({ "matching" => "x" })
    assert_refused %(#{key}.maxSeverity: is "fatal", and it takes "none", "warning", or "error"), with_comment({ "maxSeverity" => "fatal" })
    assert_refused_all [
      %(#{key}.maxSeverty: unknown key "maxSeverty", did you mean "maxSeverity"?; ng-nudge reads only these, so remove it),
      %(#{key}.maxSeverity: is missing, and withComment as an object takes it, as "none", "warning", or "error"),
], with_comment({ "maxSeverty" => "none" })
    assert_refused %(#{key}.matching: is 5, and it takes a JavaScript regular expression as a string), with_comment({ "maxSeverity" => "none", "matching" => 5 })
  end

  def test_refuses_a_matching_it_cannot_translate_and_names_the_reason
    assert_refused %(rules.has-debt.withComment.matching: is "\\\\p{L}", which has \\p, which CrossLint doesn't translate; write it another way, or remove it),
      with_comment({ "maxSeverity" => "none", "matching" => "\\p{L}" })
  end

  def test_converts_options_to_warnings_and_verbosity
    configuration = convert({ "options" => { "warnings" => "error", "verbosity" => "quiet" } }).configuration

    assert_equal [:error, :quiet], [configuration.warnings, configuration.verbosity]
    assert_equal [:none, nil], [convert({ "options" => { "warnings" => "none" } }).configuration.warnings, convert({ "options" => {} }).configuration.verbosity]
  end

  def test_refuses_an_option_it_cannot_carry
    assert_refused %(options.warnings: is "some", and it takes "all", "none", or "error"), { "options" => { "warnings" => "some" } }
    assert_refused %(options.verbosity: is "loud", and it takes "normal", "quiet", or "silent"), { "options" => { "verbosity" => "loud" } }
    assert_refused %(options.verbosity: is null, and it takes "normal", "quiet", or "silent"), { "options" => { "verbosity" => nil } }
    assert_refused %(options.verbosty: unknown key "verbosty", did you mean "verbosity"?; ng-nudge reads only these, so remove it), { "options" => { "verbosty" => "quiet" } }
    assert_refused "options: is 1, and it takes an object in braces", { "options" => 1 }
  end

  def test_refuses_a_key_it_does_not_carry_with_the_nearest_spelling
    assert_refused %(srcDirr: unknown key "srcDirr", did you mean "srcDir"?; ng-nudge reads only these keys, so remove it), { "srcDirr" => "x" }
    assert_refused %(zzzzzzzz: unknown key "zzzzzzzz"; expected "$schema", "srcDir", "tsConfig", "artifacts", "rules", or "options"; ng-nudge reads only these keys, so remove it),
      { "zzzzzzzz" => 1 }
  end

  def test_lists_every_key_it_cannot_carry_in_the_order_of_the_file_not_only_the_first
    assert_refused_all [
      %(srcDir: is "../x", which is outside the project; write a path inside it, relative to the project's root),
      %(tsConfig: is 5, and it takes a path as a string, such as "tsconfig.json"),
      %(artifacts.store.pattern: is "app/?.ts", which has ?, which CrossLint's path patterns don't have),
      %(artifacts.store.expects: is ["a"], and CrossLint's Angular plugin takes [] or ["spec"] only; in ng-nudge 0.3.0 any expects list turned the role's ) +
        "checks off, so the setting never did what it says. Remove it, or write one of those",
      %(artifacts.my store: has a role name with a character other than a letter, digit, - or _, which a CrossLint role can't have; rename it),
      %(rules.nope: unknown rule "nope"; expected "spec-exists", "stub-exists", "interface-exists", "stub-matches-component", ) +
        %("interface-matches-component", "prefer-css-over-scss", or "has-debt"; ng-nudge has no other, so remove it),
      %(rules.spec-exists.enabled: is "no", and it takes true or false),
      %(rules.spec-exists.severity: is "fatal", and it takes "error" or "warning"),
      %(rules.has-debt.withComment.matching: is "\\\\p{L}", which has \\p, which CrossLint doesn't translate; write it another way, or remove it),
      %(options.warnings: is "some", and it takes "all", "none", or "error"),
      %(options.verbosity: is "loud", and it takes "normal", "quiet", or "silent"),
],
      {
"srcDir" => "../x",
"tsConfig" => 5,
"artifacts" => { "store" => { "pattern" => "app/?.ts", "expects" => ["a"] }, "my store" => {} },
"rules" => {
"nope" => {},
"spec-exists" => { "enabled" => "no", "severity" => "fatal" },
"has-debt" => { "withComment" => { "maxSeverity" => "none", "matching" => "\\p{L}" } },
},
"options" => { "warnings" => "some", "verbosity" => "loud" },
}
  end

  def test_lists_every_key_of_an_object_it_does_not_carry
    assert_refused_all [
      %(zzzzzzzz: unknown key "zzzzzzzz"; expected "$schema", "srcDir", "tsConfig", "artifacts", "rules", or "options"; ng-nudge reads only these keys, so remove it),
      %(srcDirr: unknown key "srcDirr", did you mean "srcDir"?; ng-nudge reads only these keys, so remove it),
], { "zzzzzzzz" => 1, "srcDirr" => "x" }
    assert_refused_all [
      %(artifacts.store.patern: unknown key "patern", did you mean "pattern"?; ng-nudge reads only these, so remove it),
      %(artifacts.store.exp: unknown key "exp"; expected "pattern" or "expects"; ng-nudge reads only these, so remove it),
],
      { "artifacts" => { "store" => { "patern" => "x", "exp" => [] } } }
    assert_refused_all [
      %(options.verbosty: unknown key "verbosty", did you mean "verbosity"?; ng-nudge reads only these, so remove it),
      %(options.zzzzzzzz: unknown key "zzzzzzzz"; expected "warnings" or "verbosity"; ng-nudge reads only these, so remove it),
],
      { "options" => { "verbosty" => "quiet", "zzzzzzzz" => 1 } }
  end

  def test_lists_a_problem_of_every_role_and_every_rule
    assert_refused_all [
      %(artifacts.a.pattern: is 1, and it takes a glob pattern as a string),
      %(artifacts.b.pattern: is 2, and it takes a glob pattern as a string),
      "rules.spec-exists: is true, and it takes an object in braces",
      "rules.stub-exists: is false, and it takes an object in braces",
],
      { "artifacts" => { "a" => { "pattern" => 1 }, "b" => { "pattern" => 2 } }, "rules" => { "spec-exists" => true, "stub-exists" => false } }
  end

  def test_still_stops_at_once_for_a_file_that_is_not_an_object_or_not_json_since_there_is_nothing_else_to_read
    assert_raises(Core::Mistake) { Core::NgNudge::Rc.new("[1]").call }.then { |mistake| refute_kind_of Core::Mistakes, mistake }
  end

  def test_refuses_a_file_that_is_not_an_object_or_not_json
    assert_refused "holds [1], and it takes one object in braces", "[1]"
    assert_refused "holds \"x\", and it takes one object in braces", '"x"'
    mistake = assert_raises(Core::Mistake) { Core::NgNudge::Rc.new("{").call }

    assert_equal FILE, mistake.file
    assert_match(/\Aisn't valid JSON; fix it, as ng-nudge's schema says: .+/, mistake.message)
  end

  def test_names_the_file_it_is_given
    mistake = assert_raises(Core::Mistake) { Core::NgNudge::Rc.new("[]", file: "other.json").call }

    assert_equal "other.json", mistake.file
  end

  def test_converts_a_configuration_with_every_kind_of_key_in_the_order_of_its_file
    result = convert({
"srcDir" => "app",
"artifacts" => { "store" => { "pattern" => "**/*.store.ts" } },
"rules" => {
"prefer-css-over-scss" => { "severity" => "warning" },
"spec-exists" => { "enabled" => false },
"has-debt" => { "withComment" => "warning" },
},
"options" => { "warnings" => "none" },
})

    assert_equal ["angular/prefer-css-over-scss", "angular/spec-exists"], result.configuration.policies.map(&:name)
    assert_equal [:none, ["angular", "debt"]], [result.configuration.warnings, result.configuration.plugins.map(&:name)]
    assert_equal ["src-dir", "role"], result.configuration.plugins.first.settings.map(&:name)
  end

  def test_gives_every_plugin_setting_and_policy_line_the_line_number_a_configuration_not_read_from_a_file_has
    result = convert({ "srcDir" => "app", "artifacts" => { "store" => { "expects" => [] } }, "rules" => { "has-debt" => { "severity" => "warning", "withComment" => true } } })
    lines = result.configuration.plugins.flat_map { |plugin| [plugin.line, *lines_of(plugin.settings)] } + result.configuration.policies.map(&:line)

    assert_equal [0] * 7, lines
  end

  private

  def lines_of(settings) = settings.flat_map { |setting| [setting.line, *lines_of(setting.children)] }

  def convert(data) = Core::NgNudge::Rc.new(JSON.generate(data)).call

  def with_comment(value) = { "rules" => { "has-debt" => { "withComment" => value } } }

  # Each of `messages`, in order, and no other, as one refusal.
  def assert_refused_all(messages, data)
    mistakes = assert_raises(Core::Mistakes) { Core::NgNudge::Rc.new(JSON.generate(data)).call }

    assert_equal messages, mistakes.all.map { |mistake| mistake.message }
    assert_equal [FILE], mistakes.all.map(&:file).uniq
  end

  def assert_refused(message, data)
    mistake = assert_raises(Core::Mistake, message) { Core::NgNudge::Rc.new(data.is_a?(String) ? data : JSON.generate(data)).call }

    assert_equal [FILE, nil, message], [mistake.file, mistake.line, mistake.message]
  end

  # Each listed plugin's name and settings, as arrays.
  def shape(result)
    settings = -> (each) { [each.name, each.arguments, each.properties, each.children.map { |child| settings.call(child) }] }
    result.configuration.plugins.map { |plugin| [plugin.name, plugin.settings.map { |setting| settings.call(setting) }] }
  end
end
