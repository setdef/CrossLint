# Contributing to CrossLint

## The documents are the specification

The README, [the glossary](docs/glossary.md), and [`crosslint.usage.kdl`](crosslint.usage.kdl) say what CrossLint does. When code and documents disagree, change the code, or change both in one commit and say why. Use the glossary's words, in code as in prose; a new idea gets a glossary entry before it gets a name.

The command reference, [`docs/reference/cli.md`](docs/reference/cli.md), is generated from `crosslint.usage.kdl`. After changing the spec, check it and regenerate the reference in the same commit:

```console
$ usage lint crosslint.usage.kdl
$ usage generate markdown --file crosslint.usage.kdl --out-file docs/reference/cli.md
```

What each part of CrossLint must guarantee is in [`docs/design/`](docs/design/README.md), and each requirement there becomes a test that fails when the requirement is broken. Architecture decisions are in [`docs/decisions/`](docs/decisions/). To change one, write a new record with the next number and delete the old one.

## Landing a change

Commit straight to `trunk`, one change at a time, each one complete and releasable. Run the checks that apply to the change before you push, and rebase and run them again when a push is refused because `trunk` moved.

## Licensing

CrossLint is MIT-licensed, copyright setdef. [`REUSE.toml`](REUSE.toml) declares the copyright and license of every file, following the [REUSE specification](https://reuse.software/spec/), and `reuse lint` must pass.

A file under a permissive license carries no SPDX header; `REUSE.toml` covers it. A file under a copyleft or share-alike license carries an SPDX header naming its license, and the license's text goes in `LICENSES/`.

Code or prose taken from [ng-nudge](https://github.com/OverTheTopMarketing/ng-nudge) (MIT, Copyright 2026 Over The Top Marketing) keeps its notice: wrap each passage in `SPDX-SnippetBegin` and `SPDX-SnippetEnd`, with `SPDX-SnippetCopyrightText` and `SPDX-License-Identifier` naming its copyright holder and license, the way [setdef/Tokra](https://github.com/setdef/Tokra) credits Tauri.

## Releases

Releases are tags and GitHub releases, cut whenever `trunk` is ready. Every version is `0.X.Y`, three plain integers, with no prerelease form such as `-rc.1` and no build metadata, and the version stays below 1.0.0. Nothing is published to a registry outside GitHub.
