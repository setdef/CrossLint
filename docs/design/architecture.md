# Architecture

How CrossLint's code divides, and which way dependencies point. The decision is [ADR 0002](../decisions/0002-the-engine-is-a-core-of-plain-ruby-objects-behind-ports.md). What each part must guarantee is on the other design pages; how to meet it is the implementer's choice, within these lines.

## Parts

| Part | Where | Holds | Requires |
| --- | --- | --- | --- |
| Core | `lib/cross_lint/core/` | The domain's value objects, one use case per command, and `CrossLint::Rule` and `CrossLint::Artifacts`, the classes a helper on CrossLint's Ruby inherits from | Ruby's core and standard library |
| Ports | `sig/cross_lint/ports.rbs` | One RBS interface for each thing outside the core | Nothing; Ruby never loads them |
| Adapters | `lib/cross_lint/adapters/` | One implementation of a port per format or system, and an in-memory one of each | The core, and gems |
| Contract tests | `lib/cross_lint/testing.rb` | For each port, the Minitest tests every adapter of it passes | The core, and Minitest |
| Command line | `lib/cross_lint/cli.rb` and beside it | Reading arguments by `crosslint.usage.kdl` and the commands the project's plugins declare, calling one use case, and turning its result into an exit status | The composition root |
| Composition root | `lib/cross_lint/app.rb` | Building the adapters and handing them to a use case | Everything above |
| Built-in plugins | `plugins/angular/`, `plugins/debt/` | Each a folder with a `plugin.kdl`, its helpers, and its tests with their fixtures | Only what any plugin can reach |

- **The domain:** artifact, piece (the [glossary](../glossary.md)'s piece), policy, rule result, violation with its identity, and debt entry. Each is immutable, and defined as `class Violation < Data.define(...)`: RBS's runtime checker misses a class defined with a block passed to `Data.define`.
- **The use cases:** check, initialize a configuration, move a project from ng-nudge (`crosslint init --from-ng-nudge`), and update shared plugins (`crosslint update`). A plugin's command, such as `crosslint debt update`, runs the check use case and tells the plugin's step the command's name and the command flags given; the debt plugin's step then rewrites its file. How plugins reach the engine is [ADR 0006](../decisions/0006-a-plugin-reaches-the-engine-only-through-what-its-manifest-declares.md). A use case takes its ports as keyword arguments and returns a value; it never prints, reads a file, or exits.
- **The ports:** project files (which files exist, as Git sees the working tree), configuration, plugin manifests, debt file (which also moves a debt file as it is), shared plugins (fetching them, and listing a repository's tags), CrossLint's Ruby (loading the files of helpers that run on it), helpers (running the helpers that a program runs), report, debug output (what a use case does at each step, under `--debug`), ng-nudge's files (its `rc.json` and the files of its extension folders), and JavaScript (asking Node what a regular expression matches, and what node-glob finds). Each one's contract is its RBS interface plus its contract tests: change the tests first, then the interface, then the adapters.

## Rules

- Dependencies point inward. Nothing in the core requires an adapter, the command line, or a gem; a test loads the core alone to show it.
- The command line has no rule about artifacts or debt. It turns arguments into one use case's call, and the result into output and an exit status.
- Every adapter of a port passes that port's contract tests, the in-memory adapter included; the use cases' tests run against the in-memory adapters.
- Nothing outside `plugins/angular/` refers to anything inside it, so it can move to a separate repository.
- Every file under `lib/` has an RBS signature at the matching path under `sig/`. Steep checks `lib/` against `sig/`, and the test suite runs a second time under RBS's runtime checker. CrossLint checks that every file has its signature with a local plugin, the one in the README's first example.
- The file of each helper on `command=(crosslint)"ruby"` in a plugin in `plugins/` loads at run time, once for each check, so the tests load it once as well, each plugin's into a separate module (`test/crosslint_ruby.rb`), and coverage measures it as it measures `lib/`.
