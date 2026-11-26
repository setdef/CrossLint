# Plugin reference

A plugin is a folder with a `plugin.kdl` at its root, which declares the plugin's artifacts, policies, and rules in [KDL](https://kdl.dev/). This page lists everything `plugin.kdl` can hold. A local plugin and a shared one use the same file; [the configuration reference](configuration.md) says how a project lists either.

Every example on this page comes from one plugin, kept in a Ruby project at `.config/crosslint/signatures/`, that checks each Ruby file under `lib/` for a signature file under `sig/` and a test under `test/`:

```kdl
artifact "ruby-file" {
  files "lib/{path}.rb"
  companion "signature" "sig/{path}.rbs"
  companion "test" "test/{path}_test.rb"
}

policy "has-signature" {
  applies-to "ruby-file"
  rule "companion-exists" companion="signature"
}

policy "has-test" {
  applies-to "ruby-file"
  rule "companion-exists" companion="test" severity="warning"
}
```

A plugin's name is its folder's name, here `signatures`. CrossLint names each violation by the plugin and the policy that found it: `signatures/has-signature`.

## `artifact`

`artifact NAME { ... }` declares a kind of artifact: which files are its primary files, and where each of its companions belongs. `NAME` is unique within the plugin.

| Child | Meaning |
| --- | --- |
| `files PATTERN` | The path pattern that finds the primary files, relative to the project's root. Required, once. |
| `companion NAME PATTERN` | A companion called `NAME`, at the path `PATTERN` gives for each primary file. Any number, each name once. |

A path pattern is a path with placeholders in braces. In `files`, `{path}` matches a file name and the folders before it, if any, and `{name}` matches one segment of a path, with no `/`. In a companion's pattern, each placeholder stands for what it matched in `files`. For `lib/fledge/archive.rb`, the pattern `lib/{path}.rb` matches with `{path}` as `fledge/archive`, so the companion `sig/{path}.rbs` is `sig/fledge/archive.rbs`; for `lib/fledge.rb`, `{path}` is `fledge`.

- A pattern uses `/` on every system, and matches case-sensitively.
- Files that Git ignores, and anything under `.git/`, never match.
- A file that two artifacts' `files` patterns both match is a primary file of each, and both are checked.
- An artifact whose `files` pattern matches no file is reported once as a warning, since a pattern that finds nothing usually has a typo.

## `policy`

`policy NAME { ... }` says when rules apply. `NAME` is unique within the plugin, and is the name violations carry.

| Child | Meaning |
| --- | --- |
| `applies-to ARTIFACT` | The artifact the policy covers, by name: one of this plugin's, or another listed plugin's as `PLUGIN/ARTIFACT`. Required, once. |
| `when CONDITION` | Apply the policy only to artifacts the condition holds for. Optional; without it, the policy applies to every artifact of the kind in `applies-to`. |
| `rule RULE ...` | A rule the policy runs on each artifact it applies to, with the rule's arguments as properties. At least one. |

A `rule` line also takes `severity="error"` or `severity="warning"`, which overrides the rule's default severity for this policy. The project's configuration can override it again.

### Conditions

| Condition | Holds when |
| --- | --- |
| `companion-exists COMPANION` | The artifact's companion of that name exists. |
| `not { CONDITION }` | The condition inside doesn't hold. |
| `all { CONDITION ... }` | Every condition inside holds. |
| `any { CONDITION ... }` | At least one condition inside holds. |

For example, ng-nudge's rule that a component with an interface must have a stub is a policy on components, `when companion-exists "interface"`, that runs `companion-exists companion="stub"`.

A condition that these can't state goes in a Ruby rule, which can return no violation where the condition doesn't hold.

## Rules

A rule is either built into CrossLint or written in Ruby in the plugin.

### Built-in rules

| Rule | Arguments | Reports | Default severity |
| --- | --- | --- | --- |
| `companion-exists` | `companion=NAME` | The artifact's companion doesn't exist, with its path. | error |
| `companion-absent` | `companion=NAME` | The artifact's companion exists, with its path. For a file that shouldn't be there, such as a `.scss` beside a `.css`. | error |

### Rules in Ruby

`rule NAME ruby=FILE` declares a rule written in Ruby, in `FILE` relative to the plugin's folder, and a policy then runs it as `rule "NAME"`. The file defines one class, named after the rule in camel case and inheriting from `CrossLint::Rule`, with a `check` method that takes the artifact and returns the rule's violations. `violation(artifact, message)` makes one:

```ruby
# .config/crosslint/signatures/rules/signature_names_class.rb
class SignatureNamesClass < CrossLint::Rule
  def check(artifact)
    signature = artifact.companion("signature")
    return [] unless signature.exist?

    name = artifact.match["path"].split("/").map { _1.split("_").map(&:capitalize).join }.join("::")
    return [] if signature.read.include?("class #{name}") || signature.read.include?("module #{name}")

    [violation(artifact, "#{signature.path} declares no class or module #{name}")]
  end
end
```

```kdl
rule "signature-names-class" ruby="rules/signature_names_class.rb"

policy "signature-matches" {
  applies-to "ruby-file"
  when companion-exists "signature"
  rule "signature-names-class"
}
```

The artifact a rule gets has these methods:

| Method | Returns |
| --- | --- |
| `path` | The primary file's path, relative to the project's root. |
| `role` | The artifact's name, such as `ruby-file`. |
| `match` | What each placeholder matched, by name: `artifact.match["path"]`. |
| `read` | The primary file's contents. |
| `companion(NAME)` | The companion of that name, with `name`, `path`, `exist?`, and `read`. |

`violation(artifact, message, detail: TEXT)` makes a violation with a detail, for a rule that can find several things wrong with one artifact, such as each missing member by name. Debt records each detail as a separate entry.

CrossLint makes one instance of the class per check, with no arguments, and calls `check` once for each artifact a policy applies the rule to. A policy's `rule` line gives a rule written in Ruby no arguments; a line that does is a mistake.

The rule's file runs on the Ruby that CrossLint carries, so a project needs no Ruby installed. It can use Ruby's standard library and other files in the plugin's folder. Requiring a gem CrossLint wasn't built with, or `bundler/inline`, stops the plugin with a message naming it. Anything the file or `check` raises is a fault: the plugin reports nothing else, the other plugins still run, and `crosslint check` exits with 2. `--debug` shows where it was raised.

### Helpers

A plugin that reads files of another language can carry a helper in that language: `helper NAME command=... file=...`, run with the project's runtime for that language. A Ruby rule calls it with `helper("NAME").call(input)`, which sends `input` as JSON on the helper's standard input and returns the JSON it writes to standard output.

```kdl
helper "members" command="node" file="helpers/members.mjs"
```

CrossLint starts a helper at the first call, as `COMMAND FILE` in the project's root, and ends it, with everything it started, when the check ends. Each request and each answer is one line of JSON. The helper's standard error appears under `--debug`. A helper that exits, answers with a line that isn't JSON, or doesn't answer within 60 seconds is a fault, and the message includes what it wrote to standard error.

A helper whose command isn't on the `PATH` stops CrossLint with exit status 2, and a message naming the plugin and the command it needs.
