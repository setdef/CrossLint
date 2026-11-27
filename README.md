# CrossLint

[![CI](https://github.com/setdef/CrossLint/actions/workflows/ci.yml/badge.svg?branch=trunk)](https://github.com/setdef/CrossLint/actions/workflows/ci.yml) [![Release](https://img.shields.io/github/v/release/setdef/CrossLint)](https://github.com/setdef/CrossLint/releases) [![License](https://img.shields.io/badge/license-MIT-a2c93e)](LICENSE) [![Platforms](https://img.shields.io/badge/platforms-macOS%20%7C%20Linux%20%7C%20Windows-a2c93e)](#compatibility) [![Certified Shovelware](https://justin.searls.co/img/shovelware.svg)](https://justin.searls.co/shovelware/)

Check the rules that span files: every source file has its test, every component has its template, every Ruby file has its signature file.

## Introduction

CrossLint checks how a project's files relate to each other. Linters such as [ESLint](https://eslint.org/) and [RuboCop](https://rubocop.org/) read one file at a time, so a rule like "every file in `lib/` has a signature file at the matching path under `sig/`" is one they can't check. CrossLint finds each group of files that belong together, checks that each has the files it should, and exits non-zero when one doesn't, so a project's CI fails on a missing test as it would on a failing one.

Most rules of this kind are relations between paths, and you declare them as data, with no code: which files to find, and where each of their pieces belongs. A check that has to read inside files, such as comparing an Angular component's inputs with those of its test stub, comes in a plugin. CrossLint ships one for Angular. CrossLint also tracks debt: violations a project accepts for now, each with a comment, so the check passes today and fails on any new violation.

CrossLint is one program for projects in any language. It carries what it needs to run, so a project installs no Ruby, Node, or other runtime to use it.

### What CrossLint replaces

- **[ng-nudge](https://github.com/OverTheTopMarketing/ng-nudge).** ng-nudge checks Angular projects only, and builds its debt tracking and its Angular checks into one tool. CrossLint keeps what ng-nudge checks, as its Angular plugin and its debt plugin, and a project moves from ng-nudge to CrossLint with one command.
- **A script in CI.** A shell script that loops over files and tests for each piece works until a second rule needs a second script. CrossLint declares each rule in one place, reports every violation with its file, and lets a project accept existing violations as debt instead of fixing them all before the check can go on.
- **A custom linter rule.** A rule written for ESLint or RuboCop can read the file it is checking, but can't see whether another file exists. CrossLint's rules see every file in the project.

## A first example

[Fledge](https://github.com/setdef/Fledge) keeps a signature file under `sig/` for each Ruby file under `lib/`, such as `sig/fledge/archive.rbs` for `lib/fledge/archive.rb`. A local plugin in Fledge's repository can say so in a few lines of [KDL](https://kdl.dev/):

<!--
SPDX-SnippetBegin
SPDX-License-Identifier: MIT-0
SPDX-SnippetCopyrightText: 2026 setdef
-->
```kdl
// .config/crosslint/signatures/plugin.kdl
artifact "ruby-file" {
  primary "lib/{path}.rb"
  piece "signature" "sig/{path}.rbs"
}

policy "has-signature" {
  applies-to "ruby-file"
  rule "piece-exists" piece="signature"
}
```
<!-- SPDX-SnippetEnd -->

The artifact covers every Ruby file under `lib/`, each with the path of the signature file that belongs beside it. The policy applies CrossLint's `piece-exists` rule to every one of them. Fledge's configuration lists the plugin:

<!--
SPDX-SnippetBegin
SPDX-License-Identifier: MIT-0
SPDX-SnippetCopyrightText: 2026 setdef
-->
```kdl
// .config/crosslint/config.kdl
plugin ".config/crosslint/signatures"
```
<!-- SPDX-SnippetEnd -->

Running `crosslint check` in the project checks every Ruby file under `lib/`. Each one has its signature file, so the check passes, and `crosslint` exits with 0:

<!--
SPDX-SnippetBegin
SPDX-License-Identifier: MIT-0
SPDX-SnippetCopyrightText: 2026 setdef
-->
```console
$ crosslint check
crosslint: checked 112 ruby-file artifacts: no violations
```
<!-- SPDX-SnippetEnd -->

Add `lib/fledge/doctor.rb` without writing `sig/fledge/doctor.rbs`, and the check fails, with exit status 1:

<!--
SPDX-SnippetBegin
SPDX-License-Identifier: MIT-0
SPDX-SnippetCopyrightText: 2026 setdef
-->
```console
$ crosslint check
lib/fledge/doctor.rb: no signature file at sig/fledge/doctor.rbs (signatures/has-signature)
crosslint: checked 113 ruby-file artifacts: 1 error
```
<!-- SPDX-SnippetEnd -->

Each finding is one line on standard output, with the file, the message, and the plugin and policy it comes from, so `grep` and an editor's problem matcher both read it. `crosslint check --json` prints the same findings as JSON. A script should read that, because [a minor release may change the line format](#versions).

## Compatibility

| What | Supported |
| --- | --- |
| Where `crosslint` runs | macOS on Apple silicon; Linux on x86-64, with glibc 2.39 or later; Windows on x86-64 |
| Projects | Any language, in any folder layout |
| The Angular plugin | Angular projects with [Node](https://nodejs.org/) on the `PATH` |
| Moving from ng-nudge | Projects that use ng-nudge 0.3.0; one whose `rc.json` sets `withComment.matching` needs Node on the `PATH` |

## Versions

CrossLint's versions follow [Semantic Versioning](https://semver.org/). Before 1.0.0, any release may change anything. From 1.0.0 on, a minor or patch release keeps each of these working as it did:

- The commands and flags, and the exit statuses: [the command reference](docs/reference/cli.md).
- `config.kdl`: [the configuration reference](docs/reference/configuration.md).
- `plugin.kdl`: [the plugin reference](docs/reference/plugin.md).
- The helper protocol, where each request and each answer is one line of JSON: [Rules a program runs](docs/reference/plugin.md#rules-a-program-runs) and [Artifacts a program declares](docs/reference/plugin.md#artifacts-a-program-declares).
- The library that a `(crosslint)"ruby"` helper uses: [Rules in CrossLint's Ruby](docs/reference/plugin.md#rules-in-crosslints-ruby).
- The output of `crosslint check --json`: [the command reference](docs/reference/cli.md#crosslint-check).
- The format of the debt file: [the debt plugin's settings](docs/reference/configuration.md#debt).

A minor or patch release may change the line format of findings and any other text CrossLint prints for people, on standard output and standard error, and the layout of the cache folder. Read `--json` from a script, and leave the cache folder to CrossLint.

CrossLint 1.0.0 carries Ruby 4.1.0-preview1, and a `(crosslint)"ruby"` helper runs on it. The release that moves CrossLint to Ruby 4.1.0 is a minor release.

## Installation

Download the archive for your computer from [the releases page](https://github.com/setdef/CrossLint/releases), check it against the release's `SHA256SUMS` file, unpack it anywhere, and put `crosslint` on your `PATH`. The archive contains everything CrossLint needs, so you install no Ruby or other runtime. CrossLint sends no usage data anywhere.

To check that this repository's release workflow built a file, run `gh attestation verify` from the [GitHub CLI](https://cli.github.com/manual/gh_attestation_verify) on the archive or on `SHA256SUMS`. It looks up the file's build provenance attestation and fails when none is signed by a workflow of `setdef/CrossLint`:

<!--
SPDX-SnippetBegin
SPDX-License-Identifier: MIT-0
SPDX-SnippetCopyrightText: 2026 setdef
-->
```console
$ gh attestation verify crosslint-VERSION-PLATFORM.tar.gz --repo setdef/CrossLint
```
<!-- SPDX-SnippetEnd -->

To uninstall CrossLint, delete the unpacked folder. If you listed a shared plugin, also delete the cache folder CrossLint fetched it into: `$XDG_CACHE_HOME/crosslint`, or `~/.cache/crosslint` when `XDG_CACHE_HOME` isn't set to an absolute path, or `%LOCALAPPDATA%\crosslint\cache` on Windows.

## Usage

1. **Write a configuration.** In the project's root, `crosslint init` writes `.config/crosslint/config.kdl`, which lists the plugins CrossLint runs, with the recommended ones already in it. No plugin runs until the configuration lists it.
2. **Declare the project's rules** in a local plugin: a folder in the repository with a `plugin.kdl` that declares its artifacts, policies, and rules, as in [A first example](#a-first-example). List the folder in `.config/crosslint/config.kdl`.
3. **Run the checks** with `crosslint check` from anywhere in the project. It exits with 0 when every check passes, 1 when there are violations, and 2 when CrossLint can't run, such as for a mistake in the configuration.
4. **Accept what you can't fix yet** with `crosslint debt update`, a command of the debt plugin, which writes every current violation to `.config/crosslint/debt.tsv`. Add a comment to each line saying why it's there. From then on, `crosslint check` passes as long as no violation is new, and fails when a recorded one is fixed, until `crosslint debt update` removes it from the file. `crosslint debt update --dry-run` lists what an update would change, and writes nothing.
5. **Run it in CI** as you run the project's tests, so a pull request with a new violation fails.

### Plugins for any project

This repository also keeps shared plugins for checks many projects want, each in its folder under [`plugins/`](plugins/), with a README that says what it checks and how to list it:

- [markdown-links](plugins/markdown-links/README.md): every relative link in the project's Markdown resolves, anchors included.
- [decision-log](plugins/decision-log/README.md): a decision log's index links to exactly the records in its folder.
- [agents-md](plugins/agents-md/README.md): every `AGENTS.md` has a `CLAUDE.md` beside it whose first line is `@AGENTS.md`.
- [page-features](plugins/page-features/README.md): every page component of an app has a Gherkin feature file.

A project lists one by this repository's URL, a tag, and the plugin's folder, such as `plugin "https://github.com/setdef/CrossLint" ref="TAG" path="plugins/markdown-links"`. `TAG` is a release of CrossLint that has the plugin's folder.

### Moving from ng-nudge

In the project's root, run `crosslint init --from-ng-nudge --dry-run` first: it lists every change the move would make, and makes none. Then run `crosslint init --from-ng-nudge`, which:

- writes `.config/crosslint/config.kdl` from `.config/ng-nudge/rc.json`, with the Angular plugin, the debt plugin, and every setting `rc.json` has, or ng-nudge's defaults when there is no `rc.json`;
- moves the debt file to `.config/crosslint/debt.tsv` byte for byte, with every entry and comment, and deletes ng-nudge's copy;
- leaves `rc.json` and the rule files in `.config/ng-nudge/rules/`, which ng-nudge never ran, where they are;
- lists each file that ng-nudge's patterns and CrossLint's would find differently, using the glob package in the project's `node_modules`.

It checks everything before it changes anything. A setting it can't carry with the same meaning, such as a pattern with braces, stops it with exit status 2, naming the setting and what to write instead, and one run lists every such problem, not only the first. So does a file in `.config/ng-nudge/artifacts/` or `policies/`, whose code CrossLint can't run, and an existing configuration or debt file, which `--force` replaces. Then replace ng-nudge's dev dependency and each `npx ng-nudge` in the project's scripts and CI with `crosslint check`.

CrossLint finds some violations ng-nudge misses, such as inputs ng-nudge doesn't read and stylesheets it looks for in the wrong folder. Run `crosslint debt update` once after moving, and work through the entries it adds as you would any other debt. The next check then passes, unless `rc.json` had ng-nudge report debt entries as errors, which CrossLint keeps doing.

## Documentation

[The documentation's map](docs/README.md) says where to start for what you're doing.

- In the terminal: `crosslint --help` lists every command with examples, and `crosslint check --help` explains one.
- [Getting started](docs/getting-started.md): add CrossLint to a project, write a rule for it, and keep the check passing with debt.
- [Plugin reference](docs/reference/plugin.md): everything a `plugin.kdl` can declare, including rules written in Ruby.
- [Configuration reference](docs/reference/configuration.md): everything `.config/crosslint/config.kdl` can hold, including the settings of the Angular and debt plugins.
- [Command reference](docs/reference/cli.md): every command, flag, and exit status.
- [Glossary](docs/glossary.md): the word CrossLint uses for each idea, and the words it avoids.

## Reporting problems

Ask questions and report problems on the [CrossLint forum](https://forum.setdef.com/c/crosslint). Include the command you ran, its output, `crosslint --version`, and your system. GitHub Issues are open to the project's collaborators only.

To send a patch, post it on the forum, or email it with `git send-email` to `replies+crosslint@forum.setdef.com`. [git-send-email.io](https://git-send-email.io) shows how to set that up.

## Contributing

[CONTRIBUTING.md](CONTRIBUTING.md) says how a change lands, how files are licensed, and how releases are cut.

## License

CrossLint is released under the [MIT License](LICENSE). It places no conditions on the projects you check with it. An example between SPDX snippet comments, in this README, the plugins' READMEs, or the guides and references under `docs/`, is under [MIT-0](LICENSES/MIT-0.txt), so you may copy it without a notice. The command reference and its examples are under the MIT License, like the rest.

## How this was made

I use four words for how code and prose comes to exist. Code or prose I wrote, I typed by hand, with nothing generated. Code or prose I wrought, an AI agent generated while I iterated with it, and I reviewed every change before committing it, so I own every diff. Code or prose I requested, an agent built with little or no review from me, but I take ownership of the outcome or product because I tested and iterated. Code or prose I rushed, an agent built with little or no feedback from me, and may or may not be useful (or safe).

This README is requested: an agent wrote it from my goals and decisions, as the specification CrossLint is built to. [declare-ai.org](https://declare-ai.org/1.0.0/total.html)
