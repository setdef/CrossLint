# Checking

How `crosslint check` finds a project's files, runs its plugins, and reports, and why each is done the way it is. What it does for users is in [the README](../../README.md) and [the command reference](../reference/cli.md); what it does exactly is in its tests.

## Finding the project and its files

- **The project's root is the folder that holds `.config/crosslint/config.kdl`,** found by looking upward. CrossLint never guesses a root from anything else, since a guess would check the wrong folder without saying so.
- **Files come from Git's view of the working tree, but existence comes from the filesystem.** Git's listing gives the files a pattern may match, so ignored files and `.git/` never match. Whether a piece exists is asked of the filesystem, and never of another tool's idea of the project, such as the files a `tsconfig.json` includes: ng-nudge asked TypeScript, and an excluded spec counted as missing.
- **Git runs with none of CrossLint's `GIT_*` variables.** Inside a Git hook, Git sets `GIT_DIR`, `GIT_INDEX_FILE`, and others, and a Git command that inherits them reads that repository instead of the project, as when a pre-push hook in a linked worktree runs `crosslint check`. Windows ignores case in environment names, so the variables go whatever their case. The same holds for the Git that fetches shared plugins.
- **Paths are matched case-sensitively, with `/` on every system,** so output and debt keys are the same on macOS, Linux, and Windows. macOS and Windows filesystems ignore case, which is the trap: asking whether `card.Spec.ts` exists there says yes for `card.spec.ts`. A piece's existence is therefore checked by its exact name in the folder's listing.

## Running plugins

- **Every plugin is read and checked before any file is.** A line CrossLint doesn't understand is a mistake, never skipped, because a skipped rule is a check that never runs and nobody notices.
- **A violation carries its identity:** its plugin and policy, its artifact with the artifact's role, and a detail where one artifact can fail a rule in several ways. Debt matches by that identity, so a violation without it is a fault in its plugin rather than something debt can't record.
- **A check writes nothing.** Only the commands whose job is to write, `init`, `update`, and a plugin's command such as `crosslint debt update`, write, so a check can run anywhere, a read-only checkout included.

## Output

- **Findings go to standard output, and everything CrossLint says about itself to standard error,** so a script reading findings never reads a summary or a warning.
- **The order of findings never depends on the order the filesystem lists files in,** or the output and the debt file would change from one computer to another.
- **On a terminal, a first line comes before CrossLint reads any project file beyond its configuration, and before any helper starts,** so the wait for it never grows with the project. A fixed time from the moment the process starts can't be met: the app's launcher and its Ruby take about 70 ms on Linux and over 200 ms on Windows and macOS before any of CrossLint's code runs (#13).
- **The words CrossLint writes are ASCII, and what it takes from the project prints as it is, in UTF-8.** Writing `lib/café.rb` as `lib/caf?.rb` would leave a path no editor opens and no debt entry matches.
- **A check leaves nothing to clean up,** so Ctrl-C stops it at once.
