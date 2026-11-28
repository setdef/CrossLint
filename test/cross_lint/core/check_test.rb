# frozen_string_literal: true

require "test_helper"

# Core::Check against the in-memory project-files adapter: every
# requirement of checking that isn't about Git, the filesystem, or how the
# report looks.
class CheckTest < Minitest::Test
  cover "CrossLint::Core::Check*"
  cover "CrossLint::Core::BuiltInRule*"
  cover "CrossLint::Core::Condition*"

  include CrossLint::Core

  ROOT = File.expand_path("/app")

  INVOICES = %w[currency invoice line_item pdf customer tax total discount payment].map { |name| "lib/invoices/#{name}.rb" }
  TESTED = %w[invoice line_item customer total discount payment].map { |name| "test/invoices/#{name}_test.rb" }

  def test_reports_each_artifact_whose_piece_is_missing
    result = check(project(tests_plugin), files: INVOICES + TESTED)

    assert_equal [
      ["lib/invoices/currency.rb", "no test file at test/invoices/currency_test.rb"],
      ["lib/invoices/pdf.rb", "no test file at test/invoices/pdf_test.rb"],
      ["lib/invoices/tax.rb", "no test file at test/invoices/tax_test.rb"],
    ], result.findings.map { |violation| [violation.artifact, violation.message] }
    assert_equal ["checked 9 ruby-file artifacts: 3 errors", true], [result.summary.line, result.failed]
  end

  def test_gives_each_violation_its_plugin_policy_artifact_role_and_severity
    violation = check(project(tests_plugin), files: ["lib/a.rb"]).findings.first

    assert_equal Violation.new(plugin: "tests", policy: "has-test", artifact: "lib/a.rb", role: "ruby-file",
      message: "no test file at test/a_test.rb", severity: :error, detail: "test", built_in: true), violation
  end

  def test_gives_a_violation_of_a_built_in_rule_the_name_of_the_piece_it_checked_as_its_detail
    plugin = plugin("tests", artifacts: [declaration("ruby-file", "lib/{path}.rb", "test" => "test/{path}_test.rb", "signature" => "sig/{path}.rbs")],
      policies: [policy("has-test", rules: [rule, rule(piece: "signature")])])
    details = check(project(plugin), files: ["lib/a.rb"]).findings.map { [it.message, it.detail] }

    assert_equal [["no signature file at sig/a.rbs", "signature"], ["no test file at test/a_test.rb", "test"]], details
  end

  def test_gives_an_artifact_and_its_violations_the_key_its_declaration_gives
    keyed = declaration("ruby-file", "lib/{path}.rb", "test" => "test/{path}_test.rb").with(key: PathPattern.new(source: "{path}"))
    plugin = plugin("tests", artifacts: [keyed, declaration("rake-file", "{path}.rake", "test" => "test/{path}_test.rb")],
      policies: [policy("has-test", rules: [rule]), policy("rake-has-test", rules: [rule], applies_to: "rake-file")])

    assert_equal [["lib/app/a.rb", "app/a"], ["tasks.rake", nil]], check(project(plugin), files: ["lib/app/a.rb", "tasks.rake"]).findings.map { [it.artifact, it.key] }
  end

  def test_names_each_artifact_and_its_violations_by_its_declarations_name_pattern_and_lists_one_that_passes_by_it
    named = declaration("ruby-file", "lib/{path}.rb", "test" => "test/{path}_test.rb").with(name_pattern: PathPattern.new(source: "{path} class"))
    result = check(project(plugin("tests", artifacts: [named], policies: [policy("has-test", rules: [rule])])),
      files: ["lib/app/b.rb", "lib/app/a.rb", "test/app/a_test.rb"], all: true)

    assert_equal [["lib/app/a.rb", "app/a class", Artifact], ["lib/app/b.rb", "app/b class", Violation]],
      result.findings.map { |finding| [finding.path, finding.is_a?(Violation) ? finding.artifact : finding.name, finding.class] }
  end

  def test_stops_a_plugin_at_a_fault_when_two_of_its_artifacts_of_one_role_have_one_name_and_runs_the_others
    named = declaration("ruby-file", "src/{path}/{name}.rb", "test" => "test/{name}_test.rb").with(name_pattern: PathPattern.new(source: "{name}"))
    plugin = plugin("named", artifacts: [named], policies: [policy("has-test", rules: [rule])])
    result = check(project(plugin, tests_plugin), files: ["src/a/card.rb", "src/b/card.rb", "lib/c.rb"])

    assert_equal ["fault in plugin named: artifact ruby-file has two artifacts named card, src/a/card.rb and src/b/card.rb"], result.faults.map(&:line)
    assert_equal [%w[tests lib/c.rb]], result.findings.map { [it.plugin, it.artifact] }
  end

  def test_names_an_artifact_by_its_primary_piece_unless_its_declaration_gives_a_name_pattern
    violation = check(project(tests_plugin), files: ["lib/a.rb"]).findings.first

    assert_equal [["lib/a.rb", "lib/a.rb"]], [[violation.path, violation.artifact]]
  end

  def test_reports_a_piece_that_is_a_match_in_a_file_by_the_line_of_its_first_match
    style = PieceDeclaration.new(name: "unscoped-style", pattern: PathPattern.new(source: "src/{path}.vue"), line: 2,
      regex: Regex.new(source: '<style(?![^>]*\bscoped)[^>]*>'))
    vue = plugin("vue", artifacts: [ArtifactDeclaration.new(name: "vue-component", primary: PathPattern.new(source: "src/{path}.vue"), pieces: [style], line: 1)],
      policies: [policy("scoped-styles", rules: [rule("piece-absent", piece: "unscoped-style")], applies_to: "vue-component")])
    contents = { "src/a.vue" => "<template/>\r\n<style>\n</style>\n<style>\n", "src/b.vue" => "<style scoped>\n</style>\n", "src/c.vue" => "" }

    assert_equal [["src/a.vue", "unscoped-style at src/a.vue:2"]], check(project(vue), files: [], contents:).findings.map { [it.artifact, it.message] }
  end

  def test_tells_a_piece_whose_file_has_no_match_from_one_with_no_file
    action = PieceDeclaration.new(name: "action", pattern: PathPattern.new(source: "app/{name}_controller.rb"), line: 2,
      regex: Regex.new(source: 'def {name}\b'))
    routes = plugin("routes", artifacts: [ArtifactDeclaration.new(name: "page", primary: PathPattern.new(source: "pages/{name}.md"), pieces: [action], line: 1)],
      policies: [
        policy("has-action", rules: [rule(piece: "action")], applies_to: "page"),
        policy("documented", rules: [rule("piece-absent", piece: "action")], applies_to: "page",
          condition: Condition::PieceExists.new(piece: "action", line: 7)),
])
    pages = %w[show index edit new].to_h { ["pages/#{it}.md", ""] }
    contents = pages.merge("app/show_controller.rb" => "def show_all\n", "app/index_controller.rb" => "def index\n", "app/edit_controller.rb/x" => "")

    assert_equal [
      ["pages/edit.md", "no action in app/edit_controller.rb, which isn't a file"],
      ["pages/new.md", "no action in app/new_controller.rb, which isn't a file"],
      ["pages/show.md", "no action in app/show_controller.rb"],
],
      check(project(routes), files: [], contents:).findings.select { it.policy == "has-action" }.map { [it.artifact, it.message] }
    assert_equal [["pages/index.md", "action at app/index_controller.rb:1"]],
      check(project(routes), files: [], contents:).findings.reject { it.policy == "has-action" }.map { [it.artifact, it.message] }
  end

  def test_stops_a_plugin_at_a_fault_when_a_pieces_regex_runs_past_its_time_limit_or_meets_text_that_isnt_utf_8
    slow = PieceDeclaration.new(name: "slow", pattern: PathPattern.new(source: "{path}.txt"), line: 2,
      regex: Regex.new(source: '^(a+)+\1$', time_limit: 0.01))
    plugin = plugin("texts", artifacts: [ArtifactDeclaration.new(name: "text", primary: PathPattern.new(source: "{path}.txt"), pieces: [slow], line: 1)],
      policies: [policy("fast", rules: [rule(piece: "slow")], applies_to: "text")])

    assert_equal ["fault in plugin texts: artifact text ran past the 0.01-second time limit searching a.txt with the regex of piece \"slow\""],
      check(project(plugin), files: [], contents: { "a.txt" => "#{'a' * 32}c" }).faults.map(&:line)
    assert_equal ["fault in plugin texts: artifact text can't search a.txt with the regex of piece \"slow\", since it isn't UTF-8"],
      check(project(plugin), files: [], contents: { "a.txt" => "caf\xE9".b.force_encoding(Encoding::UTF_8) }).faults.map(&:line)
  end

  ROUTE = %((?<verb>get|post) "(?<route>[^"]+)", to: "(?<controller>[^#"]+)#(?<action>\\w+)"(?<options>, as: \\w+)?)

  ROUTES = %(get "/cart", to: "carts#show"\r\npost "/cart", to: "carts#create", as: cart\r\n\r\nget "/", to: "home#index"\r\n)

  def routes_plugin(source = ROUTE, name: "{verb} {route}", time_limit: Regex::TIME_LIMIT)
    action = PieceDeclaration.new(name: "action", pattern: PathPattern.new(source: "app/controllers/{controller}_controller.rb", captures: %w[controller]),
      line: 4, regex: Regex.new(source: 'def {action}\b'))
    spec = PieceDeclaration.new(name: "request-spec", pattern: PathPattern.new(source: "spec/requests/{controller}_spec.rb", captures: %w[controller]), line: 5)
    route = ArtifactDeclaration.new(name: "route", primary: PathPattern.new(source: "config/routes.rb"), pieces: [action, spec], line: 1,
      regex: Regex.new(source:, time_limit:), name_pattern: name && PathPattern.new(source: name, captures: %w[verb route]))
    plugin("routes", artifacts: [route], policies: [
      policy("has-action", rules: [rule(piece: "action")], applies_to: "route"),
      policy("has-spec", rules: [rule(piece: "request-spec", severity: :warning)], applies_to: "route"),
])
  end

  def test_finds_an_artifact_for_each_match_of_a_primarys_regex_named_by_its_captures_on_the_line_it_starts
    contents = {
"config/routes.rb" => ROUTES,
"app/controllers/carts_controller.rb" => "class CartsController\n  def show\n  end\nend\n",
"spec/requests/carts_spec.rb" => "",
}
    result = check(project(routes_plugin), files: [], contents:, all: true)

    assert_equal [
      ["config/routes.rb", 1, "get /cart", "route passes"],
      ["config/routes.rb", 2, "post /cart", "no action in app/controllers/carts_controller.rb"],
      ["config/routes.rb", 4, "get /", "no action in app/controllers/home_controller.rb, which isn't a file"],
      ["config/routes.rb", 4, "get /", "no request-spec file at spec/requests/home_spec.rb"],
],
      result.findings.map { it.is_a?(Violation) ? [it.path, it.line, it.artifact, it.message] : [it.path, it.line, it.name, "route passes"] }
    assert_equal [{ "verb" => "get", "route" => "/cart", "controller" => "carts", "action" => "show" }],
      result.findings.grep(Artifact).map(&:match)
  end

  def test_stops_a_plugin_at_a_capture_it_uses_that_matched_nothing_or_at_two_matches_of_one_name
    empty = routes_plugin(ROUTE.sub("[^#\"]+", "[^#\"]*"))

    assert_equal ["fault in plugin routes: artifact route captured nothing for {controller} at config/routes.rb:2"],
      check(project(empty), files: [], contents: { "config/routes.rb" => %(get "/", to: "home#a"\nget "/cart", to: "#show"\n) }).faults.map(&:line)
    assert_equal [
"fault in plugin routes: artifact route has two artifacts named config/routes.rb, config/routes.rb:1 and config/routes.rb:2; " \
  "a name PATTERN tells them apart",
],
      check(project(routes_plugin(name: nil)), files: [], contents: { "config/routes.rb" => ROUTES }).faults.map(&:line)
  end

  def test_finds_no_piece_out_of_the_project_whatever_a_capture_holds
    contents = { "config/routes.rb" => %(get "/", to: "../../../etc/passwd#x"\n) }

    assert_equal ["no action in app/controllers/../../../etc/passwd_controller.rb, which isn't a file"],
      check(project(routes_plugin), files: [], contents:).findings.select { it.policy == "has-action" }.map(&:message)
  end

  def test_stops_a_plugin_at_a_fault_when_a_primarys_regex_runs_past_its_time_limit
    slow = routes_plugin('^(a+)+\1$', time_limit: 0.01)

    assert_equal ["fault in plugin routes: artifact route ran past the 0.01-second time limit searching config/routes.rb with the regex of its primary"],
      check(project(slow), files: [], contents: { "config/routes.rb" => "#{'a' * 32}c" }).faults.map(&:line)
  end

  def test_says_when_no_file_has_a_match_of_a_primarys_regex_and_finds_none_in_a_file_it_cant_read
    notice = %(no file that "config/routes.rb" matches has a match of its regex, the primary pattern of role "route")

    assert_equal [notice], check(project(routes_plugin), files: [], contents: { "config/routes.rb" => "resources :carts\n" }).notices.map(&:message)
    assert_equal [notice], check(project(routes_plugin), files: ["config/routes.rb"]).notices.map(&:message)
  end

  def test_passes_when_every_piece_exists
    result = check(project(tests_plugin), files: ["lib/a.rb", "lib/a/b.rb", "test/a_test.rb", "test/a/b_test.rb", "README.md"])

    assert_equal [[], "checked 2 ruby-file artifacts: no violations", false], [result.findings, result.summary.line, result.failed]
    assert_equal :normal, result.verbosity
  end

  def test_asks_whether_a_piece_exists_of_the_filesystem_not_of_git
    result = check(project(tests_plugin), files: ["lib/a.rb"], ignored: ["test/a_test.rb"])

    assert_empty result.findings
  end

  def test_reports_a_piece_that_exists_with_piece_absent
    plugin = tests_plugin(rules: [rule("piece-absent", piece: "test")])

    assert_equal [["lib/a.rb", "test file exists at test/a_test.rb"]],
      check(project(plugin), files: ["lib/a.rb", "test/a_test.rb", "lib/b.rb"]).findings.map { |violation| [violation.artifact, violation.message] }
  end

  def test_applies_a_policy_only_where_its_condition_holds
    files = ["lib/a.rb", "lib/b.rb", "lib/c.rb", "lib/d.rb", "sig/a.rbs", "sig/b.rbs", "doc/a.md", "doc/c.md"]
    has = -> (name) { Condition::PieceExists.new(piece: name, line: 7) }
    cases = {
      has.call("signature") => ["lib/a.rb", "lib/b.rb"],
      Condition::Not.new(condition: has.call("signature"), line: 7) => ["lib/c.rb", "lib/d.rb"],
      Condition::All.new(conditions: [has.call("signature"), has.call("doc")], line: 7) => ["lib/a.rb"],
      Condition::Any.new(conditions: [has.call("signature"), has.call("doc")], line: 7) => ["lib/a.rb", "lib/b.rb", "lib/c.rb"],
    }
    cases.each do |condition, expected|
      plugin = plugin("tests", artifacts: [
declaration("ruby-file", "lib/{path}.rb", "test" => "test/{path}_test.rb",
  "signature" => "sig/{path}.rbs", "doc" => "doc/{path}.md"),
], policies: [policy("has-test", rules: [rule], condition:)])

      assert_equal expected, check(project(plugin), files:).findings.map(&:artifact), condition.inspect
    end
  end

  def test_runs_every_rule_of_a_policy
    plugin = plugin("tests", artifacts: [declaration("ruby-file", "lib/{path}.rb", "test" => "test/{path}_test.rb", "signature" => "sig/{path}.rbs")],
      policies: [policy("complete", rules: [rule, rule(piece: "signature")])])

    assert_equal ["no signature file at sig/a.rbs", "no test file at test/a_test.rb"],
      check(project(plugin), files: ["lib/a.rb"]).findings.map(&:message)
  end

  def test_gives_a_violation_the_severity_of_its_rule_its_policy_or_the_configuration
    warning = tests_plugin(rules: [rule(severity: :warning)])
    severities = -> (plugin, settings = []) { check(project(plugin, policies: settings), files: ["lib/a.rb"]).findings.map(&:severity) }

    assert_equal [:error], severities.call(tests_plugin)
    assert_equal [:warning], severities.call(warning)
    assert_equal [:error], severities.call(warning, [setting("tests/has-test", severity: :error)])
    assert_equal [:warning], severities.call(tests_plugin, [setting("tests/has-test", severity: :warning)])
    assert_equal [:warning], severities.call(warning, [setting("tests/has-test", enabled: true)])
    assert_equal [:error], severities.call(tests_plugin, [setting("tests/other", severity: :warning)])
  end

  def test_runs_no_policy_the_configuration_disables
    result = check(project(tests_plugin, policies: [setting("tests/has-test", enabled: false)]), files: ["lib/a.rb"])

    assert_equal [[], "checked 0 artifacts: no violations", false], [result.findings, result.summary.line, result.failed]
  end

  def test_shows_warnings_by_default_and_fails_only_on_errors
    result = check(project(tests_plugin(rules: [rule(severity: :warning)])), files: ["lib/a.rb"])

    assert_equal [[:warning], "checked 1 ruby-file artifact: 1 warning", false],
      [result.findings.map(&:severity), result.summary.line, result.failed]
  end

  def test_hides_warnings_with_none
    result = check(project(mixed_plugin), files: ["lib/a.rb"], warnings: :none)

    assert_equal [["no test file at test/a_test.rb"], "checked 1 ruby-file artifact: 1 error", true],
      [result.findings.map(&:message), result.summary.line, result.failed]
    result = check(project(tests_plugin(rules: [rule(severity: :warning)])), files: ["lib/a.rb"], warnings: :none)

    assert_equal [[], "checked 1 ruby-file artifact: no errors", false], [result.findings, result.summary.line, result.failed]
  end

  def test_fails_on_a_warning_with_error
    result = check(project(tests_plugin(rules: [rule(severity: :warning)])), files: ["lib/a.rb"], warnings: :error)

    assert_equal [[:warning], true], [result.findings.map(&:severity), result.failed]
  end

  def test_takes_warnings_from_the_configuration_unless_the_command_line_gives_it
    plugin = tests_plugin(rules: [rule(severity: :warning)])

    assert check(project(plugin, warnings: :error), files: ["lib/a.rb"]).failed
    refute check(project(plugin, warnings: :error), files: ["lib/a.rb"], warnings: :all).failed
    assert_empty check(project(plugin, warnings: :none), files: ["lib/a.rb"]).findings
  end

  def test_reports_only_what_fails_the_check_when_quiet
    result = check(project(mixed_plugin), files: ["lib/a.rb"], verbosity: :quiet)

    assert_equal [["no test file at test/a_test.rb"], :quiet, true], [result.findings.map(&:message), result.verbosity, result.failed]
    assert_equal "checked 1 ruby-file artifact: 1 error, 1 warning", result.summary.line
    assert_equal 2, check(project(mixed_plugin), files: ["lib/a.rb"], verbosity: :quiet, warnings: :error).findings.size
  end

  def test_orders_findings_that_differ_only_in_severity_errors_first_whatever_the_order_of_the_rules
    warns = rule(severity: :warning)
    fails = rule(severity: :error)
    orders = [[warns, fails], [fails, warns]].map do |rules|
      check(project(tests_plugin(rules:)), files: ["lib/a.rb"]).findings.map(&:severity)
    end

    assert_equal [[:error, :warning], [:error, :warning]], orders
  end

  def test_reports_nothing_when_silent
    result = check(project(mixed_plugin, unused: true), files: ["lib/a.rb"], verbosity: :silent, warnings: :error, all: true)

    assert_equal [[], [], :silent, true], [result.findings, result.notices, result.verbosity, result.failed]
  end

  def test_takes_the_verbosity_from_the_configuration_unless_the_command_line_gives_it
    assert_equal :quiet, check(project(tests_plugin, verbosity: :quiet), files: []).verbosity
    assert_equal :normal, check(project(tests_plugin, verbosity: :quiet), files: [], verbosity: :normal).verbosity
  end

  def test_lists_each_passing_artifact_with_all_in_order_among_the_violations
    result = check(project(tests_plugin), files: ["lib/c.rb", "lib/b.rb", "lib/a.rb", "test/a_test.rb", "test/c_test.rb"], all: true)

    assert_equal [["lib/a.rb", Artifact], ["lib/b.rb", Violation], ["lib/c.rb", Artifact]],
      result.findings.map { |finding| [finding.is_a?(Violation) ? finding.artifact : finding.path, finding.class] }
    assert_equal "checked 3 ruby-file artifacts: 1 error", result.summary.line
    assert_equal [Violation], check(project(tests_plugin), files: ["lib/a.rb", "lib/b.rb", "test/a_test.rb"], all: true,
      verbosity: :quiet).findings.map(&:class)
  end

  def test_lists_no_artifact_with_a_hidden_warning_as_passing
    result = check(project(tests_plugin(rules: [rule(severity: :warning)])), files: ["lib/a.rb"], all: true, warnings: :none)

    assert_empty result.findings
  end

  def test_lists_a_passing_artifact_with_its_pieces_and_match
    artifact = check(project(tests_plugin), files: ["lib/a/b.rb", "test/a/b_test.rb"], all: true).findings.first

    assert_equal Artifact.new(plugin: "tests", role: "ruby-file", path: "lib/a/b.rb", match: { "path" => "a/b" },
      pieces: [Piece.new(name: "test", path: "test/a/b_test.rb", exists: true)]), artifact
  end

  def test_sorts_findings_by_artifact_then_plugin_policy_and_message
    other = plugin("other", artifacts: [declaration("ruby-file", "lib/{path}.rb", "spec" => "spec/{path}_spec.rb")],
      policies: [policy("has-spec", rules: [rule(piece: "spec")]), policy("a-spec", rules: [rule(piece: "spec")])])
    result = check(project(tests_plugin, other), files: ["lib/b.rb", "lib/a.rb"])

    assert_equal [
      ["lib/a.rb", "other", "a-spec"],
      ["lib/a.rb", "other", "has-spec"],
      ["lib/a.rb", "tests", "has-test"],
      ["lib/b.rb", "other", "a-spec"],
      ["lib/b.rb", "other", "has-spec"],
      ["lib/b.rb", "tests", "has-test"],
],
      result.findings.map { |violation| [violation.artifact, violation.plugin, violation.policy] }
    assert_equal "checked 2 tests/ruby-file and 2 other/ruby-file artifacts: 6 errors", result.summary.line
  end

  def test_sorts_by_plugin_the_findings_of_policies_with_one_name
    other = plugin("other", artifacts: [], policies: [policy("has-test", applies_to: "tests/ruby-file", rules: [rule])])
    zed = plugin("zed", artifacts: [], policies: [policy("has-test", applies_to: "tests/ruby-file", rules: [rule])])

    assert_equal %w[other tests zed], check(project(tests_plugin, zed, other), files: ["lib/a.rb"]).findings.map(&:plugin)
  end

  def test_sorts_passing_artifacts_on_one_path_by_plugin_and_role_before_its_violations
    roles = %w[zed ruby-file alpha].map { |role| declaration(role, "lib/{path}.rb", "test" => "test/{path}_test.rb") }
    passing = plugin("tests", artifacts: roles, policies: roles.map { |role| policy("p-#{role.name}", applies_to: role.name, rules: [rule]) })
    spec = plugin("spec", artifacts: [declaration("ruby-file", "lib/{path}.rb", "spec" => "spec/{path}_spec.rb")],
      policies: [policy("has-spec", rules: [rule(piece: "spec")])])
    findings = check(project(passing, spec), files: ["lib/a.rb", "test/a_test.rb", "spec/a_spec.rb"], all: true).findings

    assert_equal [%w[spec ruby-file], %w[tests alpha], %w[tests ruby-file], %w[tests zed]], findings.map { |finding| [finding.plugin, finding.role] }
    mixed = plugin("tests", artifacts: [roles.first, declaration("ruby-file", "lib/{path}.rb", "signature" => "sig/{path}.rbs")],
      policies: [policy("p-zed", applies_to: "zed", rules: [rule]), policy("has-signature", rules: [rule(piece: "signature")])])
    findings = check(project(mixed), files: ["lib/a.rb", "test/a_test.rb"], all: true).findings

    assert_equal [[Artifact, "zed"], [Violation, "ruby-file"]], findings.map { |finding| [finding.class, finding.role] }
  end

  def test_applies_a_policy_to_another_plugins_artifact
    other = plugin("other", artifacts: [], policies: [policy("has-test", applies_to: "tests/ruby-file", rules: [rule])])
    result = check(project(tests_plugin(policies: []), other), files: ["lib/a.rb"])

    assert_equal [["other", "ruby-file"]], result.findings.map { |violation| [violation.plugin, violation.role] }
    assert_equal "checked 1 ruby-file artifact: 1 error", result.summary.line
  end

  def test_applies_a_policy_with_no_applies_to_to_each_artifact_of_its_plugin_with_the_pieces_it_names
    artifacts = [
      declaration("ruby-file", "lib/{path}.rb", "test" => "test/{path}_test.rb"),
      declaration("rake-file", "{path}.rake"),
      declaration("doc", "{path}.md", "test" => "test/{path}_test.md", "note" => "{path}.txt"),
]
    has_note = policy("note", rules: [rule(piece: "test")], applies_to: nil, condition: Condition::PieceExists.new(piece: "note", line: 7))
    plugin = plugin("tests", artifacts:, policies: [policy("has-test", rules: [rule], applies_to: nil), has_note])
    result = check(project(plugin), files: ["lib/a.rb", "a.rake", "a.md", "a.txt"])

    assert_equal [["a.md", "has-test"], ["a.md", "note"], ["lib/a.rb", "has-test"]], result.findings.map { [it.artifact, it.policy] }
    assert_equal "checked 1 ruby-file and 1 doc artifacts: 3 errors", result.summary.line
  end

  def test_finds_a_file_two_artifacts_match_as_a_primary_file_of_each
    plugin = plugin("tests", artifacts: [
      declaration("ruby-file", "lib/{path}.rb", "test" => "test/{path}_test.rb"),
      declaration("library", "lib/{name}.rb", "test" => "spec/{name}_spec.rb"),
],
      policies: [policy("has-test", rules: [rule]), policy("has-spec", applies_to: "library", rules: [rule])])
    result = check(project(plugin), files: ["lib/a.rb", "lib/x/y.rb"])

    assert_equal [["lib/a.rb", "library"], ["lib/a.rb", "ruby-file"], ["lib/x/y.rb", "ruby-file"]],
      result.findings.map { |violation| [violation.artifact, violation.role] }
    assert_equal "checked 2 ruby-file and 1 library artifacts: 3 errors", result.summary.line
  end

  def test_counts_only_the_kinds_an_enabled_policy_applies_to
    plugin = plugin("tests", artifacts: [
      declaration("ruby-file", "lib/{path}.rb", "test" => "test/{path}_test.rb"),
      declaration("doc", "doc/{path}.md"),
], policies: [policy("has-test", rules: [rule])])

    assert_equal "checked 1 ruby-file artifact: 1 error", check(project(plugin), files: ["lib/a.rb", "doc/a.md"]).summary.line
  end

  def test_warns_of_a_files_pattern_that_matches_no_file
    plugin = plugin("tests", artifacts: [
      declaration("ruby-file", "lib/{path}.rb", "test" => "test/{path}_test.rb"),
      declaration("doc", "docs/{path}.md", line: 9),
], policies: [policy("has-test", rules: [rule])])
    result = check(project(plugin), files: ["lib/a.rb", "test/a_test.rb"])

    assert_equal [
Notice.new(file: ".config/tests/plugin.kdl", line: 9,
  message: %(no file matches "docs/{path}.md", the primary pattern of role "doc")),
], result.notices
    refute result.failed
  end

  def test_warns_of_an_optional_artifact_that_matches_no_file_only_when_none_of_its_plugins_does
    optional = -> (name, files, line) { declaration(name, files, "test" => "{path}.spec.ts").with(line:, optional: true) }
    artifacts = [
      declaration("store", "src/{path}.store.ts", line: 4),
      optional.call("pipe", "src/{path}.pipe.ts", 2),
      optional.call("component", "src/{path}.component.ts", 3),
]
    plugin = plugin("tests", artifacts:, policies: [policy("p", rules: [rule], applies_to: "pipe")])
    some = check(project(plugin), files: ["src/a.component.ts"])
    none = check(project(plugin), files: ["app/a.component.ts"])

    assert_equal [Notice.new(file: ".config/tests/plugin.kdl", line: 4, message: %(no file matches "src/{path}.store.ts", the primary pattern of role "store"))],
      some.notices
    assert_equal [
Notice.new(file: ".config/tests/plugin.kdl", line: 2,
  message: %(no file matches the primary pattern of any role of plugin tests, such as "src/{path}.pipe.ts")),
], none.notices
  end

  def test_finds_no_artifact_whose_match_has_a_name_that_starts_with_a_dot_when_its_declaration_leaves_dotfiles_out
    plain = declaration("ruby-file", "lib/{path}.rb", "test" => "test/{path}_test.rb")
    solid = plain.with(dotfiles: false)
    files = ["lib/a.rb", "lib/.b.rb", "lib/.c/d.rb", "lib/e/.f/g.rb", "lib/h/.i.rb", "lib/j.k.rb"]
    found = -> (declaration) { check(project(plugin("tests", artifacts: [declaration], policies: [policy("has-test", rules: [rule])])), files:).findings.map(&:artifact) }

    assert_equal files.sort, found.call(plain)
    assert_equal ["lib/a.rb", "lib/j.k.rb"], found.call(solid)
  end

  # Any placeholder's value, and not every one's.
  def test_finds_no_artifact_when_only_one_of_two_placeholders_matched_a_name_that_starts_with_a_dot
    pair = declaration("pair", "{name}/{path}.rb", "test" => "test/{name}/{path}_test.rb").with(dotfiles: false)
    files = ["x/y.rb", "x/.y.rb", ".x/y.rb", "x/z/.y.rb"]

    assert_equal ["x/y.rb"], check(project(plugin("tests", artifacts: [pair], policies: [policy("has-test", rules: [rule], applies_to: "pair")])), files:).findings.map(&:artifact)
  end

  def test_says_under_debug_each_file_git_lists_in_order
    assert_equal ["README.md", "lib/a.rb", "lib/b.rb"], debugged(project(tests_plugin), files: ["lib/b.rb", "README.md", "lib/a.rb"]).written("file")
  end

  def test_says_under_debug_how_many_artifacts_each_roles_primary_found_and_each_artifacts_pieces
    debug = debugged(project(tests_plugin), files: ["lib/b.rb", "lib/a.rb", "test/a_test.rb"])

    assert_equal [%(tests/ruby-file: 2 artifacts, from primary "lib/{path}.rb")], debug.written("role")
    assert_equal [%(tests/ruby-file lib/b.rb: piece "test" at test/b_test.rb is missing), %(tests/ruby-file lib/a.rb: piece "test" at test/a_test.rb exists)],
      debug.written("artifact")
  end

  def test_says_under_debug_where_a_primarys_regex_found_each_artifact_and_what_each_pieces_regex_found
    contents = {
"config/routes.rb" => ROUTES,
"app/controllers/carts_controller.rb" => "class CartsController\n  def show\n  end\nend\n",
"app/controllers/home_controller.rb/x" => "",
"spec/requests/carts_spec.rb" => "",
}
    debug = debugged(project(routes_plugin), files: ["config/routes.rb.bak"], contents:)

    assert_equal [%(routes/route: 3 artifacts, from primary "config/routes.rb" with regex #{ROUTE.dump})], debug.written("role")
    assert_equal [
      %(routes/route config/routes.rb:1, named get /cart: piece "action" at app/controllers/carts_controller.rb:2 exists; ) +
        %(piece "request-spec" at spec/requests/carts_spec.rb exists),
      %(routes/route config/routes.rb:2, named post /cart: piece "action" is missing, since app/controllers/carts_controller.rb has no match of its regex; ) +
        %(piece "request-spec" at spec/requests/carts_spec.rb exists),
      %(routes/route config/routes.rb:4, named get /: piece "action" is missing, since app/controllers/home_controller.rb isn't a file; ) +
        %(piece "request-spec" at spec/requests/home_spec.rb is missing),
    ], debug.written("artifact")
  end

  def test_says_under_debug_which_file_a_primarys_regex_has_no_match_in_or_cant_read
    assert_includes debugged(project(routes_plugin), files: [], contents: { "config/routes.rb" => "resources :carts\n" }).written("role"),
      "routes/route: config/routes.rb has no match of the primary's regex"
    assert_includes debugged(project(routes_plugin), files: ["config/routes.rb"]).written("role"), "routes/route: config/routes.rb isn't a file CrossLint can read"
  end

  def test_says_under_debug_the_key_of_an_artifact_with_one
    keyed = declaration("ruby-file", "lib/{path}.rb", "test" => "test/{path}_test.rb").with(key: PathPattern.new(source: "{path}"))
    debug = debugged(project(plugin("tests", artifacts: [keyed], policies: [policy("has-test", rules: [rule])])), files: ["lib/app/a.rb"])

    assert_equal [%(tests/ruby-file lib/app/a.rb, with key app/a: piece "test" at test/app/a_test.rb is missing)], debug.written("artifact")
  end

  def test_says_under_debug_which_file_a_role_that_takes_no_dotfiles_leaves_out
    solid = declaration("ruby-file", "lib/{path}.rb").with(dotfiles: false)
    debug = debugged(project(plugin("tests", artifacts: [solid], policies: [])), files: ["lib/a.rb", "lib/.b.rb"])

    assert_equal [
      %(tests/ruby-file: leaves out lib/.b.rb, since a placeholder matched a name that starts with "." and the role has dotfiles=#false),
      %(tests/ruby-file: 1 artifact, from primary "lib/{path}.rb"),
], debug.written("role")
    assert_equal ["tests/ruby-file lib/a.rb: no piece but its primary"], debug.written("artifact")
  end

  def test_says_under_debug_what_each_policy_applies_to_and_whether_its_when_held_on_each_artifact
    stub = Condition::PieceExists.new(piece: "stub", line: 7)
    unstubbed = Condition::Not.new(condition: Condition::All.new(conditions: [stub, Condition::Any.new(conditions: [stub], line: 7)], line: 7), line: 7)
    plugin = plugin("tests", artifacts: [declaration("ruby-file", "lib/{path}.rb", "test" => "test/{path}_test.rb", "stub" => "stub/{path}.rb")],
      policies: [policy("has-test", rules: [rule]), policy("unstubbed", rules: [rule], condition: unstubbed)])
    debug = debugged(project(plugin), files: ["lib/a.rb", "named/b.rb", "stub/a.rb"])

    assert_equal [
      "tests/has-test applies to tests/ruby-file: 1 artifact",
      "tests/has-test runs on lib/a.rb",
      "tests/unstubbed applies to tests/ruby-file: 1 artifact",
      %(tests/unstubbed skips lib/a.rb, since its when fails: not { all { piece-exists "stub" (exists) any { piece-exists "stub" (exists) } } }),
    ], debug.written("policy")
  end

  def test_says_under_debug_where_a_policy_runs_on_an_artifact_named_apart_from_its_path_and_its_when_holds
    named = declaration("ruby-file", "lib/{path}.rb", "test" => "test/{path}_test.rb").with(name_pattern: PathPattern.new(source: "{path} class"))
    untested = Condition::Not.new(condition: Condition::PieceExists.new(piece: "test", line: 7), line: 7)
    plugin = plugin("tests", artifacts: [named], policies: [policy("has-test", rules: [rule], condition: untested)])

    assert_equal [
      "tests/has-test applies to tests/ruby-file: 1 artifact",
      %(tests/has-test runs on b class at lib/b.rb, since its when holds: not { piece-exists "test" (missing) }),
],
      debugged(project(plugin), files: ["lib/b.rb"]).written("policy")
  end

  def test_says_under_debug_which_policy_the_configuration_turns_off
    debug = debugged(project(mixed_plugin, policies: [setting("tests/has-signature", enabled: false)]), files: ["lib/a.rb"])

    assert_equal [
      "tests/has-signature doesn't run, since it is off in .config/crosslint/config.kdl:4",
      "tests/has-test applies to tests/ruby-file: 1 artifact",
      "tests/has-test runs on lib/a.rb",
], debug.written("policy")
  end

  def test_says_under_debug_what_each_rule_found_on_each_artifact_with_its_severity_and_detail
    debug = debugged(project(mixed_plugin, policies: [setting("tests/has-test", severity: :warning)]), files: ["lib/a.rb", "test/a_test.rb", "lib/b.rb"])

    assert_equal [
      %(piece-exists piece="test" of tests/has-test on lib/a.rb: no violation),
      %(piece-exists piece="test" of tests/has-test on lib/b.rb: warning: no test file at test/b_test.rb, with detail "test"),
      %(piece-exists piece="signature" of tests/has-signature on lib/a.rb: warning: no signature file at sig/a.rbs, with detail "signature"),
      %(piece-exists piece="signature" of tests/has-signature on lib/b.rb: warning: no signature file at sig/b.rbs, with detail "signature"),
    ], debug.written("rule")
  end

  def test_warns_of_a_ruby_rule_no_policy_runs
    result = check(project(tests_plugin, unused: true), files: ["lib/a.rb", "test/a_test.rb"])

    assert_equal [Notice.new(file: ".config/tests/plugin.kdl", line: 3, message: %(no policy runs rule "unused", so CrossLint doesn't load it))],
      result.notices
  end

  def test_treats_its_own_warnings_as_warnings
    files = ["lib/a.rb", "test/a_test.rb"]
    plugin = project(tests_plugin, unused: true)

    assert_empty check(plugin, files:, warnings: :none).notices
    refute check(plugin, files:, warnings: :none).failed
    assert_empty check(plugin, files:, verbosity: :quiet).notices
    assert_empty check(plugin, files:, verbosity: :quiet, warnings: :all).notices
    assert_equal 1, check(plugin, files:, verbosity: :quiet, warnings: :error).notices.size
    assert check(plugin, files:, warnings: :error).failed
    refute check(project(tests_plugin), files:, warnings: :error).failed
  end

  def test_stops_at_a_root_outside_a_git_working_tree
    port = CrossLint::Adapters::MemoryProjectFiles.new
    assert_raises(Mistake) { Check.new(project_files: port, crosslint_ruby: CrossLint::Adapters::MemoryCrossLintRuby.new, helpers: CrossLint::Adapters::MemoryHelpers.new, steps: {}).call(project(tests_plugin)) }
  end

  # A step that records what it sees and answers with what it is given.
  class ScriptedStep
    attr_reader :inputs

    def initialize(answer = nil, **result)
      @answer = answer || -> (_) { CrossLint::Core::StepResult.new(excused: [], violations: [], paid_off: [], notices: [], wrote: [], summary: []).with(**result) }
      @inputs = []
    end

    def policies = ["has-debt"]

    def check_settings(_settings, _file) = nil

    def call(input)
      @inputs << input
      @answer.call(input)
    end
  end

  def stepped(name = "debt", commands: [])
    manifest = Manifest.new(file: "#{name}/plugin.kdl", artifacts: [], policies: [], rules: [], helpers: [],
      step_policies: [StepPolicy.new(name: "has-debt", line: 1)], commands: commands.map { |command| CommandDeclaration.new(name: command, help: "Does #{command}", line: 2) },
      steps: [StepDeclaration.new(name: "track-debt", line: 3)])
    Plugin.new(name:, folder: "#{ROOT}/#{name}", manifest:, listing: ListedPlugin.new(name:, ref: nil, settings: [], line: 1))
  end

  def paid_off(artifact) = PaidOffEntry.new(plugin: "tests", policy: "has-test", artifact:, file: "debt.tsv", line: 2, message: "is paid off")

  def debt_violation(severity = :error)
    Violation.new(plugin: "debt", policy: "has-debt", artifact: "debt.tsv", role: "debt-file", message: "line 2", severity:, detail: "2")
  end

  def test_runs_each_step_on_every_violation_whatever_warnings_hides
    step = ScriptedStep.new
    files = ["lib/a.rb", "lib/b.rb"]
    check(project(mixed_plugin, stepped), files:, warnings: :none, steps: { "track-debt" => step })
    input = step.inputs.fetch(0)

    assert_equal [4, "debt", [], nil], [input.violations.size, input.plugin.name, input.faulted, input.command]
    assert_equal ROOT, input.project.root
  end

  def test_leaves_out_what_a_step_excuses_and_reports_what_it_adds
    excuse = -> (input) { StepResult.new(excused: input.violations.take(1), violations: [debt_violation(:warning)], paid_off: [], notices: [], wrote: [], summary: ["1 accepted as debt"]) }
    result = check(project(tests_plugin, stepped), files: ["lib/a.rb", "lib/b.rb", "test/b_test.rb", "lib/c.rb"], steps: { "track-debt" => ScriptedStep.new(excuse) })

    assert_equal [["debt.tsv", "line 2"], ["lib/c.rb", "no test file at test/c_test.rb"]], result.findings.map { |each| [each.artifact, each.message] }
    assert_equal ["checked 3 ruby-file artifacts: 1 error, 1 warning, 1 accepted as debt", true], [result.summary.line, result.failed]
    excused = check(project(tests_plugin, stepped), files: ["lib/a.rb", "lib/b.rb", "test/b_test.rb"], all: true, steps: { "track-debt" => ScriptedStep.new(excuse) })

    assert_equal [["lib/a.rb", Artifact], ["lib/b.rb", Artifact], ["debt.tsv", Violation]].sort, excused.findings.map { |each| [each.is_a?(Artifact) ? each.path : each.artifact, each.class] }.sort
    refute excused.failed
  end

  def test_counts_each_violation_a_step_excuses_whatever_quiet_or_hiding_warnings_leaves_out
    excuse = -> (input) { StepResult.new(excused: input.violations, violations: [], paid_off: [], notices: [], wrote: [], summary: []) }
    files = ["lib/a.rb", "lib/b.rb"]
    counted = [{}, { verbosity: :quiet }, { warnings: :none }, { verbosity: :silent }].map do |options|
      check(project(mixed_plugin, stepped), files:, steps: { "track-debt" => ScriptedStep.new(excuse) }, **options).summary.excused
    end

    assert_equal [4, 4, 4, 4], counted
    assert_equal 0, check(project(mixed_plugin, stepped), files:, steps: { "track-debt" => ScriptedStep.new }).summary.excused
  end

  def test_drops_what_a_step_adds_of_a_policy_the_configuration_disables
    step = ScriptedStep.new(violations: [debt_violation])
    result = check(project(stepped, policies: [setting("debt/has-debt", enabled: false)]), files: [], steps: { "track-debt" => step })

    assert_equal [[], false], [result.findings, result.failed]
  end

  def test_fails_at_a_paid_off_entry_and_reports_it_among_the_findings_even_when_quiet
    step = ScriptedStep.new(paid_off: [paid_off("lib/b.rb")])
    result = check(project(tests_plugin, stepped), files: ["lib/a.rb", "lib/c.rb"], verbosity: :quiet, steps: { "track-debt" => step })

    assert_equal ["lib/a.rb", "lib/b.rb", "lib/c.rb"], result.findings.map(&:artifact)
    assert_equal [true, 1], [result.failed, result.summary.paid_off]
    assert_empty check(project(stepped), files: [], verbosity: :silent, steps: { "track-debt" => step }).findings
  end

  def test_orders_paid_off_entries_by_artifact_then_plugin_then_policy_then_message
    entry = -> (artifact, plugin, policy, message) { PaidOffEntry.new(plugin:, policy:, artifact:, file: "debt.tsv", line: 2, message:) }
    ordered = [
      entry.call("a", "p1", "x", "m1"),
      entry.call("a", "p1", "x", "m2"),
      entry.call("a", "p1", "y", "m1"),
      entry.call("a", "p2", "x", "m1"),
      entry.call("b", "p1", "x", "m1"),
]
    step = ScriptedStep.new(paid_off: ordered.reverse)

    assert_equal ordered, check(project(stepped), files: [], steps: { "track-debt" => step }).findings
  end

  def test_reports_a_steps_warnings_only_at_the_normal_verbosity_and_never_fails_on_them
    notice = Notice.new(file: "debt.tsv", line: 3, message: "coarse")
    step = ScriptedStep.new(notices: [notice])
    results = [{}, { verbosity: :quiet }, { warnings: :none }, { warnings: :error }].map { |options| check(project(stepped), files: [], steps: { "track-debt" => step }, **options) }

    assert_equal [[notice], [], [], [notice]], results.map(&:notices)
    assert_equal [false] * 4, results.map(&:failed)
  end

  def test_passes_a_command_that_wrote_and_says_what_it_wrote_unless_silent
    step = ScriptedStep.new(wrote: ["wrote debt.tsv"], violations: [debt_violation], paid_off: [paid_off("lib/a.rb")])
    result = check(project(stepped), files: [], command: ["debt", "update"], steps: { "track-debt" => step })

    assert_equal [false, ["wrote debt.tsv"]], [result.failed, result.wrote]
    assert_empty check(project(stepped), files: [], command: ["debt", "update"], verbosity: :silent, steps: { "track-debt" => step }).wrote
  end

  def test_passes_a_command_whatever_the_check_found_and_fails_the_same_check_without_it
    step = ScriptedStep.new(paid_off: [paid_off("lib/a.rb")])
    errors = -> (**options) { check(project(tests_plugin, stepped), files: ["lib/a.rb"], steps: { "track-debt" => step }, **options) }

    assert_equal [true, false], [errors.call.failed, errors.call(command: ["debt", "update"]).failed]
    assert_equal [true, false], [errors.call(warnings: :error).failed, errors.call(warnings: :error, command: ["debt", "update"]).failed]
  end

  def test_tells_only_the_step_of_the_plugin_a_command_belongs_to_the_commands_name
    step = ScriptedStep.new
    check(project(stepped(commands: ["update"]), stepped("other", commands: ["update"])), files: [], command: ["debt", "update"], steps: { "track-debt" => step })

    assert_equal [["debt", "update"], ["other", nil]], step.inputs.map { |input| [input.plugin.name, input.command] }
    assert_equal [{}, {}], step.inputs.map(&:flags)
  end

  def test_tells_the_step_of_the_plugin_a_command_belongs_to_the_flags_given_and_no_other_step
    step = ScriptedStep.new
    check(project(stepped(commands: ["update"]), stepped("other", commands: ["update"])), files: [], command: ["debt", "update"],
      flags: { "dry-run" => true }, steps: { "track-debt" => step })
    check(project(stepped(commands: ["update"])), files: [], steps: { "track-debt" => step }, flags: { "dry-run" => true })

    assert_equal [{ "dry-run" => true }, {}, {}], step.inputs.map(&:flags)
  end

  def test_runs_no_step_of_a_plugin_that_stopped_and_tells_the_others_which_stopped
    step = ScriptedStep.new
    broken = tests_plugin(rules: [rule("boom")], ruby: ["boom"]).then do |plugin|
      plugin.with(manifest: plugin.manifest.with(step_policies: [StepPolicy.new(name: "has-debt", line: 1)], steps: [StepDeclaration.new(name: "track-debt", line: 3)]))
    end
    ruby = { "#{ROOT}/.config/tests/rules/boom.rb" => -> (_namespace) { raise "boom" } }
    result = check(project(broken, stepped), files: ["lib/a.rb"], ruby:, steps: { "track-debt" => step })

    assert_equal [["debt"], [["tests"]], ["tests"]], [step.inputs.map { |input| input.plugin.name }, step.inputs.map(&:faulted), result.faults.map(&:plugin)]
  end

  def test_fails_at_a_paid_off_entry_alone
    step = ScriptedStep.new(paid_off: [paid_off("lib/a.rb")], summary: ["0 accepted as debt"])
    result = check(project(stepped, stepped("other")), files: [], steps: { "track-debt" => step })

    assert_equal [true, ["0 accepted as debt", "0 accepted as debt"]], [result.failed, result.summary.steps]
  end

  def test_drops_only_what_a_step_adds_of_the_policy_the_configuration_disables
    kept = debt_violation.with(policy: "kept")
    policies = [setting("debt/kept", severity: :error), setting("debt/has-debt", enabled: false), setting("other/kept", enabled: false)]
    result = check(project(stepped, policies:), files: [], steps: { "track-debt" => ScriptedStep.new(violations: [debt_violation, kept]) })

    assert_equal [kept], result.findings
  end

  private

  def check(project, files:, ignored: [], steps: {}, ruby: {}, contents: {}, debug: nil, **)
    port = CrossLint::Adapters::MemoryProjectFiles.new({ ROOT => files + contents.keys }, ignored: { ROOT => ignored }, contents: { ROOT => contents })
    Check.new(project_files: port, crosslint_ruby: CrossLint::Adapters::MemoryCrossLintRuby.new(ruby), helpers: CrossLint::Adapters::MemoryHelpers.new, steps:,
      debug:).call(project, **)
  end

  # What the check says under --debug, by topic.
  def debugged(project, **)
    debug = CrossLint::Adapters::MemoryDebugOutput.new
    check(project, debug:, **)
    debug
  end

  def declaration(name, files, line: 1, **pieces)
    ArtifactDeclaration.new(name:, primary: PathPattern.new(source: files), line:,
      pieces: pieces.map { |piece, pattern| PieceDeclaration.new(name: piece, pattern: PathPattern.new(source: pattern), line: line + 1) })
  end

  def rule(name = "piece-exists", piece: "test", severity: nil, line: 6)
    arguments = BuiltInRule.named(name) ? { "piece" => piece } : {}
    PolicyRule.new(name:, arguments:, severity:, line:)
  end

  def policy(name, rules:, applies_to: "ruby-file", condition: nil)
    Policy.new(name:, applies_to: applies_to && AppliesTo.new(artifact: applies_to, line: 6), condition:, rules:, line: 5)
  end

  def plugin(name, artifacts:, policies:, ruby: [])
    rules = ruby.map { |rule| RuleDeclaration.new(name: rule, ruby: "rules/#{rule}.rb", line: 3) }
    manifest = Manifest.new(file: ".config/#{name}/plugin.kdl", artifacts:, policies:, rules:, helpers: [])
    Plugin.new(name:, folder: "#{ROOT}/.config/#{name}", listing: ListedPlugin.new(name: "./.config/#{name}", ref: nil, settings: [], line: 1),
      manifest:)
  end

  def tests_plugin(rules: [rule], policies: nil, ruby: [])
    plugin("tests", artifacts: [declaration("ruby-file", "lib/{path}.rb", "test" => "test/{path}_test.rb")],
      policies: policies || [policy("has-test", rules:)], ruby:)
  end

  def mixed_plugin
    plugin("tests", artifacts: [declaration("ruby-file", "lib/{path}.rb", "test" => "test/{path}_test.rb", "signature" => "sig/{path}.rbs")],
      policies: [policy("has-test", rules: [rule]), policy("has-signature", rules: [rule(piece: "signature", severity: :warning)])])
  end

  def setting(name, enabled: nil, severity: nil) = PolicySetting.new(name:, enabled:, severity:, line: 4)

  def project(*plugins, policies: [], warnings: nil, verbosity: nil, unused: false)
    if unused
      first = plugins.first
      rules = [RuleDeclaration.new(name: "unused", ruby: "unused.rb", line: 3)]
      plugins = [first.with(manifest: first.manifest.with(rules:))] + plugins.drop(1)
    end
    configuration = Configuration.new(file: ".config/crosslint/config.kdl", plugins: plugins.map(&:listing), policies:, warnings:, verbosity:)
    Project.new(root: ROOT, configuration:, plugins:)
  end
end
