# ng-nudge study

The question: what does [ng-nudge](https://github.com/OverTheTopMarketing/ng-nudge) do, which of its behaviors are bugs, and what must a replacement keep? This is step 1 of #1, and the "rest of ng-nudge" item of its step 3.

Every file and line reference below is to ng-nudge at commit [`10a7224`](https://github.com/OverTheTopMarketing/ng-nudge/tree/10a722456daacca08f6425c5b74e5586183c654b), its `main` branch, package version 0.3.0. ng-nudge is about 1,700 lines of JavaScript, with 700 more of `.d.ts` sidecar files, and this study read all of it.

## How to rerun

```sh
./fetch-ng-nudge.sh /some/empty/dir     # clones ng-nudge at 10a7224 and runs npm ci
./reproduce.sh /some/empty/dir          # every case
./reproduce.sh /some/empty/dir 04-debt-shared-base-path   # one case
```

`reproduce.sh` copies each folder under `fixtures/` to a temporary folder, links ng-nudge into its `node_modules`, runs the commands in its `steps.sh`, and prints each command with its output and `[exit N]`. The fixtures need no Angular packages: ng-nudge reads decorators by name and never resolves `@angular/core`.

The recorded runs:

- [`transcript-macos.txt`](transcript-macos.txt): every case on macOS with Node 26.
- [`transcript-windows.txt`](transcript-windows.txt): cases 01 to 20 on Windows with Node 22. There, the script's `ln -s` made a copy instead of a link, so case 19 ran with two copies of ng-nudge and shows bug 24 instead of the custom artifact working.
- [`transcript-node-20.10.txt`](transcript-node-20.10.txt): the three cases with project extensions, on Node 20.10 (`mise x node@20.10.0 -- ./reproduce.sh DIR 10-custom-rules-folder-unused 11-custom-policy-ignores-rc 19-custom-artifact-class`). Node 18.20 gives the same result.

## How ng-nudge works

`bin/ng-nudge` reads `.config/ng-nudge/rc.json` from the working directory, builds a `Config`, a `Codebase`, a `DebtFile`, a `ConsoleOutput` and a `VerificationTask`, runs the task, and exits with its exit code (`bin/ng-nudge:63-88`).

- **Configuration** (`lib/config/`): `RcFile` reads the JSON file, or uses `{}` when there is none (`rc-file.js:13-20`). `Config.from` builds four registries: artifact definitions, rule configurations, custom rules and custom policies (`config.js:19-30`).
- **Artifacts** (`lib/artifact/`): for each artifact definition, `Codebase.artifacts` globs its pattern inside `srcDir` and builds one artifact per file (`codebase.js:40-57`). An artifact's base path is the file's path relative to `srcDir` with `.<role>.ts` removed (`artifact.js:33-36`); its name is the last segment of that (`artifact.js:38-40`). Companion files hang off the base path: the spec at `<base>.<role>.spec.ts` (`spec.js:15-21`), and for components the stub at `<base>.component.stub.ts`, the interface at `<base>.component.i.d.ts`, and `<base>.component.css` and `.scss` (`component.artifact.js:27-41`).
- **Policies** (`lib/policy/`): `Codebase` holds four built-in policies, then the project's custom ones (`codebase.js:23-29`). For each artifact, `VerificationTask` asks every policy whether it applies, and collects the violations of each that does (`verification-task.js:41-58`).
- **Rules** (`lib/rule/`): a rule takes an artifact and the config, looks up its configuration by its static `name`, and returns violations from `check()` unless it is disabled (`rule.js:4-47`).
- **Debt** (`lib/debt.js`, `lib/config/debt-file.js`, `lib/policy/has-debt.policy.js`, `lib/rule/has-debt.rule.js`): after the artifact checks, the task finds stale debt entries, runs the `HasDebt` policy against the whole codebase, reports violations the debt file does not excuse, and with `--update-debt` rewrites the debt file (`verification-task.js:17-23, 60-92`).
- **Output** (`lib/console-output.js`): collects passes and violations by artifact name and prints everything in `finish()`.

## The claims in #1

| Claim | Verdict | Where |
|---|---|---|
| There are seven built-in artifacts. | Holds: component, directive, pipe, service, guard, resolver, interceptor. | `lib/artifact/index.js:24-32` |
| An artifact is found by a glob on a role, such as `**/*.component.ts`. | Holds. The pattern defaults to `**/*.<role>.ts`, searched inside `srcDir`. | `lib/config/artifact-definition.js:18, 33`; `lib/codebase.js:45-47` |
| An artifact holds the path of each companion file and whether each exists. | Holds for the paths. Whether a TypeScript companion exists is answered by ts-morph's project, which holds only the files `tsconfig.json` includes (bug 3), and the stylesheet check looks in the wrong folder (bug 1). | `lib/artifact/artifact-file.js:16-18`; `lib/artifact/component.artifact.js:71-77` |
| For a component, the artifact holds the inputs and outputs its class declares. | Holds in part. It collects properties initialized with `input()`, `input.required()` or `output()`, and properties decorated `@Input()` or `@Output()` that also have an initializer. It misses decorated properties with no initializer, setters, `model()`, `outputFromObservable()`, and aliases (bugs 16 and 17). | `lib/artifact/api.js:52-96` |
| Six of the seven built-in artifacts are the same seventeen lines with a different role name, each expecting only a test file. | Holds. Directive, guard, interceptor, pipe, resolver and service are 17 lines each and expect `[Spec]`. | `lib/artifact/directive.artifact.js` and the five like it |
| A project can already declare a new artifact as data: a role, a pattern, and the companion files it expects. | Fails for the companion files. The role and the pattern work. Any `expects` list turns the check off, and the companion paths can't be declared at all: they are fixed by code (bug 4). | `lib/config/artifact-definition.js:24-37`; `lib/artifact/artifact.js:80-82` |
| A policy is about twenty-five lines: which kind of artifact, under what condition, which rules. | Holds. The five policies are 23 to 27 lines. | `lib/policy/*.policy.js` |
| A rule is about a dozen lines: it reads one fact from an artifact and returns a message. | Holds for the six artifact rules (12 to 15 lines, on a 47-line base class). The two "matches" rules return one message per missing member. `HasDebtRule` is 60 lines and reads the debt file, not an artifact. | `lib/rule/*.rule.js`; `lib/rule/rule.js` |
| Only the component artifact reads inside files, to compare a class's inputs and outputs with its stub's and its interface's. | Holds. `ComponentApi` reads the component and the stub, and `InterfaceApi` reads the interface. Nothing else reads a source file. | `lib/artifact/api.js`; `lib/artifact/interface-api.js` |
| That is ts-morph's only real use. | Fails. ts-morph also answers every "does this companion file exist?" for TypeScript files, through a project loaded from `tsconfig.json`, and `Codebase` builds that project for every run, so a project with no `tsconfig.json` can't run ng-nudge at all (case 15). Reading members also calls the type checker (`getType().getText()`, `getBaseClass()`). | `lib/codebase.js:18-21`; `lib/artifact/artifact-file.js:17`; `lib/artifact/api.js:46, 66-68, 94` |
| The comparison is by name; the collected types are not compared. | Holds. Types are stored as the map's values and never read. The comparison runs one way: a stub's or interface's extra members are never reported. The interface comparison doesn't tell inputs from outputs: any property satisfies either. | `lib/artifact/api.js:21-29`; `lib/artifact/interface-api.js:8-14` |
| It follows a class's base classes, which may live in other files. | Holds for the component and the stub: case 13 reports two inputs inherited from a class in another file. It does not follow an interface's `extends` (bug 14). | `lib/artifact/api.js:43-47` |

## Bugs

Each bug below was reproduced by a case under `fixtures/`, unless marked suspected. "Judgment" says why it counts as a bug and not an intended behavior.

### Checks that report wrongly

1. **`prefer-css-over-scss` never fires.** `hasCss` and `hasScss` call `existsSync` on the base path, which is relative to `srcDir`, so Node resolves it against the working directory (`component.artifact.js:71-77`). With the default `srcDir` of `src`, ng-nudge never finds a stylesheet. Case 01: a component with only a `.scss` file passes; the same files with `"srcDir": "."` fail.
2. **Every rule defaults to error.** A rule's `static defaultSeverity` is used only when there is no rule configuration (`rule.js:27-33`), but `RuleRegistry.get` returns `RuleConfig.default()`, with severity `error`, for every rule without an entry in `rc.json` (`rule.registry.js:18-20`, `rule-config.js:20-22`). So `prefer-css-over-scss`, which declares `Severity.Warning` (`prefer-css-over-scss.rule.js:6`) and is listed as a warning in the README, is an error and fails the run. Case 01, second run: `✗ uses SCSS instead of CSS`, exit 1.
3. **A companion file outside `tsconfig.json` counts as missing.** `ArtifactFile.exists` asks the ts-morph project for the file (`artifact-file.js:16-18`), and the project holds only what `tsconfig.json` includes (`codebase.js:18-21`). Case 02: with spec files excluded from `tsconfig.json`, ng-nudge reports `spec file missing` for a spec that is there. Judgment: whether a file exists is a filesystem fact.
4. **`expects` in `rc.json` doesn't work.** The schema describes `expects` as a list of strings (`rc.schema.json`), and `ArtifactDefinition.fromRc` stores those strings (`artifact-definition.js:32-36`), but `HasSpec` asks `expects.includes(Spec)`, comparing against the class (`artifact.js:80-82`, `has-spec.policy.js:12-14`). A string never equals a class, so any `expects` list turns off every check for that artifact. Overriding a built-in artifact's `expects` is ignored, because each built-in's `from` drops the argument (`component.artifact.js:22-25`, `service.artifact.js:13-16` and the others). Case 03.
5. **Debt excuses a different artifact with the same base path.** A debt entry matches on rule name and base path (`debt.js:30-35`), and the base path drops the role (`artifact.js:34`). `foo.component.ts` and `foo.service.ts` share `app/foo/foo`, so the component's `spec-exists` entry excuses the new service's missing spec. Case 04.
6. **Output merges artifacts with the same file name.** `ConsoleOutput` groups by `subject.name`, the base path's last segment (`console-output.js:15-24`, `artifact.js:38-40`). Two `widget` components in different folders print as one `widget`, without the folder, and "Checked 1 artifact(s)" counts them as one. Case 05. A component and a service with the same name in one folder merge the same way (the last run of case 04 prints `✓ foo` for both). On Windows the name is the whole path instead, because the code splits on `/` (`artifact.js:39`).
7. **Debt ignores the message.** Because entries match on rule and base path only, one entry excuses every violation of that rule on that artifact, including ones added later: a third input added to a component with two recorded `stub-matches-component` violations passes. `--update-debt` also writes one identical row per violation (`debt-file.js:70-74`). Case 06. Judgment: the README says ng-nudge "only reports new ones", and a new missing input is a new violation.
8. **`--update-debt` on a project with no `.config/ng-nudge` folder prints only an error.** `DebtFile.update` writes without creating the folder (`debt-file.js:81`), and the exception escapes before `finish()` prints the results (`verification-task.js:17-23`). Case 07.
9. **A `--update-debt` run reports the state from before the update.** The exit code and the report use the debt as it was read at the start (`verification-task.js:25-39`), so the run that removes a stale entry still prints "Run `npx ng-nudge --update-debt` to update debt.tsv" and exits 1, and the run that records new violations prints them as errors and exits 1. Case 08. Judgment: the instruction line is a bug, because the command did what it asks. The exit code is a call a replacement has to make: the help text says only "Run all checks, then update debt.tsv", so exit 1 can be read as the result of the checks. A script that runs `--update-debt` and then goes on sees whichever it chooses.
10. **An empty debt file loses its header.** With no entries, `tsvFormat([])` returns an empty string, so the file becomes a single newline (`debt-file.js:76-81`). Case 08. ng-nudge reads that back as empty, but a person adding a row by hand has no header to follow.
11. **Disabling a rule pays off its debt and fails the run.** A disabled rule returns no violations (`rule.js:39-42`), so its debt entries look stale (`debt.js:45-49`), and stale debt sets exit 1 (`verification-task.js:26`). Case 09. A `--update-debt` run with the rule still disabled then deletes those entries, and the comments on them (case 24). Judgment: turning a check off is not fixing it.
12. **Rules in `.config/ng-nudge/rules/` never run.** The help text says custom extensions go there (`bin/ng-nudge:14-16`). `CustomRuleRegistry` imports them (`custom-rule.registry.js:11-15`), and nothing ever reads `config.customRules` (`config.js:44-46`). Case 10. A project rule runs only if a project policy constructs it. Judgment: the help text says custom rules go there, but the README's recipe adds each rule to a policy, so whether a rule file in this folder is meant to run by itself is unclear. A replacement has to decide what a rule file in that folder does.
13. **`rc.json` can't configure the rules of a project's policies.** `PolicyRegistry` constructs each policy with no arguments (`policy.registry.js:14`), so a policy has no config to pass its rules, and `severity` and `enabled` for those rules are ignored. Case 11: `"severity": "warning"` and `"enabled": false` both leave `readme-exists` an error.
14. **An interface that inherits its members is reported as missing them.** `InterfaceApi` reads only the properties declared in that interface (`interface-api.js:28-31`). Case 12: `CardApi extends Titled` gets `interface missing input: title`.
15. **An interface file with two interfaces stops the whole run.** `InterfaceApi.from` throws (`interface-api.js:20-25`), and `bin/ng-nudge` catches it, prints the message and exits 1 (`bin/ng-nudge:86-88`), so no other artifact is reported. Case 12.
16. **Decorated inputs and outputs with no initializer are invisible.** `#collectProperties` skips any property without an initializer before it looks at decorators (`api.js:58-59, 65-69`), so `@Input() hint: string;` and `@Input() hint!: string;` are never compared. Case 13.
17. **Current Angular member forms are missed or misread.** `model()` (an input and a `<name>Change` output), setter inputs (`@Input() set size(...)`, which `getProperties()` doesn't return), and `outputFromObservable()` are not collected; an aliased input (`input('', { alias: 'caption' })`) is compared by its property name, so a stub with `caption` is reported as missing `label` (`api.js:52-88`). Case 13. Judgment: each one makes the check pass a stub that lacks a public member, or fail one that has it.
18. **A stub with no `@Component` class is not compared.** `ComponentApi.from` returns `null` when no class has the decorator (`api.js:37-38`), and the rule then returns no violations (`stub-matches-component.rule.js:10`). Case 13, second run: an empty stub class passes.

### Configuration, command line and output

19. **A syntax error in `rc.json` ends in a stack trace.** `bin/ng-nudge` reads `rc.json` before its `try` (`bin/ng-nudge:63`). Case 14.
20. **Mistakes in configuration and flags are ignored silently.** Nothing validates `rc.json` against `rc.schema.json`: a misspelled key (`"rule"`), an unknown severity (`"warn"`, which falls back to the default at `rule.js:30-32`), and a `srcDir` that doesn't exist (the run passes with "No artifacts require verification.") all go unreported. Unknown flags (`--quite`) and values (`--warnings=eror`, which acts as `all`, `bin/ng-nudge:66-74`) are ignored too. Case 15. Judgment: each one leaves the user believing a check runs that doesn't.
21. **A warning's heading and its message go to different streams.** Headings are written with `console.log` (`console-output.js:53-56`), and each message with its severity's `log`, which is `console.warn` for warnings (`severity.js:9`). Case 16: with standard error discarded, `⚠ api:` appears with nothing under it.
22. **Debt files don't carry between Windows and other systems.** glob returns paths with `\` on Windows (`codebase.js:45-47` passes no `posix` option), so `--update-debt` there writes `app\api\api`, and a debt file written on macOS or Linux matches nothing: every entry is reported as paid off and every excused violation as new. Case 20 in `transcript-windows.txt`, and cases 09 and 17 there.
23. **Project extensions fail on Node 18 and early Node 20.** `package.json` says Node 18 or later, and extensions must be ES modules ending in `.js` (`extension-directory.js:18-21`). In a project whose `package.json` has no `"type": "module"`, Node 18.20 and 20.10 load them as CommonJS, and the run stops with "Cannot use import statement outside a module" (`transcript-node-20.10.txt`). Node 22.23 and 26 load them.
24. **A project's artifact class is checked only if it shares ng-nudge's copy of `Spec`.** `expectsPiece` compares classes by identity (`artifact.js:80-82`). When the ng-nudge that runs is not the copy the project's extension imports (a global install, a second version, or a copied folder), the project's page artifact expects a different `Spec` and nothing checks it. Case 21, and case 19 on Windows.
25. **The debt file counts as an artifact.** "Checked N artifact(s)" counts every name with a violation (`console-output.js:16, 64`), so `has-debt` violations add one for `debt`. Case 17: three services, "Checked 4 artifact(s)".
26. **`--warnings=error` fails the run on a warning, but `--quiet` then hides it.** The exit code counts every unexcused violation when `failOnWarnings` is set (`verification-task.js:25-29`), but the printer decides what to show from each violation's own severity, so a warning is a `⚠` that fails the run and, with `--quiet`, is not printed at all (`console-output.js:48-50`). Case 22: exit 1 with no output.
27. **A violation built without a rule can't become debt, and breaks every run that has debt.** `Violation.ruleName` comes from the rule (`violation.js:20`). A violation made as the README's and CONTRIBUTING's custom-rule examples make it, from a subject and a message, has none. `--update-debt` then writes an empty rule name, `Debt` refuses it, and the run stops with "Debt entry 1 has an empty or missing rule" and writes nothing (`debt-file.js:70-75`, `debt.js:4-13`). Once the debt file has any entry, every run stops with "Cannot match a violation without a ruleName" (`debt.js:30-35`). Case 23. A rule that extends `Rule` avoids it, because `Rule.violation()` passes the rule.

### Documentation errors, found by reading

28. The README's custom rule imports `../violation.mjs`; the file is `lib/violation.js`. `Violation` and `Severity` are not in `package.json`'s `exports`, so a project's rule can't import either by package name: it has to extend `Rule` and call `this.violation()`, and it can set a default severity only through an exported rule's `defaultSeverity`. The example's rule extends nothing and builds its `Violation` itself, which is bug 27.
29. The README lists neither `HasSpec` nor the `spec-exists` and `interface-matches-component` rules, calls the debt rule `HasDebtRule` where its configuration key is `has-debt`, and lists `PreferCssOverScss` as a warning (bug 2). Its `HasDebt` row says debt entries "must be resolved or documented", which holds only when `withComment` is set. The help text gives exit 1 as "One or more violations detected" and leaves out stale debt.
30. "Updated … debt (N entries)" prints the debt file's path without `.tsv` (`verification-task.js:91`, `debt-file.js:17`).

### Suspected, not reproduced

- **Order may differ between machines.** Artifacts are reported, and new debt rows written, in the order glob walks the folders, which is not sorted: case 17 lists `c`, `b`, `a`, and case 18 lists `plain` before `card`. Both macOS and Windows gave the same order here. `Debt.sorted()` exists and nothing calls it (`debt.js:59-63`). If the order differs on another filesystem, `debt.tsv` changes in diffs with no change in debt.
- **Overlapping patterns check one file twice.** Each definition's glob runs separately (`codebase.js:43-54`), so a role with a pattern that matches another role's files makes a second artifact for the same file.
- **A role name with a regular-expression character breaks its base path.** `Artifact.from` builds a `RegExp` from the role without escaping it (`artifact.js:34`).

### Intended behaviors that look like bugs

These follow the README or the code's evident design. A replacement keeps them unless the maintainer decides otherwise.

- **Debt is silent unless `withComment` is set.** `HasDebt` applies only when `rules.has-debt.withComment` is present (`has-debt.policy.js:12-17`). Without it, excused violations are hidden and the debt is never shown. With it, every entry is reported as a `has-debt` violation, an uncommented one at the base severity (error by default). `withComment: false` and `withComment: "error"` both report every entry as an error, since neither caps anything. Case 17 shows every setting.
- **An artifact whose violations are all excused prints `✓`.**
- **`--update-debt` records warnings as debt too,** since it snapshots every violation.
- **Stub and interface comparison runs one way and by name.**
- **Config errors and violations both exit 1.**

## What a replacement must keep

This is every behavior, option, exit code, configuration key and message a user can rely on. Fixing the bugs above changes some of them; those are marked.

### Installing and running

- Run from the project root; everything is resolved from the working directory.
- The command is `ng-nudge`, installed as an npm dev dependency from GitHub and run with `npx ng-nudge` or from a `package.json` script.
- The project needs `tsconfig.json` (path set by `tsConfig`) and a source folder (`srcDir`, default `src`). The tsconfig requirement is a consequence of bug 3 and of ts-morph; only the Angular checks need it.

### Command line

| Flag | Effect |
|---|---|
| `--warnings=all` | Show warnings (the default). |
| `--warnings=none` | Hide warnings. An artifact whose only violations are warnings prints `✓`. |
| `--warnings=error` | Warnings fail the run. |
| `-q`, `--quiet` | Print only artifacts with errors, no summary. Debt payoff, the instruction line, and "Updated" still print. |
| `-s`, `--silent` | Print nothing; only the exit code. Wins over `--quiet`. Errors that stop the run still print. |
| `-d`, `--update-debt` | Run every check, report, then rewrite the debt file. |
| `-h`, `--help` | Print the help text and exit 0. |

Flags on the command line win over `options` in `rc.json`.

### Exit codes

- `0`: no unexcused violation that fails the run, and no stale debt.
- `1`: an unexcused error; an unexcused warning with `--warnings=error`; any stale debt entry; or any error that stops the run (unreadable configuration, missing `tsconfig.json`, an interface file with several interfaces).

### Configuration: `.config/ng-nudge/rc.json`

Optional; JSON with no comments; described by `rc.schema.json` (`$id` `https://github.com/OverTheTopMarketing/ng-nudge/rc.schema.json`), which ng-nudge never checks it against.

| Key | Meaning |
|---|---|
| `srcDir` | Folder to search, relative to the working directory. Default `src`. Artifact paths and debt keys are relative to it. |
| `tsConfig` | Path to the tsconfig. Default `tsconfig.json`. |
| `artifacts.<role>.pattern` | Glob, relative to `srcDir`, that finds the role's primary files. Default `**/*.<role>.ts`. Overrides a built-in role's pattern, or adds a new role. |
| `artifacts.<role>.expects` | Companion files the role expects. Broken (bug 4); a replacement has to make it work, since #1 counts on it. |
| `rules.<name>.enabled` | `false` turns the rule off. |
| `rules.<name>.severity` | `error` or `warning`. |
| `rules.has-debt.withComment` | `true` or `"warning"`: commented entries become warnings. `"none"`: commented entries are not reported. `"error"` or `false`: no cap. `{ "maxSeverity": "none" \| "warning" \| "error", "matching": "<regex>" }`: the cap applies only to comments the regular expression matches, searched anywhere in the comment. Present at all: turns on `has-debt` reporting. |
| `options.warnings` | Default for `--warnings`: `all`, `none` or `error`. |
| `options.verbosity` | `normal`, `quiet` or `silent`. |

Rule names, used as `rules` keys and in the debt file: `spec-exists`, `stub-exists`, `interface-exists`, `stub-matches-component`, `interface-matches-component`, `prefer-css-over-scss`, `has-debt`. A project rule's name is its static `name`, or its class name.

### Project extensions

- `.config/ng-nudge/artifacts/<role>.artifact.js`: an ES module whose default export, or else first export, is an artifact class. The file name gives the role. It replaces the class of a built-in role of that name, keeping that role's pattern and any `rc.json` pattern, or adds a role with pattern `**/*.<role>.ts` and the class's static `expects` (case 19).
- `.config/ng-nudge/policies/<name>.policy.js`: a class with `applies(artifact)`, `rules(artifact)` and `violations(artifact)`; ng-nudge runs one instance of it on every artifact, after the built-in policies (case 11).
- `.config/ng-nudge/rules/<name>.rule.js`: loaded, not run (bug 12).
- Package exports a project's code can import: `@overthetopmarketing/ng-nudge` (`Codebase`), `/artifacts` (`ArtifactFile`, `Artifact`, `Spec`, `Component`, `ComponentClass`, `Stub`, `Interface`, `Directive`, `Pipe`, `Service`, `Guard`, `Resolver`, `Interceptor`, `ComponentApi`) and `/rules` (`Rule`, `SpecExists`, `StubExists`, `InterfaceExists`, `StubMatchesComponent`, `PreferCssOverScss`).
- What an extension can use on an artifact: `name`, `role`, `basePath`, `primaryPath`, `primary`, `spec`, `hasSpec`, `expects`, `expectsPiece()`, `project` (the ts-morph project), and for a component `stubPath`, `interfacePath`, `cssPath`, `scssPath`, `class`, `stub`, `interface` (each with `path`, `exists`, and `api` for the TypeScript ones), `hasCss`, `hasScss`. On a rule: `artifact`, `severity`, `violation(message)`, `violations`, `check()`.

### Artifacts

- Seven roles, each found by `**/*.<role>.ts` inside `srcDir`: `component`, `directive`, `pipe`, `service`, `guard`, `resolver`, `interceptor`.
- Every role expects a spec at `<base>.<role>.spec.ts`.
- A component also has a stub `<base>.component.stub.ts`, an interface `<base>.component.i.d.ts`, and stylesheets `<base>.component.css` and `.scss`.
- A component's inputs and outputs: from the first class in the file with a `@Component` decorator, its properties initialized with `input(...)` or `input.<anything>(...)` (inputs), `output(...)` (outputs), or decorated `@Input()` or `@Output()`; following `extends` through every base class, in any file the TypeScript program resolves; a subclass's member hides a base member of the same name; `#private` members skipped. The stub is read the same way. A replacement must also collect what bugs 16 and 17 miss.
- An interface's members: the property names of the one interface in the file.

### Policies and rules

| Policy | Applies to | Runs |
|---|---|---|
| `HasSpec` | every artifact whose role expects a spec | `spec-exists` |
| `HasInterface` | a component whose interface file exists | `stub-exists`, `interface-matches-component` |
| `HasStub` | a component whose stub file exists | `interface-exists`, `stub-matches-component` |
| `HasStyles` | every component | `prefer-css-over-scss` |
| `HasDebt` | the codebase, when the debt file has entries and `has-debt` has `withComment` and isn't disabled | `has-debt` |

| Rule | Fails when | Message | Default |
|---|---|---|---|
| `spec-exists` | the spec doesn't exist | `spec file missing` | error |
| `stub-exists` | the stub doesn't exist | `stub file missing` | error |
| `interface-exists` | the interface doesn't exist | `interface file missing` | error |
| `stub-matches-component` | a component input or output is missing from the stub; one violation each | `stub missing input: <name>`, `stub missing output: <name>` | error |
| `interface-matches-component` | a component input or output is missing from the interface; one violation each | `interface missing input: <name>`, `interface missing output: <name>` | error |
| `prefer-css-over-scss` | the `.scss` exists and the `.css` doesn't | `uses SCSS instead of CSS` | warning, as declared and documented (error in practice, bug 2) |
| `has-debt` | one violation per debt entry | `<rule>⇥<artifact>`, or `<rule>⇥<artifact>⇥<comment>` | error, capped by `withComment` |

An artifact is listed in the output if at least one policy applies to it; otherwise it is not mentioned. A disabled rule still lets its policy apply.

### Debt tracking

- The file is `.config/ng-nudge/debt.tsv`. A missing file means no debt.
- Tab-separated, header row `Rule`, `Artifact`, `Comment`, quoted the way d3-dsv quotes (a field holding a tab, newline or `"` is wrapped in `"` with `"` doubled). The file ends with a newline.
- `Rule` is the rule's name; `Artifact` is the base path relative to `srcDir` with the role suffix removed (`app/foo/foo`); `Comment` is the user's, kept across updates.
- A row with an empty `Rule` or `Artifact` stops the run with `<path>.tsv row <N>: Rule column is empty or missing` (or `Artifact column`), counting the header as row 1.
- A violation matching an entry's rule and artifact is excused: not printed and not failing. (Matching on base path alone is bugs 5 and 7.)
- An entry no violation matches is stale: printed under `★  Debt paid off:` as `   <artifact> no longer owes <rule>`, followed by "Run `npx ng-nudge --update-debt` to update debt.tsv", and the run exits 1.
- `--update-debt` keeps every entry that still matches, with its comment and in its place; drops stale entries; appends one row per unexcused violation, warnings included, with an empty comment; and prints `Updated <path> (<N> entries)`.
- The `has-debt` rule and `withComment`, described under configuration, let a team require a comment on every entry, or let commented entries through as warnings or not at all.

### Output

```
✓ <name>
✗ <name>:
   ✗ <message>
⚠ <name>:
   ⚠ <message>

Checked <N> artifact(s).
```

- `✗` heads an artifact with at least one error, `⚠` one with only warnings, `✓` one with none.
- Artifacts appear in discovery order: roles in the order component, directive, pipe, service, guard, resolver, interceptor, then `rc.json` roles, then extension roles, and within a role in glob order. Debt violations come last, under `debt`.
- With no listed artifacts the summary is `No artifacts require verification.`
- An error that stops the run prints its message alone, with no stack trace (except bug 19).
- The help text is the comment at the top of `bin/ng-nudge`.

## Where the engine, Angular and debt are tangled

| Where | Tangle |
|---|---|
| `lib/codebase.js:1, 18-21` | The engine imports ts-morph and builds a TypeScript project from `tsconfig.json` on every run, whatever the checks. |
| `lib/codebase.js:6-9, 23-29` | The engine hard-codes the four Angular policies. |
| `lib/config/registry/artifact.registry.js:2, 16-18` | Configuration loading seeds the seven Angular roles. |
| `lib/artifact/artifact-file.js:16-18`; `lib/artifact/project-view.js` | Whether any companion file exists is answered by the TypeScript project. |
| `lib/artifact/artifact.js:4-12, 33-36, 58-60`; `lib/artifact/spec.js:15-21`; `lib/config/artifact-definition.js:18, 33-35` | The generic `Artifact` assumes `.ts` primary files, `<base>.<role>.ts` naming and a `.spec.ts` companion. |
| `lib/policy/has-*.policy.js:13` | The Angular policies test `instanceof Component`. That belongs in an Angular plugin, and is fine there. |
| `lib/config/debt-file.js:5, 51-53` | The configuration module imports the debt policy. |
| `lib/verification-task.js:7, 25-39, 60-76, 88-92` | The run loop holds the debt file, filters with it, finds stale entries, runs the debt policy, decides the exit code with it, and writes it. |
| `bin/ng-nudge:46, 75, 79, 84` | The command line builds the debt file and owns `--update-debt`. |
| `lib/console-output.js:6-8, 27-37, 72-85` | The printer has debt-only methods, and the literal "Run `npx ng-nudge --update-debt`". |
| `lib/config/rule-config.js:4, 32`; `rc.schema.json` | Every rule's configuration carries `withComment`, which only `has-debt` reads. |
| `lib/debt.js:24, 34`; `lib/violation.js:20` | Debt identity is the violation's rule class name and its subject's `basePath`, so every subject must look like an Angular-style artifact, and the debt file is itself made a violation's subject. |
| `lib/config/rc-file.js:14, 35` | The folder name `.config/ng-nudge` and the `tsConfig` key are fixed in the generic loader. |

What it would take to separate them:

- **Engine:** configuration loading; artifact definitions as a role, a pattern and companion path templates; existence from the filesystem; the policy and rule loop; severity and per-rule configuration; the printer; the exit code. No ts-morph, no roles, and no policies.
- **A stable violation identity** for the engine to give every plugin: rule name, artifact key with its role, and a detail such as the member name. Debt can then match without knowing what an artifact is (bugs 5 and 7).
- **Hooks for a debt plugin:** filter the violations before reporting, add its violations after the artifact checks, add to the exit code, add a command-line flag (`--update-debt`), add configuration keys under its rule, and print its lines. With those, `Debt`, `DebtFile`, `HasDebt`, `HasDebtRule` and the payoff output all move out of the engine.
- **An Angular plugin** with the seven roles, the component's companion paths, `ComponentApi`, `InterfaceApi`, the four policies and the five Angular rules, which loads a TypeScript parser only when one of its checks reads a file.
- **Plugins give their artifacts, policies and rules to the engine**, which runs them with configuration (bug 13 is the engine skipping that step).

## What would be hard to carry over into another language

- **Project extensions are JavaScript.** They are ES modules that subclass ng-nudge's classes and call its methods, loaded with `import()` (`extension-directory.js:23-33`). A tool in another language can't load them without running Node. Of the extension points, artifacts are mostly data (case 19's `Page` is an empty subclass) and can become configuration; policies and rules are code.
- **Reading TypeScript semantically.** Following a base class into another file goes through the TypeScript program (`getBaseClass()`), which resolves imports, `tsconfig.json` `paths`, re-exports and `extends` chains in tsconfig files. A syntax-only parser has to resolve those itself. The types ng-nudge collects are never compared, so nothing else needs the type checker.
- **Glob semantics.** Patterns in `rc.json` are node-glob 11 patterns: dotfiles skipped, `**`, braces, extglobs, and a walk order that isn't sorted. Another language's glob differs in each of these, so a pattern can match different files.
- **A regular expression in configuration.** `withComment.matching` is a JavaScript regular expression, tested with `RegExp.test` (`has-debt.rule.js:44-46`). Other languages' syntax and flags differ, for example in lookbehind and Unicode classes.
- **The TSV dialect.** `debt.tsv` is read and written by d3-dsv. Another language's TSV library must parse and write the same quoting, the header, and the final newline, byte for byte, or a team's committed debt file changes on its first update.
- **Rule names as identifiers.** Each rule's name is a static property on its JavaScript class (`rule.js:5`, `violation.js:20`), and a project rule without one falls back to its class name. The names are keys in `rc.json` and in committed debt files, so they must stay exactly as they are.
- **Paths.** Debt keys must use `/` on every system (bug 22), relative to `srcDir`.
- **Output characters.** `✓ ✗ ⚠ ★` are UTF-8; a Windows console with another code page shows them garbled unless the tool sets its output encoding.
- **How it's installed and called.** Projects call `npx ng-nudge` from `package.json` scripts and CI, and npm installs it with the project's other packages. A tool installed another way changes those calls and the CI setup.

Nothing in configuration loading, the run loop or the command line is hard to carry over: they are about 700 lines of ordinary file reading, looping and printing.

## Migrating from ng-nudge in 30 minutes or less

| Piece | What the project changes |
|---|---|
| Installation | Replace the dev dependency with the replacement's install step, and `npx ng-nudge` in `package.json` scripts and CI with its command. Nothing more if it keeps the flags and exit codes above. |
| `rc.json` | Nothing, if the replacement reads `.config/ng-nudge/rc.json` and its keys. Otherwise one move and a rename of keys, which a conversion command could do. Enabling the Angular and debt plugins is one line each, or none if they are on by default. |
| `debt.tsv` | Nothing, if the replacement reads the same format, rule names and artifact keys. Fixing bugs 5 and 7 means a key with the role and a detail; a one-time conversion can rewrite each entry from the current violations, but an entry that two artifacts share (bug 5) can't be assigned to one of them, so the conversion has to keep it on both or ask. |
| New violations | Fixing bugs 1, 3, 14, 16 and 17 makes checks find violations ng-nudge hid, and fixing bug 2 turns `prefer-css-over-scss` into a warning. One `--update-debt` run takes those violations in as debt, so the first run passes. |
| Project artifacts | An artifact class that only sets a role and its companions becomes a few lines of configuration. |
| Project policies and rules | Rewritten in the replacement's form: a policy is about 25 lines and a rule about 12, so a few take minutes each. A project with many has more than 30 minutes of work, unless the replacement can run JavaScript extensions. |
| Windows teams | A debt file written on Windows has `\` in its keys (bug 22) and needs them changed to `/` once. |
