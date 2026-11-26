# Command line

This document specifies CrossLint's command line: what holds in any language, and each place where a command-line guideline conflicts with keeping ng-nudge's behavior. Every later design of the command line is checked against it.

Its sources are two public guides, the [Command Line Interface Guidelines](https://clig.dev/) ("clig"), read at commit [`697d6a2`](https://github.com/cli-guidelines/cli-guidelines/commit/697d6a29fc8c93d3981a755c0c7683507ad39c3e), and [BetterCLI](https://bettercli.org/), read at commit [`5ef14f4`](https://github.com/BetterCLI/bettercli.org/commit/5ef14f4646c098037084502008f75b73d29cc6d0), set against ng-nudge 0.3.0's command line at commit [`10a7224`](https://github.com/OverTheTopMarketing/ng-nudge/tree/10a722456daacca08f6425c5b74e5586183c654b). Each requirement cites the section of the guide it follows. Both guides are licensed CC BY-SA 4.0; this document summarizes their guidelines and quotes neither.

The compatibility requirements are in [ng-nudge-compatibility.md](ng-nudge-compatibility.md). Where a guideline and those requirements pull apart, this document either settles it, when the guides and the requirements leave one answer, or lists it as an open choice with its options. [Conflicts with ng-nudge](#conflicts-with-ng-nudge) indexes them.

The command's name and the names of CrossLint's packages are chosen once the language is ([#4](https://github.com/setdef/CrossLint/issues/4)), so this document uses no command name. So are the names of CrossLint's environment variables and of its configuration file.

## Invocation

- The command with no arguments runs every check, as ng-nudge does. BetterCLI allows a tool to run its main action when called bare ([BetterCLI, CLI help pages][bcli-help], "Showing help by default"). A script that called ng-nudge bare calls CrossLint bare.
- Whether CrossLint has subcommands, such as one that converts ng-nudge's files or one that writes a configuration, is open. If it has any, an unknown first word is an error and never runs as a default command, and subcommands are not abbreviated ([clig, Future-proofing][clig-future]); the same flag means the same thing in every subcommand ([clig, Subcommands][clig-subcommands]); and `help <subcommand>` prints that subcommand's help ([clig, Help][clig-help]).
- `--update-debt` stays a flag. Whether it is also a subcommand is open.
- Whether CrossLint takes a list of paths to check as arguments is open. ng-nudge takes none, so adding one breaks nothing, and clig allows several arguments when they are the same kind of thing, such as files ([clig, Arguments and flags][clig-args]).

## Flags

- Every flag has a long form. A one-letter form is given only to a commonly used flag ([clig, Arguments and flags][clig-args]).
- A flag with a standard name uses it ([clig, Arguments and flags][clig-args]): `-h`/`--help`, `-q`/`--quiet`, `--json`, `--version` and `--debug`, and `--no-color` if CrossLint uses color ([clig, Output][clig-output]).
- Flags and arguments are accepted in any order ([clig, Arguments and flags][clig-args]).
- A flag's value is accepted after `=` or as the next argument, so `--warnings error` means what `--warnings=error` means. ng-nudge ignores `--warnings error` ([`bin/ng-nudge:66-67`][ngn-bin-66-67]), so a project that wrote it gets the behavior it asked for.
- A long flag is accepted only when spelled in full. An accepted abbreviation would become part of the interface, which clig says to change only through a long, documented deprecation ([clig, Future-proofing][clig-future]), and it would make adding a flag a breaking change.
- `--debug` prints what CrossLint does, such as the files it reads and the plugins it runs, on stderr ([BetterCLI, Debugging][bcli-debug]). Its short form depends on [`-d`](#-d-and---update-debt).
- The flags ng-nudge has keep their meanings: `--warnings`, `-q`/`--quiet`, `-s`/`--silent`, `--update-debt` and `-h`/`--help` ([ng-nudge-compatibility.md](ng-nudge-compatibility.md#command-line)).

### `-d` and `--update-debt`

ng-nudge gives `-d` to `--update-debt` ([`bin/ng-nudge:32`][ngn-bin-32]). The guides give `-d` to `--debug` ([clig, Arguments and flags][clig-args]; [BetterCLI, Debugging][bcli-debug]). This conflict is open:

- **Keep `-d` as `--update-debt`.** A project's scripts run unchanged. `--debug` has no short form, and `-d` differs from what users of other tools expect.
- **Remove `-d`.** Passing it is an error whose message points to `--update-debt`. A script breaks once, with a message, and the fix is one word.
- **Keep `-d` as an alias for a stated number of releases,** with a deprecation notice on stderr each time it is used ([clig, Future-proofing][clig-future]), then remove it.

`-d` never changes meaning without a release in between that rejects it or warns about it. A script that runs `-d` would otherwise run a check that updates nothing and still succeeds, and clig says to warn in the program before such a change ([clig, Future-proofing][clig-future]).

## Help

- `-h` and `--help` print the help to stdout and exit 0, wherever they appear among the arguments and whatever else is given ([clig, Help][clig-help]; [BetterCLI, CLI help pages][bcli-help], "Formatting and displaying CLI Help"). `-h` means nothing but help.
- The help says what CrossLint does, where to begin and how to learn more ([BetterCLI, CLI help pages][bcli-help]), in this order: name and version, usage with examples, the most used flags first, then the files CrossLint reads and writes and the environment variables it reads ([BetterCLI, CLI help pages][bcli-help], "Formatting and displaying CLI Help"; [clig, Help][clig-help]). It ends with a link to the documentation and to the issue tracker ([clig, Help][clig-help]).
- It lists every exit code with its meaning, stale debt included, which ng-nudge's help leaves out ([`bin/ng-nudge:35-37`][ngn-bin-35]; [BetterCLI, CLI help pages][bcli-help], "Long and short versions").
- It is generated from the flag definitions, so it can't drift from them ([BetterCLI, CLI help pages][bcli-help], "Reference").
- It is short enough to read without a pager. Long collections of examples belong in the web documentation ([clig, Help][clig-help]).
- Formatting that helps it scan is left out when stdout is not a terminal ([clig, Help][clig-help]).
- The documentation lists every artifact, policy and rule a plugin supplies, with the default severity CrossLint applies. ng-nudge's README leaves some of its rules out and gives `prefer-css-over-scss` a severity it doesn't have in practice ([ng-nudge-compatibility.md, Bugs not kept](ng-nudge-compatibility.md#bugs-not-kept)).

## Mistakes in flags and configuration

CrossLint never ignores a mistake silently ([clig, Robustness guidelines][clig-robust]; [BetterCLI, CLI help pages, "Handling typos and wrong commands"][bcli-typos]). Of the options for this conflict, that rules out keeping ng-nudge's behavior: ng-nudge ignores unknown flags, unknown `--warnings` values, unknown `rc.json` keys and an unknown severity ([`bin/ng-nudge:66-75`][ngn-bin-66]; [ng-nudge-compatibility.md, Bugs not kept](ng-nudge-compatibility.md#bugs-not-kept)), which leaves a user believing a check runs that doesn't.

- A value CrossLint can't interpret, for a flag or a configuration key CrossLint has, is an error. CrossLint reports it before it checks anything and exits non-zero ([clig, Robustness guidelines][clig-robust]). Running on would give a result the user didn't ask for, which is where both guides agree a tool fails ([clig, Robustness guidelines][clig-robust]; [BetterCLI, CLI help pages, "Handling typos and wrong commands"][bcli-typos]).
- A message about a mistake says what is wrong first, suggests the nearest valid spelling where one is close, and ends with how to list what is valid ([clig, Help][clig-help]; [BetterCLI, CLI help pages, "Handling typos and wrong commands"][bcli-typos]). CrossLint never runs the corrected form in place of what was typed ([clig, Help][clig-help]).
- **Open: an unknown flag, an unknown argument, or an unknown configuration key.** The guides differ here: clig says to validate input early and fail with an understandable error ([clig, Robustness guidelines][clig-robust]), and BetterCLI says strict and lenient parsing can both be right, and suggests a warning for a doubtful value in place of a failure ([BetterCLI, CLI help pages, "Handling typos and wrong commands"][bcli-typos]). Either it is an error, as for a value CrossLint can't interpret; or CrossLint prints one line per unknown item on stderr and carries on, so nothing fails and the typo shows. Under the second option, a flag or setting that makes these errors is a new flag.

## Streams

- Help goes to stdout ([BetterCLI, CLI help pages][bcli-help], "Formatting and displaying CLI Help").
- Messages about CrossLint itself go to stderr: errors that stop the run, warnings about configuration, deprecation notices and `--debug` output ([clig, The Basics][clig-basics]; [clig, Output][clig-output]).
- `--json` output goes to stdout, and nothing else is written there while it is on ([clig, The Basics][clig-basics]).
- An artifact's heading and its messages go to the same stream. ng-nudge writes a warning's heading to stdout and its message to stderr ([`lib/console-output.js:52-58`][ngn-out-52], [`lib/severity.js:9`][ngn-sev-9]).
- **Open: which stream findings go to.** clig says primary output goes to stdout and messages and errors to stderr ([clig, The Basics][clig-basics]), and the guides don't say which of the two a linter's findings are.
  - **All findings on stdout.** A script that discards stderr now sees warnings, and one that reads stderr to find warnings sees none.
  - **All findings on stderr.** stdout carries only structured output such as `--json`, and every script that reads stdout for findings breaks.
  - **ng-nudge's split: warnings on stderr, everything else on stdout** ([`lib/severity.js:1-11`][ngn-sev-1]), with each artifact's heading printed on every stream that carries one of its messages. Scripts that redirect one stream see what they see today.

## Output on success

- The default report doesn't list artifacts that pass, where ng-nudge lists each with `✓` ([`lib/console-output.js:52-53`][ngn-out-52-53]). Both guides lean toward printing less on success ([clig, Output][clig-output]; [BetterCLI, Messaging, "Success message"][bcli-success]), and how ng-nudge's output looks is free to change. A flag lists every artifact checked, passing ones included, so no information ng-nudge prints is lost. Its name is open.
- `-q`/`--quiet` prints only what fails the run, with no summary. `-s`/`--silent` prints nothing but errors that stop the run. Both keep their meanings from ng-nudge ([ng-nudge-compatibility.md](ng-nudge-compatibility.md#command-line)).
- **Open: what a clean run prints.** The guides differ: either a one-line summary with the number of artifacts checked, which clig recommends because silence can look like a hang ([clig, Output][clig-output]), or nothing, which BetterCLI suggests ([BetterCLI, Messaging, "Success message"][bcli-success]). A run with findings ends with the summary under both.

## Machine-readable output

- `--json` prints the report as JSON on stdout ([clig, Output][clig-output]). ng-nudge's printed text changes in CrossLint, because reporting two artifacts with the same file name apart can't be done without changing it, and scripts read `--json` instead of the text ([clig, Future-proofing][clig-future]). This rules out keeping the text byte for byte, and a flag that restores ng-nudge's printer, which would keep merging those artifacts.
- The JSON's fields are part of CrossLint's interface and change only as [Versions and change](#versions-and-change) says.
- Whether a `--plain` form is needed depends on whether the human report keeps one finding per line ([clig, Output][clig-output]).
- **Open: the symbols `✓ ✗ ⚠ ★` on a terminal that can't show them.** Either CrossLint always writes them as UTF-8, as ng-nudge does, or it writes ASCII in their place where the terminal's encoding lacks them.

## Color

ng-nudge uses no color. Whether CrossLint uses color is open. If it does:

- It uses color sparingly and with a purpose ([clig, Output][clig-output]).
- It turns color off on a stream that is not a terminal (checked per stream), when `NO_COLOR` is set to a value that is not empty, when `TERM` is `dumb`, and when `--no-color` is given ([clig, Output][clig-output]; [BetterCLI, Colors and formatting][bcli-color]). `FORCE_COLOR` turns it on and skips the checks ([clig, Environment variables][clig-env]). An empty `NO_COLOR` leaves color on, which is the [NO_COLOR standard's](https://no-color.org/) rule and clig's; BetterCLI says to turn color off whenever `NO_COLOR` is present.
- It sets a text color whenever it sets a background color ([BetterCLI, Colors and formatting][bcli-color]).
- It shows no animation on a stream that is not a terminal ([clig, Output][clig-output]).

## Exit codes

- `0` means the run passed: no unexcused violation fails it, and no debt entry is stale. Any other result is non-zero ([clig, The Basics][clig-basics]; [BetterCLI, Exit codes][bcli-exit]).
- The help and the documentation list every code ([BetterCLI, CLI help pages][bcli-help], "Long and short versions").
- **Open: one non-zero code or more.** The guides differ: clig says to map the non-zero codes to the most important failure modes ([clig, The Basics][clig-basics]), and BetterCLI says 0 and 1 are never wrong and more codes need a strong reason ([BetterCLI, Exit codes][bcli-exit]). ng-nudge exits 1 for violations, for stale debt and for every error that stops the run ([`lib/verification-task.js:25-29`][ngn-task-25], [`bin/ng-nudge:86-88`][ngn-bin-86]), and CrossLint keeps that unless the maintainer decides otherwise.
  - **0 and 1 only** ([BetterCLI, Exit codes][bcli-exit]). A script that tests `!= 0` or `== 1` sees no change, and can't tell a broken setup from violations.
  - **1 for violations and stale debt, another code (such as 2) for an error that stops the run** ([clig, The Basics][clig-basics]). A script that tests `!= 0` is unchanged. A script that tests `== 1` treats a broken configuration as a pass.
  - **The second option by default, with a flag that restores 1 for everything.**
- The exit code of a successful `--update-debt` run is an open choice in [ng-nudge-compatibility.md](ng-nudge-compatibility.md#open-choices).

## Errors

- An expected error, such as a missing file or invalid configuration, prints a message for a person, with the fix where there is one, and no stack trace ([clig, Errors][clig-errors]).
- An unexpected error says that it is a bug in CrossLint and where to report it, and `--debug` shows the stack trace ([clig, Errors][clig-errors]).
- Findings of one kind are grouped under one heading ([clig, Errors][clig-errors]).

## Configuration and environment

- A value given on the command line wins over the environment, and the environment wins over the project's configuration ([clig, Configuration][clig-config]). ng-nudge has flags and `rc.json` and nothing between them, so this order agrees with it.
- CrossLint has no user-level or system-level configuration. If it gains one, it follows the XDG base directory layout ([clig, Configuration][clig-config]) and the project's configuration wins over it.
- CrossLint reads the general variables `NO_COLOR`, `FORCE_COLOR` and `TERM` ([clig, Environment variables][clig-env]). It reads no secret from a flag or the environment ([clig, Arguments and flags][clig-args]; [clig, Environment variables][clig-env]).
- CrossLint's configuration file declares the version of its format. A version CrossLint doesn't know is reported as written by a newer CrossLint ([BetterCLI, CLI application lifecycle, "Downgrading"][bcli-downgrade]; [BetterCLI, Configuration][bcli-config]).

## Files and network

- A check run reads files by convention and writes none ([clig, Output][clig-output]). CrossLint writes the debt file only under `--update-debt`, and says which file it wrote and how many entries it holds ([clig, Output][clig-output]).
- A command that would change a file CrossLint didn't write, such as an existing configuration, asks first and says what it changes ([clig, Configuration][clig-config]).
- Every file CrossLint writes is replaced whole, so an interrupted run leaves the previous file and nothing needs cleaning up ([clig, Robustness guidelines][clig-robust]).
- A check run makes no network request. How plugins are fetched waits on [#4](https://github.com/setdef/CrossLint/issues/4); whichever way is chosen follows [BetterCLI, Networking][bcli-network] if CrossLint itself makes the request.
- CrossLint collects no usage or crash data ([clig, Analytics][clig-analytics]).

## Interruption and first output

- On Ctrl-C, CrossLint stops at once. Since every write replaces a file whole, there is nothing to clean up ([clig, Signals][clig-signals]; [clig, Robustness guidelines][clig-robust]).
- CrossLint prints something within 100 ms of starting ([clig, Robustness guidelines][clig-robust]). ng-nudge prints nothing until the run ends ([`lib/verification-task.js:17-23`][ngn-task-17]). Whether the first output is a line on stderr saying what is being checked, or the first finding, is open, and the time is measured on the built program on each platform it supports.
- CrossLint never asks a question during a check run ([clig, Interactivity][clig-interactive]). Any command that does ask has a flag for every answer and asks only when stdin is a terminal.

## Versions and change

- `--version` prints CrossLint's version, `0.X.Y`, and exits 0 ([clig, Arguments and flags][clig-args]; [BetterCLI, Versioning][bcli-version]). ng-nudge has no version flag ([`bin/ng-nudge:24-33`][ngn-bin-24]), so this conflicts with nothing. **Open:** whether it also prints build metadata, such as the commit, after the version ([BetterCLI, Versioning][bcli-version]).
- Flags, subcommands, exit codes, configuration keys, environment variables and the `--json` fields are interfaces ([clig, Future-proofing][clig-future]). A change to one is additive where it can be. Before a breaking change takes effect, CrossLint warns whenever the old form is used and says how to move to the new one ([clig, Future-proofing][clig-future]).
- The human report is not an interface and may change in any release ([clig, Future-proofing][clig-future]).
- **Open: an executable named `ng-nudge`** that runs CrossLint with ng-nudge's flags for a transition. Without it, a migrating project changes `npx ng-nudge` in its scripts and CI to CrossLint's command, which it does anyway if it also changes how it installs CrossLint.

## Waits on the language

These depend on the language CrossLint is written in, and are settled with [#4](https://github.com/setdef/CrossLint/issues/4):

- the command's name and the packages' names ([clig, Naming][clig-naming]);
- the argument-parsing library ([clig, The Basics][clig-basics]), which has to support every rule under [Flags](#flags), full spellings only among them;
- reaching first output within 100 ms ([clig, Robustness guidelines][clig-robust]);
- how stdout and stderr are buffered, and so how their output interleaves;
- how CrossLint tells whether a stream is a terminal, its width, and its encoding on Windows;
- how an uncaught error is caught at the top, and how Ctrl-C reaches the program;
- how CrossLint is distributed and removed ([clig, Distribution][clig-dist]; [BetterCLI, Distribution and installation][bcli-install]).

## Conflicts with ng-nudge

| Conflict | Status | Section |
|---|---|---|
| `-d` is `--update-debt`, and the guides' `--debug` | Open; `-d` never changes meaning silently | [`-d` and `--update-debt`](#-d-and---update-debt) |
| Mistakes in flags and configuration are ignored | Settled: never silent; a value CrossLint can't interpret is an error. Open: unknown items fail or warn | [Mistakes in flags and configuration](#mistakes-in-flags-and-configuration) |
| Warnings on stderr, everything else on stdout | Open; a heading and its messages share a stream | [Streams](#streams) |
| Exit 1 for violations and for errors that stop the run | Open | [Exit codes](#exit-codes) |
| The default lists every passing artifact | Settled: it doesn't, and a flag lists them. Open: what a clean run prints, and the flag's name | [Output on success](#output-on-success) |
| The printed text, and no machine-readable form | Settled: the text changes and `--json` exists. Open: the symbols' fallback | [Machine-readable output](#machine-readable-output) |
| Bare invocation and subcommands | Settled: bare runs the checks. Open: subcommands | [Invocation](#invocation) |
| The help lacks examples, links and exit codes | Settled | [Help](#help) |
| The command name | Waits on the language. Open: an `ng-nudge` executable | [Versions and change](#versions-and-change) |
| `--version` | Settled: it exists. Open: build metadata | [Versions and change](#versions-and-change) |

[clig-basics]: https://clig.dev/#the-basics
[clig-args]: https://clig.dev/#arguments-and-flags
[clig-help]: https://clig.dev/#help
[clig-output]: https://clig.dev/#output
[clig-errors]: https://clig.dev/#errors
[clig-robust]: https://clig.dev/#robustness-guidelines
[clig-interactive]: https://clig.dev/#interactivity
[clig-subcommands]: https://clig.dev/#subcommands
[clig-signals]: https://clig.dev/#signals
[clig-config]: https://clig.dev/#configuration
[clig-env]: https://clig.dev/#environment-variables
[clig-future]: https://clig.dev/#future-proofing
[clig-naming]: https://clig.dev/#naming
[clig-dist]: https://clig.dev/#distribution
[clig-analytics]: https://clig.dev/#analytics
[bcli-help]: https://bettercli.org/design/cli-help-page/
[bcli-typos]: https://bettercli.org/design/cli-help-page/#handling-typos-and-wrong-commands
[bcli-success]: https://bettercli.org/design/messaging/#success-message
[bcli-color]: https://bettercli.org/design/using-colors-in-cli/
[bcli-debug]: https://bettercli.org/design/debugging/
[bcli-downgrade]: https://bettercli.org/design/cli-application-lifecycle/#downgrading-cli-version
[bcli-exit]: https://bettercli.org/design/exit-codes/
[bcli-config]: https://bettercli.org/design/configuration/
[bcli-version]: https://bettercli.org/design/versioning/
[bcli-install]: https://bettercli.org/design/distribution/installation/
[bcli-network]: https://bettercli.org/design/cli-networking/
[ngn-bin-24]: https://github.com/OverTheTopMarketing/ng-nudge/blob/10a722456daacca08f6425c5b74e5586183c654b/bin/ng-nudge#L24-L33
[ngn-bin-32]: https://github.com/OverTheTopMarketing/ng-nudge/blob/10a722456daacca08f6425c5b74e5586183c654b/bin/ng-nudge#L32
[ngn-bin-35]: https://github.com/OverTheTopMarketing/ng-nudge/blob/10a722456daacca08f6425c5b74e5586183c654b/bin/ng-nudge#L35-L37
[ngn-bin-66]: https://github.com/OverTheTopMarketing/ng-nudge/blob/10a722456daacca08f6425c5b74e5586183c654b/bin/ng-nudge#L66-L75
[ngn-bin-66-67]: https://github.com/OverTheTopMarketing/ng-nudge/blob/10a722456daacca08f6425c5b74e5586183c654b/bin/ng-nudge#L66-L67
[ngn-bin-86]: https://github.com/OverTheTopMarketing/ng-nudge/blob/10a722456daacca08f6425c5b74e5586183c654b/bin/ng-nudge#L86-L88
[ngn-out-52]: https://github.com/OverTheTopMarketing/ng-nudge/blob/10a722456daacca08f6425c5b74e5586183c654b/lib/console-output.js#L52-L58
[ngn-out-52-53]: https://github.com/OverTheTopMarketing/ng-nudge/blob/10a722456daacca08f6425c5b74e5586183c654b/lib/console-output.js#L52-L53
[ngn-sev-1]: https://github.com/OverTheTopMarketing/ng-nudge/blob/10a722456daacca08f6425c5b74e5586183c654b/lib/severity.js#L1-L11
[ngn-sev-9]: https://github.com/OverTheTopMarketing/ng-nudge/blob/10a722456daacca08f6425c5b74e5586183c654b/lib/severity.js#L9
[ngn-task-17]: https://github.com/OverTheTopMarketing/ng-nudge/blob/10a722456daacca08f6425c5b74e5586183c654b/lib/verification-task.js#L17-L23
[ngn-task-25]: https://github.com/OverTheTopMarketing/ng-nudge/blob/10a722456daacca08f6425c5b74e5586183c654b/lib/verification-task.js#L25-L29
