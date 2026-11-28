# CrossLint

[![CI](https://github.com/setdef/CrossLint/actions/workflows/ci.yml/badge.svg?branch=trunk)](https://github.com/setdef/CrossLint/actions/workflows/ci.yml) [![Release](https://img.shields.io/github/v/release/setdef/CrossLint)](https://github.com/setdef/CrossLint/releases) [![Downloads](https://img.shields.io/github/downloads/setdef/CrossLint/total)](https://github.com/setdef/CrossLint/releases) [![License](https://img.shields.io/badge/license-MIT-a2c93e)](LICENSE) [![Platforms](https://img.shields.io/badge/platforms-macOS%20%7C%20Linux%20%7C%20Windows-a2c93e)](#compatibility) [![Forum: Discussion](https://img.shields.io/badge/forum-discussion-5865F2.svg?logo=discourse)](https://forum.setdef.com/tags/c/crosslint/12/discussion) [![Forum: Bug Reports](https://img.shields.io/badge/forum-bug_reports-4954d5.svg?logo=discourse)](https://forum.setdef.com/tags/c/crosslint/12/bug) [![Forum: Announcements](https://img.shields.io/badge/forum-announcements-3b44ac.svg?logo=discourse)](https://forum.setdef.com/tags/c/crosslint/12/announcement) [![Conventional Commits](https://img.shields.io/badge/Conventional%20Commits-1.0.0-FE5196)](https://www.conventionalcommits.org/en/v1.0.0/) [![Keep a Changelog](https://img.shields.io/badge/Keep%20a%20Changelog-1.1.0-E05735)](CHANGELOG.md) [![Packaged with Fledge](https://img.shields.io/badge/packaged%20with-Fledge-a2c93e)](https://github.com/setdef/Fledge) [![Certified Shovelware](https://justin.searls.co/img/shovelware.svg)](https://justin.searls.co/shovelware/)

A linter for the rules that span files, in any project and any language.

## Introduction

Most linters, such as [ESLint](https://eslint.org/) and [RuboCop](https://rubocop.org/), look at one file at a time. Many of a project's rules are about how its files relate: every database migration has a way back, every component has its test, every route has its controller's action, every link in the docs leads somewhere. CrossLint checks rules like these, across files and inside them, and exits with 1 when the project breaks one, so CI fails as it does for a failing test.

- **Lint any project, in any language.** CrossLint reads paths and text, and carries the Ruby it runs on, so a project needs no Ruby, Node, or other runtime to run it.
- **Use the rules CrossLint and its plugins have, or write your own.** A plugin is data, or code in any language.
- **Meet your project where it is, and from then on let it only get better.** Accept today's violations as debt, and the check fails on any new one.

### Compared with what you may use now

- **A script in CI.** A shell script that loops over files and tests for each one works until a second rule needs a second script. With CrossLint, you declare each rule in one place, CrossLint reports every violation with its file, and you accept existing violations as debt, so the check can pass before they are all fixed.
- **A custom rule for your linter.** A rule written for ESLint or RuboCop checks the file the linter gives it. A CrossLint rule checks an artifact, whose pieces can be in several files.
- **[ng-nudge](https://github.com/OverTheTopMarketing/ng-nudge).** ng-nudge checks Angular projects only. CrossLint keeps its checks as the Angular plugin and its debt tracking as the debt plugin, and an Angular project [moves with one command](#moving-from-ng-nudge).

## A first example

A project keeps its SQL migrations in `db/migrations/`, each as an `.up.sql` file that changes the schema and a `.down.sql` file that undoes it. One migration has no `.down.sql`:

<!--
SPDX-SnippetBegin
SPDX-License-Identifier: MIT-0
SPDX-SnippetCopyrightText: 2026 setdef
-->
```text
db/migrations/000001_create_users.up.sql
db/migrations/000001_create_users.down.sql
db/migrations/000002_create_orders.up.sql
db/migrations/000003_add_user_name.up.sql
db/migrations/000003_add_user_name.down.sql
```
<!-- SPDX-SnippetEnd -->

The rule goes in a plugin, a folder with a `plugin.kdl` in [KDL](https://kdl.dev/). This one is data, with no code, in `.config/crosslint/migrations/plugin.kdl`:

<!--
SPDX-SnippetBegin
SPDX-License-Identifier: MIT-0
SPDX-SnippetCopyrightText: 2026 setdef
-->
```kdl
artifact "migration" {
  primary "db/migrations/{name}.up.sql"
  piece "down" "db/migrations/{name}.down.sql"
}

policy "reversible" {
  applies-to "migration"
  rule "piece-exists" piece="down"
}
```
<!-- SPDX-SnippetEnd -->

For `000002_create_orders.up.sql`, `{name}` matches `000002_create_orders`, so the migration's `down` piece is `000002_create_orders.down.sql`. The project's configuration, `.config/crosslint/config.kdl`, lists the plugins CrossLint runs. `crosslint init` writes one with the recommended plugins, and the project's plugin goes below them:

<!--
SPDX-SnippetBegin
SPDX-License-Identifier: MIT-0
SPDX-SnippetCopyrightText: 2026 setdef
-->
```kdl
plugin "debt"
plugin ".config/crosslint/migrations"
```
<!-- SPDX-SnippetEnd -->

Then check the project:

<!--
SPDX-SnippetBegin
SPDX-License-Identifier: MIT-0
SPDX-SnippetCopyrightText: 2026 setdef
-->
```console
$ crosslint check
db/migrations/000002_create_orders.up.sql: no down file at db/migrations/000002_create_orders.down.sql (migrations/reversible)
crosslint: checked 3 migration artifacts: 1 error
$ echo $?
1
```
<!-- SPDX-SnippetEnd -->

Each violation is one line on standard output, with the file, the message, and the plugin and policy it comes from, so `grep` and an editor's problem matcher both read it. The summary is on standard error. `crosslint check --json` prints the same findings as JSON, and a script should read that, because [a minor release may change the line format](#versions).

## What CrossLint checks

CrossLint checks **artifacts**. An artifact is a logical unit of a project, such as a migration, an Angular component, a Rails route, or an entity in a C# domain model. It isn't a file. It has **pieces**, each a file or a part of a file, and any piece may be missing. One piece is primary: the one where the artifact is declared, by which CrossLint usually finds it. In the first example, a migration's primary piece is its `.up.sql` file, and its `down` piece is the `.down.sql` beside it.

| Word | Meaning | In the first example |
| --- | --- | --- |
| **role** | What kind of artifact one is. | `migration` |
| **policy** | When rules apply: to which artifacts of a role. | `reversible`, for every migration |
| **rule** | One check of one artifact. | `piece-exists`, which reports a missing piece |
| **violation** | What a rule reports when an artifact fails it, as an error or a warning. | the line for `000002_create_orders` |
| **plugin** | Roles, policies, and rules that belong together, in a folder with a `plugin.kdl`. | `.config/crosslint/migrations` |

A piece can be a part of a file, such as a `<style>` block in a Vue component, which exists when a regular expression has a match in the file. An artifact can be inside a file too: with a regular expression on its primary piece, each match is an artifact, so each route in `config/routes.rb` is one, and CrossLint reports it by its name and its line. The [cookbook](docs/cookbook/README.md) has a recipe for each, and [the glossary](docs/glossary.md) defines every word.

## Plugins: data, or code in any language

A plugin written as data, like the first example's, runs the rules CrossLint has, `piece-exists` and `piece-absent`, under conditions such as "every component whose stub exists". For a rule that data can't state, a plugin carries a **helper**: a command and a file in the plugin's folder, in any language. CrossLint sends the helper each artifact as a line of JSON, and turns each line the helper answers into violations.

This helper is Python. It reports each table a migration creates that its `.down.sql` doesn't drop, and gives the table's name as the violation's detail, so the debt file can accept each table by itself:

<!--
SPDX-SnippetBegin
SPDX-License-Identifier: MIT-0
SPDX-SnippetCopyrightText: 2026 setdef
-->
```python
# .config/crosslint/migrations/drops_tables.py
import json
import re
import sys

for line in sys.stdin:
    artifact = json.loads(line)["artifact"]
    down_path = artifact["pieces"]["down"]["path"]
    with open(artifact["path"]) as up, open(down_path) as down:
        created = re.findall(r"CREATE TABLE (\w+)", up.read(), re.IGNORECASE)
        dropped = re.findall(r"DROP TABLE (?:IF EXISTS )?(\w+)", down.read(), re.IGNORECASE)
    violations = [
        {"message": f"{down_path} doesn't drop {table}", "detail": table}
        for table in created
        if table not in dropped
    ]
    print(json.dumps({"violations": violations}), flush=True)
```
<!-- SPDX-SnippetEnd -->

Add to the plugin's `plugin.kdl` the helper, the rule it runs, and a policy for the migrations whose `.down.sql` exists, since the helper reads that file and `reversible` already reports a missing one:

<!--
SPDX-SnippetBegin
SPDX-License-Identifier: MIT-0
SPDX-SnippetCopyrightText: 2026 setdef
-->
```kdl
helper "sql" command="python3" file="drops_tables.py"
rule "drops-its-tables" helper="sql"

policy "undoes-its-tables" {
  applies-to "migration"
  when piece-exists "down"
  rule "drops-its-tables"
}
```
<!-- SPDX-SnippetEnd -->

With a `000002_create_orders.down.sql` that drops `users` by mistake:

<!--
SPDX-SnippetBegin
SPDX-License-Identifier: MIT-0
SPDX-SnippetCopyrightText: 2026 setdef
-->
```console
$ crosslint check
db/migrations/000002_create_orders.up.sql: db/migrations/000002_create_orders.down.sql doesn't drop orders (migrations/undoes-its-tables)
crosslint: checked 3 migration artifacts: 1 error
```
<!-- SPDX-SnippetEnd -->

A helper's command says what runs its file:

- **A program on the project's `PATH`,** such as `command="python3"`, `command="node"`, or `bundle exec ruby`, with the project's versions and packages. In a project without that program, CrossLint stops with exit status 2, and its message gives the plugin's name and the command it needs.
- **`command=(crosslint)"ruby"`,** the Ruby that CrossLint carries, so the plugin runs in every project, whatever its language. The file defines a class for each rule, with a `check` method, and CrossLint runs it in CrossLint's process.

A helper can also declare a plugin's artifacts from the settings a project gives the plugin. The [plugin reference](docs/reference/plugin.md) has the whole of `plugin.kdl`, the JSON a helper reads and writes, and the methods a rule in CrossLint's Ruby can call.

### Where plugins come from

A project lists each plugin it runs in `.config/crosslint/config.kdl`, as one of three kinds:

| Kind | Listed by | For |
| --- | --- | --- |
| Local plugin | its folder, such as `plugin ".config/crosslint/migrations"` | the project's rules |
| Shared plugin | a Git repository's URL, a tag or full commit SHA as `ref`, and `path=` for a plugin in one of the repository's folders | rules that several projects use |
| Built-in plugin | its name, `angular` or `debt` | the plugins that ship inside CrossLint |

This repository keeps shared plugins for checks many projects want, each in its folder under [`plugins/`](plugins/), with a README that says what it checks and how to list it:

- [markdown-links](plugins/markdown-links/README.md): every relative link in the project's Markdown resolves, anchors included.
- [decision-log](plugins/decision-log/README.md): a decision log's index links to exactly the records in its folder, no two records have one number, and no Markdown file cites a record number that no record has.
- [agents-md](plugins/agents-md/README.md): every `AGENTS.md` has a `CLAUDE.md` beside it whose first line is `@AGENTS.md`.
- [page-features](plugins/page-features/README.md): every page component of an app has a Gherkin feature file.

A project lists one by this repository's URL, a tag, and the plugin's folder, such as `plugin "https://github.com/setdef/CrossLint" ref="TAG" path="plugins/markdown-links"`. `TAG` is a release of CrossLint that has the plugin's folder.

> [!WARNING]
> **A plugin's code runs with your rights,** and CrossLint doesn't sandbox it. List a shared plugin only at a ref whose code you have read, as you would run a script.

## Debt: start from where the project is

A rule added to a project that grew without it can fail on dozens of files at once. Rather than leave the check failing until every one is fixed, accept them as debt with the debt plugin, which `crosslint init` lists:

<!--
SPDX-SnippetBegin
SPDX-License-Identifier: MIT-0
SPDX-SnippetCopyrightText: 2026 setdef
-->
```console
$ crosslint debt update
crosslint: wrote .config/crosslint/debt.tsv: 1 entry added, 0 removed
crosslint: checked 3 migration artifacts: 1 accepted as debt
$ crosslint check
crosslint: checked 3 migration artifacts: 1 accepted as debt
$ echo $?
0
```
<!-- SPDX-SnippetEnd -->

`.config/crosslint/debt.tsv` has one entry for each accepted violation, with a column for a comment that says why the violation is still there. Commit it with the project. From then on, the check fails on any violation the file doesn't list. When someone fixes a violation, its entry is paid off, and the check fails until `crosslint debt update` removes the entry, so the file only ever shrinks as the work gets done.

## Compatibility

| What | Supported |
| --- | --- |
| Where `crosslint` runs | macOS on Apple silicon; Linux on x86-64, with glibc 2.39 or later; Windows on x86-64 |
| Projects | Any language, in any folder layout, in a Git working tree, with Git on the `PATH` |
| A helper that runs a program | Projects with that program on the `PATH`, such as `python3` or `node` |
| The Angular plugin | Angular projects with [Node](https://nodejs.org/) on the `PATH` |
| Moving from ng-nudge | Projects that use ng-nudge 0.3.0; one whose `rc.json` sets `withComment.matching` needs Node on the `PATH` |

CrossLint lists a project's files with Git, so it never checks a file Git ignores or a file inside a submodule, and outside a Git working tree it stops with exit status 2.

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

Download the archive for your computer from [the releases page](https://github.com/setdef/CrossLint/releases), with the release's `SHA256SUMS` file, and check the archive against it. On macOS:

<!--
SPDX-SnippetBegin
SPDX-License-Identifier: MIT-0
SPDX-SnippetCopyrightText: 2026 setdef
-->
```console
$ shasum -a 256 --ignore-missing -c SHA256SUMS
crosslint-0.2.0-macos-aarch64.tar.gz: OK
$ tar -xzf crosslint-0.2.0-macos-aarch64.tar.gz
```
<!-- SPDX-SnippetEnd -->

The archive unpacks to one folder, with `crosslint` at its top. Keep the folder whole, anywhere you like, since `crosslint` runs on the Ruby inside it, and put the folder on your `PATH`. The archive contains everything CrossLint needs, so you install no Ruby or other runtime. CrossLint sends no usage data anywhere. Check that your shell finds it:

<!--
SPDX-SnippetBegin
SPDX-License-Identifier: MIT-0
SPDX-SnippetCopyrightText: 2026 setdef
-->
```console
$ crosslint --version
crosslint 0.2.0
```
<!-- SPDX-SnippetEnd -->

With [mise](https://mise.jdx.dev/), `mise use 'github:setdef/CrossLint[bin_path=.]'` installs the latest release and puts that folder on the `PATH`.

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
2. **Add the project's rules.** Write a local plugin, as in [A first example](#a-first-example), or list a shared or built-in one. CrossLint stops with exit status 2 at any line of a configuration or a `plugin.kdl` it doesn't understand, and names the file and the line, so a typo never leaves a check that doesn't run.
3. **Run the checks** with `crosslint check` from anywhere in the project. It exits with 0 when every check passes, 1 when a check fails, and 2 when CrossLint can't run, such as for a mistake in the configuration. A warning fails the check only with `--warnings=error`.
4. **Accept what you can't fix yet** with `crosslint debt update`, and add a comment to each new entry saying why it's there. `crosslint debt update --dry-run` lists what an update would change, and writes nothing.
5. **Run it in CI** as you run the project's tests, so a pull request with a new violation fails.
6. **Upgrade shared plugins** with `crosslint update`, which moves each one to the newest tag compatible with its `ref`, or with `crosslint update --latest`, which moves each one to its highest version tag.

## Moving from ng-nudge

An Angular project that uses ng-nudge 0.3.0 moves to CrossLint's Angular plugin, which keeps ng-nudge's checks under the names of ng-nudge's rules, and its debt plugin. In the project's root, run `crosslint init --from-ng-nudge --dry-run` first: it lists every change the move would make, and makes none.

<!--
SPDX-SnippetBegin
SPDX-License-Identifier: MIT-0
SPDX-SnippetCopyrightText: 2026 setdef
-->
```console
$ crosslint init --from-ng-nudge --dry-run
crosslint: would write .config/crosslint/config.kdl, with the plugins angular and debt
crosslint: would move .config/ng-nudge/debt.tsv to .config/crosslint/debt.tsv, byte for byte, with 2 entries
```
<!-- SPDX-SnippetEnd -->

Then run `crosslint init --from-ng-nudge`, which:

- writes `.config/crosslint/config.kdl` from `.config/ng-nudge/rc.json`, with the Angular plugin, the debt plugin, and every setting `rc.json` has, or ng-nudge's defaults when there is no `rc.json`;
- moves the debt file to `.config/crosslint/debt.tsv` byte for byte, with every entry and comment, and deletes ng-nudge's copy;
- leaves `rc.json` and the rule files in `.config/ng-nudge/rules/`, which ng-nudge never ran, where they are;
- lists each file that ng-nudge's patterns and CrossLint's would find differently, using the glob package in the project's `node_modules`.

It checks everything before it changes anything. A setting it can't carry with the same meaning, such as a pattern with braces, stops it with exit status 2, naming the setting and what to write instead, and one run lists every such problem, not only the first. So does a file in `.config/ng-nudge/artifacts/` or `policies/`, whose code CrossLint can't run, and an existing configuration or debt file, which `--force` replaces. Then replace ng-nudge's dev dependency and each `npx ng-nudge` in the project's scripts and CI with `crosslint check`.

CrossLint finds some violations ng-nudge misses, such as inputs ng-nudge doesn't read and stylesheets it looks for in the wrong folder. Run `crosslint debt update` once after moving, and work through the entries it adds as you would any other debt. The next check then passes, unless `rc.json` had ng-nudge report debt entries as errors, which CrossLint keeps doing. The Angular plugin's settings are in [the configuration reference](docs/reference/configuration.md#angular), and its words, such as stub and base path, in [its glossary](plugins/angular/glossary.md).

## Documentation

[The documentation's map](docs/README.md) says where to start for what you're doing.

- In the terminal: `crosslint --help` lists every command with examples, the commands of the project's plugins included, and `crosslint check --help` explains one.
- [Getting started](docs/getting-started.md): a tutorial of about 15 minutes that adds CrossLint to a project, writes a rule for it, and keeps the check passing with debt.
- [Cookbook](docs/cookbook/README.md): one recipe for each check, with a plugin to copy and what it reports, such as every Rails route having its action.
- [Plugin reference](docs/reference/plugin.md): everything a `plugin.kdl` can declare, with regular expressions and helpers.
- [Configuration reference](docs/reference/configuration.md): everything `.config/crosslint/config.kdl` can hold, including the settings of the Angular and debt plugins.
- [Command reference](docs/reference/cli.md): every command, flag, and exit status.
- [Glossary](docs/glossary.md): the words CrossLint's checking is made of. The [glossary for plugin authors](docs/reference/plugin-glossary.md), the [debt plugin's](plugins/debt/glossary.md), and the [Angular plugin's](plugins/angular/glossary.md) have the words of each.
- [Changelog](CHANGELOG.md): what changed in each release.

## Reporting problems

Ask questions and report problems on the [CrossLint forum](https://forum.setdef.com/c/crosslint). Include the command you ran, its output, `crosslint --version`, and your system. GitHub Issues are open to the project's collaborators only.

Report a security problem privately, as [SECURITY.md](SECURITY.md) says, never on the forum.

To send a patch, post it on the forum, or email it with `git send-email` to `replies+crosslint@forum.setdef.com`. [git-send-email.io](https://git-send-email.io) shows how to set that up.

## Contributing

[CONTRIBUTING.md](CONTRIBUTING.md) has the rules for every change: how it lands on the trunk, how commits are written, and how files are licensed. The [design pages](docs/design/README.md) say how each part of CrossLint works, and why.

## License

CrossLint is released under the [MIT License](LICENSE). It places no conditions on the projects you check with it. An example between SPDX snippet comments, in this README, the plugins' READMEs, or the guides and references under `docs/`, is under [MIT-0](LICENSES/MIT-0.txt), so you may copy it without a notice. The command reference and its examples are under the MIT License, like the rest.

## How this was made

I use four words for how code and prose comes to exist. Code or prose I wrote, I typed by hand, with nothing generated. Code or prose I wrought, an AI agent generated while I iterated with it, and I reviewed every change before committing it, so I own every diff. Code or prose I requested, an agent built with little or no review from me, but I take ownership of the outcome or product because I tested and iterated. Code or prose I rushed, an agent built with little or no feedback from me, and may or may not be useful (or safe).

This README is requested: an agent wrote it from my goals and decisions, as the specification CrossLint is built to. [declare-ai.org](https://declare-ai.org/1.0.0/total.html)
