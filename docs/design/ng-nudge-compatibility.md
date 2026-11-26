# ng-nudge compatibility

CrossLint replaces [ng-nudge](https://github.com/OverTheTopMarketing/ng-nudge) (MIT, Copyright 2026 Over The Top Marketing), which checks relations between files for Angular projects only. This document holds the requirements that replacement meets. Every later design is checked against it.

Three rules govern it:

- **None of ng-nudge's value is lost, and none of its bugs are kept.** How CrossLint's output looks is free to change.
- **A project that uses ng-nudge replaces it with CrossLint in 30 minutes or less,** as a drop-in or close to one.
- **Where keeping ng-nudge's behavior conflicts with a command-line guideline,** [command-line.md](command-line.md) holds the conflict and its options.

The requirements are taken from the [ng-nudge study](https://github.com/setdef/CrossLint/blob/97b1d87494cc1c81bfa07eb67c7d92bf7aac9a77/spikes/ng-nudge-study/README.md), which reads ng-nudge 0.3.0 at commit [`10a7224`](https://github.com/OverTheTopMarketing/ng-nudge/tree/10a722456daacca08f6425c5b74e5586183c654b). "Bug N" is that study's numbering, from its [Bugs](https://github.com/setdef/CrossLint/blob/97b1d87494cc1c81bfa07eb67c7d92bf7aac9a77/spikes/ng-nudge-study/README.md#bugs) section. Its [list of what a replacement must keep](https://github.com/setdef/CrossLint/blob/97b1d87494cc1c81bfa07eb67c7d92bf7aac9a77/spikes/ng-nudge-study/README.md#what-a-replacement-must-keep) holds ng-nudge's exact behavior; this document says what CrossLint does with each part of it.

In CrossLint, ng-nudge's Angular checks are part of an Angular plugin and its debt tracking is a debt plugin ([plugins.md](plugins.md)). The requirements in this document hold for CrossLint with those two plugins listed. Choices this document leaves open are collected under [Open choices](#open-choices).

## Running

- CrossLint runs from the project root and resolves every path from the working directory, as ng-nudge does.
- A project with no `tsconfig.json` runs every check that doesn't read TypeScript. Only the Angular plugin's checks that read inside TypeScript files need it (ng-nudge needs it on every run: study, case 15).
- How CrossLint is installed, and the name of its command, wait on [#4](https://github.com/setdef/CrossLint/issues/4). Either way, a migrating project replaces ng-nudge's npm dev dependency and every `npx ng-nudge` in its scripts and CI.

## Command line

CrossLint has a flag for each of ng-nudge's, with the same meaning:

| ng-nudge flag | In CrossLint |
|---|---|
| `--warnings=all`, `--warnings=none`, `--warnings=error` | Same values and meanings: show warnings (the default), hide them, or let them fail the run. |
| `-q`, `--quiet` | Prints only what fails the run, and no summary. A warning that fails the run under `--warnings=error` is printed (bug 26). |
| `-s`, `--silent` | Prints nothing but errors that stop the run; only the exit code says the result. Wins over `--quiet`. |
| `--update-debt` | Runs every check, reports, then rewrites the debt file. Its short form, `-d`, conflicts with the guidelines: see [command-line.md, `-d`](command-line.md#-d-and---update-debt). |
| `-h`, `--help` | Prints the help and exits 0. |

Flags on the command line win over `options` in `rc.json`.

What CrossLint does with an unknown flag or an invalid value is in [command-line.md](command-line.md#mistakes-in-flags-and-configuration). It never ignores either silently, as ng-nudge does (bug 20).

## Exit codes

- `0`: no unexcused violation fails the run, and no debt entry is stale.
- Non-zero: an unexcused error; an unexcused warning under `--warnings=error`; any stale debt entry; or an error that stops the run.

ng-nudge exits 1 for all of these. Whether CrossLint keeps 1 for all of them or gives errors that stop the run a separate code is a conflict with the guidelines: see [command-line.md, exit codes](command-line.md#exit-codes). The exit code of a successful `--update-debt` run is an [open choice](#open-choices).

## Configuration

CrossLint reads `.config/ng-nudge/rc.json` and gives each of its keys ng-nudge's meaning. Whether it reads that file on every run, or converts it once into a configuration file in CrossLint's format, is an [open choice](#open-choices).

| Key | Meaning in CrossLint |
|---|---|
| `srcDir` | The folder the Angular plugin's artifacts are found in, relative to the working directory. Default `src`. Artifact paths and debt keys are relative to it. A `srcDir` that doesn't exist is reported (bug 20). |
| `tsConfig` | The path of the `tsconfig.json` that the Angular plugin's TypeScript checks read. Default `tsconfig.json`. |
| `artifacts.<role>.pattern` | A glob, relative to `srcDir`, that finds the role's primary files. Default `**/*.<role>.ts`. It overrides a built-in role's pattern or adds a role. |
| `artifacts.<role>.expects` | The companion files the role expects, by name. CrossLint checks them (in ng-nudge any `expects` list turns the role's checks off: bug 4). |
| `rules.<name>.enabled` | `false` turns the rule off, whichever plugin supplies the rule (bug 13). |
| `rules.<name>.severity` | `error` or `warning`, for any rule (bug 13). For `has-debt`, the severity of every entry before `withComment` caps it. |
| `rules.has-debt.withComment` | As in ng-nudge, in all five forms: `true` or `"warning"` (commented entries become warnings), `"none"` (commented entries are not reported), `"error"` or `false` (no cap), and `{ "maxSeverity": ..., "matching": "<regex>" }` (the cap applies only to comments the regular expression matches anywhere). Present at all, it turns on `has-debt` reporting. |
| `options.warnings` | Default for `--warnings`. |
| `options.verbosity` | `normal`, `quiet` or `silent`. |

A rule with no `severity` in `rc.json` has the default severity its plugin declares (bug 2).

`withComment.matching` is a JavaScript regular expression in ng-nudge. CrossLint matches it with the same meaning for every pattern a project's `rc.json` holds; a pattern whose meaning CrossLint can't reproduce is reported, not approximated. Glob patterns in `rc.json` are node-glob 11 patterns, and CrossLint matches the same files with them: dotfiles skipped, `**`, braces and extglobs.

## Artifacts

The Angular plugin supplies ng-nudge's seven roles: `component`, `directive`, `pipe`, `service`, `guard`, `resolver` and `interceptor`.

- Each is found by `**/*.<role>.ts` inside `srcDir`, and each expects a spec at `<base>.<role>.spec.ts`. The base is the file's path relative to `srcDir` with `.<role>.ts` removed.
- A component also has a stub at `<base>.component.stub.ts`, an interface at `<base>.component.i.d.ts`, and stylesheets at `<base>.component.css` and `<base>.component.scss`. The stub and the interface are optional: a missing one is reported only when the other exists.
- Whether a companion file exists is a fact of the filesystem, not of `tsconfig.json` (bug 3). Stylesheets are looked for beside the component, inside `srcDir` (bug 1).
- A component's inputs and outputs come from the first class in the file with a `@Component` decorator, following `extends` through every base class in any file the TypeScript program resolves. A subclass's member hides a base member of the same name, and `#private` members are skipped. CrossLint collects every form Angular treats as an input or output: `input()` and `input.required()`, `output()`, `@Input()` and `@Output()` with or without an initializer (bug 16), decorated setters, `model()` as an input and a `<name>Change` output, and `outputFromObservable()` (bug 17). An aliased member is compared by its public name (bug 17).
- A stub is read the same way. A stub with no `@Component` class is reported (bug 18).
- An interface's members are the property names of the one interface in the file, including those it inherits through `extends` (bug 14). An interface file with more than one interface is reported against its artifact, and every other artifact is still checked (bug 15).

A project can declare a role as data: a name, a pattern and the companion files it expects, each with the path where it belongs (bug 4). An artifact class in `.config/ng-nudge/artifacts/` that only sets a role and its companions becomes that data.

## Policies and rules

The Angular plugin supplies ng-nudge's four Angular policies and the debt plugin supplies the fifth:

| Policy | Applies to | Runs |
|---|---|---|
| `HasSpec` | every artifact whose role expects a spec | `spec-exists` |
| `HasInterface` | a component whose interface file exists | `stub-exists`, `interface-matches-component` |
| `HasStub` | a component whose stub file exists | `interface-exists`, `stub-matches-component` |
| `HasStyles` | every component | `prefer-css-over-scss` |
| `HasDebt` | the codebase, when the debt file has entries and `has-debt` has `withComment` and is enabled | `has-debt` |

Rule names are kept exactly, because they are keys in `rc.json` and in committed debt files: `spec-exists`, `stub-exists`, `interface-exists`, `stub-matches-component`, `interface-matches-component`, `prefer-css-over-scss` and `has-debt`.

| Rule | Reports | Default severity |
|---|---|---|
| `spec-exists` | a missing spec | error |
| `stub-exists` | a missing stub | error |
| `interface-exists` | a missing interface | error |
| `stub-matches-component` | each component input or output missing from the stub, by name | error |
| `interface-matches-component` | each component input or output missing from the interface, by name | error |
| `prefer-css-over-scss` | a `.scss` stylesheet with no `.css` | warning (bug 2) |
| `has-debt` | each debt entry, with its rule, artifact and comment | error, capped by `withComment` |

These behaviors of ng-nudge look like bugs and are kept, as the study's [list of intended behaviors](https://github.com/setdef/CrossLint/blob/97b1d87494cc1c81bfa07eb67c7d92bf7aac9a77/spikes/ng-nudge-study/README.md#intended-behaviors-that-look-like-bugs) gives them:

- The stub and interface comparisons run one way, by name: extra members in a stub or an interface are not reported, types are not compared, and the interface comparison doesn't tell inputs from outputs.
- An artifact is reported on when at least one policy applies to it. A disabled rule still lets its policy apply.

Each message keeps the facts ng-nudge's message gives: the artifact, the missing file or member, and whether a member is an input or an output. Its wording is free to change.

## Debt tracking

The debt plugin keeps every part of ng-nudge's debt tracking.

- The debt file holds one entry per excused violation, with a rule, an artifact and a comment. A missing file means no debt.
- CrossLint reads a `.config/ng-nudge/debt.tsv` written by ng-nudge 0.3.0, with every entry and every comment: tab-separated, header row `Rule`, `Artifact`, `Comment`, quoted the way d3-dsv quotes (a field with a tab, newline, carriage return or `"` is wrapped in `"` with `"` doubled), ending with a newline. Whether it keeps reading and writing that file, or converts it once, is an [open choice](#open-choices).
- An entry matches a violation by the violation's identity: its rule, its artifact with the artifact's role, and a detail such as the member's name. An entry excuses only the violation it matches: not another artifact with the same base path (bug 5), and not a later violation of the same rule on the same artifact (bug 7).
- An excused violation is neither printed as a finding nor counted toward the exit code. Excusing, stale detection and `--update-debt` consider every violation, whatever `--warnings` or the verbosity hides.
- An entry that no violation matches is stale. CrossLint lists it with its artifact and rule, says how to update the debt file, and fails the run.
- An entry for a disabled rule is neither stale nor removed by `--update-debt`, and its comment is kept (bug 11).
- `--update-debt` keeps every entry that still matches, with its comment and in its place; drops stale entries; adds one entry per distinct unexcused violation, warnings included, with an empty comment, never a duplicate (bug 7); and never writes the `has-debt` violations themselves. It creates the file and its folder when they don't exist (bug 8). With no entries left, the file keeps its header (bug 10). The file is replaced whole, so an interrupted update leaves the previous file.
- After an update, CrossLint reports the state the update left: it doesn't tell the user to run the command that just ran (bug 9). It names the file it wrote by its real path (bug 30).
- Debt keys use `/` on every system, relative to `srcDir`, so a debt file written on Windows matches on macOS and Linux and the other way round (bug 22).
- Entries are written in an order that doesn't depend on the order the filesystem lists files in.
- A row with an empty rule or artifact stops the run with a message that names the file and the row.
- Debt reporting is silent unless `rules.has-debt.withComment` is set, as in ng-nudge.

## Output

ng-nudge's printed layout is free to change. The facts in it are kept: which artifacts have errors and which have only warnings, each violation's message, which debt entries are paid off, what an update wrote, and how many artifacts were checked. How passing artifacts appear is in [command-line.md](command-line.md#output-on-success).

- Each artifact is reported by its path and role, so two artifacts with the same file name in different folders, or a component and a service with the same base path, are reported apart and counted apart (bug 6).
- The debt file is not counted as an artifact (bug 25).
- Anything that fails the run is printed, unless `--silent` is given (bug 26).
- An artifact's heading and its messages go to the same stream (bug 21). Which stream findings go to is in [command-line.md](command-line.md#streams).
- The order of the report doesn't depend on the order the filesystem lists files in.
- An error that stops the run prints a message without a stack trace, a syntax error in `rc.json` included, with the file and position of the error (bug 19).

## Project extensions

ng-nudge loads a project's extensions as JavaScript classes from `.config/ng-nudge/artifacts/`, `policies/` and `rules/`. In CrossLint the artifacts, policies and rules a project writes for itself are a local plugin ([plugins.md](plugins.md)).

- A project artifact class that only sets a role and its companions becomes data in that plugin.
- How a project's policies and rules are carried over, rewritten or run as they are, waits on [#4](https://github.com/setdef/CrossLint/issues/4).
- CrossLint never ignores a file in one of those folders without saying so. A rule file that no policy runs is reported (bug 12). Which runtime version an extension needs is stated, and a runtime too old for it is reported by name (bug 23).
- Whether a project's artifact is checked never depends on which copy of CrossLint runs (bug 24).
- Every violation carries the name of the rule that reported it, so every violation can become debt (bug 27).

## Bugs not kept

Every bug in the study is fixed. Each row links to the section that gives the requirement.

| Bug | What CrossLint does instead | Where |
|---|---|---|
| 1 | Looks for stylesheets beside the component, inside `srcDir`. | [Artifacts](#artifacts) |
| 2 | Applies a rule's declared default severity. | [Configuration](#configuration) |
| 3 | Takes whether a file exists from the filesystem. | [Artifacts](#artifacts) |
| 4 | Checks `expects`, and lets a project declare companion paths as data. | [Artifacts](#artifacts) |
| 5, 7 | Matches debt by rule, artifact with role, and detail; writes no duplicate rows. | [Debt tracking](#debt-tracking) |
| 6 | Reports artifacts by path and role. | [Output](#output) |
| 8 | Creates the debt file's folder. | [Debt tracking](#debt-tracking) |
| 9 | Reports the state after an update. | [Debt tracking](#debt-tracking) |
| 10 | Keeps the header of an empty debt file. | [Debt tracking](#debt-tracking) |
| 11 | Keeps a disabled rule's debt. | [Debt tracking](#debt-tracking) |
| 12 | Reports a rule that no policy runs. | [Project extensions](#project-extensions) |
| 13 | Configures every rule the same way, whichever plugin supplies it. | [Configuration](#configuration) |
| 14 | Follows an interface's `extends`. | [Artifacts](#artifacts) |
| 15 | Reports a file with two interfaces against its artifact and checks the rest. | [Artifacts](#artifacts) |
| 16, 17 | Collects every input and output form, by public name. | [Artifacts](#artifacts) |
| 18 | Reports a stub with no component class. | [Artifacts](#artifacts) |
| 19 | Reports a configuration syntax error without a stack trace. | [Output](#output) |
| 20 | Never ignores a mistake in flags or configuration silently. | [command-line.md](command-line.md#mistakes-in-flags-and-configuration) |
| 21 | Writes an artifact's heading and messages to one stream. | [Output](#output) |
| 22 | Writes debt keys with `/` on every system. | [Debt tracking](#debt-tracking) |
| 23 | States and checks the runtime an extension needs. | [Project extensions](#project-extensions) |
| 24 | Checks a project's artifact whichever copy of CrossLint runs. | [Project extensions](#project-extensions) |
| 25 | Doesn't count the debt file as an artifact. | [Output](#output) |
| 26 | Prints whatever fails the run. | [Output](#output) |
| 27 | Gives every violation its rule's name. | [Project extensions](#project-extensions) |
| 28, 29 | Documents every artifact, policy and rule a plugin supplies, with the default severity CrossLint applies, and every exit code. | [command-line.md](command-line.md#help) |
| 30 | Names the debt file by its real path. | [Debt tracking](#debt-tracking) |

The study also lists three suspected bugs. CrossLint orders its report and its debt entries independently of the filesystem's order; checks each artifact, a file and its role, once, however many patterns match it; and takes a role name literally where ng-nudge reads it as a regular expression.

## Migrating in 30 minutes or less

A project moves from ng-nudge to CrossLint in these steps:

| Step | What the project does |
|---|---|
| Install | Replaces ng-nudge's dev dependency with CrossLint's install, and `npx ng-nudge` in its scripts and CI with CrossLint's command. A project that installed ng-nudge from GitHub Packages also removes the `@overthetopmarketing` registry line and its credentials. |
| Plugins | Lists the Angular plugin and the debt plugin in its configuration ([plugins.md](plugins.md)). |
| `rc.json` | Nothing, or one conversion command, as the [open choice](#open-choices) settles. |
| `debt.tsv` | Nothing, or one conversion command, as the [open choice](#open-choices) settles. A debt file written on Windows has its `\` keys changed to `/` once. |
| New violations | Fixing bugs 1, 3, 4, 14, 16 and 17 finds violations ng-nudge hid. One `--update-debt` run takes them in as debt, so the first run after the migration passes. |
| Project artifacts | Each artifact class that only sets a role and companions becomes a few lines of data. |
| Project policies and rules | Wait on [#4](https://github.com/setdef/CrossLint/issues/4). A project with many of them meets the 30 minutes only if CrossLint runs them as they are or converts them. |
| Scripts | A script that passes `-d`, tests for exit code 1, reads one output stream, or parses the printed text checks the changes in [command-line.md](command-line.md#conflicts-with-ng-nudge). |

Converting a debt file means giving each entry the role and detail its key needs (bugs 5 and 7). CrossLint takes them from the current violations. An entry that two artifacts share can't be given to one of them, so the conversion keeps it on both, with its comment.

## Open choices

- **`rc.json`: read in place, or convert once.** CrossLint reads `.config/ng-nudge/rc.json` on every run, so a project changes nothing, and CrossLint keeps reading a file named for another tool. Or a command converts it once into a configuration file in CrossLint's format, so a project runs one command and commits the result. The form of CrossLint's configuration waits on [#4](https://github.com/setdef/CrossLint/issues/4) and on the command's name.
- **`debt.tsv`: read in place, or convert once.** CrossLint reads and writes ng-nudge's format, with the key extended to hold the role and the detail, so the file changes on its first update; or a command converts it once into a debt file in CrossLint's format. Under both, every comment is kept.
- **The exit code of a successful `--update-debt` run.** ng-nudge exits 1 when the update recorded new violations or removed stale entries, which reads as the result of the checks before the update. CrossLint exits 0 after a successful update, which reads as the result of the command; or it exits as ng-nudge does. A script that runs `--update-debt` and then goes on sees whichever is chosen.
- **The conflicts with the command-line guidelines,** each with its options, are in [command-line.md](command-line.md#conflicts-with-ng-nudge).
