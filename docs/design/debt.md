# Debt

What the debt plugin must guarantee, and the traps known so far. The file's settings are in [the configuration reference](../reference/configuration.md#debt); how to meet each requirement is the implementer's choice.

## The file

- **ng-nudge's format, read and written byte for byte.** Tab-separated, with a header row `Rule`, `Artifact`, `Comment`, and `Detail` as an optional fourth column, which ng-nudge ignores. A field with a tab, a newline, a carriage return, or `"` is wrapped in `"` with each `"` doubled, as d3-dsv writes it; the file ends with a newline. A row CrossLint keeps is written back exactly as it was read, quoting included, so a diff after an update shows only real changes.
- **Read CRLF line endings, and write what the file had.** A debt file committed on Windows can have them.
- **Keys use `/` on every system.** A key read with `\` is read as `/`, and every key is written with `/`, so one debt file matches on macOS, Linux, and Windows.
- **Replace the file whole.** Write to a temporary file beside it and rename it into place, so an interrupted update leaves the previous file. Create the folder when it doesn't exist.
- **An empty file keeps its header.**
- **A row with no rule or no artifact** stops CrossLint with exit status 2, naming the file and the line.

## Matching

- **A violation's identity is its plugin and policy, its artifact with the artifact's role, and its detail,** such as a member's name. An entry matches one violation with the same identity. The `Artifact` column holds the base path, as ng-nudge writes it, or `<base>.<role>`; CrossLint reads both. The `Rule` column holds `PLUGIN/POLICY`, or a bare name, as ng-nudge writes it, which stands for the policy of that name when exactly one listed plugin has one.
- **An entry with no detail matches only a violation with no detail.** Except: an entry written by ng-nudge, for a policy whose violations carry a detail, matches every violation of that policy on its artifact, with a warning naming the entry, until `--update-debt` rewrites it as one entry per violation, each with its detail. Moving from ng-nudge then adds no failures, and the coarse matching ends after one update.
- **An entry two artifacts match** excuses both, with a warning naming both, and `--update-debt` rewrites it as one entry per artifact, keyed `<base>.<role>`.
- **An entry for a disabled policy, or for a plugin the configuration doesn't list, is not checked:** neither stale nor reported, and `--update-debt` keeps it with its comment.
- **Excusing, stale detection, and `--update-debt` see every violation,** whatever `--warnings` or `--quiet` hides.

## Updating

- `--update-debt` keeps each entry that still matches, with its comment, in its place; drops stale entries; adds one entry per new violation, warnings included, with an empty comment, never a duplicate; and never records the debt plugin's `has-debt` violations.
- New entries are written in an order that doesn't depend on the order the filesystem lists files in.
- After an update, report the state the update left, and exit with 0.

## Defects not to copy

From ng-nudge 0.3.0 at [`10a7224`](https://github.com/OverTheTopMarketing/ng-nudge/tree/10a722456daacca08f6425c5b74e5586183c654b):

- **Matching by rule and base path alone.** ng-nudge's base path drops the role, so a component's entry excuses a service's violation with the same base path, and one entry excuses every later violation of its rule on its artifact (`lib/debt.js:30-35`). `--update-debt` then writes one identical row per violation (`lib/config/debt-file.js:70-74`).
- **Disabling a rule pays off its debt.** A disabled rule returns no violations, so its entries look stale, fail the run, and are deleted with their comments by the next update (`lib/rule/rule.js:39-42`, `lib/debt.js:45-49`).
- **The report shows the state before the update,** so a run that just removed a stale entry still says to run `--update-debt` (`lib/verification-task.js:25-39`).
- **An update with no folder fails** before anything is reported (`lib/config/debt-file.js:81`).
- **An empty file loses its header,** and becomes a single newline (`lib/config/debt-file.js:76-81`).
- **Keys with `\` on Windows,** from glob's paths, which match nothing elsewhere (`lib/codebase.js:45-47`).
- **A violation with no rule name,** which ng-nudge's README makes in its custom-rule example, writes an empty rule and stops every later run (`lib/violation.js:20`, `lib/debt.js:4-13`).
- **The debt file counted as an artifact** in "Checked N artifact(s)" (`lib/console-output.js:16`).
