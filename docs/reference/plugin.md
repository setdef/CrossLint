# Plugin reference

A plugin is a folder with a `plugin.kdl` at its root, which declares the plugin's artifacts, policies, and rules in [KDL](https://kdl.dev/). This page lists everything `plugin.kdl` can hold. A local plugin and a shared one use the same file; [the configuration reference](configuration.md) says how a project lists either, and [the glossary for plugin authors](plugin-glossary.md) defines the words this page uses.

Every example on this page comes from one plugin, kept in a Ruby project at `.config/crosslint/signatures/`, that checks each Ruby file under `lib/` for a signature file under `sig/` and a test under `test/`:

```kdl
artifact "ruby-file" {
  primary "lib/{path}.rb"
  piece "signature" "sig/{path}.rbs"
  piece "test" "test/{path}_test.rb"
}

policy "has-signature" {
  applies-to "ruby-file"
  rule "piece-exists" piece="signature"
}

policy "has-test" {
  applies-to "ruby-file"
  rule "piece-exists" piece="test" severity="warning"
}
```

A plugin's name is its folder's name, here `signatures`. CrossLint names each violation by the plugin and the policy that found it: `signatures/has-signature`.

## `artifact`

`artifact NAME { ... }` declares a role: the path pattern that finds each artifact's primary piece, the artifact's name, and where each of its other pieces belongs. `NAME` is unique within the plugin.

| Child | Meaning |
| --- | --- |
| `primary PATTERN` | The path pattern that finds each artifact's primary piece, relative to the project's root. Required, once. |
| `name PATTERN` | The artifact's name, from the placeholders of `primary`, such as `name "{path}"`. CrossLint calls the artifact by its name in every violation and debt entry, and writes it after the primary piece's path in a report. Optional, once; without it, an artifact's name is its primary piece's path. Two artifacts of one role with one name are a fault, since a debt entry for one would match the other too. |
| `piece NAME PATTERN` | A piece called `NAME`, at the path `PATTERN` gives for each primary piece. Any number, each name once. |

A path pattern is a path with placeholders in braces. In `primary`, `{path}` matches a file name and the folders before it, if any, and `{name}` matches one segment of a path, with no `/`. In a piece's pattern, each placeholder stands for what it matched in `primary`. For `lib/fledge/archive.rb`, the pattern `lib/{path}.rb` matches with `{path}` as `fledge/archive`, so the piece `sig/{path}.rbs` is `sig/fledge/archive.rbs`; for `lib/fledge.rb`, `{path}` is `fledge`.

- A pattern uses `/` on every system, and matches case-sensitively.
- Files that Git ignores, and anything under `.git/`, never match.
- A file that two artifacts' `primary` patterns both match is the primary piece of each, and both are checked.
- An artifact whose `primary` pattern matches no file is reported once as a warning, since a pattern that finds nothing usually has a typo.

## `policy`

`policy NAME { ... }` says when rules apply. `NAME` is unique within the plugin, and is the name violations carry.

| Child | Meaning |
| --- | --- |
| `applies-to ARTIFACT` | The artifact the policy covers, by name: one of this plugin's, or another listed plugin's as `PLUGIN/ARTIFACT`. At most once. Without it, the policy covers each of its plugin's artifacts that has every piece its `when` and its rules name; a policy that would then cover none stops CrossLint with exit status 2, unless the plugin declares its artifacts with a helper. |
| `when CONDITION` | Apply the policy only to artifacts the condition holds for. Optional; without it, the policy applies to every artifact of the kind in `applies-to`. |
| `rule RULE ...` | A rule the policy runs on each artifact it applies to, with the rule's arguments as properties. At least one. |

A `rule` line also takes `severity="error"` or `severity="warning"`, which overrides the rule's default severity for this policy. The project's configuration can override it again.

### Conditions

| Condition | Holds when |
| --- | --- |
| `piece-exists PIECE` | The artifact's piece of that name exists. |
| `not { CONDITION }` | The condition inside doesn't hold. |
| `all { CONDITION ... }` | Every condition inside holds. |
| `any { CONDITION ... }` | At least one condition inside holds. |

For example, ng-nudge's rule that a component with an interface must have a stub is a policy on components, `when piece-exists "interface"`, that runs `piece-exists piece="stub"`.

A condition that these can't state goes in a Ruby rule, which can return no violation where the condition doesn't hold.

## Rules

A rule is built into CrossLint, or run by one of the plugin's helpers.

### Built-in rules

| Rule | Arguments | Reports | Default severity |
| --- | --- | --- | --- |
| `piece-exists` | `piece=NAME` | The artifact's piece doesn't exist, with its path. | error |
| `piece-absent` | `piece=NAME` | The artifact's piece exists, with its path. For a file that shouldn't be there, such as a `.scss` beside a `.css`. | error |

### Helpers

A rule that needs code is run by a helper: a command and a file in the plugin's folder, declared as `helper NAME`. A policy then runs the rule as it runs a built-in one, and the rule's line gives the helper's name: `rule NAME helper=HELPER`. The command says which runtime runs the file:

| Command | Runs the file on |
| --- | --- |
| `command=(crosslint)"ruby"` | The Ruby CrossLint carries, so every project can run the plugin, whatever its language. The file is Ruby, written as [Rules in CrossLint's Ruby](#rules-in-crosslints-ruby) says. |
| `command=PROGRAM` | A program on the project's `PATH`, such as `node`, with the project's versions and packages. The file speaks the line protocol in [Rules a program runs](#rules-a-program-runs). |
| `command "PROGRAM" "WORD" ...`, in the helper's block | The same, for a program that takes words before the file, such as `command "bundle" "exec" "ruby"` for a project's Ruby with its gems. |

```kdl
helper "names" command=(crosslint)"ruby" file="rules/signature_names_class.rb"
helper "angular" command="node" file="lib/helper.js"
helper "routes" file="routes.rb" {
  command "bundle" "exec" "ruby"
}
```

`(crosslint)` is a KDL type annotation, the only one a manifest reads. No program on a `PATH` can be mistaken for it, and `command="ruby"`, with no annotation, is the project's Ruby. Each helper's name is unique within the plugin.

### Rules in CrossLint's Ruby

A helper on `command=(crosslint)"ruby"` is a file of Ruby that CrossLint runs itself, on the Ruby it carries, for each rule whose line gives the helper's name. The file defines one class for each such rule, named after the rule in camel case and inheriting from `CrossLint::Rule`, with a `check` method that takes the artifact and returns the rule's violations. `violation(artifact, message)` makes one:

```ruby
# .config/crosslint/signatures/rules/signature_names_class.rb
class SignatureNamesClass < CrossLint::Rule
  def check(artifact)
    signature = artifact.piece("signature")
    return [] unless signature.exist?

    name = artifact.match["path"].split("/").map { _1.split("_").map(&:capitalize).join }.join("::")
    return [] if signature.read.include?("class #{name}") || signature.read.include?("module #{name}")

    [violation(artifact, "#{signature.path} declares no class or module #{name}")]
  end
end
```

```kdl
helper "names" command=(crosslint)"ruby" file="rules/signature_names_class.rb"
rule "signature-names-class" helper="names"

policy "signature-matches" {
  applies-to "ruby-file"
  when piece-exists "signature"
  rule "signature-names-class"
}
```

The artifact a rule gets has these methods:

| Method | Returns |
| --- | --- |
| `path` | The primary piece's path, relative to the project's root. |
| `role` | The artifact's name, such as `ruby-file`. |
| `match` | What each placeholder matched, by name: `artifact.match["path"]`. |
| `read` | The primary piece's contents. |
| `piece(NAME)` | The piece of that name, with `name`, `path`, `exist?`, and `read`. |

A rule can also look beyond its artifact, for a path written in the artifact's text, such as a link's target, which no piece can give:

| Method | Returns |
| --- | --- |
| `project_files` | Every file the project has, as CrossLint sees them: the files Git lists, tracked or not, minus those Git ignores, and nothing under `.git/`. Each is a path relative to the project's root, with `/` between folders, in no particular order. It is the same frozen list for every artifact of a check, so a rule can index it once, in `initialize` or at its first artifact. |
| `read(PATH)` | The text of the file at `PATH`, relative to the project's root with `/` between folders. It raises `Errno::ENOENT` when no file has that exact name. A file Git ignores can be read, though it isn't in `project_files`. |

`violation(artifact, message, detail: TEXT)` makes a violation with a detail, for a rule that can find several things wrong with one artifact, such as each missing member by name. Debt records each detail as a separate entry.

CrossLint makes one instance of the class per check, with no arguments, and calls `check` once for each artifact a policy applies the rule to. A policy's `rule` line gives such a rule no arguments; a line that does is a mistake. A rule no policy runs isn't loaded, and CrossLint says so in a warning.

The rule's file runs on the Ruby that CrossLint carries, so a project needs no Ruby installed. It can use Ruby's standard library and other files in the plugin's folder. Requiring a gem CrossLint wasn't built with, or `bundler/inline`, stops the plugin with a message naming it. Anything the file or `check` raises is a fault: the plugin reports nothing else, the other plugins still run, and `crosslint check` exits with 2. `--debug` shows where it was raised. A `check` that runs for 60 seconds on one artifact, or recurses until Ruby raises `SystemStackError`, is a fault too.

A rule in CrossLint's Ruby can call a helper that a program runs, with `helper("NAME").call(input)`, which sends `input` as JSON on the helper's standard input and returns the JSON it writes to standard output.

### Rules a program runs

A helper whose command is a program speaks a line protocol: each request and each answer is one line of JSON. For each artifact the policy applies it to, CrossLint sends the helper one request and turns its answer into the rule's violations:

```json
{"rule": "stub-matches-component", "artifact": {"path": "src/app/card/card.component.ts", "role": "component", "match": {"path": "app/card/card"},
  "key": "app/card/card", "pieces": {"stub": {"path": "src/app/card/card.component.stub.ts", "exists": true}}}}
```

The helper answers `{"violations": [{"message": TEXT, "detail": TEXT}, ...]}`, with no `detail` for a violation the rule gives none, or `{"error": MESSAGE}`. CrossLint stops the plugin with a fault at an error, at an answer of any other shape, and at a helper that fails, as it does at anything a rule in CrossLint's Ruby raises. The helper reads files itself, so CrossLint's `project_files` and `read` don't reach it. A rule a helper runs takes no arguments, and its violations are errors, unless a `severity=` on its policy's `rule` line or in the configuration says otherwise. The helper must be one the plugin declares.

```kdl
helper "angular" command="node" file="lib/helper.js"
rule "stub-matches-component" helper="angular"
```

CrossLint starts such a helper at its first request, as its command and then its file, in the project's root, with the environment CrossLint was started with. When the check ends, CrossLint closes the input of every helper at once, gives each 2 seconds to exit, and then ends it with everything it started; on Ctrl-C, it ends them without waiting. A helper CrossLint can't put in its process group or job object is ended at once, and is a fault. The helper's standard error appears under `--debug`. A helper that exits, answers with a line that isn't JSON, or doesn't answer within 60 seconds is a fault, and the message includes what it wrote to standard error.

A helper whose command isn't on the `PATH` stops CrossLint with exit status 2, and a message naming the plugin and the command it needs.

## Steps, settings, and commands

A plugin can also declare a step, the settings it takes, and commands under the plugin's name. The debt plugin's `plugin.kdl`, which ships inside CrossLint, declares all four kinds of line:

```kdl
step "track-debt"

policy "has-debt"

setting "file"
setting "report-entries"

command "update" help="Rewrite the debt file to list the current violations" {
  flag "-n --dry-run" help="List the entries update would add and remove, and write nothing"
}
```

| Line | Meaning |
| --- | --- |
| `step NAME` | A step built into CrossLint, for CrossLint to run after every rule of every plugin has run. The step sees every violation, whatever `--warnings` or `--quiet` hides, and can excuse some, add others, and report stale entries. CrossLint has one step, `track-debt`. |
| `policy NAME` with no block | A policy no rule runs, whose violations the plugin's step reports, such as `has-debt`. The configuration disables it or changes its severity like any other policy. |
| `setting NAME` | A setting the plugin takes in its block in the configuration. A setting the plugin doesn't declare stops CrossLint with exit status 2. |
| `command NAME help=TEXT` | A command the project runs as `crosslint PLUGIN NAME`, with `TEXT` as its one line in `--help`. It runs the check, then tells the plugin's step the command's name, and the step does the command's work; a plugin with a command and no step is a mistake. `NAME` is lowercase letters, digits, and `-`, and can't be `help`. It exits with 0 when it did what it was asked, and with 2 when CrossLint can't run it. |
| `flag NAMES help=TEXT` in a command's block | A command flag: a flag of that command alone, such as `flag "-n --dry-run"`, with its names in the usage spec's syntax and `TEXT` as its line in the command's `--help`. CrossLint tells the step which command flags were given. A command flag can't have the name of a global flag, `-h`, `--help`, or another flag of the same command; one that does stops CrossLint with exit status 2, naming the plugin. A `flag` line outside a command is a mistake. |

A plugin adds no flag to `crosslint check` or to any other command of CrossLint's, and a plugin that has commands can't have the name of one of CrossLint's commands, or one of the names CrossLint keeps for commands it may add: `version`, `completion`, `config`, `plugin`, `plugins`, `list`, `cache`, `doctor`, `explain`, `fix`, and `self`. A local or shared plugin can't have the name of a built-in plugin, `angular` or `debt`. Its commands take the global flags anywhere on the line, and their command flags after the command's name. `crosslint --help` and `crosslint help` list the commands of the project's plugins after CrossLint's, each with its one line of help; `crosslint debt`, `crosslint debt --help`, and `crosslint help debt` list one plugin's commands; and `crosslint debt update --help` explains one command, with its command flags and the global flags. Help never fails: with `--help` or `-h` before `--`, a flag CrossLint doesn't know or a configuration it can't read still shows help, with a line saying why a plugin's commands aren't shown, and exits with 0. Help reads only what is on disk, so a shared plugin not fetched yet is named with a line saying `crosslint check` fetches it.

A mistyped command, or a command of a plugin the configuration doesn't list, stops CrossLint with exit status 2: for a plugin the configuration doesn't list, the message names the plugin and the configuration; for a command the plugin doesn't have, it lists the plugin's commands or names the nearest; and for a word that is neither one of CrossLint's commands nor a listed plugin's name, it names the nearest of both. A command flag the command doesn't have stops CrossLint the same way, with the nearest of its command flags and the global flags.

## Artifacts declared in CrossLint's Ruby

A plugin whose artifacts depend on its settings, such as a folder the project chooses, declares them with `artifacts helper=HELPER`, in place of or beside its `artifact` lines, so its settings change where it finds each role's files. A plugin that keeps Ruby files in a folder its project chooses could have:

```kdl
setting "lib-dir"

helper "artifacts" command=(crosslint)"ruby" file="artifacts.rb"
artifacts helper="artifacts"
```

When the helper is on `command=(crosslint)"ruby"`, its file defines a class `Artifacts` inheriting from `CrossLint::Artifacts`, whose `declare` method takes the plugin's settings and returns an array of artifacts:

```ruby
# .config/crosslint/signatures/artifacts.rb
class Artifacts < CrossLint::Artifacts
  def declare(settings)
    given = settings.find { |setting| setting.name == "lib-dir" }
    raise mistake("lib-dir takes one folder, as in lib-dir \"lib\"", given) if given && given.arguments.size != 1

    lib = given ? given.arguments.first : "lib"
    [artifact("ruby-file", primary: "#{lib}/{path}.rb", pieces: {"signature" => "sig/{path}.rbs"})]
  end
end
```

| Method | Meaning |
| --- | --- |
| `declare(settings)` | Called once per check, before any rule runs. Each setting has `name`, `arguments`, `properties`, `children`, and `line`, as the configuration gives them. |
| `artifact(NAME, primary:, pieces: {}, key: nil, optional: false, dotfiles: true)` | Declares an artifact as an `artifact` line does, with `primary` and each piece's path as path patterns. `key` is a second path pattern for the artifact's key, which a debt entry can name in place of its path. With `optional: true`, a `primary` pattern that matches nothing isn't reported, unless no artifact of the plugin matches a file. With `dotfiles: false`, a file isn't an artifact when a placeholder matched a file or folder whose name starts with `.`, as the Angular plugin skips them. |
| `mistake(MESSAGE, SETTING)` | A mistake in the configuration at that setting's line, for `declare` to raise. It stops CrossLint with exit status 2, as any mistake does. |

Anything else `declare` raises stops CrossLint with exit status 2, naming the plugin, since no check can run without its artifacts.

## Artifacts a program declares

When the helper is a program, CrossLint starts it once, before any rule runs, sends it the plugin's settings, and stops it when it answers:

```json
{"settings": [{"name": "lib-dir", "arguments": ["src"], "properties": {}, "children": [], "line": 3}]}
```

The helper answers with the artifacts, each with the fields of `artifact` in the table for artifacts declared in CrossLint's Ruby, and only `name` and `primary` needed: `{"artifacts": [{"name": "ruby-file", "primary": "src/{path}.rb", "pieces": {"signature": "sig/{path}.rbs"}}]}`. For a setting it can't use, it answers `{"mistake": {"message": TEXT, "line": LINE}}`, with the setting's line, and CrossLint stops with exit status 2 at that line of the configuration. CrossLint also stops with exit status 2 at an error, at an answer of any other shape, and at an artifact that isn't one, naming the plugin and the manifest's `artifacts` line. A manifest has one `artifacts` line.
