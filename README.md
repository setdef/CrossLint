# CrossLint

[![CI](https://github.com/setdef/CrossLint/actions/workflows/ci.yml/badge.svg?branch=trunk)](https://github.com/setdef/CrossLint/actions/workflows/ci.yml) [![Release](https://img.shields.io/github/v/release/setdef/CrossLint)](https://github.com/setdef/CrossLint/releases) [![License](https://img.shields.io/badge/license-MIT-a2c93e)](LICENSE) [![Platforms](https://img.shields.io/badge/platforms-macOS%20%7C%20Linux%20%7C%20Windows-a2c93e)](#compatibility) [![Certified Shovelware](https://justin.searls.co/img/shovelware.svg)](https://justin.searls.co/shovelware/)

Check the rules that span files: every source file has its test, every component has its template, every Ruby file has its signature file.

## Introduction

CrossLint checks how a project's files relate to each other. Linters such as [ESLint](https://eslint.org/) and [RuboCop](https://rubocop.org/) read one file at a time, so a rule like "every file in `lib/` has a signature file at the matching path under `sig/`" is one they can't check. CrossLint finds each group of files that belong together, checks that each has the files it should, and exits non-zero when one doesn't, so a project's CI fails on a missing test as it would on a failing one.

Most rules of this kind are relations between paths, and you declare them as data, with no code: which files to find, and where each of their companion files belongs. A check that has to read inside files, such as comparing an Angular component's inputs with those of its test stub, comes in a plugin. CrossLint ships one for Angular. CrossLint also tracks debt: violations a project accepts for now, each with a comment, so the check passes today and fails on any new violation.

CrossLint is one program for projects in any language. It carries what it needs to run, so a project installs no Ruby, Node, or other runtime to use it.

### What CrossLint replaces

- **[ng-nudge](https://github.com/OverTheTopMarketing/ng-nudge).** ng-nudge checks Angular projects only, and builds its debt tracking and its Angular checks into one tool. CrossLint keeps what ng-nudge checks, as its Angular plugin and its debt plugin, and a project moves from ng-nudge to CrossLint with one command.
- **A script in CI.** A shell script that loops over files and tests for each companion works until a second rule needs a second script. CrossLint declares each rule in one place, reports every violation with its file, and lets a project accept existing violations as debt instead of fixing them all before the check can go on.
- **A custom linter rule.** A rule written for ESLint or RuboCop can read the file it is checking, but can't see whether another file exists. CrossLint's rules see every file in the project.

## A first example

[Fledge](https://github.com/setdef/Fledge) keeps a signature file under `sig/` for each Ruby file under `lib/`, such as `sig/fledge/archive.rbs` for `lib/fledge/archive.rb`. A local plugin in Fledge's repository can say so in a few lines of [KDL](https://kdl.dev/):

```kdl
// .config/crosslint/signatures/plugin.kdl
artifact "ruby-file" {
  files "lib/{path}.rb"
  companion "signature" "sig/{path}.rbs"
}

policy "has-signature" {
  applies-to "ruby-file"
  rule "companion-exists" companion="signature"
}
```

The artifact covers every Ruby file under `lib/`, each with the path of the signature file that belongs beside it. The policy applies CrossLint's `companion-exists` rule to every one of them. Fledge's configuration lists the plugin:

```kdl
// .config/crosslint/config.kdl
plugin ".config/crosslint/signatures"
```

Running `crosslint check` in the project checks every Ruby file under `lib/`. Each one has its signature file, so the check passes, and `crosslint` exits with 0:

```console
$ crosslint check
crosslint: checked 112 ruby-file artifacts: no violations
```

Add `lib/fledge/doctor.rb` without writing `sig/fledge/doctor.rbs`, and the check fails, with exit status 1:

```console
$ crosslint check
lib/fledge/doctor.rb: no signature file at sig/fledge/doctor.rbs (signatures/has-signature)
crosslint: checked 113 ruby-file artifacts: 1 error
```

Each finding is one line on standard output, with the file, the message, and the plugin and policy it comes from, so `grep` and an editor's problem matcher both read it. `crosslint check --json` prints the same findings as JSON for a script.

## Compatibility

| What | Supported |
| --- | --- |
| Where `crosslint` runs | macOS on Apple silicon; Linux on x86-64, with glibc 2.39 or later; Windows on x86-64 |
| Projects | Any language, in any folder layout |
| The Angular plugin | Angular projects with [Node](https://nodejs.org/) and the project's `typescript` package installed |
| Moving from ng-nudge | Projects that use ng-nudge 0.3.0 |

## Installation

Download the archive for your computer from [the releases page](https://github.com/setdef/CrossLint/releases), check it against the release's `SHA256SUMS` file, unpack it anywhere, and put `crosslint` on your `PATH`. The archive contains everything CrossLint needs, so you install no Ruby or other runtime. CrossLint sends no usage data anywhere.

To uninstall CrossLint, delete the unpacked folder. If you listed a shared plugin, also delete the cache folder CrossLint fetched it into: `$XDG_CACHE_HOME/crosslint`, or `~/.cache/crosslint` when `XDG_CACHE_HOME` isn't set to an absolute path, or `%LOCALAPPDATA%\crosslint\cache` on Windows.

## Usage

1. **Write a configuration.** In the project's root, `crosslint init` writes `.config/crosslint/config.kdl`, which lists the plugins CrossLint runs, with the recommended ones already in it. No plugin runs until the configuration lists it.
2. **Declare the project's rules** in a local plugin: a folder in the repository with a `plugin.kdl` that declares its artifacts, policies, and rules, as in [A first example](#a-first-example). List the folder in `.config/crosslint/config.kdl`.
3. **Run the checks** with `crosslint check` from anywhere in the project. It exits with 0 when every check passes, 1 when there are violations, and 2 when CrossLint can't run, such as for a mistake in the configuration.
4. **Accept what you can't fix yet** with `crosslint debt update`, a command of the debt plugin, which writes every current violation to `.config/crosslint/debt.tsv`. Add a comment to each line saying why it's there. From then on, `crosslint check` passes as long as no violation is new, and fails when a recorded one is fixed, until `crosslint debt update` removes it from the file.
5. **Run it in CI** as you run the project's tests, so a pull request with a new violation fails.

### Moving from ng-nudge

`crosslint init --from-ng-nudge` isn't available yet; until it is, keep using ng-nudge.

In the project's root, `crosslint init --from-ng-nudge` writes `.config/crosslint/config.kdl` from `.config/ng-nudge/rc.json`, with the Angular plugin and the debt plugin listed, and moves the debt file to `.config/crosslint/debt.tsv` with every comment kept. With `--dry-run`, it lists the changes and makes none. Then replace ng-nudge's dev dependency and each `npx ng-nudge` in the project's scripts and CI with `crosslint check`.

CrossLint finds some violations ng-nudge misses, such as inputs ng-nudge doesn't read and stylesheets it looks for in the wrong folder. Run `crosslint debt update` once after moving, so the next check passes, and work through the entries it adds as you would any other debt.

## Documentation

[The documentation's map](docs/README.md) says where to start for what you're doing.

- In the terminal: `crosslint --help` lists every command with examples, and `crosslint check --help` explains one.
- [Getting started](docs/getting-started.md): add CrossLint to a project, write a rule for it, and keep the check passing with debt.
- [Plugin reference](docs/reference/plugin.md): everything a `plugin.kdl` can declare, including rules written in Ruby.
- [Configuration reference](docs/reference/configuration.md): everything `.config/crosslint/config.kdl` can hold, including the settings of the Angular and debt plugins.
- [Command reference](docs/reference/cli.md): every command, flag, and exit status.
- [Glossary](docs/glossary.md): the word CrossLint uses for each idea, and the words it avoids.

## Reporting problems

Open an issue at [github.com/setdef/CrossLint/issues](https://github.com/setdef/CrossLint/issues). Include the command you ran, its output, and `crosslint --version`.

## Contributing

[CONTRIBUTING.md](CONTRIBUTING.md) says how a change lands, how files are licensed, and how releases are cut.

## License

CrossLint is released under the [MIT License](LICENSE). It places no conditions on the projects you check with it.

## How this was made

I use four words for how code and prose comes to exist. Code or prose I wrote, I typed by hand, with nothing generated. Code or prose I wrought, an AI agent generated while I iterated with it, and I reviewed every change before committing it, so I own every diff. Code or prose I requested, an agent built with little or no review from me, but I take ownership of the outcome or product because I tested and iterated. Code or prose I rushed, an agent built with little or no feedback from me, and may or may not be useful (or safe).

This README is requested: an agent wrote it from my goals and decisions, as the specification CrossLint is built to. [declare-ai.org](https://declare-ai.org/1.0.0/total.html)
