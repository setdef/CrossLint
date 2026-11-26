# Checking

What `crosslint check` must guarantee, and the traps known so far. Its interface is [`crosslint.usage.kdl`](../../crosslint.usage.kdl); this page covers what the interface can't say. How to meet each requirement is the implementer's choice.

## Finding the project and its files

- The project's root is the nearest folder, from the current one or `-C`'s upward, that has `.config/crosslint.kdl`. With none, stop with exit status 2 and say how to write one; never guess.
- **Files come from the working tree, minus what Git ignores.** A file Git ignores never matches a pattern, and neither does anything under `.git/`. Whether a companion exists is asked of the filesystem, never of another tool's idea of the project, such as the files a `tsconfig.json` includes.
- **A pattern is matched case-sensitively, with `/` on every system,** and reported paths use `/` too, so output and debt keys agree between macOS, Linux, and Windows. macOS and Windows filesystems ignore case, so check a companion's existence by its exact name, not by asking whether a path exists.
- **Each file is a primary file of each artifact whose pattern matches it, once,** however many ways the pattern could match it.
- A pattern that matches no file is a warning, since it usually has a typo.

## Running plugins

- Read and check every plugin the configuration lists before checking any file. A mistake in a configuration or a `plugin.kdl` stops CrossLint with exit status 2, naming the file, the line, and the nearest valid spelling. A line CrossLint doesn't understand is never skipped, because a skipped rule is a check that never runs.
- A rule runs only on an artifact a policy applies it to. A rule no policy runs is reported, never loaded and ignored.
- **Every violation has its plugin and policy, its artifact with the artifact's role, a message, and a severity,** and a detail where one artifact can have several, such as a missing member's name. A violation without them is a fault in its plugin, reported as such, since debt can't record it.
- A check reads files and writes none. Only `--update-debt`, `init`, and `update` write, and each says which files it wrote.

## Output and exit status

- Findings go to standard output, one per line: the path, the message, and the plugin and policy. Everything CrossLint says about itself goes to standard error, each line beginning with `crosslint:`, so a script reading findings never reads a summary or a warning.
- An artifact's findings are written together, in an order that doesn't depend on the order the filesystem lists files in.
- Print a line within 100 ms on a terminal, before reading any TypeScript, so a large project never sits silent.
- `--quiet` prints everything that fails the check, a warning under `--warnings=error` included, and drops the summary; `--silent` prints only errors that stop CrossLint.
- Output is ASCII. Color is used only for severity, only on a terminal, and never when `NO_COLOR` is set to a value that isn't empty, `TERM` is `dumb`, or `--no-color` is given; `FORCE_COLOR` turns it on even off a terminal.
- Exit 0 when the check passes, 1 when a violation fails it or an entry is stale, 2 when CrossLint can't check, and 130 on Ctrl-C. An expected error, such as a missing file or a bad configuration, prints a message with the fix and no stack trace; an unexpected one says it is a bug in CrossLint and where to report it, and `--debug` shows the trace.
- On Ctrl-C, stop at once. Nothing a check writes needs cleaning up.
