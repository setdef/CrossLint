# Checking

How `crosslint check` finds a project's files, runs its plugins, and reports, and why each is done the way it is. What it does for users is in [the README](../../README.md) and [the command reference](../reference/cli.md); what it does exactly is in its tests.

## Finding the project and its files

- **The project's root is the folder that holds `.config/crosslint/config.kdl`,** found by looking upward. CrossLint never guesses a root from anything else, since a guess would check the wrong folder without saying so.
- **Files come from Git's view of the working tree, but existence comes from the filesystem.** Git's listing gives the files a pattern may match, so ignored files and `.git/` never match. Whether a piece exists is asked of the filesystem, and never of another tool's idea of the project, such as the files a `tsconfig.json` includes: ng-nudge asked TypeScript, and an excluded spec counted as missing.
- **Git runs with none of CrossLint's `GIT_*` variables.** Inside a Git hook, Git sets `GIT_DIR`, `GIT_INDEX_FILE`, and others, and a Git command that inherits them reads that repository instead of the project, as when a pre-push hook in a linked worktree runs `crosslint check`. Windows ignores case in environment names, so the variables go whatever their case. The same holds for the Git that fetches shared plugins.
- **Paths are matched case-sensitively, with `/` on every system,** so output and debt entries are the same on macOS, Linux, and Windows. macOS and Windows filesystems ignore case, which is the trap: asking whether `card.Spec.ts` exists there says yes for `card.spec.ts`. A piece's existence is therefore checked by its exact name in the folder's listing.

## Regexes

- **A regex is in Ruby's dialect, and CrossLint refuses what PCRE or JavaScript would read another way.** Ruby's Regexp runs it in CrossLint's process, so no project needs another runtime, and a pattern behaves the same wherever CrossLint runs. Plugin authors bring the habits of the dialects most tools share, though, and Ruby reads some of their constructs another way without an error: `(?m)`, `\h`, an escape of a letter Ruby doesn't know, which it reads as the letter. A refusal costs the author one edit, where CrossLint would otherwise check something other than what they wrote, without a word. CrossLint reads a source left to right, an escape with the character after it, so `\(?m` or `\{` is never taken for what it would be without the backslash. What no other spelling can say, such as `^` matching at each line, is read as Ruby reads it, and the plugin reference says so.
- **Every match of a primary's regex is an artifact, named by what it captured.** A route is a line of `config/routes.rb`, not the file, and a violation's identity is its artifact's name, so two matches with one name are a fault: one debt entry would excuse both, and a check would pass for an artifact nobody looked at.
- **A capture that a piece or the name uses and that matched nothing is a fault,** for the same reason: `def {action}\b` with an empty action matches any method, so `piece-exists` would pass without having found the action.
- **A capture can't take a piece out of the project.** Its value is the project's text, so a piece path in which it puts a `.`, `..`, or empty segment is no file of the project, and CrossLint never looks for it.
- **A placeholder's value goes in as literal text,** escaped, so a method named `show.all` matches only itself, and text from the project can't change what a regex means.
- **Every line ending reads as `\n` before a search,** and a leading byte order mark is dropped, so `^`, `$`, and `.` match the same on a checkout with CRLF, as Git makes on Windows with `core.autocrlf`, and on one with LF.
- **A file that isn't UTF-8 is a fault, not a file with no match.** Replacing its bad bytes would let `piece-absent` pass on a file whose match the regex couldn't see, a pass the check didn't earn.
- **Each search has a time limit, and running past it is a fault.** Ruby 3.2 and later run most patterns in linear time, but a backreference can still backtrack exponentially, and a check that hangs is worse than one that stops and says why. The limit is per search for the next match, as Ruby's Regexp timeout is, so a file with many matches never runs out of time while no one search runs past it.
- **A piece with a regex whose file can't be read has no match,** whether no file is there or the path is a folder or a link out of the project, and its message says it isn't a file, so a missing file and a file without a match read differently.

## Running plugins

- **Every plugin is read and checked before any file is.** A line CrossLint doesn't understand is a mistake, never skipped, because a skipped rule is a check that never runs and nobody notices.
- **A violation carries its identity:** its plugin and policy, its artifact with the artifact's role, and a detail where one artifact can fail a rule in several ways. Debt matches by that identity, so a violation without it is a fault in its plugin rather than something debt can't record.
- **A check writes nothing.** Only the commands whose job is to write, `init`, `update`, and a plugin's command such as `crosslint debt update`, write, so a check can run anywhere, a read-only checkout included.

## Output

- **Findings go to standard output, and everything CrossLint says about itself to standard error,** so a script reading findings never reads a summary or a warning.
- **The JSON object's first key is the version of the CrossLint that wrote it, and there is no format number beside it.** CrossLint's versions follow Semantic Versioning, so its major version already says which form of the object a script reads, and a second number would be one more thing for a script's author to compare (#47).
- **The order of findings never depends on the order the filesystem lists files in,** or the output and the debt file would change from one computer to another.
- **On a terminal, a first line comes before CrossLint reads any project file beyond its configuration, and before any helper starts,** so the wait for it never grows with the project. A fixed time from the moment the process starts can't be met: the app's launcher and its Ruby take about 70 ms on Linux and over 200 ms on Windows and macOS before any of CrossLint's code runs (#13).
- **The words CrossLint writes are ASCII, and what it takes from the project prints as it is, in UTF-8.** Writing `lib/café.rb` as `lib/caf?.rb` would leave a path no editor opens and no debt entry matches.
- **A check leaves nothing to clean up,** so Ctrl-C stops it at once.
