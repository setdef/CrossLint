# frozen_string_literal: true

require "test_helper"
require "open3"

# The Angular plugin on its fixture, an Angular-shaped project with a
# component, stub, and interface for each form of input and output, a
# file of each role, and a debt file moved unchanged from ng-nudge. Its
# helper runs on Node with the plugin's own ts-morph. What it
# keeps from ng-nudge, with a test for each ng-nudge defect that reading
# TypeScript could copy and doesn't.
class AngularFixtureTest < Minitest::Test
  FIXTURE = File.join(__dir__, "fixture")

  Core = CrossLint::Core

  # ng-nudge reports, on the same project, each line here marked "both".
  # Each other line is one ng-nudge's defects hide, and ng-nudge reports
  # three that aren't here: card's interface missing title, which it
  # inherits (lib/artifact/interface-api.js:28-31), and api's spec and
  # menu's stub, which tsconfig.json leaves out
  # (lib/artifact/artifact-file.js:16-18).
  REPORTED = [
    # Both, as one widget (lib/console-output.js:15-24).
    "src/app/b/widget/widget.component.ts: no spec file at src/app/b/widget/widget.component.spec.ts (angular/spec-exists)",
    # Stylesheets relative to the working directory, and the rule's
    # declared severity (lib/artifact/component.artifact.js:71-77).
    "src/app/badge/badge.component.ts: scss file exists at src/app/badge/badge.component.scss (angular/prefer-css-over-scss)",
    # An exception that stops every check (lib/artifact/interface-api.js:20-25).
    "src/app/bare/bare.component.ts: interface file at src/app/bare/bare.component.i.d.ts has no interface, where it should have one " \
      "(angular/interface-matches-component)",
    # A decorated input with no initializer, a setter, model(),
    # outputFromObservable(), and aliases (lib/artifact/api.js:52-88).
    *%w[input:caption input:noInit input:open input:size input:tip output:changes output:openChange].flat_map do |member|
      kind, name = member.split(":")
      ["src/app/card/card.component.ts: interface missing #{kind}: #{name} (angular/interface-matches-component)",
        "src/app/card/card.component.ts: stub missing #{kind}: #{name} (angular/stub-matches-component)"]
    end,
    # Both.
    "src/app/directives/highlight.directive.ts: no spec file at src/app/directives/highlight.directive.spec.ts (angular/spec-exists)",
    "src/app/interceptors/log.interceptor.ts: no spec file at src/app/interceptors/log.interceptor.spec.ts (angular/spec-exists)",
    # An exception that stops every check.
    "src/app/pair/pair.component.ts: interface file at src/app/pair/pair.component.i.d.ts has 2 interfaces, where it should have one " \
      "(angular/interface-matches-component)",
    # Both.
    "src/app/panel/panel.component.ts: no stub file at src/app/panel/panel.component.stub.ts (angular/stub-exists)",
    # A silent pass (lib/artifact/api.js:37-38).
    "src/app/profile/profile.component.ts: stub file at src/app/profile/profile.component.stub.ts has no @Component class " \
      "(angular/stub-matches-component)",
    # expects, which turned ng-nudge's checks of the role off (lib/artifact/artifact.js:80-82).
    "src/app/stores/cart.store.ts: no spec file at src/app/stores/cart.store.spec.ts (angular/spec-exists)",
    # Both.
    "src/app/tab/tab.component.ts: no interface file at src/app/tab/tab.component.i.d.ts (angular/interface-exists)"
  ].sort.freeze

  def test_reports_what_ng_nudge_reports_and_what_its_defects_hid
    packages_installed
    result = app.check(FIXTURE)

    assert_equal REPORTED, result.violations.map { |violation| "#{violation.artifact}: #{violation.message} (#{violation.plugin}/#{violation.policy})" }
    assert_equal [:warning], result.violations.select { |violation| violation.policy == "prefer-css-over-scss" }.map(&:severity)
    # The detail of a missing member, which tells a debt entry which one it excuses.
    members = %w[input\ caption input\ noInit input\ open input\ size input\ tip output\ changes output\ openChange]
    assert_equal (members * 2).sort, result.violations.select { |violation| violation.message.match?(/ missing (in|out)put: /) }.map(&:detail).sort
    assert_equal ["checked 12 component, 1 directive, 1 pipe, 2 service, 1 guard, 1 resolver, 1 interceptor, and 1 store artifacts: " \
      "23 errors, 1 warning, 3 accepted as debt", true, []], [result.summary.line, result.failed, result.faults]
  end

  # ng-nudge's debt file names an artifact by its base path, relative to
  # srcDir and without its role, and its rule alone, so its entry for
  # foo's spec excuses the component and the service both, as ng-nudge's
  # does (lib/debt.js:30-35).
  def test_excuses_what_a_debt_file_moved_from_ng_nudge_excuses
    packages_installed
    result = app.check(FIXTURE)

    assert_empty result.violations.map(&:artifact).grep(%r{/(foo|pipes)/})
    assert_equal ["3 accepted as debt"], result.summary.steps
    assert_equal [".config/crosslint/debt.tsv:2: the entry for angular/spec-exists on app/foo/foo matches the violations of 2 artifacts, " \
      "src/app/foo/foo.component.ts as component and src/app/foo/foo.service.ts as service; crosslint debt update writes one entry for each"],
      result.notices.map { |notice| "#{notice.file}:#{notice.line}: #{notice.message}" }
  end

  # A project without the helper's command gets exit status 2, naming the
  # plugin and the command.
  def test_stops_with_2_naming_the_plugin_and_node_when_node_isnt_on_the_path
    packages_installed
    without_node = app(helpers: CrossLint::Adapters::ProcessHelpers.new(err: StringIO.new, debug: false, env: {"PATH" => ""}))
    err = StringIO.new
    status = CrossLint::CLI.new(["check", "-C", FIXTURE], out: StringIO.new, err:, env: {}, app: without_node).run

    assert_equal 2, status
    assert_match %(plugin angular needs node on the PATH for its helper "angular", and there is none), err.string
  end

  # The plugin reads TypeScript with its own ts-morph, so a project needs
  # its tsconfig and no typescript package of its own; a tsconfig the
  # helper can't read stops the plugin with what the helper said.
  def test_stops_the_plugin_at_a_project_without_its_tsconfig_or_with_one_the_helper_cant_read
    root = Dir.mktmpdir("crosslint")
    write(root, ".config/crosslint/config.kdl", %(plugin "angular"\n))
    write(root, "src/a/a.component.ts", "")
    write(root, "src/a/a.component.spec.ts", "")
    write(root, "src/a/a.component.stub.ts", "")
    write(root, "src/a/a.component.i.d.ts", "")
    Open3.capture3("git", "init", "-q", chdir: root)
    missing = app.check(root).faults.map(&:message)
    write(root, "tsconfig.json", "{}\n")
    found = app.check(root).faults.map(&:message)
    write(root, "tsconfig.json", "[]\n")
    unreadable = app.check(root).faults.map(&:message)

    assert_equal [[%(failed in helper "angular": reads TypeScript with tsconfig.json, the tsconfig setting's file, which doesn't exist)]],
      [missing.uniq]
    assert_empty found
    assert_equal [%(failed in helper "angular": The root value of a 'tsconfig.json' file must be an object.)], unreadable.uniq
  ensure
    FileUtils.rm_rf(root)
  end

  private

  def app(**options) = CrossLint::App.new(plugin_ruby: LoadedPlugins::PluginRuby.new, **options)

  # Installing the plugin's own packages is a setup step, npm ci in
  # plugins/angular, which no test runs.
  def packages_installed
    modules = File.join(__dir__, "..", "node_modules", "ts-morph")
    flunk "plugins/angular/node_modules/ts-morph doesn't exist; run npm ci in plugins/angular" unless File.directory?(modules)
  end
end
