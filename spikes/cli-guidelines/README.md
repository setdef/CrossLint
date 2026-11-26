# Command line guidelines

The question: what do two public guides to command-line design say that applies to a linter like CrossLint, how does ng-nudge's command line stand against them, and which of those guidelines depend on the language CrossLint is written in? This feeds the design in #2. It makes no decision: where a guideline and ng-nudge's behavior pull apart, it sets out the options.

## Sources and licenses

| Guide | Public page | Read at | License |
|---|---|---|---|
| Command Line Interface Guidelines ("clig") | [clig.dev](https://clig.dev/), source [cli-guidelines/cli-guidelines](https://github.com/cli-guidelines/cli-guidelines) | [`697d6a2`](https://github.com/cli-guidelines/cli-guidelines/commit/697d6a29fc8c93d3981a755c0c7683507ad39c3e), one page, `content/_index.md` | Creative Commons Attribution-ShareAlike 4.0 International (its `LICENSE` and README) |
| BetterCLI | [bettercli.org](https://bettercli.org/), source [BetterCLI/bettercli.org](https://github.com/BetterCLI/bettercli.org) | [`5ef14f4`](https://github.com/BetterCLI/bettercli.org/commit/5ef14f4646c098037084502008f75b73d29cc6d0), every page under `content/` | Creative Commons Attribution-ShareAlike 4.0 International (its `LICENSE` and README) |

Both licenses require attribution and, for adapted material, the same license. This file summarizes in plain words and copies no sentence from either guide, and each row cites its source. If a later document quotes either guide, it has to carry the credit and the ShareAlike terms.

ng-nudge is read at [`10a7224`](https://github.com/OverTheTopMarketing/ng-nudge/tree/10a722456daacca08f6425c5b74e5586183c654b), the commit the [ng-nudge study](../ng-nudge-study/README.md) uses. "Bug N" below is that study's numbering.

About the two guides:

- clig is one long page of rules. It says which rules are essential ("The Basics") and which are nice to have, and it says the rules can be broken on purpose.
- BetterCLI is a set of pages. Several are stubs: [Messaging](https://bettercli.org/design/messaging/), [Configuration](https://bettercli.org/design/configuration/) (its YAML section is empty), [shell autocomplete](https://bettercli.org/how-to/implement-shell-autocomplete/) and [CLI frameworks](https://bettercli.org/glossary/list-of-frameworks/) are unfinished. Three pages (a checklist, "falsehoods", text formatting) are marked as drafts in the source and are not published, so nothing here relies on them. BetterCLI leans toward lifecycle, distribution and analytics, where clig leans toward interaction design.

## 1. Guidelines that apply to a command-line linter

Each row has an ID that the rest of this file uses. The CrossLint column says whether the guideline applies to a linter that reads a project, writes a report and exits, and has no prompts and no network use. Rows marked "depends" are taken up in part 3.

### Arguments and flags

| ID | Source | The guideline | CrossLint |
|---|---|---|---|
| C1 | [clig, The Basics](https://clig.dev/#the-basics) | Use an argument-parsing library, which brings flag parsing, help text and spelling suggestions. | Applies. Which library depends on the language. |
| C2 | [clig, Arguments and flags](https://clig.dev/#arguments-and-flags) | Prefer flags to positional arguments: they read clearly and leave room to add input later without ambiguity. | Applies. |
| C3 | same | Give every flag a full-length form. | Applies. |
| C4 | same | Give one-letter forms only to commonly used flags, so the short namespace isn't used up. | Applies. |
| C5 | same | Several arguments are fine when they are the same kind of thing (files). Two or more arguments of different kinds are a smell, except for a primary action like `cp`. | Applies to a list of paths to check. |
| C6 | same | Use the standard flag names where one exists: `-a/--all`, `-d/--debug`, `-f/--force`, `--json`, `-h/--help` (only help), `-n/--dry-run`, `--no-input`, `-o/--output`, `-p/--port`, `-q/--quiet`, `--version`. `-v` is ambiguous (verbose or version): use it for neither, or for version. | Applies. `-d`, `-q`, `-h`, `--version`, `--json`, `-n` are relevant. |
| C7 | same | Make the default the right thing for most users. | Applies. |
| C8 | same | Where input or output is a file, accept `-` for stdin or stdout. | Applies only if CrossLint reads a path list from stdin or writes a report file. |
| C9 | same | Where a flag takes an optional value, accept a word like `none` for "no value". | Applies if a flag takes an optional path. |
| C10 | same | Make flags, arguments and subcommands order-independent where the parser allows. | Applies, and matters once there are subcommands. |
| C11 | same | Never take a secret from a flag. | Does not apply unless a plugin takes a credential. |
| C12 | [clig, Robustness](https://clig.dev/#robustness-guidelines) | Validate input early, fail before anything happens, and make the error understandable. | Applies to flags and configuration. |
| B1 | [BetterCLI, CLI help pages, "Handling typos and wrong commands"](https://bettercli.org/design/cli-help-page/#handling-typos-and-wrong-commands) | Strict parsing makes a predictable tool but can reject harmless input; lenient parsing makes the tool look like it ignores what the user typed. Choose on purpose, and consider warning on typos and failing only where execution would break. | Applies. Disagrees with C12 in degree (see D4). |

### Help and documentation

| ID | Source | The guideline | CrossLint |
|---|---|---|---|
| C13 | [clig, Help](https://clig.dev/#help) | Show full help for `-h` and `--help`, for every subcommand too. | Applies. |
| C14 | same | When arguments are required and none are given, show concise help: a description, one or two examples, the flags unless there are many, and a pointer to `--help`. Exempt: a program that is interactive by default. | Applies only if CrossLint requires an argument. |
| C15 | same | `-h` and `--help` ignore every other flag and argument, so `-h` can be added to the end of any command. `-h` means only help. A `git`-like tool also answers `help` and `help <subcommand>`. | Applies. |
| C16 | same | Give a support path (a website or issue tracker link) in the top-level help. | Applies. |
| C17 | same | Link to the web documentation, deep-linking where a page exists. | Applies. |
| C18 | same | Lead with examples, including the common complex ones. Move a long collection to a cheat-sheet command or a web page. | Applies. |
| C19 | same | List the most common flags and commands first. | Applies. |
| C20 | same | Format help so it scans (bold headings) without leaving escape characters when piped. | Applies. |
| C21 | same | When the input looks like a mistake with a likely meaning, suggest the fix. Ask before running it, and don't silently run the corrected form: it commits the tool to the typo. | Applies to unknown flags and subcommands. |
| C22 | same | If the program expects piped input and stdin is a terminal, show help and exit. | Does not apply unless CrossLint reads stdin. |
| C23 | [clig, Documentation](https://clig.dev/#documentation) | Provide web documentation and terminal documentation. Consider man pages, and also make the terminal documentation reachable through the tool, since `man` isn't on every platform. | Applies. |
| B2 | [BetterCLI, CLI help pages](https://bettercli.org/design/cli-help-page/) | Help answers three questions for a reader who knows nothing about the tool: what it does, where to begin, how to learn more. | Applies. |
| B3 | same, "Formatting and displaying CLI Help" | Help goes to stdout, not stderr, and ignores other flags. Order it as name and version, usage and examples, commands and options, then environment variables and configuration files. | Applies. |
| B4 | same, "Reference" | Generate the reference from the flag definitions so it can't drift. Keep a short reference and a long document, and expect to want both. | Applies. |
| B5 | same, "Long and short versions" | Document the exit codes in the help or the documentation. | Applies. |
| B6 | same, "Showing help by default" | Bare invocation may show help to introduce the tool, or may run the tool's main action if it has an obvious one. | Applies. Both are allowed. |
| B7 | same, "Using a Pager for longer documents" | A pager for help confuses people who don't know how to leave it. | Applies. Disagrees with C36 (see D2). |
| B8 | same, "Handling typos and wrong commands" | Put the failure first, offer near spellings, and end with how to list what is available. | Applies. |

### Output, streams, color

| ID | Source | The guideline | CrossLint |
|---|---|---|---|
| C24 | [clig, The Basics](https://clig.dev/#the-basics) | Primary output and anything machine-readable go to stdout. Log messages and errors go to stderr, so a pipe carries only the data. | Applies. For a linter the guides don't say whether findings are primary output or messages (see D7). |
| C25 | [clig, Output](https://clig.dev/#output) | Design for humans first. Test each stream separately for whether it is a TTY. | Applies. |
| C26 | same | Keep output usable by line-based tools (`grep`, `awk`). When human formatting breaks one record per line, offer `--plain`. | Applies. |
| C27 | same | Offer `--json` for structured output. | Applies. |
| C28 | same | Print something on success, but briefly. Err on the side of less. `-q` removes non-essential output. | Applies. Disagrees with B9 in degree (see D3). |
| B9 | [BetterCLI, Messaging, "Success message"](https://bettercli.org/design/messaging/#success-message) | Unless the result is the output (`ls`), consider printing nothing and exiting 0. This page is a stub. | Applies. |
| C29 | [clig, Output](https://clig.dev/#output) | Tell the user when state changes, make current state easy to see, and suggest the next commands. | Applies to anything that writes files (a debt update, a configuration generator). |
| C30 | same | Make an action that crosses the program's boundary explicit: reading or writing files the user didn't name (other than internal state such as a cache), and talking to a remote server. | Applies to reading project files by convention (configuration), to writing, and to fetching plugins. |
| C31 | same | Use color with intention and sparingly. | Applies. |
| C32 | same | Turn color off when stdout or stderr is not a TTY (check each), when `NO_COLOR` is set and not empty, when `TERM` is `dumb`, and when the user passes `--no-color`. A program-specific variable such as `MYAPP_NO_COLOR` is optional. `FORCE_COLOR` turns it on and skips detection ([clig, Environment variables](https://clig.dev/#environment-variables)). | Applies. |
| C33 | same | No animations when stdout is not a TTY. | Applies. |
| C34 | same | Symbols and emoji are fine where they make output clearer, and easy to overdo. | Applies. |
| C35 | same | Show nothing by default that only the authors can understand. Don't treat stderr as a log file: no level labels or extra context outside verbose mode. | Applies. |
| C36 | same | Page long output only when stdin or stdout is a TTY, for example with `less -FIRX`. | Applies if output can be long. |
| B10 | [BetterCLI, Colors and formatting](https://bettercli.org/design/using-colors-in-cli/) | Strip formatting when output isn't a terminal and when `NO_COLOR` is present. Keep styling simple because terminal themes make colors unpredictable. Always set a text color along with a background color. 8-bit colors render the same everywhere; the basic 16 depend on the theme. Avoid backspace overstriking. | Applies. |
| B11 | [BetterCLI, Messaging, "Progress bars"](https://bettercli.org/design/messaging/#progress-bars) | Progress bars are for interactive terminals and stay out of the final output. | Applies if CrossLint shows progress. |

### Errors, debugging, exit codes

| ID | Source | The guideline | CrossLint |
|---|---|---|---|
| C37 | [clig, Errors](https://clig.dev/#errors) | Catch expected errors and rewrite them for a person, with the fix where possible. No stack traces for expected failures. | Applies. |
| C38 | same | Keep a high signal-to-noise ratio. Group errors of one kind under one explanatory header. Put the most important line last, where the eye lands, and use red sparingly. | Applies. A linter prints many findings, so grouping matters. |
| C39 | same | For an unexpected error, give debug and traceback information and how to report the bug, preferably through a URL that pre-fills the report. Consider writing the debug log to a file. | Applies. |
| B12 | [BetterCLI, Debugging](https://bettercli.org/design/debugging/) | Offer global `-d/--debug` or `-v/--verbose`, or a `DEBUG` variable, working with any command. Debug output goes to stderr. A saved failure log should carry a timestamp and the original command, should not be written to the current directory (it dirties the work tree and can be committed by accident), and can hold secrets. | Applies. |
| B13 | [BetterCLI, Lifecycle, "Downgrading"](https://bettercli.org/design/cli-application-lifecycle/#downgrading-cli-version) | When the tool meets a configuration version it doesn't know (written by a newer release), say so explicitly. | Applies if configuration is versioned. |
| C40 | [clig, The Basics](https://clig.dev/#the-basics) | Exit 0 on success and non-zero on failure. Map the non-zero codes to the most important failure modes. | Applies. |
| B14 | [BetterCLI, Exit codes](https://bettercli.org/design/exit-codes/) | A binary 0 or 1 is never wrong. Use more codes only with a strong reason, and put detail in a parseable message on stderr. Consider whether recoverable and unrecoverable failures, warnings and partial failures need different codes. | Applies. Disagrees with C40 (see D1). |

### Interactivity, subcommands, robustness, signals

| ID | Source | The guideline | CrossLint |
|---|---|---|---|
| C42 | [clig, Interactivity](https://clig.dev/#interactivity) | Prompt only when stdin is a TTY. `--no-input` turns every prompt off. Never require a prompt: every input has a flag. Don't echo passwords. Make the way out clear. | Applies to any prompt CrossLint ever adds. ng-nudge has none. |
| C43 | [clig, Arguments and flags](https://clig.dev/#arguments-and-flags) | Confirm dangerous actions in three levels (mild, moderate, severe), with `--force` or `--confirm=<name>` for scripts, and a dry run for moderate ones. | Applies to writes such as a debt update. |
| C44 | [clig, Subcommands](https://clig.dev/#subcommands) | Be consistent across subcommands: the same flag for the same thing, similar output. Use one pattern for nested subcommands (noun then verb is more common). Don't ship similar names such as `update` and `upgrade`. | Applies if CrossLint has subcommands. |
| C45 | [clig, Robustness](https://clig.dev/#robustness-guidelines) | Print something within 100 ms. Print before a network request. Show progress for long work. Parallelize with care so output isn't interleaved. | Applies. Part 3 covers the 100 ms. |
| C46 | same | Make timeouts configurable with a sensible default. Make failures recoverable by re-running. Prefer crash-only: no cleanup that must run. Expect misuse, including odd filesystems (macOS is case-insensitive and case-preserving). | Applies. |
| B15 | [BetterCLI, Performance](https://bettercli.org/design/performance/) | Installation time and startup time shape how fast a tool feels. Quick feedback on a mistyped flag speeds recovery. Use CI timing to catch regressions. No numbers given. | Applies. |
| C47 | [clig, Signals](https://clig.dev/#signals) | On Ctrl-C, exit as soon as possible and say something before any cleanup. Put a timeout on cleanup. A second Ctrl-C skips long cleanup, and the message says what it will do. Expect to start where cleanup never ran. | Applies. |

### Configuration, environment, future-proofing

| ID | Source | The guideline | CrossLint |
|---|---|---|---|
| C48 | [clig, Configuration](https://clig.dev/#configuration) | Pick the mechanism by how the value varies. Per invocation: flags. Per machine or user: flags and environment variables. Stable in a project for everyone: a version-controlled, command-specific file. | Applies. ng-nudge's `rc.json` is the third kind. |
| C49 | same | Follow the XDG base directory layout for user-level files. | Applies only if CrossLint gets user-level configuration. |
| C50 | same | Ask consent before modifying configuration that isn't yours, and say what you change. | Applies to any `init` that edits an existing file. |
| C51 | same | Precedence from highest to lowest: flags, the shell's environment, project configuration, user configuration, system configuration. | Applies. |
| B16 | [BetterCLI, Configuration](https://bettercli.org/design/configuration/) | Treat global and local configuration, flags, environment, files and remote sources as layers that override each other. For boolean environment variables, either define "present with any value" as on, or accept several spellings for on and off. Make the file format evolvable and give it a version. Treat values read from configuration as untrusted input (a timeout can arrive as `1_000` or `1e3`). | Applies. The page has no precedence list. |
| B17 | same, "Using programming language as configuration" | A programming language as configuration gives flexibility, and costs documentation, error messages that point at the mistake, and testing. It suits stable APIs. | Applies to project-written rules and policies (see part 3). |
| C52 | [clig, Environment variables](https://clig.dev/#environment-variables) | Environment variables are for behavior that varies with context. Names use uppercase letters, digits and underscores. Aim for single-line values. Don't reuse POSIX names. Check the general-purpose ones where relevant (`NO_COLOR`, `FORCE_COLOR`, `DEBUG`, `PAGER`, `TERM`, `TMPDIR`, `HOME`, `LINES`, `COLUMNS`). Read `.env` where it fits, but not in place of a configuration file. Don't read secrets from the environment. | Applies. |
| C53 | [clig, Future-proofing](https://clig.dev/#future-proofing) | Subcommands, arguments, flags, configuration files and environment variables are all interfaces. Change them only through a long, documented deprecation. | Applies. This is the guideline behind a drop-in replacement. |
| C54 | same | Prefer additive changes. Before a breaking change, warn in the program when the old form is used, say how to migrate, and stop warning once usage has changed. | Applies. |
| C55 | same | Changing human output is usually fine, because an output that can't change can't be improved. Tell script authors to use `--plain` or `--json`. | Applies. Bears on K6. |
| C56 | same | No catch-all subcommand (an unknown first word treated as a default command), and no arbitrary abbreviations of subcommands. Aliases are fine when explicit and stable. | Applies if CrossLint has subcommands. |
| C57 | same | Avoid a "time bomb": the tool should still run in twenty years, so no dependency on a service you can't promise to keep. | Applies, and bears on install-by-URL plugins. |
| B18 | [BetterCLI, CLI application lifecycle](https://bettercli.org/design/cli-application-lifecycle/) | The machine belongs to the user. Users stay on an old version for years, run several versions, and use the tool in ways the author didn't plan. A new version should read old configuration. A breaking change pushed by auto-update breaks other people's automation. Uninstalling should leave nothing behind, or say what it leaves. | Applies. |
| B19 | [BetterCLI, Versioning](https://bettercli.org/design/versioning/) | Semantic Versioning is the most compatible choice for installers and package managers. Build metadata (`+date`, `+commit`) can show how old an install is. | Applies. Bears on how `--version` prints (see K10). |

### Naming, distribution, analytics, security

| ID | Source | The guideline | CrossLint |
|---|---|---|---|
| C58 | [clig, Naming](https://clig.dev/#naming) | A simple, memorable word, not too generic. Lowercase letters, with a dash only if needed. Short, but not so short that it collides with the names kept for core utilities. Easy to type. | Applies. |
| C59 | [clig, Distribution](https://clig.dev/#distribution) | Distribute a single binary where possible. If not, use the platform's installer so nothing is scattered on disk. Exempt: a language-specific tool such as a linter, since users can be assumed to have the language. Make uninstalling easy. | Depends (see part 3). |
| B20 | [BetterCLI, Distribution and installation](https://bettercli.org/design/distribution/installation/) | An install method should answer how to install, update, list dependencies, name supported systems, and remove all files. Prefer a method that gives checksums or signatures. | Applies. |
| B21 | [BetterCLI, Self-executing installers](https://bettercli.org/design/distribution/self-executing-installer/) | A `curl \| sh` installer is flexible and risky: host it on a domain you own, version it, keep the body in a function, and offer another route. | Applies only if CrossLint ships one. |
| B22 | [BetterCLI, Auto-updating](https://bettercli.org/design/distribution/auto-updating-cli/) | Try a nudge message in the output before building auto-update. | Applies. |
| B23 | [BetterCLI, Security considerations](https://bettercli.org/design/security-considerations/) | Rely on few third parties. Take care when running or shelling out on user input. Publish a list of the files, libraries and network access the tool uses, with a software bill of materials and signing keys. | Applies. CrossLint loads project code and may run helper processes. |
| B24 | [BetterCLI, How to code sign](https://bettercli.org/how-to/sign-cli-executable/) | Sign executables so users can verify the source and avoid OS warnings. | Applies to a distributed binary. |
| C60 | [clig, Analytics](https://clig.dev/#analytics) | Send no usage or crash data without consent. Say what, why, how anonymous, how long. Prefer opt-in, and where opt-out, announce it and make it easy to turn off. Consider docs analytics and download counts instead. | Applies if CrossLint ever collects. |
| B25 | [BetterCLI, Collecting analytics](https://bettercli.org/design/collecting-analytics/) | If collecting, collect little, sanitize on the server, fire the event after the command finishes, set a timeout of a few seconds, and fail fast. Don't send events straight to a third party. | Same. |
| B26 | [BetterCLI, Networking](https://bettercli.org/design/cli-networking/) | If the tool makes network requests, honor proxy variables, custom certificates and a configurable base URL, centralize networking in one module, and send an identifying `User-Agent`. | Applies only to a CrossLint that fetches anything itself (see part 3). |
| P1 | [clig, Philosophy](https://clig.dev/#philosophy) | Human-first design, composability, consistency with other programs, saying just enough, discoverability, treating use as a conversation, robustness, empathy, and breaking a rule only deliberately. | Applies as the reasoning behind C-rows above. |

### Where the guides disagree

- **D1, exit codes.** clig (C40) says to map non-zero codes to the most important failure modes. BetterCLI (B14) says to stay with 0 and 1 unless there is a strong reason, and to put detail in a message.
- **D2, a pager for long text.** clig (C36) says to page long output on a TTY, with `less -FIRX` as a sensible default. BetterCLI (B7) says a pager for help confuses new users. They agree on paging only when a person is reading. They differ on whether help is long text.
- **D3, output on success.** clig (C28) says to print something brief, because silence looks like a hang. BetterCLI (B9) says to consider printing nothing. clig also says to err on the side of less, so the gap is in the default, not the direction.
- **D4, how strict to be with input.** clig (C12) says to validate early and fail with an understandable error. BetterCLI (B1) says either strict or lenient can be right, and suggests a warning for a doubtful value in place of a failure. BetterCLI calls silent acceptance of a mistake a kind of lying to the user, and clig's rule is to validate, so neither endorses ignoring it.
- **D5, `NO_COLOR` with an empty value.** clig (C32) says color is disabled when `NO_COLOR` is set and not empty. BetterCLI (B10) says disabled when it is present. An empty value separates the two.
- **D6, which color conditions to check.** clig lists TTY per stream, `NO_COLOR`, `TERM=dumb`, `--no-color`, and `FORCE_COLOR`. BetterCLI lists only a TTY check and `NO_COLOR`. This is a difference in coverage, not a contradiction.
- **D7, where a linter's findings go.** The guides don't answer it. clig puts primary output on stdout and "log messages, errors, and so on" on stderr. A finding is both a result and an error.
- **D8, the debug flag.** clig lists `-d/--debug` as the standard and says `-v` is ambiguous. BetterCLI lists `-d/--debug` and `-v/--verbose` together as common.
- **D9, versions.** BetterCLI (B19) recommends Semantic Versioning for compatibility. clig (C53) says SemVer excuses only so much change.
- **D10, configuration as code.** clig (C48) points to a version-controlled, command-specific file for project settings. BetterCLI (B17) treats a programming language as a configuration format and lists what it costs.

## 2. ng-nudge's command line against the guidelines

Every row below is read from ng-nudge's source at the commit above, with the study's transcripts as the record of what runs. The command line is [`bin/ng-nudge`](https://github.com/OverTheTopMarketing/ng-nudge/blob/10a722456daacca08f6425c5b74e5586183c654b/bin/ng-nudge), the printer is [`lib/console-output.js`](https://github.com/OverTheTopMarketing/ng-nudge/blob/10a722456daacca08f6425c5b74e5586183c654b/lib/console-output.js) and the severity streams are in [`lib/severity.js`](https://github.com/OverTheTopMarketing/ng-nudge/blob/10a722456daacca08f6425c5b74e5586183c654b/lib/severity.js). "Conforms" means the guide's rule is met. "Compat conflict" means following the guide would change what a project that uses ng-nudge sees; each is set out in K1 to K10 below.

### Flags

| Flag | What ng-nudge does | Guidelines | Verdict | Compat conflict |
|---|---|---|---|---|
| `--warnings=all\|none\|error` | Long form only. Read only as `--warnings=VALUE`; `--warnings error` is ignored. Any value other than `none` and `error` acts as `all` (study bug 20). ([bin/ng-nudge:66-67, 72-73](https://github.com/OverTheTopMarketing/ng-nudge/blob/10a722456daacca08f6425c5b74e5586183c654b/bin/ng-nudge#L66-L73)) | C2, C3 (long form: conforms). C12, B1 (validation: does not conform). No standard name exists. | Partly | K2 |
| `-q`, `--quiet` | Prints only artifacts with errors, no summary. | C6 and C28 name `-q/--quiet`: conforms. Behavior hides warnings it still counts (bug 26). | Conforms in name | K5 (what "quiet" hides) |
| `-s`, `--silent` | No report; fatal errors still print. Wins over `--quiet`. | Not in C6's list. Neither guide covers a second level of quiet. C4 says one-letter flags are for commonly used flags. | Not covered | None |
| `-d`, `--update-debt` | Runs the checks, reports, then rewrites the debt file, and prints what it wrote. | C6 gives `-d` to `--debug`. C29 (tell the user) conforms. C43 (confirm): a rewrite of a version-controlled file is at the mild end and prints what it did. | Conflicts on `-d` | K1 |
| `-h`, `--help` | Found anywhere in the arguments, prints the help to stdout, exits 0. | C13, C15, B3: conforms. | Conforms | None |
| (no `--version`) | There is no way to print the version. | C6 and B19 expect `--version`. | Absent | None (additive) |
| (no `--no-color`, `--json`, `--plain`, `--debug`, `--no-input`, `--dry-run`) | Not present. ng-nudge never uses color, never prompts and has no machine-readable form. | C26, C27, C32, C42, C43, B12 | Absent | None (additive), but see K2 and K6 |
| Unknown flags and positional arguments | Ignored without a message (`--quite`, `-x`, extra words). (bug 20) | C12, C21, B1, B8: does not conform. | Conflicts | K2 |

Precedence is flags over `options` in `rc.json`, which agrees with C51. ng-nudge reads no environment variables ([`bin/` and `lib/` contain no `process.env`](https://github.com/OverTheTopMarketing/ng-nudge/tree/10a722456daacca08f6425c5b74e5586183c654b)), so there is no environment layer to conflict with, and no user-level or system-level configuration.

### Exit codes

| Behavior | Guidelines | Verdict | Compat conflict |
|---|---|---|---|
| 0 for a clean run, 1 for everything else. | C40 and B14: 0 and non-zero conforms. B14 recommends exactly this. C40 says to map codes to the main failure modes, which this doesn't. | Conforms to B14, not to C40 | K4 |
| 1 covers an unexcused error, a warning under `--warnings=error`, any stale debt, and every error that stops the run (unreadable configuration, missing `tsconfig.json`, a second interface in an interface file). | C40, C37: a script can't tell "the code has violations" from "the tool couldn't run". | Conflicts with C40 | K4 |
| The help documents 0 and 1 as "all checks passed" and "one or more violations detected". It leaves out stale debt and run-stopping errors. | B5, B2: document exit codes. | Partly | None |
| `--update-debt` exits 1 when it just recorded new violations or removed stale entries (bug 9). The study leaves it to the design whether that stays. | C29, C40 | Open | K4 |
| No signal handler. A Ctrl-C ends the process by Node's default. The debt file is written in one `writeFileSync` call. | C47, C46: nothing to clean up, so the default suits it. | Conforms by default | None |

### Output

| Behavior | Guidelines | Verdict | Compat conflict |
|---|---|---|---|
| Headings (`✓`, `✗`, `⚠`), error messages, the summary, the debt lines and the help go to stdout (`console.log`). Warning messages go to stderr (`console.warn`). Fatal errors go to stderr (`console.error`). ([severity.js:3, 9](https://github.com/OverTheTopMarketing/ng-nudge/blob/10a722456daacca08f6425c5b74e5586183c654b/lib/severity.js#L1-L10), [bin/ng-nudge:87](https://github.com/OverTheTopMarketing/ng-nudge/blob/10a722456daacca08f6425c5b74e5586183c654b/bin/ng-nudge#L86-L88)) | C24, C25. Fatal errors on stderr conform. Splitting one report across both streams is unlike what C24 describes: with stderr discarded, a warning heading shows with nothing under it (bug 21). | Partly | K3 |
| Nothing prints until the whole run finishes; the printer collects everything and writes it in `finish()`. | C45 (something within 100 ms), B15 | Does not conform | None |
| Default output lists every artifact, passing ones with `✓`, then a summary line. | C28 (brief on success), B9 (consider nothing) | Conflicts in degree | K5 |
| No color, no animation, no TTY check, no `NO_COLOR` or `TERM` check. | C31 to C33, B10 | Conforms by never using color. Adding color brings these rules in. | None |
| `✓ ✗ ⚠ ★` are always written, as UTF-8, whatever the terminal. | C34 conforms. Neither guide mentions a fallback for a console that can't show them (the study notes Windows code pages). | Not covered | K6 |
| Human text is the only format; no `--json` or `--plain`. | C26, C27, C55 | Absent | K6 |
| An error that stops the run prints its message alone, with no stack trace, except a JSON syntax error in `rc.json` (bug 19). | C37, P1 (no scary traces) | Partly | None |
| Debt payoff prints an instruction naming the command to run. | C29 (suggest next commands) conforms. It hard-codes `npx ng-nudge` (bug 9 covers when it should not print). | Conforms | None |
| The help is the comment block at the top of `bin/ng-nudge`. It has a description, usage, options and exit codes. It has no examples, no documentation link, no support path and no mention of the debt file's location. | C16 to C19, B2 to B4 | Partly | None |
| ng-nudge reads `.config/ng-nudge/rc.json`, `debt.tsv` and `tsconfig.json` by convention, writes only `debt.tsv`, and only under `--update-debt`. It makes no network requests and collects nothing. | C30, C60, B25: conforms. | Conforms | None |
| No prompts. | C42: conforms. | Conforms | None |
| `rc.json` has no version field and is never checked against its schema. | B16, B13, C12 | Does not conform | K2 |
| Command name `ng-nudge`: lowercase, a dash, short. Run as `npx ng-nudge`. | C58 | Conforms | K9 |

### Conflicts with keeping ng-nudge's behavior

Each conflict lists the options without choosing among them. C54 (warn in the program before a breaking change, say how to migrate, stop warning once the usage has changed) applies to every option that departs from ng-nudge, and a "compatibility flag" below means a flag or setting that keeps ng-nudge's behavior while the default follows the guideline.

**K1. `-d` means `--update-debt`; the guides give `-d` to `--debug`** (C6, B12).
- *Keep:* `-d` stays `--update-debt`. A project's scripts run unchanged. CrossLint has no `-d` for debug and spells it `--debug` (C4 allows a long-only flag). The cost is a flag that differs from what users of other tools expect.
- *Follow:* `-d` becomes debug. A script that runs `ng-nudge -d` now runs a normal check that updates nothing, and the debt file is never rewritten. This is the one option where the old command still succeeds but does something different.
- *Follow with a transition:* `-d` is removed, and passing it fails with a message that points to `--update-debt`. The script breaks once, loudly, and the fix is a one-word edit. Or `-d` stays an alias for a release or two and prints a deprecation notice on stderr (C54).

**K2. Mistakes are ignored: unknown flags, unknown `--warnings` values, `--warnings error`, unknown `rc.json` keys, an unknown severity** (C12, B1, B8, bug 20).
- *Keep:* ignore, as now. A project that passes a flag ng-nudge ignores keeps working. Typos stay invisible.
- *Follow:* reject with a message and a non-zero exit. A project whose script has a flag CrossLint doesn't know, or an `rc.json` key it doesn't read, fails on the first run. Some of these are meaningful: `--warnings error` is ignored today, so a project that believes warnings fail its build is not getting that, and parsing it properly changes pass and fail.
- *Warn:* print one line on stderr per ignored item and carry on (B1's middle path). Nothing fails, and the typo shows up. A flag that turns warnings into failures covers projects that want the strict form, and is itself a new flag.
- Which items fail and which warn is a separate choice: B1 suggests failing only where execution would break.

**K3. A report split across both streams: warning messages on stderr, everything else on stdout** (C24, bug 21, D7).
- *Keep:* the split stays. Scripts that redirect one stream keep their results, and the dangling `⚠` heading remains.
- *Follow, all findings on stdout:* diagnostics about the tool (fatal errors, deprecation notices) go to stderr, findings go to stdout. A script that discards stderr (`2>/dev/null`) now sees warnings, one that captures stdout to a file now captures warnings, and one that reads stderr to detect warnings stops seeing any.
- *Follow, all findings on stderr:* if findings count as messages (D7), stdout would carry only structured output such as `--json`. Every script that reads stdout for findings breaks.
- *With a compatibility flag:* a flag or setting restores the split. It keeps the dangling-heading bug unless the warning heading moves with its messages.

**K4. Exit code 1 covers both "violations found" and "the tool failed"; stale debt is also 1** (C40, B14, D1, bug 9).
- *Keep:* 0 and 1 only. B14 recommends this. A script that tests `!= 0` or `== 1` sees no change. A script still can't tell violations from a broken setup, and detail goes to stderr or `--json`.
- *Follow C40:* a separate code (for example 2) for usage and run-stopping errors, 1 for violations. A script that tests `!= 0` is unchanged. A script that tests `== 1` now treats a broken configuration as success.
- *Follow with a compatibility setting:* distinct codes by default, with a flag that restores 1 for everything.
- In every option the help lists all codes, including the stale-debt case ng-nudge's help leaves out. Whether `--update-debt` exits 0 after it succeeds is open (bug 9).

**K5. The default output lists every passing artifact and a summary** (C28, B9, D3).
- *Keep:* as now. CI logs and any script that reads "Checked N artifact(s)" are unchanged. A large project prints one line per artifact.
- *Follow:* the default prints the findings and a summary line, and the passing list moves behind a verbose flag. `-q` then means less than the default again, or merges with it. A script that reads the `✓` lines breaks.
- *Follow B9:* print only findings, nothing when clean. The summary and the `✓` lines go behind a flag. Scripts that check for a final summary line break.
- With any non-keep option, ng-nudge's `--quiet` and `--silent` need new definitions, because they are defined against the current default.

**K6. The text format of the default output, and its lack of a machine-readable form** (C26, C27, C55, bug 6).
- *Keep byte for byte:* scripts that parse the text keep working. The format can't improve, and artifacts with the same file name still merge (bug 6).
- *Change the text, add `--json` (and `--plain` if needed):* C55 says human output may change. The plan already treats how the output looks as free to change. Scripts that parse the text break, and the migration says to move to `--json`.
- *Change the text, offer the old format behind a compatibility flag:* both work, at the price of keeping the old printer.
- The symbols `✓ ✗ ⚠ ★` come with a related choice: always UTF-8 as now, or fall back to ASCII where the terminal can't show them. The guides don't say.

**K7. Bare invocation and subcommands** (C14, C44, C56, B6).
- ng-nudge has no subcommands, and bare `ng-nudge` runs the checks. C14 asks for concise help only when arguments are required, so this conforms today.
- *If CrossLint adds subcommands* (for example for debt, listing rules, or setup), bare `crosslint` can still run the checks (B6 allows a main action) or can print help. Running the checks keeps ng-nudge's habit. Printing help follows C14's spirit for a tool with several verbs, and breaks a script that calls the bare command. C56 says an unknown first word must not become a default command, and so a bare default and "an unknown word" have to be told apart.
- `--update-debt` can stay a flag, become a subcommand, or both. K1 depends on that choice.

**K8. Where ng-nudge's `--help` lacks C16 to C19**: no conflict with compatibility, since scripts rarely read help. It is a design matter.

**K9. The command name.** A project must change `npx ng-nudge` in its scripts and CI in any case. The options are to ship only the new name, or also an executable named `ng-nudge` that behaves like ng-nudge for a transition. The naming guideline (C58) is met by a lowercase, short name either way. Whether `crosslint` or another word is the command is for the design, and I did not check for a collision with an existing command of that name.

**K10. `--version`.** ng-nudge has none, so nothing conflicts. If CrossLint prints SemVer build metadata (B19), the printed string can differ from a plain `0.X.Y` release tag. The plan fixes versions as three plain integers; whether the printed string follows the tag exactly is a design choice.

### Migration summary

A project that scripts only `npx ng-nudge` and checks for a non-zero exit is affected only by K9 and K4 (if its script tests for exactly 1). A project that passes flags beyond the documented ones, redirects a stream, greps the output or uses `-d` is affected by K1, K2, K3, K5 or K6 respectively. Each of those is the kind of change C54 says to announce in the program before it takes effect.

## 3. Language-independent and language-dependent

### Independent of the language CrossLint is written in

These hold in Ruby, TypeScript or anything else, and are the design's to settle once, in one place:

- Flag names, short forms, long forms, and the meanings given in K1 to K10 (C2 to C10, C12, B1).
- What goes to stdout and stderr, and the exit codes (C24, C40, B14, D1, D7, K3, K4).
- The content and layout of help, and the documentation set (C13 to C23, B2 to B5).
- The set of conditions for color and animation (C31 to C33, B10, D5, D6).
- Configuration layers and precedence, the file format and its version field, and environment variable names (C48 to C52, B16).
- Error wording, grouping and the bug-report path (C37 to C39).
- The deprecation policy and the rule that changes are additive (C53 to C55).
- The command name and the form of the version string (C58, B19).
- What the tool reads and writes by convention, and that it asks before changing a file that isn't its own (C30, C50).
- Analytics: none, unless added with consent (C60).

### Dependent on the language

- **Time to first output.** C45 sets 100 ms for printing something, and B15 names startup time with no number. ng-nudge prints nothing until it has finished (part 2, Output). A Ruby app built with Fledge carries its own Ruby ([#1](https://github.com/setdef/CrossLint/issues/1)), so the time before the first byte includes starting that Ruby and loading CrossLint's code and its gems. [Fledge#123](https://github.com/setdef/Fledge/issues/123) covers installing such an app through mise and gives no timing. The first output can be a one-line "checking N files" message on stderr or the first finding streamed as found, either of which works in any language; whether the process reaches that line within 100 ms is a measurement the design has to take on the real app, per platform. #1 says speed is not a concern; C45 is about showing that the program is working, not about finishing fast.
- **Output buffering and ordering.** Interleaving of stdout and stderr, and whether a non-TTY stdout is buffered until exit, differ by runtime. This matters to K3 and to any streaming output. Ruby's `$stdout` is buffered when it isn't a terminal and Node's `console.log` is not, as far as I recall; I did not verify either here.
- **TTY, color, width.** Each runtime has its own call for "is this stream a terminal", for the terminal width (C32, C36, `COLUMNS`), and for enabling ANSI sequences on Windows consoles.
- **Console encoding.** The `✓ ✗ ⚠ ★` symbols and UTF-8 output depend on the runtime's default encoding for standard output on Windows (K6).
- **Argument parser behavior.** The parser library chosen under C1 determines how an unknown flag, a missing value, `--flag=value` against `--flag value`, option abbreviation and `--` are handled, and so how K2 is implemented. clig lists TTY as its Ruby example. I recall that Ruby's standard `OptionParser` accepts unambiguous abbreviations of long flags by default, which is the behavior C56 warns against for subcommands, and I did not verify it here.
- **Uncaught errors and stack traces.** A runtime prints a trace for an uncaught exception by default, and C37 calls for a rewritten message. The top-level handler is language-specific.
- **Signals.** C47 asks for an immediate message on Ctrl-C and a timeout on cleanup. How the runtime delivers SIGINT (a signal handler, or an exception raised in the main thread) and what exit code results are language-specific, and so is Windows behavior.
- **Distribution.** C59 exempts a language-specific tool because its users have the language. CrossLint serves several languages, so the exemption doesn't carry over directly, and the single-binary advice applies, which is what a Fledge app is. Fledge#123 reports that an app installed through mise puts the app's bundled Ruby on `PATH` ahead of a Ruby project's Ruby unless the archive is installed with two options. That bears on C59 ("tread lightly on the user's computer"), B20 (how to remove all files) and K9.
- **Project-written rules in a programming language.** B17 lists what configuration as code costs: documentation, error messages that point at the mistake, testing. Which language the rules are written in follows the language question in #1, and so does whether a project's rule file can be a declarative file (C48, third kind) rather than code.
- **Patterns and regular expressions in configuration.** The study notes that ng-nudge's glob and regular-expression semantics are JavaScript's. B16 says to treat configuration values as untrusted input; the dialect a pattern is read in is language-specific.

### Not verified

- I did not run ng-nudge for this file. Streams and exit codes come from reading its source at the commit above and the study's transcripts. That errors print on stdout and warnings on stderr is read from `lib/severity.js`.
- Facts about Ruby's and Node's defaults in part 3 are recalled, not checked, and are marked where they appear.
- I did not measure the start-up time of a Fledge app, and did not check whether `crosslint` collides with a command on any registry or package manager.
- The two guides were read at the commits listed. Pages that are stubs or drafts add no guidelines beyond what the table gives.
