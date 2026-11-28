# Debt

How the debt plugin keeps a project's debt, and why each is done the way it is. The debt file's format and settings are in [the configuration reference](../reference/configuration.md#debt).

## The file

- **The format is ng-nudge's, read and written byte for byte,** so a debt file moved from ng-nudge reads unchanged, and an entry CrossLint keeps is written back exactly as it was read, quoting included. A diff after an update then shows only real changes, which is what a reviewer reads the debt file for.
- **Paths use `/` on every system,** and line endings stay as the file had them, so one debt file, committed from any computer, matches on macOS, Linux, and Windows.
- **The file is replaced whole,** through a temporary file with a name of its own beside it, renamed into place, so an interrupted update leaves the previous file.

## Matching

- **A violation's identity is its plugin and policy, its artifact with the artifact's role, and its detail,** such as a missing member's name. An entry matches one violation with the same identity, so fixing one of an artifact's violations shows as one paid-off entry, not as the artifact's whole entry.
- **An entry may hold its artifact's name or its key.** An artifact's name is its primary piece's path unless its declaration has a `name`, and the key is a second name a helper's declaration can give, such as ng-nudge's base path for an Angular artifact, so entries ng-nudge wrote match without being rewritten.
- **An entry with no detail still matches coarsely, once, where a rule gave none before.** ng-nudge wrote one entry per rule and artifact, with no detail, and CrossLint's own update wrote one for all of an artifact's violations of a policy's built-in rules, which gave no detail until they gave the name of the piece each checks. Such an entry matches every violation of its policy on its artifact, with a warning, until the next update rewrites it as one entry per violation, so moving from ng-nudge, or from a CrossLint that wrote no detail, adds no failures, and the coarse matching ends after one update.
- **Which entries match coarsely depends on who reported the violation.** An entry that names only a policy, as ng-nudge's do, matches every detail of every violation of that policy. An entry that names its plugin and policy matches every detail only of a violation a built-in rule reported, which the core marks where it makes the violation, and only when no entry has that violation's detail, so the entry left for a helper's violation with no detail doesn't excuse the built-in rules' violations an update wrote entries for. A violation a helper's rule reported keeps exact matching, so an entry written for a helper's violation with no detail can't excuse the same rule's violations that have one.
- **An entry for a disabled policy, or for a plugin the configuration doesn't list, is left alone:** the check doesn't count it as paid off, which would fail the check, and the debt plugin's `report-entries` setting doesn't report it. An update keeps it with its comment. ng-nudge took such entries for paid-off ones and deleted them with their comments, so turning a rule off for a week lost the reasons written down for it.
- **Matching sees every violation,** whatever `--warnings` or `--quiet` hides, so a hidden warning can't look like a fixed one.

## Updating

- **An update changes only what changed:** an entry that still matches keeps its place and its comment, so the comments people wrote survive every update.
- **A dry run lists exactly what an update would write,** so it can be read before it is trusted.

## Defects not to copy

From ng-nudge 0.3.0 at [`10a7224`](https://github.com/OverTheTopMarketing/ng-nudge/tree/10a722456daacca08f6425c5b74e5586183c654b):

- **Matching by rule and base path alone.** ng-nudge's base path drops the role, so a component's entry excuses a service's violation with the same base path, and one entry excuses every later violation of its rule on its artifact (`lib/debt.js:30-35`). `--update-debt` then writes one identical entry per violation (`lib/config/debt-file.js:70-74`).
- **Disabling a rule looks like paying off its debt.** A disabled rule returns no violations, so its entries look paid off, fail the run, and are deleted with their comments by the next update (`lib/rule/rule.js:39-42`, `lib/debt.js:45-49`).
- **The report shows the state before the update,** so a run that just removed a paid-off entry still says to run `--update-debt` (`lib/verification-task.js:25-39`).
- **An update with no folder fails** before anything is reported (`lib/config/debt-file.js:81`).
- **An empty file loses its header,** and becomes a single newline (`lib/config/debt-file.js:76-81`).
- **Keys with `\` on Windows,** from glob's paths, which match nothing elsewhere (`lib/codebase.js:45-47`).
- **A violation with no rule name,** which ng-nudge's README makes in its custom-rule example, writes an empty rule and stops every later run (`lib/violation.js:20`, `lib/debt.js:4-13`).
- **The debt file counted as an artifact** in "Checked N artifact(s)" (`lib/console-output.js:16`).
