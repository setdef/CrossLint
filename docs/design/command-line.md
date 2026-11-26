# Command line

This document specifies CrossLint's command line: what holds in any language, and each place where a command-line guideline conflicts with keeping ng-nudge's behavior. Every later design of the command line is checked against it.

Its sources are two public guides, the [Command Line Interface Guidelines](https://clig.dev/) ("clig") and [BetterCLI](https://bettercli.org/), as set against ng-nudge's command line in the [command-line guidelines spike](https://github.com/setdef/CrossLint/blob/97b1d87494cc1c81bfa07eb67c7d92bf7aac9a77/spikes/cli-guidelines/README.md). IDs such as C6 (a clig guideline), B12 (a BetterCLI guideline), D1 (a disagreement between the two) and K1 (a conflict with ng-nudge) are that spike's. Both guides are licensed CC BY-SA 4.0; this document summarizes their guidelines and quotes neither.

The compatibility requirements are in [ng-nudge-compatibility.md](ng-nudge-compatibility.md). Where a guideline and those requirements pull apart, this document either settles it, when the guides and the requirements leave one answer, or lists it as an open choice with its options. [Conflicts with ng-nudge](#conflicts-with-ng-nudge) indexes them.

The command's name and the names of CrossLint's packages are chosen once the language is ([#4](https://github.com/setdef/CrossLint/issues/4)), so this document names no command. So are the names of CrossLint's environment variables and of its configuration file.

## Invocation

- The command with no arguments runs every check, as ng-nudge does (K7; B6 allows a tool to run its main action when called bare). A script that called ng-nudge bare calls CrossLint bare.
- Whether CrossLint has subcommands, such as one that converts ng-nudge's files or one that writes a configuration, is open. If it has any, an unknown first word is an error and never runs as a default command (C56), subcommands are not abbreviated (C56), the same flag means the same thing in every subcommand (C44), and `help <subcommand>` prints that subcommand's help (C15).
- `--update-debt` stays a flag. Whether it is also a subcommand is open (K7).
- Whether CrossLint takes a list of paths to check as arguments is open. ng-nudge takes none, so adding one breaks nothing (C5).

## Flags

- Every flag has a long form (C3). A one-letter form is given only to a commonly used flag (C4).
- A flag with a standard name uses it (C6): `-h`/`--help`, `-q`/`--quiet`, `--json`, `--version` and `--debug`, and `--no-color` if CrossLint uses color (C32).
- Flags and arguments are accepted in any order (C10).
- A flag's value is accepted after `=` or as the next argument, so `--warnings error` means what `--warnings=error` means. In ng-nudge the first form is ignored (bug 20 in the [ng-nudge study](https://github.com/setdef/CrossLint/blob/97b1d87494cc1c81bfa07eb67c7d92bf7aac9a77/spikes/ng-nudge-study/README.md#bugs)), so a project that wrote it gets the behavior it asked for.
- A long flag is accepted only when spelled in full. An accepted abbreviation would become part of the interface that C53 says to keep, and it would make adding a flag a breaking change.
- `--debug` prints what CrossLint does, such as the files it reads and the plugins it runs, on stderr (B12). Its short form depends on [`-d`](#-d-and---update-debt).
- The flags ng-nudge has keep their meanings: `--warnings`, `-q`/`--quiet`, `-s`/`--silent`, `--update-debt` and `-h`/`--help` ([ng-nudge-compatibility.md](ng-nudge-compatibility.md#command-line)).

### `-d` and `--update-debt`

ng-nudge gives `-d` to `--update-debt`. The guides give `-d` to `--debug` (C6, B12). This is K1, and it is open:

- **Keep `-d` as `--update-debt`.** A project's scripts run unchanged. `--debug` has no short form, and `-d` differs from what users of other tools expect.
- **Remove `-d`.** Passing it is an error whose message points to `--update-debt`. A script breaks once, with a message, and the fix is one word.
- **Keep `-d` as an alias for a stated number of releases,** with a deprecation notice on stderr each time it is used (C54), then remove it.

`-d` never changes meaning without a release in between that rejects it or warns about it. A script that runs `-d` would otherwise run a check that updates nothing and still succeeds, and C54 asks for a warning in the program before such a change.

## Help

- `-h` and `--help` print the help to stdout and exit 0, wherever they appear among the arguments and whatever else is given (C13, C15, B3). `-h` means nothing but help.
- The help says what CrossLint does, where to begin and how to learn more (B2), in this order: name and version, usage with examples, the most used flags first, then the files CrossLint reads and writes and the environment variables it reads (B3, C18, C19). It ends with a link to the documentation and to the issue tracker (C16, C17).
- It lists every exit code with its meaning, stale debt included, which ng-nudge's help leaves out (B5).
- It is generated from the flag definitions, so it can't drift from them (B4).
- It is short enough to read without a pager. Long collections of examples belong in the web documentation (C18).
- Formatting that helps it scan is left out when stdout is not a terminal (C20).
- The documentation lists every artifact, policy and rule a plugin supplies, with the default severity CrossLint applies (bugs 28 and 29).

## Mistakes in flags and configuration

CrossLint never ignores a mistake silently (C12, B1 and bug 20). This settles the "keep" option of K2: ng-nudge ignores unknown flags, unknown `--warnings` values, unknown `rc.json` keys and an unknown severity, which leaves a user believing a check runs that doesn't.

- A value CrossLint can't interpret, for a flag or a configuration key CrossLint has, is an error. CrossLint reports it before it checks anything and exits non-zero (C12). Running on would give a result the user didn't ask for, which is where both guides agree a tool fails (B1).
- A message about a mistake says what is wrong first, suggests the nearest valid spelling where one is close, and ends with how to list what is valid (C21, B8). CrossLint never runs the corrected form in place of what was typed (C21).
- **Open: an unknown flag, an unknown argument, or an unknown configuration key** (K2, D4). Either it is an error, as for a value CrossLint can't interpret; or CrossLint prints one line per unknown item on stderr and carries on, so nothing fails and the typo shows. Under the second option, a flag or setting that makes these errors is a new flag.

## Streams

- Help goes to stdout (B3).
- Messages about CrossLint itself go to stderr: errors that stop the run, warnings about configuration, deprecation notices and `--debug` output (C24, C35).
- `--json` output goes to stdout, and nothing else is written there while it is on (C24).
- An artifact's heading and its messages go to the same stream (bug 21).
- **Open: which stream findings go to** (K3, D7). The guides don't say whether a linter's findings are primary output or messages.
  - **All findings on stdout.** A script that discards stderr now sees warnings, and one that reads stderr to find warnings sees none.
  - **All findings on stderr.** stdout carries only structured output such as `--json`, and every script that reads stdout for findings breaks.
  - **ng-nudge's split: warnings on stderr, everything else on stdout,** with each artifact's heading printed on every stream that carries one of its messages. Scripts that redirect one stream see what they see today.

## Output on success

- The default report doesn't list artifacts that pass (K5). Both guides lean toward printing less on success (C28, B9), and how ng-nudge's output looks is free to change. A flag lists every artifact checked, passing ones included, so no information ng-nudge prints is lost. Its name is open.
- `-q`/`--quiet` prints only what fails the run, with no summary. `-s`/`--silent` prints nothing but errors that stop the run. Both keep their meanings from ng-nudge ([ng-nudge-compatibility.md](ng-nudge-compatibility.md#command-line)).
- **Open: what a clean run prints** (D3). Either a one-line summary with the number of artifacts checked (C28, which says silence can look like a hang), or nothing (B9). A run with findings ends with the summary under both.

## Machine-readable output

- `--json` prints the report as JSON on stdout (C27). ng-nudge's printed text changes in CrossLint (bug 6 can't be fixed without changing it), and scripts read `--json` instead of the text (C55). This settles K6 against keeping the text byte for byte, and against a flag that restores ng-nudge's printer, which would keep bug 6.
- The JSON's fields are part of CrossLint's interface (C53) and change only as C54 describes.
- Whether a `--plain` form is needed depends on whether the human report keeps one finding per line (C26).
- **Open: the symbols `✓ ✗ ⚠ ★` on a terminal that can't show them** (K6). Either CrossLint always writes them as UTF-8, as ng-nudge does, or it writes ASCII in their place where the terminal's encoding lacks them.

## Color

ng-nudge uses no color. Whether CrossLint uses color is open. If it does:

- It uses color sparingly and with a purpose (C31).
- It turns color off on a stream that is not a terminal (checked per stream), when `NO_COLOR` is set to a value that is not empty, when `TERM` is `dumb`, and when `--no-color` is given (C32, B10). `FORCE_COLOR` turns it on and skips the checks (C32). An empty `NO_COLOR` leaves color on, which is the [NO_COLOR standard's](https://no-color.org/) rule and clig's (D5).
- It sets a text color whenever it sets a background color (B10).
- It shows no animation on a stream that is not a terminal (C33).

## Exit codes

- `0` means the run passed: no unexcused violation fails it, and no debt entry is stale. Any other result is non-zero (C40, B14).
- The help and the documentation list every code (B5).
- **Open: one non-zero code or more** (K4, D1). ng-nudge exits 1 for violations, for stale debt and for every error that stops the run, and the ng-nudge study keeps that unless the maintainer decides otherwise.
  - **0 and 1 only** (B14). A script that tests `!= 0` or `== 1` sees no change, and can't tell a broken setup from violations.
  - **1 for violations and stale debt, another code (such as 2) for an error that stops the run** (C40). A script that tests `!= 0` is unchanged. A script that tests `== 1` treats a broken configuration as a pass.
  - **The second option by default, with a flag that restores 1 for everything.**
- The exit code of a successful `--update-debt` run is an open choice in [ng-nudge-compatibility.md](ng-nudge-compatibility.md#open-choices).

## Errors

- An expected error, such as a missing file or invalid configuration, prints a message for a person, with the fix where there is one, and no stack trace (C37).
- An unexpected error says that it is a bug in CrossLint and where to report it, and `--debug` shows the stack trace (C39).
- Findings of one kind are grouped under one heading (C38).

## Configuration and environment

- A value given on the command line wins over the environment, and the environment wins over the project's configuration (C51). ng-nudge has flags and `rc.json` and nothing between them, so this order agrees with it.
- CrossLint has no user-level or system-level configuration. If it gains one, it follows the XDG base directory layout (C49) and the project's configuration wins over it.
- CrossLint reads the general variables `NO_COLOR`, `FORCE_COLOR` and `TERM` (C52). It reads no secret from a flag or the environment (C11, C52).
- CrossLint's configuration file declares the version of its format. A version CrossLint doesn't know is reported as written by a newer CrossLint (B13, B16).

## Files and network

- A check run reads files by convention and writes none (C30). CrossLint writes the debt file only under `--update-debt`, and says which file it wrote and how many entries it holds (C29).
- A command that would change a file CrossLint didn't write, such as an existing configuration, asks first and says what it changes (C50).
- Every file CrossLint writes is replaced whole, so an interrupted run leaves the previous file and nothing needs cleaning up (C46).
- A check run makes no network request. How plugins are fetched waits on [#4](https://github.com/setdef/CrossLint/issues/4); whichever way is chosen follows B26 if CrossLint itself makes the request.
- CrossLint collects no usage or crash data (C60).

## Interruption and first output

- On Ctrl-C, CrossLint stops at once. Since every write replaces a file whole, there is nothing to clean up (C47, C46).
- CrossLint prints something within 100 ms of starting (C45). ng-nudge prints nothing until the run ends. Whether the first output is a line on stderr saying what is being checked, or the first finding, is open, and the time is measured on the built program on each platform it supports.
- CrossLint never asks a question during a check run (C42). Any command that does ask has a flag for every answer and asks only when stdin is a terminal.

## Versions and change

- `--version` prints CrossLint's version, `0.X.Y`, and exits 0 (C6, B19). ng-nudge has no version flag, so this conflicts with nothing. **Open:** whether it also prints build metadata, such as the commit, after the version (B19, K10).
- Flags, subcommands, exit codes, configuration keys, environment variables and the `--json` fields are interfaces (C53). A change to one is additive where it can be (C54). Before a breaking change takes effect, CrossLint warns whenever the old form is used and says how to move to the new one (C54).
- The human report is not an interface and may change in any release (C55).
- **Open: an executable named `ng-nudge`** that runs CrossLint with ng-nudge's flags for a transition (K9). Without it, a migrating project changes `npx ng-nudge` in its scripts and CI to CrossLint's command, which it does anyway if it also changes how it installs CrossLint.

## Waits on the language

These depend on the language CrossLint is written in, and are settled with [#4](https://github.com/setdef/CrossLint/issues/4) ([spike, part 3](https://github.com/setdef/CrossLint/blob/97b1d87494cc1c81bfa07eb67c7d92bf7aac9a77/spikes/cli-guidelines/README.md#dependent-on-the-language)):

- the command's name and the packages' names (C58);
- the argument-parsing library (C1), which has to support every rule under [Flags](#flags), full spellings only among them;
- reaching first output within 100 ms (C45);
- how stdout and stderr are buffered, and so how their output interleaves;
- how CrossLint tells whether a stream is a terminal, its width, and its encoding on Windows;
- how an uncaught error is caught at the top, and how Ctrl-C reaches the program;
- how CrossLint is distributed and removed (C59, B20).

## Conflicts with ng-nudge

| ID | Conflict | Status | Section |
|---|---|---|---|
| K1 | `-d` is `--update-debt`, and the guides' `--debug` | Open; `-d` never changes meaning silently | [`-d` and `--update-debt`](#-d-and---update-debt) |
| K2 | Mistakes in flags and configuration are ignored | Settled: never silent; a value CrossLint can't interpret is an error. Open: unknown items fail or warn | [Mistakes in flags and configuration](#mistakes-in-flags-and-configuration) |
| K3 | Warnings on stderr, everything else on stdout | Open; a heading and its messages share a stream | [Streams](#streams) |
| K4 | Exit 1 for violations and for errors that stop the run | Open | [Exit codes](#exit-codes) |
| K5 | The default lists every passing artifact | Settled: it doesn't, and a flag lists them. Open: what a clean run prints, and the flag's name | [Output on success](#output-on-success) |
| K6 | The printed text, and no machine-readable form | Settled: the text changes and `--json` exists. Open: the symbols' fallback | [Machine-readable output](#machine-readable-output) |
| K7 | Bare invocation and subcommands | Settled: bare runs the checks. Open: subcommands | [Invocation](#invocation) |
| K8 | The help lacks examples, links and exit codes | Settled | [Help](#help) |
| K9 | The command name | Waits on the language. Open: an `ng-nudge` executable | [Versions and change](#versions-and-change) |
| K10 | `--version` | Settled: it exists. Open: build metadata | [Versions and change](#versions-and-change) |
