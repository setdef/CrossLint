# Plugin reference

A plugin is a folder with a `plugin.kdl` at its root, which declares the plugin's artifacts, policies, and rules in [KDL](https://kdl.dev/), and the helpers that run whatever code the plugin has, in any language. This page lists everything `plugin.kdl` can hold; [the cookbook](../cookbook/README.md) has whole plugins for single checks, such as the actions of a Rails app's routes. A local plugin and a shared one use the same file; [the configuration reference](configuration.md) says how a project lists either, and [the glossary for plugin authors](plugin-glossary.md) defines the words this page uses.

Every example on this page comes from one plugin, kept in a JavaScript project at `.config/crosslint/modules/`, that checks each module under `src/` for a declaration file beside it, such as `src/cart/total.d.ts` for `src/cart/total.js`, and a test under `test/`:

<!--
SPDX-SnippetBegin
SPDX-License-Identifier: MIT-0
SPDX-SnippetCopyrightText: 2026 setdef
-->
```kdl
artifact "module" {
  primary "src/{path}.js"
  piece "declaration" "src/{path}.d.ts"
  piece "test" "test/{path}.test.js"
}

policy "has-declaration" {
  applies-to "module"
  rule "piece-exists" piece="declaration"
}

policy "has-test" {
  applies-to "module"
  rule "piece-exists" piece="test" severity="warning"
}
```
<!-- SPDX-SnippetEnd -->

A plugin's name is its folder's name, here `modules`. CrossLint names each violation by the plugin and the policy that found it: `modules/has-declaration`.

## `artifact`

`artifact ROLE { ... }` declares a role: the path pattern that finds each artifact's primary piece, the artifact's name, and where each of its other pieces belongs. `ROLE` is unique within the plugin.

| Child | Meaning |
| --- | --- |
| `primary PATTERN` | The path pattern that finds each artifact's primary piece, relative to the project's root. With `regex=REGEX`, each match of [the regex](#regexes) in such a file is an artifact, such as each route in `config/routes.rb`. Required, once. |
| `name PATTERN` | The artifact's name, from the placeholders of `primary` and the captures of its regex, such as `name "{path}"`. CrossLint calls the artifact by its name in every violation and debt entry, and writes it after the primary piece's path in a report. Optional, once; without it, an artifact's name is its primary piece's path. Two artifacts of one role with one name are a fault, since a debt entry for one would match the other too. |
| `piece NAME PATTERN` | A piece called `NAME`, at the path `PATTERN` gives for each primary piece. With `regex=REGEX`, the piece is a part of that file: it exists when [the regex](#regexes) has a match there. Any number, each name once. |

A path pattern is a path with placeholders in braces. In `primary`, `{path}` matches a file name and the folders before it, if any, and `{name}` matches one segment of a path, with no `/`. In a piece's pattern, each placeholder stands for what it matched in `primary`. For `src/cart/total.js`, the pattern `src/{path}.js` matches with `{path}` as `cart/total`, so the piece `src/{path}.d.ts` is `src/cart/total.d.ts`; for `src/cart.js`, `{path}` is `cart`.

- A pattern uses `/` on every system, and matches case-sensitively.
- Files that Git ignores, and anything under `.git/`, never match.
- A file that two artifacts' `primary` patterns both match is the primary piece of each, and both are checked.
- An artifact whose `primary` pattern matches no file, or whose regex matches nothing in any file it matches, is reported once as a warning, since a pattern that finds nothing usually has a typo.

### Regexes

A piece with `regex=` is a part of a file rather than the whole file, such as a function in a module or a `<style>` block in a component. Here each module's declaration file has to export something:

<!--
SPDX-SnippetBegin
SPDX-License-Identifier: MIT-0
SPDX-SnippetCopyrightText: 2026 setdef
-->
```kdl
artifact "module" {
  primary "src/{path}.js"
  piece "declaration" "src/{path}.d.ts"
  piece "exports" "src/{path}.d.ts" regex=#"^export "#
}

policy "declares-exports" {
  applies-to "module"
  when piece-exists "declaration"
  rule "piece-exists" piece="exports"
}
```
<!-- SPDX-SnippetEnd -->

Write a regex as a KDL raw string, `#"..."#`, so that its backslashes and quotes reach CrossLint as written. The piece exists when its file has at least one match. A file that isn't there, or a path that is a folder, has no match, and the violation's message says which of the two CrossLint found:

| Rule | The file has a match | The file has none | No file is at the path |
| --- | --- | --- | --- |
| `piece-exists` | Passes. | `no exports in src/a.d.ts` | `no exports in src/a.d.ts, which isn't a file` |
| `piece-absent` | `exports at src/a.d.ts:3`, the line of the first match | Passes. | Passes. |

The same holds for `when piece-exists` and for every helper: the piece exists only when its file has a match.

A regex on `primary` finds artifacts inside files. Each match in a file the primary pattern matches is one artifact, on the line where the match starts, and a file with no match has none. Each named capture, such as `(?<function>...)`, is a placeholder that the name, the path of each piece, and each piece's regex can use. Here each function a module exports needs a test named after it:

<!--
SPDX-SnippetBegin
SPDX-License-Identifier: MIT-0
SPDX-SnippetCopyrightText: 2026 setdef
-->
```kdl
artifact "function" {
  primary "src/{path}.js" regex=#"^export (?:async )?function (?<function>[A-Za-z_$][\w$]*)"#
  name "{path}#{function}"
  piece "test" "test/{path}.test.js" regex=#"test\("{function}""#
}

policy "has-test" {
  applies-to "function"
  rule "piece-exists" piece="test"
}
```
<!-- SPDX-SnippetEnd -->

CrossLint reports a violation of such an artifact with its line, then its name:

<!--
SPDX-SnippetBegin
SPDX-License-Identifier: MIT-0
SPDX-SnippetCopyrightText: 2026 setdef
-->
```text
src/cart/total.js:6: cart/total#total: no test in test/cart/total.test.js (modules/has-test)
```
<!-- SPDX-SnippetEnd -->

- A capture can't be named `path` or `name`, the placeholders of a path pattern.
- A capture that the name, a piece's path, or a piece's regex uses, and that matched nothing in a match, is a fault, since a piece's path or regex without it would find what the author never meant.
- Two matches with one name are a fault, as two artifacts of a role with one name always are. Without `name`, every artifact in a file has the file's path as its name, so a primary regex usually needs a `name`.
- A capture comes from the project's text, so a piece path in which it would put a `.` or `..` segment, or an empty one, is never a file of the project: the piece doesn't exist.
- What a capture didn't take part in isn't in `match`, in a helper's request or in a rule in CrossLint's Ruby.
- An artifact a helper declares can't have a regex.

A placeholder in a regex stands for what it matched in `primary`, or what the primary's regex captured, as literal text: in `"{path}"`, a `{path}` that matched `v1.2/total` matches `v1.2/total` and never `v1x2/total`. `\{` is a brace, and `{2}` and `{2,3}` stay counts. A placeholder that is neither stops CrossLint with exit status 2.

#### The dialect

A regex is in Ruby's dialect, Onigmo, as [Ruby's documentation](https://docs.ruby-lang.org/en/master/regexp_rdoc.html) describes it, with no options, whatever language the plugin's helpers are in: CrossLint runs every regex in `plugin.kdl` itself, and a helper's regular expressions are in its language's dialect. CrossLint refuses what Ruby reads without an error but PCRE or JavaScript, the dialects most tools share, reads another way, and stops with exit status 2, saying what to write instead:

| Written | Ruby reads | Elsewhere | Write instead |
| --- | --- | --- | --- |
| `(?m)`, `(?m:...)` | `.` matches a newline | PCRE and JavaScript: `^` and `$` match at each line | `[\s\S]` for any character |
| `\h`, `\H` | a hex digit, or anything else | PCRE: a space or a tab, or anything else | `[0-9a-fA-F]` or `[ \t]` |
| `\v` | a vertical tab | PCRE: any vertical space | `\x0B` or `[\n\f]` |
| `\pL` | the letters `pL` | PCRE: a Unicode property | `\p{L}` |
| `\Q`, `\N`, or another letter Ruby has no escape for | the letter alone | PCRE: an escape or an error | the letter |
| `{,3}` | `{0,3}` | JavaScript: the text `{,3}` | `{0,3}` |
| `[[:alpha:]]` and the other POSIX brackets | every Unicode character in the class | PCRE: its ASCII characters alone | `\p{Alpha}`, or `[A-Za-z]` |

Some differences have no other way to write them, so CrossLint reads them as Ruby does:

- `^` and `$` match at the start and end of each line, as with `m` in PCRE and JavaScript, and `\A` and `\z` match at the start and end of the file.
- `.` matches any character but a newline.
- `\d`, `\w`, and `\s` match ASCII characters alone, while `\b` counts a letter such as `é` as part of a word, so `a\b` doesn't match in `aé`, as it does in PCRE and JavaScript.

#### Line endings, encoding, and time

- Before CrossLint searches a file, it reads each `\r\n` and each `\r` alone as `\n`, and drops a byte order mark at its start, so a regex matches the same on every system, whatever line endings Git checked out. Write `\n` for a line ending, never `\r`.
- A file has to be UTF-8. A file that isn't is a fault: the plugin reports nothing else, and `crosslint check` exits with 2.
- One search for a match may run for 1 second. A search that runs longer, as one for `(a+)+\1` can on a long line of `a`s, is a fault, never a hang.

## `policy`

`policy NAME { ... }` says when rules apply. `NAME` is unique within the plugin, and is the name violations carry.

| Child | Meaning |
| --- | --- |
| `applies-to ROLE` | The role the policy covers: one this plugin declares, or another listed plugin's as `PLUGIN/ROLE`. At most once. Without it, the policy covers each of its plugin's artifacts that has every piece its `when` and its rules name; a policy that would then cover none stops CrossLint with exit status 2, unless the plugin declares its artifacts with a helper. |
| `when CONDITION` | Apply the policy only to artifacts the condition holds for. Optional; without it, the policy applies to every artifact of the role in `applies-to`. |
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

A condition that these can't state goes in a rule that a [helper](#helpers) runs, which can return no violation where the condition doesn't hold.

## Rules

A rule is built into CrossLint, or run by one of the plugin's [helpers](#helpers).

### Built-in rules

| Rule | Arguments | Reports | Default severity |
| --- | --- | --- | --- |
| `piece-exists` | `piece=NAME` | The artifact's piece doesn't exist, with its path. For a piece with a regex, whether its file has no match or isn't a file. | error |
| `piece-absent` | `piece=NAME` | The artifact's piece exists, with its path. For a file that shouldn't be there, such as a `.scss` beside a `.css`, or, with a regex, a part that shouldn't be in a file, with the line of its first match. | error |

## Helpers

A plugin's code is in its helpers. A helper is a command and a file in the plugin's folder, declared as `helper NAME`, and the file is in whatever language the command runs. A helper runs rules, each declared as `rule NAME helper=HELPER`, which a policy then runs as it runs a built-in one, and it can declare the plugin's artifacts, with [`artifacts helper=HELPER`](#artifacts-a-helper-declares). The command says which runtime runs the file:

| Command | Runs the file on |
| --- | --- |
| `command=PROGRAM` | A program on the project's `PATH`, such as `node` or `python3`, with the project's versions and packages. The file speaks the line protocol in [Rules a program runs](#rules-a-program-runs). |
| `command "PROGRAM" "WORD" ...`, in the helper's block | The same, for a program that takes words before the file, such as `command "uv" "run"` for a project's Python with its packages, or `command "bundle" "exec" "ruby"` for a project's Ruby with its gems. |
| `command=(crosslint)"ruby"` | The Ruby CrossLint carries, so every project can run the plugin, whatever its language. The file is Ruby, written as [Rules in CrossLint's Ruby](#rules-in-crosslints-ruby) says. |

<!--
SPDX-SnippetBegin
SPDX-License-Identifier: MIT-0
SPDX-SnippetCopyrightText: 2026 setdef
-->
```kdl
helper "declarations" command="node" file="rules/declarations.mjs"
helper "types" file="rules/types.py" {
  command "uv" "run"
}
helper "exports" command=(crosslint)"ruby" file="rules/declares_every_export.rb"
```
<!-- SPDX-SnippetEnd -->

`(crosslint)` is a KDL type annotation, the only one a manifest reads. No program on a `PATH` can be mistaken for it, and `command="ruby"`, with no annotation, is the project's Ruby. Each helper's name is unique within the plugin, and a `rule` line's `helper=` has to be one the plugin declares.

A policy's `rule` line gives a rule a helper runs no arguments; a line that does is a mistake. The rule's violations are errors, unless a `severity=` on its policy's `rule` line or in the configuration says otherwise. A rule no policy runs isn't loaded, and CrossLint says so in a warning.

> **Which runtime to choose.** A helper on the project's runtime is written in the project's language, with the packages and versions the project already has. A project without that runtime can't run it: CrossLint stops with exit status 2 and a message naming the plugin and the command it needs, so a shared plugin whose helper runs on `node` serves only projects that have Node. Every project has the Ruby CrossLint carries, so a shared plugin meant for projects of every language runs its helpers there, with Ruby's standard library and the gems CrossLint was built with. Such a helper runs inside CrossLint and can read the project's files through it: `project_files` lists them as Git sees them, and `read` finds a file only by its exact name and refuses a path or a link out of the project. The Angular plugin's helper runs on Node, and reads TypeScript with ts-morph; the shared plugins in CrossLint's repository run on CrossLint's Ruby.

### Rules a program runs

A helper whose command is a program speaks a line protocol on its standard input and standard output: each request and each answer is one line of JSON. For each artifact a policy applies the rule to, CrossLint sends the helper one request and turns its answer into the rule's violations. For the module `src/cart/total.js`, the request is:

<!--
SPDX-SnippetBegin
SPDX-License-Identifier: MIT-0
SPDX-SnippetCopyrightText: 2026 setdef
-->
```json
{"rule": "declares-every-export", "artifact": {"path": "src/cart/total.js", "role": "module", "match": {"path": "cart/total"}, "key": null,
  "pieces": {"declaration": {"path": "src/cart/total.d.ts", "exists": true}, "test": {"path": "test/cart/total.test.js", "exists": true}}}}
```
<!-- SPDX-SnippetEnd -->

| Field | Holds |
| --- | --- |
| `rule` | The rule's name, so one helper can run several rules. |
| `artifact.path` | The primary piece's path, relative to the project's root. |
| `artifact.role` | The artifact's role, such as `module`. |
| `artifact.match` | What each placeholder matched, and each capture of the primary's regex, by name. |
| `artifact.key` | The artifact's [key](plugin-glossary.md#declaring), or `null` when its declaration gives none. |
| `artifact.pieces` | Each piece by its name, with its `path` and whether it `exists`. For a piece with a regex, `exists` says whether its file has a match. |

The helper answers `{"violations": [{"message": TEXT, "detail": TEXT}, ...]}`, with no `detail` for a violation the rule gives none, or `{"error": MESSAGE}`. A detail tells apart the violations one rule finds on one artifact, such as each missing function by name, and debt records each detail as a separate entry. CrossLint stops the plugin with a fault at an error, at an answer of any other shape, and at a helper that fails, as it does at anything a rule in CrossLint's Ruby raises. The helper reads files itself, at the paths the request gives, from the project's root, so CrossLint's `project_files` and `read` don't reach it.

This helper runs on Node and checks that a module's declaration file declares every function the module exports. Each function it doesn't declare is a violation, with the function's name as the detail:

<!--
SPDX-SnippetBegin
SPDX-License-Identifier: MIT-0
SPDX-SnippetCopyrightText: 2026 setdef
-->
```js
// .config/crosslint/modules/rules/declarations.mjs
import { readFileSync } from 'node:fs';
import { createInterface } from 'node:readline';

const EXPORTED = /^export (?:declare )?(?:async )?function (\w+)/gm;

const exported = (path) => [...readFileSync(path, 'utf8').matchAll(EXPORTED)].map((match) => match[1]);

const rules = {
  'declares-every-export'(artifact) {
    const declaration = artifact.pieces.declaration;
    const declared = exported(declaration.path);
    return exported(artifact.path)
      .filter((name) => !declared.includes(name))
      .map((name) => ({ message: `${declaration.path} declares no function ${name}`, detail: name }));
  },
};

for await (const line of createInterface({ input: process.stdin })) {
  const { rule, artifact } = JSON.parse(line);
  let answer;
  try {
    answer = { violations: rules[rule](artifact) };
  } catch (error) {
    answer = { error: error.message };
  }
  process.stdout.write(`${JSON.stringify(answer)}\n`);
}
```
<!-- SPDX-SnippetEnd -->

The manifest declares the helper and its rule, and a policy runs the rule on each module that has a declaration file, so the helper never reads one that isn't there:

<!--
SPDX-SnippetBegin
SPDX-License-Identifier: MIT-0
SPDX-SnippetCopyrightText: 2026 setdef
-->
```kdl
helper "declarations" command="node" file="rules/declarations.mjs"
rule "declares-every-export" helper="declarations"

policy "declaration-matches" {
  applies-to "module"
  when piece-exists "declaration"
  rule "declares-every-export"
}
```
<!-- SPDX-SnippetEnd -->

In a project of three modules, where `src/cart/total.js` exports `addTax` and `total` and `src/cart/total.d.ts` declares only `addTax`, the check reports the one function:

<!--
SPDX-SnippetBegin
SPDX-License-Identifier: MIT-0
SPDX-SnippetCopyrightText: 2026 setdef
-->
```console
$ crosslint check
src/cart/total.js: src/cart/total.d.ts declares no function total (modules/declaration-matches)
crosslint: checked 3 module artifacts: 1 error
```
<!-- SPDX-SnippetEnd -->

The protocol is the same in every language. The same helper in Python, declared as `helper "declarations" command="python3" file="rules/declarations.py"`, reports the same violation:

<!--
SPDX-SnippetBegin
SPDX-License-Identifier: MIT-0
SPDX-SnippetCopyrightText: 2026 setdef
-->
```python
# .config/crosslint/modules/rules/declarations.py
import json
import re
import sys

EXPORTED = re.compile(r"^export (?:declare )?(?:async )?function (\w+)", re.MULTILINE)


def exported(path):
    with open(path, encoding="utf-8") as file:
        return EXPORTED.findall(file.read())


def declares_every_export(artifact):
    declaration = artifact["pieces"]["declaration"]
    declared = exported(declaration["path"])
    return [{"message": f"{declaration['path']} declares no function {name}", "detail": name}
            for name in exported(artifact["path"]) if name not in declared]


RULES = {"declares-every-export": declares_every_export}

for line in sys.stdin:
    request = json.loads(line)
    try:
        answer = {"violations": RULES[request["rule"]](request["artifact"])}
    except Exception as error:
        answer = {"error": repr(error)}
    print(json.dumps(answer), flush=True)
```
<!-- SPDX-SnippetEnd -->

> **Warning:** write each answer as one line, and flush it. CrossLint waits for the line, so an answer left in the helper's output buffer never reaches it, and after 60 seconds the rule is a fault. Python buffers its standard output when it is a pipe, which is why the example passes `flush=True`.

CrossLint starts such a helper at its first request, as its command and then its file, in the project's root, with the environment CrossLint was started with. When the check ends, CrossLint closes the input of every helper at once, gives each 2 seconds to exit, and then ends it with everything it started; on Ctrl-C, it ends them without waiting. A helper CrossLint can't put in its process group or job object is ended at once, and is a fault. The helper's standard error appears under `--debug`. A helper that exits, answers with a line that isn't JSON, or doesn't answer within 60 seconds is a fault, and the message includes what it wrote to standard error.

A helper whose command isn't on the `PATH` stops CrossLint with exit status 2, and a message naming the plugin and the command it needs.

### Rules in CrossLint's Ruby

A helper on `command=(crosslint)"ruby"` is a file of Ruby that CrossLint runs itself, on the Ruby it carries, for each rule whose line gives the helper's name. It speaks no protocol: CrossLint calls it with the artifact as an object, and it returns the violations. The file defines one class for each such rule, named after the rule in camel case and inheriting from `CrossLint::Rule`, with a `check` method that takes the artifact and returns the rule's violations. `violation(artifact, message)` makes one. Here is the rule from [Rules a program runs](#rules-a-program-runs), in CrossLint's Ruby:

<!--
SPDX-SnippetBegin
SPDX-License-Identifier: MIT-0
SPDX-SnippetCopyrightText: 2026 setdef
-->
```ruby
# .config/crosslint/modules/rules/declares_every_export.rb
class DeclaresEveryExport < CrossLint::Rule
  EXPORTED = /^export (?:declare )?(?:async )?function (\w+)/

  def check(artifact)
    declaration = artifact.piece("declaration")
    declared = declaration.read.scan(EXPORTED).flatten
    (artifact.read.scan(EXPORTED).flatten - declared).map do |name|
      violation(artifact, "#{declaration.path} declares no function #{name}", detail: name)
    end
  end
end
```
<!-- SPDX-SnippetEnd -->

<!--
SPDX-SnippetBegin
SPDX-License-Identifier: MIT-0
SPDX-SnippetCopyrightText: 2026 setdef
-->
```kdl
helper "exports" command=(crosslint)"ruby" file="rules/declares_every_export.rb"
rule "declares-every-export" helper="exports"

policy "declaration-matches" {
  applies-to "module"
  when piece-exists "declaration"
  rule "declares-every-export"
}
```
<!-- SPDX-SnippetEnd -->

The artifact a rule gets has these methods. They give what a program's request holds, apart from the key, and read the pieces' text:

| Method | Returns |
| --- | --- |
| `path` | The primary piece's path, relative to the project's root. |
| `role` | The artifact's role, such as `module`. |
| `match` | What each placeholder matched, and each capture of the primary's regex, by name: `artifact.match["path"]`. |
| `read` | The primary piece's contents. |
| `piece(NAME)` | The piece of that name, with `name`, `path`, `exist?`, and `read`. For a piece with a regex, `exist?` says whether its file has a match, and `read` gives the whole file. |

A rule can also look beyond its artifact, for a path written in the artifact's text, such as a link's target, which no piece can give:

| Method | Returns |
| --- | --- |
| `project_files` | Every file the project has, as CrossLint sees them: the files Git lists, tracked or not, minus those Git ignores, and nothing under `.git/`. Each is a path relative to the project's root, with `/` between folders, in no particular order. It is the same frozen list for every artifact of a check, so a rule can index it once, in `initialize` or at its first artifact. |
| `read(PATH)` | The text of the file at `PATH`, relative to the project's root with `/` between folders. It raises `Errno::ENOENT` when no file has that exact name. A file Git ignores can be read, though it isn't in `project_files`. |

`violation(artifact, message, detail: TEXT)` makes a violation with a detail, as the example does for each missing function. Debt records each detail as a separate entry.

CrossLint makes one instance of the class per check, with no arguments, and calls `check` once for each artifact a policy applies the rule to.

The rule's file runs on the Ruby that CrossLint carries, so a project needs no Ruby installed. CrossLint 1.0.0 carries Ruby 4.1.0-preview1, and the release that moves it to Ruby 4.1.0 is a minor release. The file can use Ruby's standard library and other files in the plugin's folder. Requiring a gem CrossLint wasn't built with, or `bundler/inline`, stops the plugin with a message naming it. Anything the file or `check` raises is a fault: the plugin reports nothing else, the other plugins still run, and `crosslint check` exits with 2. `--debug` shows where it was raised. A `check` that runs for 60 seconds on one artifact, or recurses until Ruby raises `SystemStackError`, is a fault too.

A rule in CrossLint's Ruby can call a helper that a program runs, with `helper("NAME").call(input)`, which sends `input` as JSON on the helper's standard input and returns the JSON it writes to standard output.

## Steps, settings, and commands

A plugin can also declare a step, the settings it takes, and commands under the plugin's name. The debt plugin's `plugin.kdl`, which ships inside CrossLint, declares all four kinds of line:

<!--
SPDX-SnippetBegin
SPDX-License-Identifier: MIT-0
SPDX-SnippetCopyrightText: 2026 setdef
-->
```kdl
step "track-debt"

policy "has-debt"

setting "file"
setting "report-entries"

command "update" help="Rewrite the debt file to list the current violations" {
  flag "-n --dry-run" help="List the entries update would add and remove, and write nothing"
}
```
<!-- SPDX-SnippetEnd -->

| Line | Meaning |
| --- | --- |
| `step NAME` | A step built into CrossLint, for CrossLint to run after every rule of every plugin has run. The step sees every violation, whatever `--warnings` or `--quiet` hides, and can excuse some, add others, and report paid-off entries. CrossLint has one step, `track-debt`. |
| `policy NAME` with no block | A policy no rule runs, whose violations the plugin's step reports, such as `has-debt`. The configuration disables it or changes its severity like any other policy. |
| `setting NAME` | A setting the plugin takes in its block in the configuration. A setting the plugin doesn't declare stops CrossLint with exit status 2. |
| `command NAME help=TEXT` | A command the project runs as `crosslint PLUGIN NAME`, with `TEXT` as its one line in `--help`. It runs the check, then tells the plugin's step the command's name, and the step does the command's work; a plugin with a command and no step is a mistake. `NAME` is lowercase letters, digits, and `-`, and can't be `help`. It exits with 0 when it did what it was asked, and with 2 when CrossLint can't run it. |
| `flag NAMES help=TEXT` in a command's block | A command flag: a flag of that command alone, such as `flag "-n --dry-run"`, with its names in the usage spec's syntax and `TEXT` as its line in the command's `--help`. CrossLint tells the step which command flags were given. A command flag can't have the name of a global flag, `-h`, `--help`, or another flag of the same command; one that does stops CrossLint with exit status 2, naming the plugin. A `flag` line outside a command is a mistake. |

A plugin adds no flag to `crosslint check` or to any other command of CrossLint's, and a plugin that has commands can't have the name of one of CrossLint's commands, or one of the names CrossLint keeps for commands it may add: `version`, `completion`, `config`, `plugin`, `plugins`, `list`, `cache`, `doctor`, `explain`, `fix`, and `self`. A local or shared plugin can't have the name of a built-in plugin, `angular` or `debt`. Its commands take the global flags anywhere on the line, and their command flags after the command's name. `crosslint --help` and `crosslint help` list the commands of the project's plugins after CrossLint's, each with its one line of help; `crosslint debt`, `crosslint debt --help`, and `crosslint help debt` list one plugin's commands; and `crosslint debt update --help` explains one command, with its command flags and the global flags. Help never fails: with `--help` or `-h` before `--`, a flag CrossLint doesn't know or a configuration it can't read still shows help, with a line saying why a plugin's commands aren't shown, and exits with 0. Help reads only what is on disk, so a shared plugin not fetched yet is named with a line saying `crosslint check` fetches it.

A mistyped command, or a command of a plugin the configuration doesn't list, stops CrossLint with exit status 2: for a plugin the configuration doesn't list, the message names the plugin and the configuration; for a command the plugin doesn't have, it lists the plugin's commands or names the nearest; and for a word that is neither one of CrossLint's commands nor a listed plugin's name, it names the nearest of both. A command flag the command doesn't have stops CrossLint the same way, with the nearest of its command flags and the global flags.

## Artifacts a helper declares

A plugin whose artifacts depend on its settings, such as a folder the project chooses, declares them with `artifacts helper=HELPER`, in place of or beside its `artifact` lines, so its settings change where it finds each role's pieces. A plugin whose project chooses the folder of its modules could have:

<!--
SPDX-SnippetBegin
SPDX-License-Identifier: MIT-0
SPDX-SnippetCopyrightText: 2026 setdef
-->
```kdl
setting "src-dir"

helper "artifacts" command="node" file="artifacts.mjs"
artifacts helper="artifacts"
```
<!-- SPDX-SnippetEnd -->

CrossLint asks the helper once per check, before any rule runs, with the plugin's settings, and the helper declares each role with these fields:

| Field | Meaning |
| --- | --- |
| `name` | The role, such as `module`. Required. |
| `primary` | The path pattern that finds each artifact's primary piece, as in an `artifact` line's `primary`. Required. |
| `pieces` | Each piece's name and the path pattern of its path. Optional; without it, the role has no pieces. |
| `key` | A second path pattern, for the artifact's [key](plugin-glossary.md#declaring), which a debt entry can hold in place of the artifact's name. Optional. |
| `optional` | With `true`, a `primary` pattern that matches nothing isn't reported, unless no artifact of the plugin matches a file. Optional; `false` without it. |
| `dotfiles` | With `false`, a file isn't an artifact when a placeholder matched a file or folder whose name starts with `.`, as the Angular plugin skips them. Optional; `true` without it. |

An artifact a helper declares has no regex and no `name`, so its name is its primary piece's path. A manifest has one `artifacts` line.

### Artifacts a program declares

When the helper is a program, CrossLint starts it once, before any rule runs, sends it the plugin's settings, and stops it when it answers:

<!--
SPDX-SnippetBegin
SPDX-License-Identifier: MIT-0
SPDX-SnippetCopyrightText: 2026 setdef
-->
```json
{"settings": [{"name": "src-dir", "arguments": ["lib"], "properties": {}, "children": [], "line": 2}]}
```
<!-- SPDX-SnippetEnd -->

Each setting has `name`, `arguments`, `properties`, `children`, and `line`, as the configuration gives them. The helper answers with the roles it declares, each with the fields in [Artifacts a helper declares](#artifacts-a-helper-declares): `{"artifacts": [{"name": "module", "primary": "lib/{path}.js", "pieces": {"declaration": "lib/{path}.d.ts"}}]}`. For a setting it can't use, it answers `{"mistake": {"message": TEXT, "line": LINE}}`, with the setting's line, and CrossLint stops with exit status 2 at that line of the configuration. CrossLint also stops with exit status 2 at an error, at an answer of any other shape, and at an artifact that isn't one, naming the plugin and the manifest's `artifacts` line.

<!--
SPDX-SnippetBegin
SPDX-License-Identifier: MIT-0
SPDX-SnippetCopyrightText: 2026 setdef
-->
```js
// .config/crosslint/modules/artifacts.mjs
import { createInterface } from 'node:readline';

function declare(settings) {
  const given = settings.find((setting) => setting.name === 'src-dir');
  if (given && given.arguments.length !== 1) {
    return { mistake: { message: 'src-dir takes one folder, as in src-dir "src"', line: given.line } };
  }
  const src = given ? given.arguments[0] : 'src';
  return { artifacts: [{ name: 'module', primary: `${src}/{path}.js`, pieces: { declaration: `${src}/{path}.d.ts` } }] };
}

for await (const line of createInterface({ input: process.stdin })) {
  process.stdout.write(`${JSON.stringify(declare(JSON.parse(line).settings))}\n`);
}
```
<!-- SPDX-SnippetEnd -->

One helper can answer both kinds of request, as the Angular plugin's does: a request with `settings` asks for artifacts, and one with `rule` asks for a rule's violations. CrossLint starts the helper again for the rules, at their first request.

### Artifacts declared in CrossLint's Ruby

When the helper is on `command=(crosslint)"ruby"`, its file defines a class `Artifacts` inheriting from `CrossLint::Artifacts`, whose `declare` method takes the plugin's settings and returns an array of artifacts. The helper from [Artifacts a program declares](#artifacts-a-program-declares), in CrossLint's Ruby and declared as `helper "artifacts" command=(crosslint)"ruby" file="artifacts.rb"`, is:

<!--
SPDX-SnippetBegin
SPDX-License-Identifier: MIT-0
SPDX-SnippetCopyrightText: 2026 setdef
-->
```ruby
# .config/crosslint/modules/artifacts.rb
class Artifacts < CrossLint::Artifacts
  def declare(settings)
    given = settings.find { |setting| setting.name == "src-dir" }
    raise mistake("src-dir takes one folder, as in src-dir \"src\"", given) if given && given.arguments.size != 1

    src = given ? given.arguments.first : "src"
    [artifact("module", primary: "#{src}/{path}.js", pieces: {"declaration" => "#{src}/{path}.d.ts"})]
  end
end
```
<!-- SPDX-SnippetEnd -->

| Method | Meaning |
| --- | --- |
| `declare(settings)` | Called once per check, before any rule runs. Each setting has `name`, `arguments`, `properties`, `children`, and `line`, as the configuration gives them. |
| `artifact(ROLE, primary:, pieces: {}, key: nil, optional: false, dotfiles: true)` | Declares a role, with the fields in [Artifacts a helper declares](#artifacts-a-helper-declares): the role first, and the rest as keyword arguments, with `primary`, each piece's path, and `key` as path patterns. |
| `mistake(MESSAGE, SETTING)` | A mistake in the configuration at that setting's line, for `declare` to raise. It stops CrossLint with exit status 2, as any mistake does. |

Anything else `declare` raises stops CrossLint with exit status 2, naming the plugin, since no check can run without its artifacts.
