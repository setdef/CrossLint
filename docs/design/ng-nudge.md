# Replacing ng-nudge

What CrossLint must keep from [ng-nudge](https://github.com/OverTheTopMarketing/ng-nudge) 0.3.0, and the defects in it that CrossLint must not copy. File and line references are to ng-nudge at commit [`10a7224`](https://github.com/OverTheTopMarketing/ng-nudge/tree/10a722456daacca08f6425c5b74e5586183c654b). How a project moves is in [the README](../../README.md#moving-from-ng-nudge); how to meet each requirement is the implementer's choice.

## What must carry over

- **A project moves in 30 minutes or less.** `crosslint init --from-ng-nudge` carries every key of `.config/ng-nudge/rc.json` into `.config/crosslint/config.kdl`, and moves the debt file with every entry and comment. A key it can't carry stops it before it changes anything, naming the key.
- **Every check.** The Angular plugin finds the seven roles ng-nudge finds (`component`, `directive`, `pipe`, `service`, `guard`, `resolver`, `interceptor`) by the same patterns inside `src-dir`, and its policies keep ng-nudge's rule names, since projects' configurations and debt files hold them: `spec-exists`, `stub-exists`, `interface-exists`, `stub-matches-component`, `interface-matches-component`, `prefer-css-over-scss`.
- **The conditions.** A stub and an interface are optional: a missing one is reported only when the other exists. A component is checked against its stub and its interface by member name, one way: extra members in the stub or the interface aren't reported, and types aren't compared.
- **Every setting.** Each `rc.json` key keeps its meaning: `srcDir`, `tsConfig`, `artifacts.<role>.pattern` and `expects`, `rules.<name>.enabled` and `severity`, `rules.has-debt.withComment` in all five of its forms, `options.warnings`, and `options.verbosity`.
- **Patterns mean what they meant.** Globs in `rc.json` are node-glob 11 patterns (dotfiles skipped, `**`, braces, extglobs), and `withComment.matching` is a JavaScript regular expression tested anywhere in the comment. Conversion turns each into the form CrossLint uses with the same matches; one it can't reproduce exactly is refused with the pattern named, never approximated.
- **The facts in the report.** Which artifacts have errors and which only warnings, each violation's message, which debt entries are stale, what an update wrote, and how many artifacts were checked. The layout is free to change.
- **Debt silent by default.** ng-nudge reports debt entries only when `has-debt` has `withComment` (`lib/policy/has-debt.policy.js:12-17`); the converted configuration reports them only when `rc.json` did.

## Defects not to copy

- **Existence from the filesystem, not from TypeScript.** ng-nudge asks its ts-morph project whether a companion exists, and that project holds only what `tsconfig.json` includes, so an excluded spec counts as missing (`lib/artifact/artifact-file.js:16-18`).
- **Stylesheets beside the component.** ng-nudge looks for them relative to the working directory instead of `srcDir`, so `prefer-css-over-scss` never fires (`lib/artifact/component.artifact.js:71-77`). Fixing this finds violations ng-nudge hid, which is why moving ends with one `crosslint debt update`.
- **A rule's declared severity.** ng-nudge gives every rule with no `rc.json` entry `error`, so its warning rule fails the run (`lib/config/registry/rule.registry.js:18-20`).
- **`expects` that works.** In ng-nudge any `expects` list turns a role's checks off, because strings are compared with a class (`lib/artifact/artifact.js:80-82`).
- **Every input and output form.** ng-nudge skips a decorated property with no initializer, setters, `model()`, `outputFromObservable()`, and aliases (`lib/artifact/api.js:52-88`), and doesn't follow an interface's `extends` (`lib/artifact/interface-api.js:28-31`).
- **One artifact per path and role.** ng-nudge groups the report by the last segment of the base path, so two `widget` components in different folders, or a component and a service with one base path, print and count as one (`lib/console-output.js:15-24`).
- **A role's spec beside its file, whatever its pattern.** ng-nudge takes a primary file's base path by removing `.ROLE.ts` from its end, and builds the primary path back as base plus `.ROLE.ts` (`lib/artifact/artifact.js:34`, `lib/artifact/artifact.js:58-59`). A role whose pattern doesn't end in `.ROLE.ts`, such as a `store` role found by `*.state.ts`, keeps the whole file name as its base, so ng-nudge looks for the spec of `a.state.ts` at `a.state.ts.store.spec.ts` and reports a spec missing that exists.
- **A file with two interfaces is a violation,** not an exception that stops every check (`lib/artifact/interface-api.js:20-25`).
- **A stub with no `@Component` class is a violation,** not a silent pass (`lib/artifact/api.js:37-38`).
- **Project rules that run.** ng-nudge loads the rules in `.config/ng-nudge/rules/` and never runs them, and ignores `severity` and `enabled` for a project policy's rules (`lib/config/registry/policy.registry.js:14`).
- **No silent mistakes.** ng-nudge never checks `rc.json` against its schema, ignores unknown flags and `--warnings error`, and treats an unknown `--warnings` value as `all` (`bin/ng-nudge:66-75`).
- **No stack trace for a configuration error,** a syntax error in `rc.json` included (`bin/ng-nudge:63`).
- **A heading and its messages on one stream.** ng-nudge writes a warning's heading to standard output and its message to standard error (`lib/console-output.js:52-58`).
- **`--quiet` prints what fails.** Under `--warnings=error`, ng-nudge's `--quiet` hides the warning that failed the run (`lib/console-output.js:48-50`).

The debt defects are in [Debt](debt.md#defects-not-to-copy).
