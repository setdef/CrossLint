# frozen_string_literal: true

require "test_helper"
require "open3"

# The Angular plugin's checks of which files exist, through the app: what
# it keeps from ng-nudge, with a test for each ng-nudge defect these checks
# could copy and don't.
class AngularPathsTest < Minitest::Test
  Core = CrossLint::Core

  def setup
    @root = Dir.mktmpdir("crosslint")
  end

  def teardown
    FileUtils.rm_rf(@root)
  end

  def test_checks_every_role_for_its_spec_inside_src
    roles = %w[component directive pipe service guard resolver interceptor]
    roles.each { |role| write(@root, "src/app/a/a.#{role}.ts", "") }
    write(@root, "src/app/a/a.service.spec.ts", "")
    write(@root, "lib/b.service.ts", "")
    result = check

    assert_equal (roles - ["service"]).map { |role| ["src/app/a/a.#{role}.ts", role, "spec-exists", "no spec file at src/app/a/a.#{role}.spec.ts"] }.sort,
      findings(result)
    assert_equal "checked 1 component, 1 directive, 1 pipe, 1 service, 1 guard, 1 resolver, and 1 interceptor artifacts: 6 errors",
      result.summary.line
  end

  def test_asks_for_a_stub_and_an_interface_only_of_a_component_with_either
    write(@root, "src/a/a.component.ts", "")
    write(@root, "src/b/b.component.ts", "")
    write(@root, "src/b/b.component.stub.ts", "")
    write(@root, "src/c/c.component.ts", "")
    write(@root, "src/c/c.component.i.d.ts", "")
    %w[a b c].each { |name| write(@root, "src/#{name}/#{name}.component.spec.ts", "") }
    # The policies that read TypeScript are the fixture's tests'.
    reading = %(policy "angular/stub-matches-component" enabled=#false\npolicy "angular/interface-matches-component" enabled=#false\n)

    assert_equal [["src/b/b.component.ts", "component", "interface-exists", "no interface file at src/b/b.component.i.d.ts"],
      ["src/c/c.component.ts", "component", "stub-exists", "no stub file at src/c/c.component.stub.ts"]], findings(check(lines: reading))
  end

  # ng-nudge looked for stylesheets relative to the working directory, so
  # prefer-css-over-scss never fired (lib/artifact/component.artifact.js:71-77),
  # and gave its warning rule error (lib/config/registry/rule.registry.js:18-20).
  def test_warns_of_a_component_with_scss_and_no_css_beside_it
    %w[a b].each do |name|
      write(@root, "src/#{name}/#{name}.component.ts", "")
      write(@root, "src/#{name}/#{name}.component.spec.ts", "")
      write(@root, "src/#{name}/#{name}.component.scss", "")
    end
    write(@root, "src/b/b.component.css", "")
    result = check

    assert_equal [["src/a/a.component.ts", "component", "prefer-css-over-scss", "scss file exists at src/a/a.component.scss"]], findings(result)
    assert_equal [:warning, false], [result.violations.first.severity, result.failed]
  end

  # ng-nudge asked TypeScript whether a companion exists, so a spec
  # tsconfig.json leaves out was missing (lib/artifact/artifact-file.js:16-18).
  def test_finds_a_spec_tsconfig_leaves_out
    write(@root, "tsconfig.json", %({"include": ["src/**/*.ts"], "exclude": ["src/**/*.spec.ts"]}\n))
    write(@root, "src/a.service.ts", "")
    write(@root, "src/a.service.spec.ts", "")

    assert_empty findings(check)
  end

  # ng-nudge grouped its report by the base path's last segment
  # (lib/console-output.js:15-24).
  def test_reports_and_counts_one_artifact_per_path_and_role
    write(@root, "src/a/widget/widget.component.ts", "")
    write(@root, "src/b/widget/widget.component.ts", "")
    write(@root, "src/b/widget/widget.service.ts", "")
    result = check

    assert_equal ["src/a/widget/widget.component.ts", "src/b/widget/widget.component.ts", "src/b/widget/widget.service.ts"],
      findings(result).map(&:first)
    assert_equal "checked 2 component and 1 service artifacts: 3 errors", result.summary.line
  end

  def test_finds_the_roles_inside_the_folder_src_dir_names
    write(@root, "app/a.pipe.ts", "")
    write(@root, "src/b.pipe.ts", "")

    assert_equal [["app/a.pipe.ts", "pipe", "spec-exists", "no spec file at app/a.pipe.spec.ts"]], findings(check(%(src-dir "./app/")))
    assert_equal ["app/a.pipe.ts", "src/b.pipe.ts"], findings(check(%(src-dir "."))).map(&:first)
  end

  # ng-nudge's node-glob patterns skip a file or a folder whose name
  # starts with a dot, below src-dir; src-dir itself can be one.
  def test_finds_no_artifact_in_a_folder_or_file_under_src_dir_whose_name_starts_with_a_dot
    %w[src/.cache/a.pipe.ts src/app/.hidden/b.pipe.ts src/app/.c.pipe.ts src/.d/e/f.service.ts src/pages/.g-page.ts src/app/h.pipe.ts
      .app/i.pipe.ts .app/.j/k.pipe.ts].each { |path| write(@root, path, "") }
    settings = %(role "page" files="pages/{name}-page.ts")

    assert_equal [["src/app/h.pipe.ts", "pipe", "spec-exists", "no spec file at src/app/h.pipe.spec.ts"]], findings(check(settings))
    assert_equal [[".app/i.pipe.ts", "pipe", "spec-exists", "no spec file at .app/i.pipe.spec.ts"]], findings(check(%(src-dir ".app")))
  end

  def test_warns_once_when_no_role_matches_a_file_and_never_of_one_role_that_doesnt
    write(@root, "src/a.pipe.ts", "")
    write(@root, "src/a.pipe.spec.ts", "")

    assert_empty check.notices
    assert_equal [%(no file matches the files of any artifact of plugin angular, such as "source/{path}.component.ts")],
      check(%(src-dir "source")).notices.map(&:message)
  end

  # In ng-nudge any expects list turned its role's checks off
  # (lib/artifact/artifact.js:80-82).
  def test_checks_a_spec_only_for_a_role_that_expects_one
    write(@root, "src/a.service.ts", "")
    write(@root, "src/b.store.ts", "")
    write(@root, "src/c.guard.ts", "")
    result = check(%(role "service" {\n    expects\n  }\n  role "store" {\n    expects "spec"\n  }\n  role "guard" {\n    expects "spec"\n  }))

    assert_equal [["src/b.store.ts", "store", "spec-exists", "no spec file at src/b.store.spec.ts"],
      ["src/c.guard.ts", "guard", "spec-exists", "no spec file at src/c.guard.spec.ts"]].sort, findings(result)
    refute_includes result.summary.line, "service"
  end

  def test_finds_a_role_by_the_pattern_its_files_give_inside_src_dir_and_adds_a_role
    write(@root, "src/app/cart.store.ts", "")
    write(@root, "src/app/cart.store.spec.ts", "")
    write(@root, "src/pages/home-page.ts", "")
    write(@root, "src/app/x.service.ts", "")
    result = check(%(role "service" files="pages/{name}-page.ts"\n  role "store"))

    assert_equal [["src/pages/home-page.ts", "service", "spec-exists", "no spec file at src/pages/home-page.spec.ts"]], findings(result)
    assert_equal "checked 1 service and 1 store artifacts: 1 error", result.summary.line
  end

  def test_warns_of_a_role_pattern_that_matches_no_file
    write(@root, "src/a.service.ts", "")
    write(@root, "src/a.service.spec.ts", "")

    assert_equal [%(no file matches "src/{path}.store.ts", the files of artifact "store")], check(%(role "store")).notices.map(&:message)
  end

  # Only a component has a stub, an interface, stylesheets, and the
  # tsconfig as companions.
  def test_declares_each_role_with_its_pattern_companions_key_and_whether_a_project_may_have_none
    component = {"spec" => "src/{path}.component.spec.ts", "stub" => "src/{path}.component.stub.ts", "interface" => "src/{path}.component.i.d.ts",
                 "css" => "src/{path}.component.css", "scss" => "src/{path}.component.scss", "tsconfig" => "tsconfig.json"}
    default = %w[component directive pipe service guard resolver interceptor].map do |role|
      [role, "src/{path}.#{role}.ts", (role == "component") ? component : {"spec" => "src/{path}.#{role}.spec.ts"}, "{path}", true]
    end
    moved = component.transform_values { |pattern| pattern.sub("src/", "app/") }.merge("tsconfig" => "config/tsconfig.app.json")

    assert_equal default, declared(nil)
    assert_equal default.map { |role, *rest| (role == "service") ? [role, rest[0], {}, rest[2], rest[3]] : [role, *rest] }, declared(%(role "service" {\n    expects\n  }))
    assert_equal default.map { |role, *rest| (role == "service") ? [role, "src/x/{name}.service.ts", {"spec" => "src/x/{name}.service.spec.ts"}, "x/{name}", false] : [role, *rest] },
      declared(%(role "service" files="x/{name}.service.ts"))
    assert_equal default.map { |role, _, companions, key, optional| [role, "app/{path}.#{role}.ts", (role == "component") ? moved : companions.transform_values { it.sub("src/", "app/") }, key, optional] } +
      [["store", "app/{path}.store.ts", {"spec" => "app/{path}.store.spec.ts"}, "{path}", false]],
      declared(%(src-dir "app"\n  tsconfig "config/tsconfig.app.json"\n  role "store"))
  end

  def test_finds_a_role_in_a_folder_with_two_dots_in_its_name_and_ignores_an_empty_segment_of_a_setting
    write(@root, "src/a..b/c.store.ts", "")
    write(@root, "app/x/d.pipe.ts", "")

    assert_equal [["src/a..b/c.store.ts", "store", "spec-exists", "no spec file at src/a..b/c.store.spec.ts"]],
      findings(check(%(role "store" files="a..b/{path}.store.ts")))
    assert_equal [["app/x/d.pipe.ts", "pipe", "spec-exists", "no spec file at app/x/d.pipe.spec.ts"]], findings(check(%(src-dir "app//x")))
  end

  def test_gives_each_artifact_ng_nudges_base_path_as_its_key
    write(@root, "src/app/foo/foo.component.ts", "")
    write(@root, "src/pages/home-page.ts", "")
    result = check(%(role "page" files="pages/{name}-page.ts"))

    assert_equal [["src/app/foo/foo.component.ts", "app/foo/foo"], ["src/pages/home-page.ts", "pages/home-page.ts"]],
      result.violations.map { |violation| [violation.artifact, violation.key] }
  end

  # ng-nudge's debt file names an artifact by its base path, relative to
  # srcDir and without its role, and its rule alone.
  def test_excuses_what_a_debt_file_moved_from_ng_nudge_excuses
    write(@root, "src/app/foo/foo.component.ts", "")
    write(@root, "src/app/foo/foo.service.ts", "")
    write(@root, "src/app/bar/bar.pipe.ts", "")
    write(@root, ".config/crosslint/debt.tsv", "Rule\tArtifact\tComment\nspec-exists\tapp/foo/foo\tlater\nspec-exists\tapp/bar/bar\t\n")
    result = check(debt: true)

    assert_empty result.violations
    assert_equal "checked 1 component, 1 pipe, and 1 service artifacts: 3 accepted as debt", result.summary.line
    assert_equal [%(the entry for angular/spec-exists on app/foo/foo matches the violations of 2 artifacts, ) +
      %(src/app/foo/foo.component.ts as component and src/app/foo/foo.service.ts as service; crosslint debt update writes one entry for each)],
      result.notices.map(&:message)
  end

  # The tsconfig setting names the file the plugin's TypeScript checks
  # read: the project's tsconfig.json is valid, and the file the setting
  # names is the one whose fault stops the plugin.
  def test_reads_typescript_with_the_file_the_tsconfig_setting_names
    write(@root, "src/a/a.component.ts", "")
    %w[spec stub].each { |kind| write(@root, "src/a/a.component.#{kind}.ts", "") }
    write(@root, "src/a/a.component.i.d.ts", "")
    write(@root, "tsconfig.json", "{}\n")
    settings = %(tsconfig "./config/tsconfig.app.json")
    # Each of the two rules that read TypeScript, with the other off.
    alone = %w[stub interface].to_h { |rule| [rule, (%w[stub interface] - [rule]).map { |off| %(policy "angular/#{off}-matches-component" enabled=#false\n) }.join] }
    missing = alone.transform_values { |lines| check(settings, lines:).faults.map(&:message).uniq }
    write(@root, "config/tsconfig.app.json", "[]\n")
    found = alone.transform_values { |lines| check(settings, lines:).faults.map(&:message).uniq }

    assert_equal %w[stub interface].to_h { |rule| [rule, [%(failed in helper "angular": reads TypeScript with config/tsconfig.app.json, the tsconfig setting's file, which doesn't exist)]] },
      missing
    assert_equal %w[stub interface].to_h { |rule| [rule, [%(failed in helper "angular": The root value of a 'tsconfig.json' file must be an object.)]] },
      found
  end

  def test_stops_at_a_setting_it_cant_use_naming_the_line
    {
      %(src-dir "src"\n  src-dir "app") => [3, "src-dir is set twice; the first is on line 2"],
      %(src-dir) => [2, %(src-dir takes one path and nothing else, as in src-dir "src")],
      %(src-dir "a" "b") => [2, %(src-dir takes one path and nothing else, as in src-dir "src")],
      %(src-dir 3) => [2, %(src-dir takes one path and nothing else, as in src-dir "src")],
      %(src-dir "a" x=1) => [2, %(src-dir takes one path and nothing else, as in src-dir "src")],
      %(src-dir "a" {\n    b\n  }) => [2, %(src-dir takes one path and nothing else, as in src-dir "src")],
      %(src-dir "/src") => [2, %(src-dir takes a path inside the project, relative to its root, with / between folders, not "/src")],
      %(src-dir "C:/src") => [2, %(src-dir takes a path inside the project, relative to its root, with / between folders, not "C:/src")],
      %(src-dir "../src") => [2, %(src-dir takes a path inside the project, relative to its root, with / between folders, not "../src")],
      %(src-dir "a\\\\src") => [2, %(src-dir takes a path inside the project, relative to its root, with / between folders, not "a\\\\src")],
      %(src-dir "{src}") => [2, %(src-dir takes a path inside the project, relative to its root, with / between folders, not "{src}")],
      %(tsconfig "./") => [2, %(tsconfig takes a file's path, not "./")],
      %(tsconfig 1) => [2, %(tsconfig takes one path and nothing else, as in tsconfig "tsconfig.json")],
      %(role) => [2, %(role takes one name of letters, digits, - and _, as in role "store" files="{path}.store.ts")],
      %(role "a/b") => [2, %(role takes one name of letters, digits, - and _, as in role "store" files="{path}.store.ts")],
      %(role "a" "b") => [2, %(role takes one name of letters, digits, - and _, as in role "store" files="{path}.store.ts")],
      %(role 3) => [2, %(role takes one name of letters, digits, - and _, as in role "store" files="{path}.store.ts")],
      %(role "store"\n  role "store") => [3, %(role "store" is set twice; the first is on line 2)],
      %(role "store" pattern="x") => [2, "role takes files= and nothing else, not pattern="],
      %(role "store" files="{path}.store.js") => [2, %(role "store" takes files= as a path pattern ending in .ts, relative to src-dir)],
      %(role "store" files="/{path}.store.ts") => [2, %(role "store" takes files= as a path pattern ending in .ts, relative to src-dir)],
      %(role "store" files="../{path}.store.ts") => [2, %(role "store" takes files= as a path pattern ending in .ts, relative to src-dir)],
      %(role "store" files="{pth}.store.ts") => [2, %(role "store" takes files= as a path pattern ending in .ts, relative to src-dir)],
      %(role "store" files=3) => [2, %(role "store" takes files= as a path pattern ending in .ts, relative to src-dir)],
      %(role "store" {\n    expect "spec"\n  }) => [3, %(role "store" takes one thing in its block, expects COMPANION ...)],
      %(role "store" {\n    expects "spec"\n    expects "spec"\n  }) => [4, %(role "store" takes one thing in its block, expects COMPANION ...)],
      %(role "store" {\n    expects "spec" x=1\n  }) => [3, %(role "store" takes one thing in its block, expects COMPANION ...)],
      %(role "store" {\n    expects "stub"\n  }) => [3, %(role "store" expects "stub", and a role can expect only "spec")],
      %(role "store" {\n    expects 3\n  }) => [3, %(role "store" expects 3, and a role can expect only "spec")],
      %(role "store" {\n    expects "spec" {\n      x\n    }\n  }) => [3, %(role "store" takes one thing in its block, expects COMPANION ...)],
      %(role "store" {\n    bad\n    expects "spec"\n  }) => [3, %(role "store" takes one thing in its block, expects COMPANION ...)],
      %(role "store" {\n    expects "spec"\n    bad\n    worse\n  }) => [4, %(role "store" takes one thing in its block, expects COMPANION ...)],
      %(srcDir "src") => [2, %(unknown setting "srcDir", did you mean "src-dir"?)]
    }.each do |settings, (line, message)|
      mistake = assert_raises(Core::Mistake, settings) { check(settings) }

      assert_equal [".config/crosslint/config.kdl", line, message], [mistake.file, mistake.line, mistake.message], settings
    end
  end

  private

  def check(settings = nil, debt: false, lines: "") = app(settings, debt:, lines:).check(@root)

  def declared(settings)
    app(settings).load_project(@root).plugins.first.manifest.artifacts.map do |artifact|
      [artifact.name, artifact.files.source, artifact.companions.to_h { [it.name, it.pattern.source] }, artifact.key.source, artifact.optional]
    end
  end

  # The app, over a project whose configuration lists the plugin with
  # these settings.
  def app(settings, debt: false, lines: "")
    block = settings ? " {\n  #{settings}\n}" : ""
    write(@root, ".config/crosslint/config.kdl", %(plugin "angular"#{block}\n#{%(plugin "debt"\n) if debt}#{lines}))
    Open3.capture3("git", "init", "-q", chdir: @root) unless File.directory?(File.join(@root, ".git"))
    CrossLint::App.new(plugin_ruby: LoadedPlugins::PluginRuby.new)
  end

  def findings(result) = result.violations.map { |violation| [violation.artifact, violation.role, violation.policy, violation.message] }.sort
end
