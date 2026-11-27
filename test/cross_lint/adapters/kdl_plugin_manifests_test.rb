# frozen_string_literal: true

require "test_helper"

class KDLPluginManifestsTest < Minitest::Test
  cover "CrossLint::Adapters::KDLPluginManifests*"

  include CrossLint::Testing::PluginManifestsContract
  include CrossLint::Core

  EXAMPLE = <<~KDL
    artifact "ruby-file" {
      primary "lib/{path}.rb"
      piece "signature" "sig/{path}.rbs"
    }

    policy "has-signature" {
      applies-to "ruby-file"
      rule "piece-exists" piece="signature" severity="warning"
    }

    rule "names-class" ruby="rules/names_class.rb"
    helper "members" command="node" file="helpers/members.mjs"
  KDL

  CONTRACT_EXAMPLE = <<~KDL
    artifact "ruby-file" {
      primary "lib/{path}.rb"
      piece "signature" "sig/{path}.rbs"
      piece "test" "test/{path}_test.rb"
    }

    policy "has-signature" {
      applies-to "ruby-file"
      rule "piece-exists" piece="signature" severity="warning"
    }

    policy "names-match" {
      applies-to "ruby-file"
      when not { piece-exists "test"; }
      rule "names-class"
    }

    policy "covered" {
      applies-to "ruby-file"
      when all { piece-exists "signature"; piece-exists "test"; }
      rule "piece-exists" piece="test" severity="error"
    }

    policy "either" {
      applies-to "ruby-file"
      when any { piece-exists "signature"; not { piece-exists "test"; }; }
      rule "piece-absent" piece="signature"
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
    first, ruby_rule, helper, helped, steps, artifacts = doc_blocks("docs/reference/plugin.md", "kdl").map { |text| read(text) }

    assert_equal [["ruby-file", ["signature", "test"]]], first.artifacts.map { |artifact| [artifact.name, artifact.pieces.map(&:name)] }
    assert_equal [["has-signature", nil], ["has-test", :warning]], first.policies.map { |policy| [policy.name, policy.rules.first.severity] }
    assert_equal [["signature-names-class", "rules/signature_names_class.rb", 1]],
      ruby_rule.rules.map { |rule| [rule.name, rule.ruby, rule.line] }
    assert_equal Condition::PieceExists.new(piece: "signature", line: 5), ruby_rule.policies.first.condition
    assert_equal [HelperDeclaration.new(name: "members", command: "node", file: "helpers/members.mjs", line: 1)], helper.helpers
    assert_equal [[RuleDeclaration.new(name: "stub-matches-component", helper: "angular", line: 2)], ["angular"]], [helped.rules, helped.helpers.map(&:name)]
    assert_equal [ArtifactsRuby.new(ruby: "artifacts.rb", line: 3)], [artifacts.artifacts_ruby]
    assert_equal [["track-debt"], ["has-debt"], ["file", "report-entries"], ["update"]],
      [steps.steps, steps.step_policies, steps.settings, steps.commands].map { |list| list.map(&:name) }
    flag = CommandFlag.new(short: "n", long: "dry-run", value: nil, help: "List the entries update would add and remove, and write nothing", line: 9)

    assert_equal [CommandDeclaration.new(name: "update", help: "Rewrite the debt file to list the current violations", line: 8, flags: [flag])], steps.commands
  end

  def test_reads_the_plugins_in_the_readme_and_the_tutorial
    [doc_blocks("README.md", "kdl").fetch(0), doc_blocks("docs/getting-started.md", "kdl").fetch(0)].each do |text|
      manifest = read(text)

      assert_equal [["ruby-file", "lib/{path}.rb"]], manifest.artifacts.map { |artifact| [artifact.name, artifact.primary.source] }
      assert_equal [{"piece" => manifest.artifacts.first.pieces.first.name}], manifest.policies.first.rules.map(&:arguments)
    end
  end

  def test_reads_each_condition
    manifest = read(<<~KDL)
      artifact "component" {
        primary "src/{path}.component.ts"
        piece "stub" "src/{path}.stub.ts"
        piece "interface" "src/{path}.interface.ts"
      }
      policy "stub-exists" {
        applies-to "component"
        when not {
          all {
            piece-exists "stub"
            any { piece-exists "interface"; piece-exists "stub"; }
          }
        }
        rule "piece-exists" piece="stub"
      }
    KDL
    stub = Condition::PieceExists.new(piece: "stub", line: 10)
    any = Condition::Any.new(conditions: [Condition::PieceExists.new(piece: "interface", line: 11),
      Condition::PieceExists.new(piece: "stub", line: 11)], line: 11)

    assert_equal Condition::Not.new(condition: Condition::All.new(conditions: [stub, any], line: 9), line: 8),
      manifest.policies.first.condition
  end

  def test_reads_the_lines_of_what_it_declares
    manifest = read(EXAMPLE)
    artifact = manifest.artifacts.first
    policy = manifest.policies.first

    assert_equal [1, 3, 6, 7, 8, 11, 12], [artifact.line, artifact.pieces.first.line, policy.line, policy.applies_to.line,
      policy.rules.first.line, manifest.rules.first.line, manifest.helpers.first.line]
  end

  def test_refuses_a_node_it_does_not_know
    assert_refuses 2, %(unknown node "primay", did you mean "primary"?), %(artifact "a" {\n  primay "lib/{path}.rb"\n}\n)
    assert_refuses 1, %(unknown node "artefact", did you mean "artifact"?), %(artefact "a")
    assert_refuses 1, %(unknown node "zzz"; expected "artifact", "artifacts", "policy", "rule", "helper", "setting", "command", or "step"), %(zzz)
    assert_refuses 2, %(unknown node "polcy", did you mean "policy"?), %(rule "r" ruby="r.rb"\npolcy "p")
  end

  def test_refuses_an_artifact_written_wrong
    assert_refuses 1, "artifact has 0 arguments; write it as artifact NAME { ... }", %(artifact { primary "a"; })
    assert_refuses 1, %(unknown property "kind"; artifact takes none), %(artifact "a" kind="x" { primary "a"; })
    assert_refuses 1, %(artifact "a" has no primary), %(artifact "a" { piece "b" "c"; })
    assert_refuses 3, "artifact has primary twice; the first is on line 2", %(artifact "a" {\n  primary "x"\n  primary "y"\n}\n)
    assert_refuses 2, "primary has 2 arguments; write it as primary PATTERN", %(artifact "a" {\n  primary "x" "y"\n}\n)
    assert_refuses 2, %(unknown property "glob"; primary takes none), %(artifact "a" {\n  primary "x" glob=#true\n}\n)
    assert_refuses 2, %(unknown node "x"; primary takes no children), %(artifact "a" {\n  primary "x" { x; }\n}\n)
    assert_refuses 3, "piece has 1 argument; write it as piece NAME PATTERN", %(artifact "a" {\n  primary "x"\n  piece "b"\n}\n)
    assert_refuses 3, %(unknown property "optional"; piece takes none),
      %(artifact "a" {\n  primary "x"\n  piece "b" "c" optional=#true\n}\n)
  end

  def test_refuses_a_path_pattern_that_is_not_one
    assert_refuses 2, %(path pattern "lib/{pth}.rb" has unknown placeholder "{pth}", did you mean "{path}"?),
      %(artifact "a" {\n  primary "lib/{pth}.rb"\n}\n)
    assert_refuses 3, %(path pattern "" is empty), %(artifact "a" {\n  primary "x"\n  piece "b" ""\n}\n)
  end

  def test_reads_the_file_whose_ruby_declares_artifacts
    assert_equal [nil, ArtifactsRuby.new(ruby: "roles.rb", line: 2)],
      [read(%(setting "x"\n)).artifacts_ruby, read(%(setting "x"\nartifacts ruby="roles.rb"\n)).artifacts_ruby]
  end

  def test_reads_the_helper_that_declares_artifacts
    helped = read(%(helper "roles" command="node" file="roles.mjs"\nartifacts helper="roles"\n))

    assert_equal [nil, ArtifactsHelper.new(helper: "roles", line: 2), nil],
      [read(%(setting "x"\n)).artifacts_helper, helped.artifacts_helper, helped.artifacts_ruby]
  end

  def test_refuses_artifacts_written_wrong
    assert_refuses 2, "artifacts is declared twice; the first is on line 1", %(artifacts ruby="a.rb"\nartifacts ruby="b.rb"\n)
    assert_refuses 1, "artifacts has neither ruby=, the file that declares them, nor helper=, the helper that declares them", %(artifacts\n)
    assert_refuses 1, "artifacts has both ruby= and helper=; artifacts are declared in the plugin's Ruby or by its helper", %(artifacts ruby="a.rb" helper="h"\n)
    assert_refuses 1, "artifacts has 1 argument; write it as artifacts ruby=FILE or artifacts helper=HELPER", %(artifacts "a.rb"\n)
    assert_refuses 1, %(unknown property "rb"; expected "ruby" or "helper"), %(artifacts rb="a.rb"\n)
    assert_refuses 1, "helper= takes a string, not 1", %(artifacts helper=1\n)
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
      %(policy "p" {\n  applies-to "a"\n  when piece-exists "b"\n  when piece-exists "c"\n  rule "r"\n}\n)
    assert_refuses 1, %(unknown property "x"; policy takes none), %(policy "p" x=1 { applies-to "a"; rule "r"; })
    assert_refuses 2, %(unknown property "x"; applies-to takes none), %(policy "p" {\n  applies-to "a" x=1\n  rule "r"\n}\n)
  end

  def test_refuses_a_policy_rule_written_wrong
    assert_refuses 3, %(unknown severity "warn", did you mean "warning"?), %(policy "p" {\n  applies-to "a"\n  rule "r" severity="warn"\n}\n)
    assert_refuses 3, "rule has 0 arguments; write it as rule RULE", %(policy "p" {\n  applies-to "a"\n  rule piece="b"\n}\n)
    assert_refuses 4, %(unknown node "x"; rule takes no children), %(policy "p" {\n  applies-to "a"\n  rule "r" {\n    x\n  }\n}\n)
  end

  def test_reads_a_policy_rule_with_no_severity
    assert_equal [["r", {"style" => "strict"}, nil]],
      read(%(policy "p" { applies-to "a"; rule "r" style="strict"; })).policies.first.rules.map { |rule| [rule.name, rule.arguments, rule.severity] }
  end

  def test_refuses_a_condition_written_wrong
    assert_refuses 3, "when has no condition; write it as when piece-exists PIECE", policy_with("when")
    assert_refuses 3, %(unknown condition "piece-exist", did you mean "piece-exists"?), policy_with(%(when piece-exist "b"))
    assert_refuses 3, %(unknown condition "zzz"; expected "piece-exists", "not", "all", or "any"), policy_with(%(when zzz))
    assert_refuses 3, "piece-exists has 0 arguments; write it as piece-exists PIECE", policy_with(%(when piece-exists))
    assert_refuses 3, %(unknown node "x"; piece-exists takes no children), policy_with(%(when piece-exists "b" { x; }))
    assert_refuses 3, %(unknown property "x"; piece-exists takes none), policy_with(%(when piece-exists "b" x=1))
    assert_refuses 3, "not has 0 conditions; write it as not { CONDITION }", policy_with(%(when not))
    assert_refuses 3, "not has 2 conditions; write it as not { CONDITION }",
      policy_with(%(when not { piece-exists "b"; piece-exists "c"; }))
    assert_refuses 3, "all has no condition; write it as all { CONDITION ... }", policy_with(%(when all))
    assert_refuses 3, "any has no condition; write it as any { CONDITION ... }", policy_with(%(when any { }))
    assert_refuses 3, "all has 1 argument; write it as all { CONDITION ... }", policy_with(%(when all "b" { piece-exists "b"; }))
    assert_refuses 3, "not has 1 argument; write it as not { CONDITION }", policy_with(%(when not "b" { piece-exists "b"; }))
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

  def test_reads_a_rule_its_helper_runs
    assert_equal [RuleDeclaration.new(name: "r", helper: "h", line: 1)], read(%(rule "r" helper="h"\n)).rules
  end

  def test_refuses_a_ruby_rule_written_wrong
    assert_refuses 1, %(rule "r" has neither ruby=, the file its code is in, nor helper=, the helper that runs it), %(rule "r")
    assert_refuses 1, %(rule "r" has both ruby= and helper=; a rule is in the plugin's Ruby or run by its helper), %(rule "r" ruby="r.rb" helper="h")
    assert_refuses 1, "helper= takes a string, not 1", %(rule "r" helper=1)
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
    assert_refuses 1, "command has 0 arguments; write it as command NAME help=TEXT", %(command help="Help")
    assert_refuses 1, %(unknown property "hlp", did you mean "help"?), %(command "update" hlp="Help")
    assert_refuses 1, %(unknown node "x"; expected "flag"), %(command "update" help="Help" { x; })
    assert_refuses 1, "help= takes a string, not 1", %(command "update" help=1)
  end

  def test_reads_the_flags_a_command_declares_in_the_usage_specs_syntax
    manifest = read(%(step "s"\ncommand "update" help="Rewrite it" {\n  flag "-n --dry-run" help="Write nothing"\n  flag "--since <rev>" help="From a revision"\n}\n))

    assert_equal [CommandFlag.new(short: "n", long: "dry-run", value: nil, help: "Write nothing", line: 3),
      CommandFlag.new(short: nil, long: "since", value: "rev", help: "From a revision", line: 4)], manifest.commands.first.flags
    assert_empty read(%(command "update" help="Rewrite it" {\n}\n)).commands.first.flags
  end

  def test_refuses_a_flag_of_a_command_written_wrong
    inside = ->(flag) { %(command "update" help="Help" {\n  #{flag}\n}\n) }

    assert_refuses 2, %(flag "-n --dry-run" has no help=, its line in --help), inside.call(%(flag "-n --dry-run"))
    assert_refuses 2, %(flag "-n --dry-run" has no help=, its line in --help), inside.call(%(flag "-n --dry-run" help=""))
    assert_refuses 2, %(flag "-n" has no long name), inside.call(%(flag "-n" help="x"))
    assert_refuses 2, %(flag "-n --Dry" has "--Dry", which CrossLint doesn't read), inside.call(%(flag "-n --Dry" help="x"))
    assert_refuses 2, "flag has 0 arguments; write it as flag NAMES help=TEXT", inside.call(%(flag help="x"))
    assert_refuses 2, %(unknown property "hlp", did you mean "help"?), inside.call(%(flag "--n" hlp="x"))
    assert_refuses 2, %(unknown node "x"; flag takes no children), inside.call(%(flag "--n" help="x" { x; }))
  end

  def test_refuses_a_flag_as_a_mistake_that_says_what_to_write_instead
    message = "flag isn't a node CrossLint reads outside a command: a plugin adds commands under its own name, as in command NAME help=TEXT, " \
      "and flags only to its commands, as in flag \"-n --name\" help=TEXT inside one; it adds no flag to crosslint check"

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
      %(rule) => "rule has 0 arguments; write it as rule NAME ruby=FILE or rule NAME helper=HELPER",
      %(helper) => "helper has 0 arguments; write it as helper NAME command=COMMAND file=FILE",
      %(artifact "a" { primary; }) => "primary has 0 arguments; write it as primary PATTERN",
      %(artifact "a" { primary "x"; piece; }) => "piece has 0 arguments; write it as piece NAME PATTERN",
      %(policy "p" { applies-to; }) => "applies-to has 0 arguments; write it as applies-to ARTIFACT",
      %(policy "p" { applies-to "a"; rule; }) => "rule has 0 arguments; write it as rule RULE",
      %(policy "p" { applies-to "a"; when piece-exists; rule "r"; }) =>
        "piece-exists has 0 arguments; write it as piece-exists PIECE"
    }.each { |text, message| assert_refuses 1, message, text }
  end

  def test_refuses_a_condition_that_is_not_a_name
    assert_refuses 3, %(unknown condition "3"; expected "piece-exists", "not", "all", or "any"), policy_with(%(when 3))
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
