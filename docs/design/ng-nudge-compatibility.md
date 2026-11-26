# ng-nudge compatibility

CrossLint replaces [ng-nudge](https://github.com/OverTheTopMarketing/ng-nudge) (MIT, Copyright 2026 Over The Top Marketing), which checks relations between files for Angular projects only. This document holds the requirements that replacement meets. Every later design is checked against it.

Three rules govern it:

- **None of ng-nudge's value is lost, and none of its bugs are kept.** How CrossLint's output looks is free to change.
- **A project that uses ng-nudge replaces it with CrossLint in 30 minutes or less,** as a drop-in or close to one.
- **Where keeping ng-nudge's behavior conflicts with a command-line guideline,** [command-line.md](command-line.md) holds the conflict and its options.

Every statement here about what ng-nudge does is about ng-nudge 0.3.0, the package version at commit [`10a7224`](https://github.com/OverTheTopMarketing/ng-nudge/tree/10a722456daacca08f6425c5b74e5586183c654b) of its `main` branch. References such as `lib/debt.js:30-35` are to files and lines at that commit. Each section says which of ng-nudge's behaviors CrossLint keeps, and how. [Bugs not kept](#bugs-not-kept) lists each bug CrossLint doesn't keep, with where ng-nudge has it.

In CrossLint, ng-nudge's Angular checks are part of an Angular plugin and its debt tracking is a debt plugin ([plugins.md](plugins.md)). The requirements in this document hold for CrossLint with those two plugins listed. Choices this document leaves open are collected under [Open choices](#open-choices).

## Running

- CrossLint runs from the project root and resolves every path from the working directory, as ng-nudge does.
- A project with no `tsconfig.json` runs every check that doesn't read TypeScript. Only the Angular plugin's checks that read inside TypeScript files need it. ng-nudge builds a TypeScript project from `tsconfig.json` on every run, whatever the checks ([`lib/codebase.js:18-21`][codebase-18]), so it can't run in a project without one.
- How CrossLint is installed, and the name of its command, wait on [#4](https://github.com/setdef/CrossLint/issues/4). Either way, a migrating project replaces ng-nudge's npm dev dependency and every `npx ng-nudge` in its scripts and CI.

## Command line

CrossLint has a flag for each of ng-nudge's ([`bin/ng-nudge:24-33`][bin-24]), with the same meaning:

| ng-nudge flag | In CrossLint |
|---|---|
| `--warnings=all`, `--warnings=none`, `--warnings=error` | Same values and meanings: show warnings (the default), hide them, or let them fail the run. |
| `-q`, `--quiet` | Prints only what fails the run, and no summary. A warning that fails the run under `--warnings=error` is printed, where ng-nudge leaves it out. |
| `-s`, `--silent` | Prints nothing but errors that stop the run; only the exit code says the result. Wins over `--quiet`. |
| `--update-debt` | Runs every check, reports, then rewrites the debt file. Its short form, `-d`, conflicts with the guidelines: see [command-line.md, `-d`](command-line.md#-d-and---update-debt). |
| `-h`, `--help` | Prints the help and exits 0. |

Flags on the command line win over `options` in `rc.json`.

What CrossLint does with an unknown flag or an invalid value is in [command-line.md](command-line.md#mistakes-in-flags-and-configuration). It never ignores either silently, as ng-nudge does.

## Exit codes

- `0`: no unexcused violation fails the run, and no debt entry is stale.
- Non-zero: an unexcused error; an unexcused warning under `--warnings=error`; any stale debt entry; or an error that stops the run.

ng-nudge exits 1 for all of these ([`lib/verification-task.js:25-29`][task-25], [`bin/ng-nudge:86-88`][bin-86]). Whether CrossLint keeps 1 for all of them or gives errors that stop the run a separate code is a conflict with the guidelines: see [command-line.md, exit codes](command-line.md#exit-codes). The exit code of a successful `--update-debt` run is an [open choice](#open-choices).

## Configuration

CrossLint reads `.config/ng-nudge/rc.json` and gives each of its keys ng-nudge's meaning. Whether it reads that file on every run, or converts it once into a configuration file in CrossLint's format, is an [open choice](#open-choices).

| Key | Meaning in CrossLint |
|---|---|
| `srcDir` | The folder the Angular plugin's artifacts are found in, relative to the working directory. Default `src`. Artifact paths and debt keys are relative to it. A `srcDir` that doesn't exist is reported, where ng-nudge passes the run with no artifacts. |
| `tsConfig` | The path of the `tsconfig.json` that the Angular plugin's TypeScript checks read. Default `tsconfig.json`. |
| `artifacts.<role>.pattern` | A glob, relative to `srcDir`, that finds the role's primary files. Default `**/*.<role>.ts`. It overrides a built-in role's pattern or adds a role. |
| `artifacts.<role>.expects` | The companion files the role expects, by name. CrossLint checks them (in ng-nudge any `expects` list turns the role's checks off). |
| `rules.<name>.enabled` | `false` turns the rule off, whichever plugin supplies the rule. |
| `rules.<name>.severity` | `error` or `warning`, for any rule. For `has-debt`, the severity of every entry before `withComment` caps it. |
| `rules.has-debt.withComment` | As in ng-nudge, in all five forms: `true` or `"warning"` (commented entries become warnings), `"none"` (commented entries are not reported), `"error"` or `false` (no cap), and `{ "maxSeverity": ..., "matching": "<regex>" }` (the cap applies only to comments the regular expression matches anywhere). Present at all, it turns on `has-debt` reporting. |
| `options.warnings` | Default for `--warnings`. |
| `options.verbosity` | `normal`, `quiet` or `silent`. |

A rule with no `severity` in `rc.json` has the default severity its plugin declares. ng-nudge gives such a rule `error`, whatever it declares.

`withComment.matching` is a JavaScript regular expression, which ng-nudge matches with `RegExp.test` ([`lib/rule/has-debt.rule.js:44-46`][hasdebt-44]). CrossLint matches it with the same meaning for every pattern a project's `rc.json` holds; a pattern whose meaning CrossLint can't reproduce is reported, not approximated. Glob patterns in `rc.json` are node-glob 11 patterns, and CrossLint matches the same files with them: dotfiles skipped, `**`, braces and extglobs.

## Artifacts

The Angular plugin supplies ng-nudge's seven roles: `component`, `directive`, `pipe`, `service`, `guard`, `resolver` and `interceptor`.

- Each is found by `**/*.<role>.ts` inside `srcDir`, and each expects a spec at `<base>.<role>.spec.ts`. The base is the file's path relative to `srcDir` with `.<role>.ts` removed.
- A component also has a stub at `<base>.component.stub.ts`, an interface at `<base>.component.i.d.ts`, and stylesheets at `<base>.component.css` and `<base>.component.scss`. The stub and the interface are optional: a missing one is reported only when the other exists.
- Whether a companion file exists is a fact of the filesystem, not of `tsconfig.json`. Stylesheets are looked for beside the component, inside `srcDir`.
- A component's inputs and outputs come from the first class in the file with a `@Component` decorator, following `extends` through every base class in any file the TypeScript program resolves. A subclass's member hides a base member of the same name, and `#private` members are skipped. CrossLint collects every form Angular treats as an input or output: `input()` and `input.required()`, `output()`, `@Input()` and `@Output()` with or without an initializer, decorated setters, `model()` as an input and a `<name>Change` output, and `outputFromObservable()`. An aliased member is compared by its public name.
- A stub is read the same way. A stub with no `@Component` class is reported.
- An interface's members are the property names of the one interface in the file, including those it inherits through `extends`. An interface file with more than one interface is reported against its artifact, and every other artifact is still checked.

A project can declare a role as data: a name, a pattern and the companion files it expects, each with the path where it belongs. An artifact class in `.config/ng-nudge/artifacts/` that only sets a role and its companions becomes that data.

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
| `prefer-css-over-scss` | a `.scss` stylesheet with no `.css` | warning |
| `has-debt` | each debt entry, with its rule, artifact and comment | error, capped by `withComment` |

These behaviors of ng-nudge look like bugs, follow from its design, and are kept:

- The stub and interface comparisons run one way, by name: extra members in a stub or an interface are not reported, types are not compared, and the interface comparison doesn't tell inputs from outputs. ng-nudge looks up only the component's members in the other file, and an interface's property satisfies either an input or an output ([`lib/artifact/api.js:21-29`][api-21], [`lib/artifact/interface-api.js:8-14`][iapi-8]).
- An artifact is reported on when at least one policy applies to it ([`lib/verification-task.js:44-56`][task-44]). A disabled rule still lets its policy apply: a disabled rule returns no violations ([`lib/rule/rule.js:39-42`][rule-39]), and the four Angular policies' conditions don't read whether a rule is enabled ([`lib/policy/has-spec.policy.js:11-13`][hasspec-11] is one).

Each message keeps the facts ng-nudge's message gives: the artifact, the missing file or member, and whether a member is an input or an output. Its wording is free to change.

## Debt tracking

The debt plugin keeps every part of ng-nudge's debt tracking.

- The debt file holds one entry per excused violation, with a rule, an artifact and a comment. A missing file means no debt.
- CrossLint reads a `.config/ng-nudge/debt.tsv` written by ng-nudge 0.3.0, with every entry and every comment: tab-separated, header row `Rule`, `Artifact`, `Comment`, quoted the way d3-dsv quotes (a field with a tab, newline, carriage return or `"` is wrapped in `"` with `"` doubled), ending with a newline. Whether it keeps reading and writing that file, or converts it once, is an [open choice](#open-choices).
- An entry matches a violation by the violation's identity: its rule, its artifact with the artifact's role, and a detail such as the member's name. An entry excuses only the violation it matches: not another artifact with the same base path, and not a later violation of the same rule on the same artifact. ng-nudge matches on the rule and the base path alone ([`lib/debt.js:30-35`][debt-30]).
- An excused violation is neither printed as a finding nor counted toward the exit code. Excusing, stale detection and `--update-debt` consider every violation, whatever `--warnings` or the verbosity hides.
- An entry that no violation matches is stale. CrossLint lists it with its artifact and rule, says how to update the debt file, and fails the run.
- An entry for a disabled rule is neither stale nor removed by `--update-debt`, and its comment is kept.
- `--update-debt` keeps every entry that still matches, with its comment and in its place; drops stale entries; adds one entry per distinct unexcused violation, warnings included, with an empty comment, never a duplicate; and never writes the `has-debt` violations themselves. It creates the file and its folder when they don't exist. With no entries left, the file keeps its header. The file is replaced whole, so an interrupted update leaves the previous file.
- After an update, CrossLint reports the state the update left: it doesn't tell the user to run the command that just ran. It names the file it wrote by its real path.
- Debt keys use `/` on every system, relative to `srcDir`, so a debt file written on Windows matches on macOS and Linux and the other way round.
- Entries are written in an order that doesn't depend on the order the filesystem lists files in.
- A row with an empty rule or artifact stops the run with a message that names the file and the row.
- Debt reporting is silent unless `rules.has-debt.withComment` is set, as in ng-nudge ([`lib/policy/has-debt.policy.js:12-17`][hasdebtpolicy-12]).

## Output

ng-nudge's printed layout is free to change. The facts in it are kept: which artifacts have errors and which have only warnings, each violation's message, which debt entries are paid off, what an update wrote, and how many artifacts were checked ([`lib/console-output.js:39-86`][out-39]). How passing artifacts appear is in [command-line.md](command-line.md#output-on-success).

- Each artifact is reported by its path and role, so two artifacts with the same file name in different folders, or a component and a service with the same base path, are reported apart and counted apart.
- The debt file is not counted as an artifact.
- Anything that fails the run is printed, unless `--silent` is given.
- An artifact's heading and its messages go to the same stream. Which stream findings go to is in [command-line.md](command-line.md#streams).
- The order of the report doesn't depend on the order the filesystem lists files in.
- An error that stops the run prints a message without a stack trace, a syntax error in `rc.json` included, with the file and position of the error.

## Project extensions

ng-nudge loads a project's extensions as JavaScript classes from `.config/ng-nudge/artifacts/`, `policies/` and `rules/` ([`lib/config/extension-directory.js:18-33`][ext-18]). In CrossLint the artifacts, policies and rules a project writes for itself are a local plugin ([plugins.md](plugins.md)).

- A project artifact class that only sets a role and its companions becomes data in that plugin.
- How a project's policies and rules are carried over, rewritten or run as they are, waits on [#4](https://github.com/setdef/CrossLint/issues/4).
- CrossLint never ignores a file in one of those folders without saying so. A rule file that no policy runs is reported. Which runtime version an extension needs is stated, and a runtime too old for it is reported by name.
- Whether a project's artifact is checked never depends on which copy of CrossLint runs.
- Every violation carries the name of the rule that reported it, so every violation can become debt.

## Bugs not kept

CrossLint keeps none of these bugs of ng-nudge 0.3.0. Each row says what ng-nudge does and where, and links to the section that holds CrossLint's requirement.

| Bug | What ng-nudge does | What CrossLint does instead | Where |
|---|---|---|---|
| Stylesheets looked for in the wrong folder | `hasCss` and `hasScss` call `existsSync` on a path relative to `srcDir`, which Node resolves against the working directory, so with the default `srcDir` no stylesheet is found and `prefer-css-over-scss` never fires ([`lib/artifact/component.artifact.js:71-77`][comp-71]). | Looks for stylesheets beside the component, inside `srcDir`. | [Artifacts](#artifacts) |
| Declared default severity ignored | Every rule with no entry in `rc.json` gets a configuration with severity `error`, so a rule's declared default is never used, and `prefer-css-over-scss`, declared a warning, fails the run ([`lib/config/registry/rule.registry.js:18-20`][rulereg-18], [`lib/config/rule-config.js:20-22`][ruleconfig-20], [`lib/rule/rule.js:27-33`][rule-27]). | Applies a rule's declared default severity. | [Configuration](#configuration) |
| Existence taken from `tsconfig.json` | Whether a TypeScript companion exists is asked of the ts-morph project, which holds only the files `tsconfig.json` includes, so a spec excluded from `tsconfig.json` counts as missing ([`lib/artifact/artifact-file.js:16-18`][afile-16], [`lib/codebase.js:18-21`][codebase-18]). | Takes whether a file exists from the filesystem. | [Artifacts](#artifacts) |
| `expects` turns checks off | `rc.json` holds `expects` as strings, and `HasSpec` compares them with a class, so any `expects` list turns off every check for the role. Companion paths are fixed in code, and a built-in role's `from` drops an overriding `expects` ([`lib/config/artifact-definition.js:24-37`][artdef-24], [`lib/artifact/artifact.js:80-82`][art-80], [`lib/policy/has-spec.policy.js:11-13`][hasspec-11], [`lib/artifact/component.artifact.js:22-25`][comp-22]). | Checks `expects`, and lets a project declare companion paths as data. | [Artifacts](#artifacts) |
| Debt shared across roles, and debt that ignores the detail | A debt entry matches on rule and base path, and the base path drops the role, so `foo.component.ts`'s entry excuses `foo.service.ts`'s violation of the same rule. One entry excuses every violation of its rule on its artifact, later ones included, and `--update-debt` writes one identical row per violation ([`lib/debt.js:30-35`][debt-30], [`lib/artifact/artifact.js:33-36`][art-33], [`lib/config/debt-file.js:70-74`][debtfile-70]). | Matches debt by rule, artifact with role, and detail; writes no duplicate rows. | [Debt tracking](#debt-tracking) |
| Artifacts merged by file name | ng-nudge groups and counts artifacts in the report by the last segment of the base path, so two `widget` components in different folders, or a component and a service with one base path, print and count as one ([`lib/console-output.js:15-24`][out-15], [`lib/artifact/artifact.js:38-40`][art-38]). | Reports artifacts by path and role. | [Output](#output) |
| Update fails without the folder | `--update-debt` writes the debt file without creating its folder, and the error escapes before the report prints ([`lib/config/debt-file.js:81`][debtfile-81], [`lib/verification-task.js:17-23`][task-17]). | Creates the debt file's folder. | [Debt tracking](#debt-tracking) |
| Update reports the state before it | ng-nudge computes the report and the exit code from the debt as it read it at the start, so a run that removes a stale entry still tells the user to run `--update-debt` ([`lib/verification-task.js:25-39`][task-25-39], [`lib/verification-task.js:73-75`][task-73]). | Reports the state after an update. | [Debt tracking](#debt-tracking) |
| Empty debt file loses its header | With no entries, the file becomes a single newline ([`lib/config/debt-file.js:76-81`][debtfile-76]). | Keeps the header of an empty debt file. | [Debt tracking](#debt-tracking) |
| Disabling a rule pays off its debt | A disabled rule returns no violations, so its entries look stale and fail the run, and `--update-debt` then deletes them with their comments ([`lib/rule/rule.js:39-42`][rule-39], [`lib/debt.js:45-49`][debt-45], [`lib/verification-task.js:26`][task-26]). | Keeps a disabled rule's debt. | [Debt tracking](#debt-tracking) |
| Rule files that never run | The help says custom extensions go in `.config/ng-nudge/rules/`, and ng-nudge imports the rules there, but nothing reads them ([`bin/ng-nudge:13-16`][bin-13], [`lib/config/registry/custom-rule.registry.js:11-15`][customrule-11], [`lib/config/config.js:44-46`][config-44]). | Reports a rule that no policy runs. | [Project extensions](#project-extensions) |
| Rules of project policies can't be configured | A project's policy is constructed with no configuration, so `severity` and `enabled` for its rules are ignored ([`lib/config/registry/policy.registry.js:14`][policyreg-14]). | Configures every rule the same way, whichever plugin supplies it. | [Configuration](#configuration) |
| Inherited interface members missed | Only the properties declared in the interface itself are read, so a member inherited through `extends` is reported missing ([`lib/artifact/interface-api.js:28-31`][iapi-28]). | Follows an interface's `extends`. | [Artifacts](#artifacts) |
| Two interfaces stop the run | ng-nudge throws an error on an interface file with two interfaces, and reports no other artifact ([`lib/artifact/interface-api.js:20-25`][iapi-20], [`bin/ng-nudge:86-88`][bin-86]). | Reports a file with two interfaces against its artifact and checks the rest. | [Artifacts](#artifacts) |
| Input and output forms missed | A property with no initializer is skipped before its decorators are read, so `@Input() hint: string;` is never compared. `model()`, setter inputs and `outputFromObservable()` are not collected, and an aliased input is compared by its property name ([`lib/artifact/api.js:52-88`][api-52]). | Collects every input and output form, by public name. | [Artifacts](#artifacts) |
| Stub with no component class passes | When no class in the stub has `@Component`, the stub's members come back empty and the rule reports nothing ([`lib/artifact/api.js:37-38`][api-37], [`lib/rule/stub-matches-component.rule.js:10`][stubrule-10]). | Reports a stub with no component class. | [Artifacts](#artifacts) |
| Stack trace for a syntax error in `rc.json` | `rc.json` is read before the `try` that turns errors into messages ([`bin/ng-nudge:63`][bin-63], [`bin/ng-nudge:77-89`][bin-77]). | Reports a configuration syntax error without a stack trace. | [Output](#output) |
| Mistakes ignored silently | `rc.json` is never checked against `rc.schema.json`, so a misspelled key, an unknown severity and a `srcDir` that doesn't exist go unreported. Unknown flags are ignored, `--warnings error` is ignored, and an unknown `--warnings` value acts as `all` ([`bin/ng-nudge:66-75`][bin-66], [`lib/rule/rule.js:27-33`][rule-27]). | Never ignores a mistake in flags or configuration silently. | [command-line.md](command-line.md#mistakes-in-flags-and-configuration) |
| Heading and messages on different streams | Headings go to stdout and a warning's message to stderr, so with stderr discarded a `⚠` heading shows with nothing under it ([`lib/console-output.js:52-58`][out-52], [`lib/severity.js:9`][sev-9]). | Writes an artifact's heading and messages to one stream. | [Output](#output) |
| Debt keys with `\` on Windows | glob returns paths with `\` on Windows, so a debt file written on Windows matches nothing on macOS or Linux, and the other way round ([`lib/codebase.js:45-47`][codebase-45]). | Writes debt keys with `/` on every system. | [Debt tracking](#debt-tracking) |
| Extensions fail on the oldest supported Node | `package.json` declares Node 18 or later, and extensions are `.js` ES modules loaded with `import()`. In a project whose `package.json` has no `"type": "module"`, Node 18.20 and 20.10 load them as CommonJS, and the run stops with "Cannot use import statement outside a module" ([`package.json:34-36`][pkg-34], [`lib/config/extension-directory.js:18-33`][ext-18]). | States and checks the runtime an extension needs. | [Project extensions](#project-extensions) |
| Project artifact tied to one copy of ng-nudge | Whether an artifact expects a spec is a test of class identity, so when the ng-nudge that runs is not the copy a project's extension imports, the project's artifact is not checked ([`lib/artifact/artifact.js:80-82`][art-80]). | Checks a project's artifact whichever copy of CrossLint runs. | [Project extensions](#project-extensions) |
| Debt file counted as an artifact | ng-nudge counts every name with a violation in "Checked N artifact(s)", `has-debt`'s subject included ([`lib/console-output.js:16`][out-16], [`lib/console-output.js:64`][out-64]). | Doesn't count the debt file as an artifact. | [Output](#output) |
| `--quiet` hides a warning that fails the run | Under `--warnings=error` a warning fails the run, but `--quiet` prints only artifacts with errors, so the run fails with no output ([`lib/verification-task.js:25-29`][task-25], [`lib/console-output.js:48-50`][out-48]). | Prints whatever fails the run. | [Output](#output) |
| Violation without a rule | A violation's rule name comes from its rule, and in the README's custom-rule example the violation has none. `--update-debt` then writes an empty rule name and stops, and once the debt file has any entry, every run stops ([`lib/violation.js:20`][viol-20], [`README.md:95-118`][readme-95], [`lib/config/debt-file.js:70-75`][debtfile-70], [`lib/debt.js:4-13`][debt-4], [`lib/debt.js:30-35`][debt-30]). | Gives every violation its rule's name. | [Project extensions](#project-extensions) |
| Documentation that doesn't match the code | The README's custom rule imports `../violation.mjs`, which doesn't exist, and `Violation` and `Severity` are not in the package's `exports`. The README leaves out `HasSpec`, `spec-exists` and `interface-matches-component`, lists the debt rule as `HasDebtRule` where its configuration key is `has-debt`, and lists `PreferCssOverScss` as a warning, which it isn't in practice. The help lists exit 1 as violations only, leaving out stale debt ([`README.md:76-100`][readme-76], [`package.json:7-11`][pkg-7], [`bin/ng-nudge:35-37`][bin-35]). | Documents every artifact, policy and rule a plugin supplies, with the default severity CrossLint applies, and every exit code. | [command-line.md](command-line.md#help) |
| Debt file named without `.tsv` | In "Updated … (N entries)", ng-nudge prints the debt file's path without its extension ([`lib/verification-task.js:91`][task-91], [`lib/config/debt-file.js:17`][debtfile-17]). | Names the debt file by its real path. | [Debt tracking](#debt-tracking) |

ng-nudge also reports artifacts and writes new debt rows in the order glob walks the folders, which is not sorted, and never calls the `Debt.sorted()` it has ([`lib/debt.js:59-63`][debt-59]). It globs each role's pattern separately, so a pattern that matches another role's files makes a second artifact for the same file ([`lib/codebase.js:43-54`][codebase-43]). And it builds a regular expression from a role's name without escaping it ([`lib/artifact/artifact.js:34`][art-34]). CrossLint orders its report and its debt entries independently of the filesystem's order; checks each artifact, a file and its role, once, however many patterns match it; and takes a role name literally.

## Migrating in 30 minutes or less

A project moves from ng-nudge to CrossLint in these steps:

| Step | What the project does |
|---|---|
| Install | Replaces ng-nudge's dev dependency with CrossLint's install, and `npx ng-nudge` in its scripts and CI with CrossLint's command. A project that installed ng-nudge from GitHub Packages also removes the `@overthetopmarketing` registry line and its credentials. |
| Plugins | Lists the Angular plugin and the debt plugin in its configuration ([plugins.md](plugins.md)). |
| `rc.json` | Nothing, or one conversion command, as the [open choice](#open-choices) settles. |
| `debt.tsv` | Nothing, or one conversion command, as the [open choice](#open-choices) settles. A debt file written on Windows has its `\` keys changed to `/` once. |
| New violations | Fixing the stylesheet folder, existence from `tsconfig.json`, `expects`, inherited interface members and the missed input and output forms ([Bugs not kept](#bugs-not-kept)) finds violations ng-nudge hid. One `--update-debt` run takes them in as debt, so the first run after the migration passes. |
| Project artifacts | Each artifact class that only sets a role and companions becomes a few lines of data. |
| Project policies and rules | Wait on [#4](https://github.com/setdef/CrossLint/issues/4). A project with many of them meets the 30 minutes only if CrossLint runs them as they are or converts them. |
| Scripts | A script that passes `-d`, tests for exit code 1, reads one output stream, or parses the printed text checks the changes in [command-line.md](command-line.md#conflicts-with-ng-nudge). |

Converting a debt file means giving each entry the role and detail its key needs ([Debt tracking](#debt-tracking)). CrossLint takes them from the current violations. An entry that two artifacts share can't be given to one of them, so the conversion keeps it on both, with its comment.

## Open choices

- **`rc.json`: read in place, or convert once.** CrossLint reads `.config/ng-nudge/rc.json` on every run, so a project changes nothing, and CrossLint keeps reading a file named for another tool. Or a command converts it once into a configuration file in CrossLint's format, so a project runs one command and commits the result. The form of CrossLint's configuration waits on [#4](https://github.com/setdef/CrossLint/issues/4) and on the command's name.
- **`debt.tsv`: read in place, or convert once.** CrossLint reads and writes ng-nudge's format, with the key extended to hold the role and the detail, so the file changes on its first update; or a command converts it once into a debt file in CrossLint's format. Under both, every comment is kept.
- **The exit code of a successful `--update-debt` run.** ng-nudge exits 1 when the update recorded new violations or removed stale entries, which reads as the result of the checks before the update. CrossLint exits 0 after a successful update, which reads as the result of the command; or it exits as ng-nudge does. A script that runs `--update-debt` and then goes on sees whichever is chosen.
- **The conflicts with the command-line guidelines,** each with its options, are in [command-line.md](command-line.md#conflicts-with-ng-nudge).

[afile-16]: https://github.com/OverTheTopMarketing/ng-nudge/blob/10a722456daacca08f6425c5b74e5586183c654b/lib/artifact/artifact-file.js#L16-L18
[api-21]: https://github.com/OverTheTopMarketing/ng-nudge/blob/10a722456daacca08f6425c5b74e5586183c654b/lib/artifact/api.js#L21-L29
[api-37]: https://github.com/OverTheTopMarketing/ng-nudge/blob/10a722456daacca08f6425c5b74e5586183c654b/lib/artifact/api.js#L37-L38
[api-52]: https://github.com/OverTheTopMarketing/ng-nudge/blob/10a722456daacca08f6425c5b74e5586183c654b/lib/artifact/api.js#L52-L88
[art-33]: https://github.com/OverTheTopMarketing/ng-nudge/blob/10a722456daacca08f6425c5b74e5586183c654b/lib/artifact/artifact.js#L33-L36
[art-34]: https://github.com/OverTheTopMarketing/ng-nudge/blob/10a722456daacca08f6425c5b74e5586183c654b/lib/artifact/artifact.js#L34
[art-38]: https://github.com/OverTheTopMarketing/ng-nudge/blob/10a722456daacca08f6425c5b74e5586183c654b/lib/artifact/artifact.js#L38-L40
[art-80]: https://github.com/OverTheTopMarketing/ng-nudge/blob/10a722456daacca08f6425c5b74e5586183c654b/lib/artifact/artifact.js#L80-L82
[artdef-24]: https://github.com/OverTheTopMarketing/ng-nudge/blob/10a722456daacca08f6425c5b74e5586183c654b/lib/config/artifact-definition.js#L24-L37
[bin-13]: https://github.com/OverTheTopMarketing/ng-nudge/blob/10a722456daacca08f6425c5b74e5586183c654b/bin/ng-nudge#L13-L16
[bin-24]: https://github.com/OverTheTopMarketing/ng-nudge/blob/10a722456daacca08f6425c5b74e5586183c654b/bin/ng-nudge#L24-L33
[bin-35]: https://github.com/OverTheTopMarketing/ng-nudge/blob/10a722456daacca08f6425c5b74e5586183c654b/bin/ng-nudge#L35-L37
[bin-63]: https://github.com/OverTheTopMarketing/ng-nudge/blob/10a722456daacca08f6425c5b74e5586183c654b/bin/ng-nudge#L63
[bin-66]: https://github.com/OverTheTopMarketing/ng-nudge/blob/10a722456daacca08f6425c5b74e5586183c654b/bin/ng-nudge#L66-L75
[bin-77]: https://github.com/OverTheTopMarketing/ng-nudge/blob/10a722456daacca08f6425c5b74e5586183c654b/bin/ng-nudge#L77-L89
[bin-86]: https://github.com/OverTheTopMarketing/ng-nudge/blob/10a722456daacca08f6425c5b74e5586183c654b/bin/ng-nudge#L86-L88
[codebase-18]: https://github.com/OverTheTopMarketing/ng-nudge/blob/10a722456daacca08f6425c5b74e5586183c654b/lib/codebase.js#L18-L21
[codebase-43]: https://github.com/OverTheTopMarketing/ng-nudge/blob/10a722456daacca08f6425c5b74e5586183c654b/lib/codebase.js#L43-L54
[codebase-45]: https://github.com/OverTheTopMarketing/ng-nudge/blob/10a722456daacca08f6425c5b74e5586183c654b/lib/codebase.js#L45-L47
[comp-22]: https://github.com/OverTheTopMarketing/ng-nudge/blob/10a722456daacca08f6425c5b74e5586183c654b/lib/artifact/component.artifact.js#L22-L25
[comp-71]: https://github.com/OverTheTopMarketing/ng-nudge/blob/10a722456daacca08f6425c5b74e5586183c654b/lib/artifact/component.artifact.js#L71-L77
[config-44]: https://github.com/OverTheTopMarketing/ng-nudge/blob/10a722456daacca08f6425c5b74e5586183c654b/lib/config/config.js#L44-L46
[customrule-11]: https://github.com/OverTheTopMarketing/ng-nudge/blob/10a722456daacca08f6425c5b74e5586183c654b/lib/config/registry/custom-rule.registry.js#L11-L15
[debt-4]: https://github.com/OverTheTopMarketing/ng-nudge/blob/10a722456daacca08f6425c5b74e5586183c654b/lib/debt.js#L4-L13
[debt-30]: https://github.com/OverTheTopMarketing/ng-nudge/blob/10a722456daacca08f6425c5b74e5586183c654b/lib/debt.js#L30-L35
[debt-45]: https://github.com/OverTheTopMarketing/ng-nudge/blob/10a722456daacca08f6425c5b74e5586183c654b/lib/debt.js#L45-L49
[debt-59]: https://github.com/OverTheTopMarketing/ng-nudge/blob/10a722456daacca08f6425c5b74e5586183c654b/lib/debt.js#L59-L63
[debtfile-17]: https://github.com/OverTheTopMarketing/ng-nudge/blob/10a722456daacca08f6425c5b74e5586183c654b/lib/config/debt-file.js#L17
[debtfile-70]: https://github.com/OverTheTopMarketing/ng-nudge/blob/10a722456daacca08f6425c5b74e5586183c654b/lib/config/debt-file.js#L70-L75
[debtfile-76]: https://github.com/OverTheTopMarketing/ng-nudge/blob/10a722456daacca08f6425c5b74e5586183c654b/lib/config/debt-file.js#L76-L81
[debtfile-81]: https://github.com/OverTheTopMarketing/ng-nudge/blob/10a722456daacca08f6425c5b74e5586183c654b/lib/config/debt-file.js#L81
[ext-18]: https://github.com/OverTheTopMarketing/ng-nudge/blob/10a722456daacca08f6425c5b74e5586183c654b/lib/config/extension-directory.js#L18-L33
[hasdebt-44]: https://github.com/OverTheTopMarketing/ng-nudge/blob/10a722456daacca08f6425c5b74e5586183c654b/lib/rule/has-debt.rule.js#L44-L46
[hasdebtpolicy-12]: https://github.com/OverTheTopMarketing/ng-nudge/blob/10a722456daacca08f6425c5b74e5586183c654b/lib/policy/has-debt.policy.js#L12-L17
[hasspec-11]: https://github.com/OverTheTopMarketing/ng-nudge/blob/10a722456daacca08f6425c5b74e5586183c654b/lib/policy/has-spec.policy.js#L11-L13
[iapi-8]: https://github.com/OverTheTopMarketing/ng-nudge/blob/10a722456daacca08f6425c5b74e5586183c654b/lib/artifact/interface-api.js#L8-L14
[iapi-20]: https://github.com/OverTheTopMarketing/ng-nudge/blob/10a722456daacca08f6425c5b74e5586183c654b/lib/artifact/interface-api.js#L20-L25
[iapi-28]: https://github.com/OverTheTopMarketing/ng-nudge/blob/10a722456daacca08f6425c5b74e5586183c654b/lib/artifact/interface-api.js#L28-L31
[out-15]: https://github.com/OverTheTopMarketing/ng-nudge/blob/10a722456daacca08f6425c5b74e5586183c654b/lib/console-output.js#L15-L24
[out-16]: https://github.com/OverTheTopMarketing/ng-nudge/blob/10a722456daacca08f6425c5b74e5586183c654b/lib/console-output.js#L16
[out-39]: https://github.com/OverTheTopMarketing/ng-nudge/blob/10a722456daacca08f6425c5b74e5586183c654b/lib/console-output.js#L39-L86
[out-48]: https://github.com/OverTheTopMarketing/ng-nudge/blob/10a722456daacca08f6425c5b74e5586183c654b/lib/console-output.js#L48-L50
[out-52]: https://github.com/OverTheTopMarketing/ng-nudge/blob/10a722456daacca08f6425c5b74e5586183c654b/lib/console-output.js#L52-L58
[out-64]: https://github.com/OverTheTopMarketing/ng-nudge/blob/10a722456daacca08f6425c5b74e5586183c654b/lib/console-output.js#L64
[pkg-7]: https://github.com/OverTheTopMarketing/ng-nudge/blob/10a722456daacca08f6425c5b74e5586183c654b/package.json#L7-L11
[pkg-34]: https://github.com/OverTheTopMarketing/ng-nudge/blob/10a722456daacca08f6425c5b74e5586183c654b/package.json#L34-L36
[policyreg-14]: https://github.com/OverTheTopMarketing/ng-nudge/blob/10a722456daacca08f6425c5b74e5586183c654b/lib/config/registry/policy.registry.js#L14
[readme-76]: https://github.com/OverTheTopMarketing/ng-nudge/blob/10a722456daacca08f6425c5b74e5586183c654b/README.md?plain=1#L76-L100
[readme-95]: https://github.com/OverTheTopMarketing/ng-nudge/blob/10a722456daacca08f6425c5b74e5586183c654b/README.md?plain=1#L95-L118
[rule-27]: https://github.com/OverTheTopMarketing/ng-nudge/blob/10a722456daacca08f6425c5b74e5586183c654b/lib/rule/rule.js#L27-L33
[rule-39]: https://github.com/OverTheTopMarketing/ng-nudge/blob/10a722456daacca08f6425c5b74e5586183c654b/lib/rule/rule.js#L39-L42
[rulereg-18]: https://github.com/OverTheTopMarketing/ng-nudge/blob/10a722456daacca08f6425c5b74e5586183c654b/lib/config/registry/rule.registry.js#L18-L20
[ruleconfig-20]: https://github.com/OverTheTopMarketing/ng-nudge/blob/10a722456daacca08f6425c5b74e5586183c654b/lib/config/rule-config.js#L20-L22
[sev-9]: https://github.com/OverTheTopMarketing/ng-nudge/blob/10a722456daacca08f6425c5b74e5586183c654b/lib/severity.js#L9
[stubrule-10]: https://github.com/OverTheTopMarketing/ng-nudge/blob/10a722456daacca08f6425c5b74e5586183c654b/lib/rule/stub-matches-component.rule.js#L10
[task-17]: https://github.com/OverTheTopMarketing/ng-nudge/blob/10a722456daacca08f6425c5b74e5586183c654b/lib/verification-task.js#L17-L23
[task-25]: https://github.com/OverTheTopMarketing/ng-nudge/blob/10a722456daacca08f6425c5b74e5586183c654b/lib/verification-task.js#L25-L29
[task-25-39]: https://github.com/OverTheTopMarketing/ng-nudge/blob/10a722456daacca08f6425c5b74e5586183c654b/lib/verification-task.js#L25-L39
[task-26]: https://github.com/OverTheTopMarketing/ng-nudge/blob/10a722456daacca08f6425c5b74e5586183c654b/lib/verification-task.js#L26
[task-44]: https://github.com/OverTheTopMarketing/ng-nudge/blob/10a722456daacca08f6425c5b74e5586183c654b/lib/verification-task.js#L44-L56
[task-73]: https://github.com/OverTheTopMarketing/ng-nudge/blob/10a722456daacca08f6425c5b74e5586183c654b/lib/verification-task.js#L73-L75
[task-91]: https://github.com/OverTheTopMarketing/ng-nudge/blob/10a722456daacca08f6425c5b74e5586183c654b/lib/verification-task.js#L91
[viol-20]: https://github.com/OverTheTopMarketing/ng-nudge/blob/10a722456daacca08f6425c5b74e5586183c654b/lib/violation.js#L20
