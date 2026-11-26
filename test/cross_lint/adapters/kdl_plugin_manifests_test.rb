# frozen_string_literal: true

require "test_helper"

class KDLPluginManifestsTest < Minitest::Test
  cover "CrossLint::Adapters::KDLPluginManifests*"

  include CrossLint::Testing::PluginManifestsContract
  include CrossLint::Core

  EXAMPLE = <<~KDL
    artifact "ruby-file" {
      files "lib/{path}.rb"
      companion "signature" "sig/{path}.rbs"
    }

    policy "has-signature" {
      applies-to "ruby-file"
      rule "companion-exists" companion="signature" severity="warning"
    }

    rule "names-class" ruby="rules/names_class.rb"
    helper "members" command="node" file="helpers/members.mjs"
  KDL

  CONTRACT_EXAMPLE = <<~KDL
    artifact "ruby-file" {
      files "lib/{path}.rb"
      companion "signature" "sig/{path}.rbs"
      companion "test" "test/{path}_test.rb"
    }

    policy "has-signature" {
      applies-to "ruby-file"
      rule "companion-exists" companion="signature" severity="warning"
    }

    policy "names-match" {
      applies-to "ruby-file"
      when not { companion-exists "test"; }
      rule "names-class"
    }

    policy "covered" {
      applies-to "ruby-file"
      when all { companion-exists "signature"; companion-exists "test"; }
      rule "companion-exists" companion="test" severity="error"
    }

    policy "either" {
      applies-to "ruby-file"
      when any { companion-exists "signature"; not { companion-exists "test"; }; }
      rule "companion-absent" companion="signature"
    }

    rule "names-class" ruby="rules/names_class.rb"
    helper "members" command="node" file="helpers/members.mjs"

    policy "has-debt"
    setting "file"
    setting "report-entries"
    command "update" help="Rewrite the debt file to list the current violations"
    step "track-debt"
  KDL

  def setup
    @base = Dir.mktmpdir("crosslint")
  end

  def teardown
    FileUtils.rm_rf(@base)
  end

  attr_reader :base

  def manifests_port(example: [], broken: [])
    example.each { |folder| write(@base, File.join(folder, "plugin.kdl"), CONTRACT_EXAMPLE) }
    broken.each { |folder| write(@base, File.join(folder, "plugin.kdl"), %(artifact "a" {\n  file "b"\n}\n)) }
    CrossLint::Adapters::KDLPluginManifests.new
  end

  def test_reads_every_example_in_the_plugin_reference
    first, ruby_rule, helper, steps = doc_blocks("docs/reference/plugin.md", "kdl").map { |text| read(text) }

    assert_equal [["ruby-file", ["signature", "test"]]], first.artifacts.map { |artifact| [artifact.name, artifact.companions.map(&:name)] }
    assert_equal [["has-signature", nil], ["has-test", :warning]], first.policies.map { |policy| [policy.name, policy.rules.first.severity] }
    assert_equal [["signature-names-class", "rules/signature_names_class.rb", 1]],
      ruby_rule.rules.map { |rule| [rule.name, rule.ruby, rule.line] }
    assert_equal Condition::CompanionExists.new(companion: "signature", line: 5), ruby_rule.policies.first.condition
    assert_equal [HelperDeclaration.new(name: "members", command: "node", file: "helpers/members.mjs", line: 1)], helper.helpers
    assert_equal [["track-debt"], ["has-debt"], ["file", "report-entries"], ["update"]],
      [steps.steps, steps.step_policies, steps.settings, steps.commands].map { |list| list.map(&:name) }
    assert_equal [CommandDeclaration.new(name: "update", help: "Rewrite the debt file to list the current violations", line: 8)], steps.commands
  end

  def test_reads_the_plugins_in_the_readme_and_the_tutorial
    [doc_blocks("README.md", "kdl").fetch(0), doc_blocks("docs/getting-started.md", "kdl").fetch(0)].each do |text|
      manifest = read(text)

      assert_equal [["ruby-file", "lib/{path}.rb"]], manifest.artifacts.map { |artifact| [artifact.name, artifact.files.source] }
      assert_equal [{"companion" => manifest.artifacts.first.companions.first.name}], manifest.policies.first.rules.map(&:arguments)
    end
  end

  def test_reads_each_condition
    manifest = read(<<~KDL)
      artifact "component" {
        files "src/{path}.component.ts"
        companion "stub" "src/{path}.stub.ts"
        companion "interface" "src/{path}.interface.ts"
      }
      policy "stub-exists" {
        applies-to "component"
        when not {
          all {
            companion-exists "stub"
            any { companion-exists "interface"; companion-exists "stub"; }
          }
        }
        rule "companion-exists" companion="stub"
      }
    KDL
    stub = Condition::CompanionExists.new(companion: "stub", line: 10)
    any = Condition::Any.new(conditions: [Condition::CompanionExists.new(companion: "interface", line: 11),
      Condition::CompanionExists.new(companion: "stub", line: 11)], line: 11)

    assert_equal Condition::Not.new(condition: Condition::All.new(conditions: [stub, any], line: 9), line: 8),
      manifest.policies.first.condition
  end

  def test_reads_the_lines_of_what_it_declares
    manifest = read(EXAMPLE)
    artifact = manifest.artifacts.first
    policy = manifest.policies.first

    assert_equal [1, 3, 6, 7, 8, 11, 12], [artifact.line, artifact.companions.first.line, policy.line, policy.applies_to.line,
      policy.rules.first.line, manifest.rules.first.line, manifest.helpers.first.line]
  end

  def test_refuses_a_node_it_does_not_know
    assert_refuses 2, %(unknown node "file", did you mean "files"?), %(artifact "a" {\n  file "lib/{path}.rb"\n}\n)
    assert_refuses 1, %(unknown node "artefact", did you mean "artifact"?), %(artefact "a")
    assert_refuses 1, %(unknown node "zzz"; expected "artifact", "artifacts", "policy", "rule", "helper", "setting", "command", or "step"), %(zzz)
    assert_refuses 2, %(unknown node "polcy", did you mean "policy"?), %(rule "r" ruby="r.rb"\npolcy "p")
  end

  def test_refuses_an_artifact_written_wrong
    assert_refuses 1, "artifact has 0 arguments; write it as artifact NAME { ... }", %(artifact { files "a"; })
    assert_refuses 1, %(unknown property "kind"; artifact takes none), %(artifact "a" kind="x" { files "a"; })
    assert_refuses 1, %(artifact "a" has no files), %(artifact "a" { companion "b" "c"; })
    assert_refuses 3, "artifact has files twice; the first is on line 2", %(artifact "a" {\n  files "x"\n  files "y"\n}\n)
    assert_refuses 2, "files has 2 arguments; write it as files PATTERN", %(artifact "a" {\n  files "x" "y"\n}\n)
    assert_refuses 2, %(unknown property "glob"; files takes none), %(artifact "a" {\n  files "x" glob=#true\n}\n)
    assert_refuses 2, %(unknown node "x"; files takes no children), %(artifact "a" {\n  files "x" { x; }\n}\n)
    assert_refuses 3, "companion has 1 argument; write it as companion NAME PATTERN", %(artifact "a" {\n  files "x"\n  companion "b"\n}\n)
    assert_refuses 3, %(unknown property "optional"; companion takes none),
      %(artifact "a" {\n  files "x"\n  companion "b" "c" optional=#true\n}\n)
  end

  def test_refuses_a_path_pattern_that_is_not_one
    assert_refuses 2, %(path pattern "lib/{pth}.rb" has unknown placeholder "{pth}", did you mean "{path}"?),
      %(artifact "a" {\n  files "lib/{pth}.rb"\n}\n)
    assert_refuses 3, %(path pattern "" is empty), %(artifact "a" {\n  files "x"\n  companion "b" ""\n}\n)
  end

  def test_reads_the_file_whose_ruby_declares_artifacts
    assert_equal [nil, ArtifactsRuby.new(ruby: "roles.rb", line: 2)],
      [read(%(setting "x"\n)).artifacts_ruby, read(%(setting "x"\nartifacts ruby="roles.rb"\n)).artifacts_ruby]
  end

  def test_refuses_artifacts_written_wrong
    assert_refuses 2, "artifacts is declared twice; the first is on line 1", %(artifacts ruby="a.rb"\nartifacts ruby="b.rb"\n)
    assert_refuses 1, "artifacts has no ruby=, the file that declares them", %(artifacts\n)
    assert_refuses 1, "artifacts has 1 argument; write it as artifacts ruby=FILE", %(artifacts "a.rb"\n)
    assert_refuses 1, %(unknown property "rb"; expected "ruby"), %(artifacts rb="a.rb"\n)
    assert_refuses 2, %(unknown node "x"; artifacts takes no children), %(artifacts ruby="a.rb" {\n  x\n}\n)
  end

  def test_reads_a_policy_with_no_applies_to
    assert_equal [["p", nil, ["r"]]], read(%(policy "p" { rule "r"; })).policies.map { |policy| [policy.name, policy.applies_to, policy.rules.map(&:name)] }
  end

  def test_refuses_a_policy_written_wrong
    assert_refuses 3, "policy has applies-to twice; the first is on line 2", %(policy "p" {\n  applies-to "a"\n  applies-to "b"\n  rule "r"\n}\n)
    assert_refuses 1, %(policy "p" has no rule), %(policy "p" { applies-to "a"; })
    assert_refuses 2, "applies-to has 3 where a string goes; write it as applies-to ARTIFACT", %(policy "p" {\n  applies-to 3\n  rule "r"\n}\n)
    assert_refuses 2, %(unknown node "appliesto", did you mean "applies-to"?), %(policy "p" {\n  appliesto "a"\n}\n)
    assert_refuses 4, "policy has when twice; the first is on line 3",
      %(policy "p" {\n  applies-to "a"\n  when companion-exists "b"\n  when companion-exists "c"\n  rule "r"\n}\n)
    assert_refuses 1, %(unknown property "x"; policy takes none), %(policy "p" x=1 { applies-to "a"; rule "r"; })
    assert_refuses 2, %(unknown property "x"; applies-to takes none), %(policy "p" {\n  applies-to "a" x=1\n  rule "r"\n}\n)
  end

  def test_refuses_a_policy_rule_written_wrong
    assert_refuses 3, %(unknown severity "warn", did you mean "warning"?), %(policy "p" {\n  applies-to "a"\n  rule "r" severity="warn"\n}\n)
    assert_refuses 3, "rule has 0 arguments; write it as rule RULE", %(policy "p" {\n  applies-to "a"\n  rule companion="b"\n}\n)
    assert_refuses 4, %(unknown node "x"; rule takes no children), %(policy "p" {\n  applies-to "a"\n  rule "r" {\n    x\n  }\n}\n)
  end

  def test_reads_a_policy_rule_with_no_severity
    assert_equal [["r", {"style" => "strict"}, nil]],
      read(%(policy "p" { applies-to "a"; rule "r" style="strict"; })).policies.first.rules.map { |rule| [rule.name, rule.arguments, rule.severity] }
  end

  def test_refuses_a_condition_written_wrong
    assert_refuses 3, "when has no condition; write it as when companion-exists COMPANION", policy_with("when")
    assert_refuses 3, %(unknown condition "companion-exist", did you mean "companion-exists"?), policy_with(%(when companion-exist "b"))
    assert_refuses 3, %(unknown condition "zzz"; expected "companion-exists", "not", "all", or "any"), policy_with(%(when zzz))
    assert_refuses 3, "companion-exists has 0 arguments; write it as companion-exists COMPANION", policy_with(%(when companion-exists))
    assert_refuses 3, %(unknown node "x"; companion-exists takes no children), policy_with(%(when companion-exists "b" { x; }))
    assert_refuses 3, %(unknown property "x"; companion-exists takes none), policy_with(%(when companion-exists "b" x=1))
    assert_refuses 3, "not has 0 conditions; write it as not { CONDITION }", policy_with(%(when not))
    assert_refuses 3, "not has 2 conditions; write it as not { CONDITION }",
      policy_with(%(when not { companion-exists "b"; companion-exists "c"; }))
    assert_refuses 3, "all has no condition; write it as all { CONDITION ... }", policy_with(%(when all))
    assert_refuses 3, "any has no condition; write it as any { CONDITION ... }", policy_with(%(when any { }))
    assert_refuses 3, "all has 1 argument; write it as all { CONDITION ... }", policy_with(%(when all "b" { companion-exists "b"; }))
    assert_refuses 3, "not has 1 argument; write it as not { CONDITION }", policy_with(%(when not "b" { companion-exists "b"; }))
  end

  def test_reads_a_policy_with_no_block_as_one_a_step_reports
    manifest = read(%(policy "has-debt"\npolicy "p" {\n  applies-to "a"\n  rule "r"\n}\n))

    assert_equal [[["has-debt", 1]], ["p"]], [manifest.step_policies.map { |policy| [policy.name, policy.line] }, manifest.policies.map(&:name)]
  end

  def test_refuses_a_setting_or_step_written_wrong
    %w[setting step].each do |kind|
      assert_refuses 1, "#{kind} has 0 arguments; write it as #{kind} NAME", kind
      assert_refuses 1, %(unknown property "x"; #{kind} takes none), %(#{kind} "a" x=1)
      assert_refuses 1, %(unknown node "x"; #{kind} takes no children), %(#{kind} "a" { x; })
    end
    assert_refuses 1, %(unknown property "x"; policy takes none), %(policy "a" x=1)
    assert_refuses 1, "policy has 0 arguments; write it as policy NAME { ... }", %(policy { applies-to "a"; })
  end

  def test_refuses_a_ruby_rule_written_wrong
    assert_refuses 1, %(rule "r" has no ruby=, the file its code is in), %(rule "r")
    assert_refuses 1, %(unknown property "rubby", did you mean "ruby"?), %(rule "r" rubby="r.rb")
    assert_refuses 1, %(unknown node "x"; rule takes no children), %(rule "r" ruby="r.rb" { x; })
    assert_refuses 1, "ruby= takes a string, not 1", %(rule "r" ruby=1)
  end

  def test_reads_a_command_with_its_help
    manifest = read(%(step "s"\ncommand "update" help="Rewrite it"\ncommand "check-all" help="Check all"\n))

    assert_equal [CommandDeclaration.new(name: "update", help: "Rewrite it", line: 2), CommandDeclaration.new(name: "check-all", help: "Check all", line: 3)],
      manifest.commands
    assert_empty read(%(step "s")).commands
  end

  def test_refuses_a_command_written_wrong
    assert_refuses 1, %(command "update" has no help=, its line in --help), %(command "update")
    assert_refuses 1, %(command "update" has no help=, its line in --help), %(command "update" help="")
    assert_refuses 1, %(command "update" has no help=, its line in --help), %(command "update" help=" ")
    assert_refuses 1, "command has 0 arguments; write it as command NAME help=TEXT", %(command help="Help")
    assert_refuses 1, %(unknown property "hlp", did you mean "help"?), %(command "update" hlp="Help")
    assert_refuses 1, %(unknown node "x"; command takes no children), %(command "update" help="Help" { x; })
    assert_refuses 1, "help= takes a string, not 1", %(command "update" help=1)
  end

  def test_refuses_a_flag_as_a_mistake_that_says_what_to_write_instead
    message = "flag isn't a node CrossLint reads: a plugin adds commands under its own name, as in command NAME help=TEXT, and no flag to crosslint check"

    assert_refuses 1, message, %(flag "update-debt")
    assert_refuses 2, message, %(step "s"\nflag "update-debt" help="x"\n)
  end

  def test_refuses_a_helper_written_wrong
    assert_refuses 1, %(helper "h" has no command=, the program it runs on), %(helper "h" file="h.mjs")
    assert_refuses 1, %(helper "h" has no file=, the program's file in the plugin), %(helper "h" command="node")
    assert_refuses 1, %(unknown property "cmd"; expected "command" or "file"), %(helper "h" cmd="node" file="h.mjs")
    assert_refuses 1, %(unknown node "x"; helper takes no children), %(helper "h" command="node" file="h.mjs" { x; })
  end

  def test_shows_how_to_write_each_node_with_the_wrong_arguments
    {
      %(artifact) => "artifact has 0 arguments; write it as artifact NAME { ... }",
      %(policy) => "policy has 0 arguments; write it as policy NAME { ... }",
      %(rule) => "rule has 0 arguments; write it as rule NAME ruby=FILE",
      %(helper) => "helper has 0 arguments; write it as helper NAME command=COMMAND file=FILE",
      %(artifact "a" { files; }) => "files has 0 arguments; write it as files PATTERN",
      %(artifact "a" { files "x"; companion; }) => "companion has 0 arguments; write it as companion NAME PATTERN",
      %(policy "p" { applies-to; }) => "applies-to has 0 arguments; write it as applies-to ARTIFACT",
      %(policy "p" { applies-to "a"; rule; }) => "rule has 0 arguments; write it as rule RULE",
      %(policy "p" { applies-to "a"; when companion-exists; rule "r"; }) =>
        "companion-exists has 0 arguments; write it as companion-exists COMPANION"
    }.each { |text, message| assert_refuses 1, message, text }
  end

  def test_refuses_a_condition_that_is_not_a_name
    assert_refuses 3, %(unknown condition "3"; expected "companion-exists", "not", "all", or "any"), policy_with(%(when 3))
  end

  def test_names_the_manifest_by_its_folder
    write(@base, "plugin.kdl", "zzz\n")
    mistake = assert_raises(Mistake) { CrossLint::Adapters::KDLPluginManifests.new.read(@base, "") }

    assert_equal "plugin.kdl:1", mistake.location
  end

  def test_takes_no_folder_named_like_the_manifest_for_it
    FileUtils.mkdir_p(File.join(@base, "plugins/x/plugin.kdl"))

    assert_nil CrossLint::Adapters::KDLPluginManifests.new.read(@base, "plugins/x")
  end

  def test_reads_a_file_that_starts_with_a_byte_order_mark
    assert_equal ["h"], read(%(\xEF\xBB\xBFhelper "h" command="node" file="h.mjs"\n)).helpers.map(&:name)
  end

  private

  def read(text)
    write(@base, "plugins/x/plugin.kdl", text)
    CrossLint::Adapters::KDLPluginManifests.new.read(@base, "plugins/x")
  end

  def assert_refuses(line, message, text)
    mistake = assert_raises(Mistake) { read(text) }

    assert_equal ["plugins/x/plugin.kdl", line, message], [mistake.file, mistake.line, mistake.message]
  end

  def policy_with(condition) = %(policy "p" {\n  applies-to "a"\n  #{condition}\n  rule "r"\n}\n)
end
